import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme.dart';
import '../../ui/swap_web_graph.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import 'user_detail.dart';

/// Profile > Web: your real skill network from completed sessions as a
/// live, draggable web, with filters for skill, direction, time together,
/// reach and time range.
class SwapWebTab extends StatefulWidget {
  final List<String> mySkills;

  const SwapWebTab({super.key, required this.mySkills});

  @override
  State<SwapWebTab> createState() => _SwapWebTabState();
}

class _SwapWebTabState extends State<SwapWebTab>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey _exportKey = GlobalKey();
  String? _skill;
  String _direction = 'both';
  String _links = 'all';
  int _minMinutes = 0;
  int _depth = 2;
  int _sinceDays = 0;

  Future<SwapWebData>? _future;
  bool _sharing = false;

  /// Skills for the SKILL filter: what I offer plus every skill seen on the
  /// map so far (kept across filter changes so chips don't vanish).
  late final Set<String> _skillChoices = {...widget.mySkills};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = FirebaseFunctions.instance
          .httpsCallable('mySwapWeb')
          .call({
            'filters': {
              'skill': _skill,
              'direction': _direction,
              'links': _links,
              'minMinutes': _minMinutes,
              'depth': _depth,
              'sinceDays': _sinceDays,
            },
          })
          .then((r) {
            final data = SwapWebData.fromMap(
              Map<String, dynamic>.from(r.data as Map),
            );
            final lower = _skillChoices.map((s) => s.toLowerCase()).toSet();
            final fresh = [
              for (final e in data.edges)
                for (final skill in e.skills)
                  if (skill.isNotEmpty && lower.add(skill.toLowerCase())) skill,
            ];
            if (fresh.isNotEmpty && mounted) {
              setState(() => _skillChoices.addAll(fresh));
            }
            return data;
          });
    });
  }

  void _openNode(SwapWebData data, WebNode node) {
    final c = context.sw;
    final links =
        data.edges.where((e) => e.from == node.key || e.to == node.key).toList()
          ..sort((a, b) => b.minutes.compareTo(a.minutes));
    String who(String key) {
      if (key == data.center?.key) return 'You';
      return data.nodes.where((n) => n.key == key).firstOrNull?.name ??
          'Someone';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SwapAvatar(
                    name: node.name,
                    photoUrl: node.photoUrl.isEmpty ? null : node.photoUrl,
                    size: 44,
                    radius: 22,
                    verified: node.verified,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.depth == 0 ? 'You' : node.name,
                          style: AppTheme.display(fontSize: 20, color: c.text),
                        ),
                        Text(
                          node.depth == 0
                              ? 'The centre of your web'
                              : node.depth == 1
                              ? 'Swapped with you directly'
                              : '${node.depth} steps away',
                          style: GoogleFonts.manrope(
                            fontSize: 12.5,
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              for (final e in links.take(6)) _linkLine(c, e, who),
              if (node.id != null && node.depth > 0) ...[
                const SizedBox(height: 10),
                PillButton(
                  label: 'Open profile',
                  icon: Icons.person_rounded,
                  onTap: () {
                    Navigator.pop(sheet);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserDetailPage(userId: node.id!),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Mutual swap with Manab" + what went each way, or "One way" + what the
  /// teacher taught.
  Widget _linkLine(
    SwapnioColors c,
    WebEdge e,
    String Function(String key) who,
  ) {
    final muted = TextStyle(color: c.textMuted);
    List<InlineSpan> taught(
      String teacher,
      String learner,
      List<WebSkill> xs,
    ) => [
      TextSpan(
        text: who(teacher),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      TextSpan(text: ' taught ', style: muted),
      TextSpan(
        text: xs.map((x) => x.skill).join(', '),
        style: TextStyle(fontWeight: FontWeight.w800, color: c.give),
      ),
      TextSpan(text: ' to ', style: muted),
      TextSpan(
        text: who(learner),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      TextSpan(
        text: '  ·  ${formatWebMinutes(xs.fold(0, (a, x) => a + x.minutes))}\n',
        style: muted.copyWith(fontSize: 12),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7, right: 10),
            child: Container(
              width: 14,
              height: 3,
              color: e.isMutual ? c.success : c.give,
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: e.isMutual ? 'MUTUAL SWAP\n' : 'ONE WAY\n',
                    style: AppTheme.label(
                      fontSize: 10,
                      color: e.isMutual ? c.success : c.textMuted,
                    ),
                  ),
                  if (e.forward.isNotEmpty) ...taught(e.from, e.to, e.forward),
                  if (e.back.isNotEmpty) ...taught(e.to, e.from, e.back),
                ],
              ),
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.4,
                color: c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(SwapWebData data) async {
    setState(() => _sharing = true);
    // The export card has to be painted to be captured, so it's put in an
    // overlay for a moment - near-invisible (a zero opacity would skip
    // painting it altogether) and not tappable.
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.01,
            child: RepaintBoundary(
              key: _exportKey,
              child: _ExportCard(data: data),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _exportKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/swapnio_web_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text:
            'My Swap Web on Swapnio: ${data.people} people, '
            '${formatWebMinutes(data.taughtMinutes)} taught and ${formatWebMinutes(data.learnedMinutes)} learned.',
      );
    } finally {
      entry.remove();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = context.sw;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      children: [
        _filters(context),
        const SizedBox(height: 12),
        FutureBuilder<SwapWebData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 300,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'Could not load your web.',
                    style: TextStyle(color: c.textMuted),
                  ),
                ),
              );
            }
            final data = snap.data!;
            if (data.people == 0) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(Icons.hub_rounded, size: 48, color: c.border),
                    const SizedBox(height: 12),
                    Text(
                      _skill != null ||
                              _minMinutes > 0 ||
                              _sinceDays > 0 ||
                              _direction != 'both' ||
                              _links != 'all'
                          ? 'Nobody matches these filters yet.'
                          : 'Your web grows with every completed session.\nFinish your first one to see it here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted, height: 1.4),
                    ),
                  ],
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${data.people} ${data.people == 1 ? 'person' : 'people'} in your web · '
                  '${formatWebMinutes(data.taughtMinutes)} taught · ${formatWebMinutes(data.learnedMinutes)} learned',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
                if (data.capped)
                  Text(
                    'Showing the 60 strongest connections',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: c.textMuted),
                  ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SwapWebGraph(
                    data: data,
                    onTapNode: (n) => _openNode(data, n),
                  ),
                ),
                const SizedBox(height: 10),
                const SwapWebLegend(),
                const SizedBox(height: 14),
                PillButton(
                  label: 'Share my Swap Web',
                  icon: Icons.ios_share_rounded,
                  loading: _sharing,
                  onTap: _sharing ? null : () => _share(data),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final c = context.sw;
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) {
          onTap();
          _load();
        },
        selectedColor: c.get.withValues(alpha: 0.18),
      ),
    );
    Widget row(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              title,
              style: AppTheme.label(fontSize: 10, color: c.textMuted),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        row('SKILL', [
          chip('All', _skill == null, () => _skill = null),
          for (final s in _skillChoices) chip(s, _skill == s, () => _skill = s),
        ]),
        row('SHOW', [
          chip('Both', _direction == 'both', () => _direction = 'both'),
          chip('Taught', _direction == 'taught', () => _direction = 'taught'),
          chip(
            'Learned',
            _direction == 'learned',
            () => _direction = 'learned',
          ),
        ]),
        row('LINKS', [
          chip('All', _links == 'all', () => _links = 'all'),
          chip('Mutual', _links == 'mutual', () => _links = 'mutual'),
          chip('One-way', _links == 'oneway', () => _links = 'oneway'),
        ]),
        row('TIME', [
          for (final m in const [0, 60, 300])
            chip(
              m == 0 ? 'Any' : '${m ~/ 60} h+',
              _minMinutes == m,
              () => _minMinutes = m,
            ),
        ]),
        row('REACH', [
          for (final d in const [1, 2, 3])
            chip(d == 1 ? 'Direct' : '$d steps', _depth == d, () => _depth = d),
        ]),
        row('WHEN', [
          chip('All time', _sinceDays == 0, () => _sinceDays = 0),
          chip('Past year', _sinceDays == 365, () => _sinceDays = 365),
          chip('3 months', _sinceDays == 90, () => _sinceDays = 90),
        ]),
      ],
    );
  }
}

class _ExportCard extends StatelessWidget {
  final SwapWebData data;

  const _ExportCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(
        builder: (context) {
          final c = context.sw;
          return Container(
            width: 360,
            color: c.bg,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'MY SWAP WEB',
                      style: AppTheme.label(
                        fontSize: 12,
                        color: c.get,
                      ).copyWith(letterSpacing: 2.5),
                    ),
                    const Spacer(),
                    const SwapnioMark(size: 26),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: SwapWebCanvas(
                    data: data,
                    size: const Size(324, 324),
                    showNames: false,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${data.people} people · ${formatWebMinutes(data.taughtMinutes)} taught · '
                  '${formatWebMinutes(data.learnedMinutes)} learned',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Built from verified sessions on Swapnio',
                  style: GoogleFonts.manrope(fontSize: 11, color: c.textMuted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
