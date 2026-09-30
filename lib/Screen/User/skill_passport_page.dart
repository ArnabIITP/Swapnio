import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/passport_caption.dart';
import '../../services/skill_passport_service.dart';
import '../../theme.dart';
import '../../ui/fade_slide_in.dart';
import '../../ui/skill_passport_booklet.dart';
import '../../ui/skill_passport_widgets.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';

enum _PassportView { booklet, card }

enum _ShareFormat {
  spread(
    'Open passport',
    'Identity + stamps as one wide image. Best for LinkedIn and X.',
    Icons.menu_book_rounded,
  ),
  pages(
    'Every page',
    'One image per page, posted as a carousel.',
    Icons.collections_rounded,
  ),
  card(
    'Feed card',
    'A single 4:5 image for Instagram and WhatsApp.',
    Icons.crop_portrait_rounded,
  );

  final String title;
  final String subtitle;
  final IconData icon;

  const _ShareFormat(this.title, this.subtitle, this.icon);
}

/// A verifiable, shareable record of what someone has actually taught on
/// Swapnio, built only from completed sessions and peer ratings (see
/// [SkillPassportService] for exactly what is and isn't trusted).
///
/// Shown as a swipeable booklet or a 4:5 feed card. Exports are rendered
/// off-screen at a fixed size, always in the light palette, so a shared
/// image looks the same on every phone and theme.
class SkillPassportPage extends StatefulWidget {
  final String? userId;

  const SkillPassportPage({super.key, this.userId});

  @override
  State<SkillPassportPage> createState() => _SkillPassportPageState();
}

class _SkillPassportPageState extends State<SkillPassportPage> {
  late Future<SkillPassport> _future;
  _PassportView _view = _PassportView.booklet;
  bool _isExporting = false;

  /// Widgets being rendered for export. They're laid out under the page
  /// (hidden by it) just long enough to be captured, then removed.
  List<(GlobalKey, Widget)> _stage = const [];

  String get _uid =>
      widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<SkillPassport> _load() async {
    final passport = await SkillPassportService.instance.load(_uid);
    // Warm the avatar so it's already decoded when an image is captured -
    // otherwise an export taken right away can show a blank photo.
    final url = passport.photoUrl;
    if (url != null && url.isNotEmpty && mounted) {
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {
        // The photo falls back to initials; never block the passport.
      }
    }
    return passport;
  }

  /// Export targets for a format, each at its final logical size (3x on
  /// capture).
  List<Widget> _exportWidgets(SkillPassport passport, _ShareFormat format) {
    Widget onBackdrop(Size size, Widget child) => LightDocument(
      builder: (context) => Container(
        width: size.width,
        height: size.height,
        color: context.sw.bg,
        alignment: Alignment.center,
        child: child,
      ),
    );

    switch (format) {
      case _ShareFormat.spread:
        // 1.37:1 - wide enough for LinkedIn's landscape preview with room
        // for the cover's drop shadow.
        return [
          onBackdrop(
            const Size(680, 496),
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: PassportSpread(
                left: PassportDataPage(
                  passport: passport,
                  spine: PassportSpine.right,
                ),
                right: PassportStampsPage(
                  passport: passport,
                  spine: PassportSpine.left,
                ),
              ),
            ),
          ),
        ];
      case _ShareFormat.pages:
        // 4:5 per page, the tallest ratio feeds show uncropped.
        return [
          for (final (i, page) in passportPages(passport).indexed)
            onBackdrop(
              const Size(400, 500),
              Padding(
                padding: const EdgeInsets.only(right: 7, bottom: 7),
                child: PassportFramedPage(page: page.$2, isCover: i == 0),
              ),
            ),
        ];
      case _ShareFormat.card:
        return [
          LightDocument(builder: (_) => PassportFeedCard(passport: passport)),
        ];
    }
  }

  Future<List<XFile>> _render(List<Widget> widgets, String name) async {
    final keys = [for (final _ in widgets) GlobalKey()];
    setState(
      () => _stage = [
        for (var i = 0; i < widgets.length; i++) (keys[i], widgets[i]),
      ],
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      // Pages the viewer hasn't shown yet may use font weights that are
      // still downloading; wait for them so text isn't captured in a
      // fallback face.
      await GoogleFonts.pendingFonts();
      await WidgetsBinding.instance.endOfFrame;

      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final files = <XFile>[];
      for (var i = 0; i < keys.length; i++) {
        final boundary =
            keys[i].currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) throw StateError('Passport is not ready yet.');
        final image = await boundary.toImage(pixelRatio: 3.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) {
          throw StateError('Could not render the passport image.');
        }
        final file = File(
          '${dir.path}/skill_passport_${name}_${i + 1}_$stamp.png',
        );
        await file.writeAsBytes(bytes.buffer.asUint8List());
        files.add(XFile(file.path, mimeType: 'image/png'));
      }
      return files;
    } finally {
      if (mounted) setState(() => _stage = const []);
    }
  }

  Future<void> _share(SkillPassport passport) async {
    if (_isExporting) return;
    final choice = await showModalBottomSheet<(_ShareFormat, String)>(
      context: context,
      isScrollControlled: true,
      // Keeps the sheet below the status bar when the keyboard pushes it up.
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        passport: passport,
        initial: _view == _PassportView.card
            ? _ShareFormat.card
            : _ShareFormat.spread,
      ),
    );
    if (choice == null || !mounted) return;
    final (format, caption) = choice;

    setState(() => _isExporting = true);
    try {
      // LinkedIn and some other apps discard text that arrives with an
      // image, so the caption goes on the clipboard too, ready to paste.
      if (caption.trim().isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: caption));
      }
      final files = await _render(
        _exportWidgets(passport, format),
        format.name,
      );
      await Share.shareXFiles(
        files,
        text: caption,
        subject: 'My Skill Passport on Swapnio',
      );
      if (!mounted || caption.trim().isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Caption copied - if your post is empty, long-press and paste it in.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share your passport: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          if (_stage.isNotEmpty)
            Positioned(
              left: 0,
              top: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (key, child) in _stage)
                    RepaintBoundary(key: key, child: child),
                ],
              ),
            ),
          Positioned.fill(
            child: ColoredBox(
              color: c.bg,
              child: SafeArea(
                child: FutureBuilder<SkillPassport>(
                  future: _future,
                  builder: (context, snapshot) {
                    final passport = snapshot.data;
                    return Column(
                      children: [
                        const SwapHeader(
                          title: 'Skill Passport',
                          subtitle: 'Your verified teaching record',
                        ),
                        _buildViewToggle(context),
                        Expanded(
                          child:
                              snapshot.connectionState ==
                                  ConnectionState.waiting
                              ? _buildSkeleton()
                              : snapshot.hasError || passport == null
                              ? _buildError(context)
                              : FadeSlideIn(
                                  key: ValueKey(_view),
                                  child: _view == _PassportView.booklet
                                      ? SkillPassportBooklet(passport: passport)
                                      : _buildCardPreview(passport),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: PillButton(
                            label: _isExporting
                                ? 'Preparing...'
                                : 'Share passport',
                            icon: _isExporting ? null : Icons.ios_share_rounded,
                            loading: _isExporting,
                            onTap: passport == null
                                ? null
                                : () => _share(passport),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle(BuildContext context) {
    final c = context.sw;
    Widget segment(_PassportView view, String label, IconData icon) {
      final selected = _view == view;
      return Expanded(
        child: Pressable(
          onTap: () => setState(() => _view = view),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 40,
            decoration: BoxDecoration(
              color: selected ? c.cta : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: selected ? c.onCta : c.textMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? c.onCta : c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surfaceLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            segment(_PassportView.booklet, 'Booklet', Icons.menu_book_rounded),
            segment(
              _PassportView.card,
              'Feed card',
              Icons.crop_portrait_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardPreview(SkillPassport passport) {
    final c = context.sw;
    return Center(
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 4, 24, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: FittedBox(
            child: LightDocument(
              builder: (_) => PassportFeedCard(passport: passport),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return SwapSkeleton(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 36, 16),
        child: Column(
          children: const [
            Expanded(child: SkeletonBox(height: double.infinity, radius: 18)),
            SizedBox(height: 14),
            SkeletonBox(height: 8, width: 90, radius: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final c = context.sw;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load your Skill Passport.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 180,
              child: PillButton(
                label: 'Try again',
                onTap: () => setState(() => _future = _load()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick what to share and edit a generated caption. Returns the format and
/// the final caption text.
class _ShareSheet extends StatefulWidget {
  final SkillPassport passport;
  final _ShareFormat initial;

  const _ShareSheet({required this.passport, required this.initial});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  late final List<String> _captions = PassportCaption.variants(widget.passport);
  late final TextEditingController _caption = TextEditingController(
    text: _captions.first,
  );
  late _ShareFormat _format = widget.initial;
  int _captionIndex = 0;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _nextCaption() {
    setState(() {
      _captionIndex = (_captionIndex + 1) % _captions.length;
      _caption.text = _captions[_captionIndex];
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final pageCount = passportPages(widget.passport).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        // Space left above the keyboard and below the status bar, so the
        // sheet shrinks (its body scrolls) instead of sliding under the
        // status bar when the caption is being edited.
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      MediaQuery.paddingOf(context).top -
                      12)
                  .clamp(200.0, MediaQuery.sizeOf(context).height * 0.9),
        ),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: c.border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Share your passport',
                        style: AppTheme.display(fontSize: 22, color: c.text),
                      ),
                      const SizedBox(height: 14),
                      for (final format in _ShareFormat.values) ...[
                        _formatTile(context, format, pageCount),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            'CAPTION',
                            style: AppTheme.label(
                              fontSize: 10.5,
                              color: c.textMuted,
                            ).copyWith(letterSpacing: 1.8),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _captions.length > 1
                                ? _nextCaption
                                : null,
                            icon: Icon(
                              Icons.auto_awesome_rounded,
                              size: 16,
                              color: c.get,
                            ),
                            label: Text(
                              'Try another (${_captionIndex + 1}/${_captions.length})',
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: c.get,
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _caption,
                        minLines: 5,
                        maxLines: 7,
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.45,
                          color: c.text,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: c.surface,
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: c.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: c.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: c.get, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.content_paste_rounded,
                            size: 14,
                            color: c.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              "LinkedIn doesn't accept captions from other apps, so we copy this one for you. "
                              'Long-press the post box and paste.',
                              style: GoogleFonts.manrope(
                                fontSize: 11.5,
                                height: 1.4,
                                color: c.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Pinned below the scroll area so it's always in reach, even
              // while the caption box is being scrolled or edited.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: PillButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  onTap: () => Navigator.of(
                    context,
                  ).pop((_format, _caption.text.trim())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formatTile(BuildContext context, _ShareFormat format, int pageCount) {
    final c = context.sw;
    final selected = _format == format;
    return Pressable(
      onTap: () => setState(() => _format = format),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.get : c.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (selected ? c.get : c.textMuted).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                format.icon,
                size: 20,
                color: selected ? c.get : c.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    format == _ShareFormat.pages
                        ? '${format.title} ($pageCount images)'
                        : format.title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    format.subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 11.5,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? c.get : c.border,
            ),
          ],
        ),
      ),
    );
  }
}
