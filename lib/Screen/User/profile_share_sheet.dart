import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/referral_service.dart';
import '../../theme.dart';
import '../../ui/profile_qr.dart';
import '../../ui/swapnio_kit.dart';
import 'user_detail.dart';

/// "Share profile": your own branded QR, and a scanner (camera or a
/// screenshot from the gallery) for someone else's.
Future<void> showProfileShareSheet(
  BuildContext context, {
  required Map<String, dynamic> userData,
  bool startOnScan = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        ProfileShareSheet(userData: userData, startOnScan: startOnScan),
  );
}

class ProfileShareSheet extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool startOnScan;

  const ProfileShareSheet({
    super.key,
    required this.userData,
    this.startOnScan = false,
  });

  @override
  State<ProfileShareSheet> createState() => _ProfileShareSheetState();
}

class _ProfileShareSheetState extends State<ProfileShareSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.startOnScan ? 1 : 0,
  );

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    // Its own messenger, so scan feedback shows on the sheet instead of
    // behind it.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.86,
      child: ScaffoldMessenger(
        child: Scaffold(backgroundColor: Colors.transparent, body: _body(c)),
      ),
    );
  }

  Widget _body(SwapnioColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Text(
                  'Share profile',
                  style: AppTheme.display(fontSize: 22, color: c.text),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: c.surfaceLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              controller: _tabs,
              indicator: BoxDecoration(
                color: c.cta,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerHeight: 0,
              labelColor: c.onCta,
              unselectedLabelColor: c.textMuted,
              labelStyle: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
              tabs: const [
                Tab(height: 40, icon: null, text: 'My QR'),
                Tab(height: 40, text: 'Scan'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _MyQrTab(userData: widget.userData),
                // Only run the camera while the Scan tab is showing.
                _tabs.index == 1
                    ? const SwapnioScanner(onCode: openScannedProfile)
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- QR

class _MyQrTab extends StatefulWidget {
  final Map<String, dynamic> userData;

  const _MyQrTab({required this.userData});

  @override
  State<_MyQrTab> createState() => _MyQrTabState();
}

class _MyQrTabState extends State<_MyQrTab> {
  final GlobalKey _cardKey = GlobalKey();
  String? _passport;
  int _version = 0;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _version = (widget.userData['qrVersion'] as num?)?.toInt() ?? 0;
    _loadPassport();
  }

  Future<void> _loadPassport() async {
    final existing = widget.userData['passportNumber'] as String?;
    if (existing != null && existing.isNotEmpty) {
      setState(() => _passport = existing);
      return;
    }
    // Numbers are issued (and reserved as unique) by the server.
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('issuePassportNumber')
          .call();
      final number = (result.data as Map?)?['passportNumber'] as String?;
      if (mounted) setState(() => _passport = number);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create your code. Check your connection.',
        );
      }
    }
  }

  Future<void> _shareImage() async {
    setState(() => _busy = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/swapnio_qr_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png'),
      ], text: 'Scan my Swapnio code to swap skills with me.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reset your QR?'),
        content: const Text(
          'You get a new code, and screenshots of your old one will stop opening your profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ReferralService.instance.resetMyQr();
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: c.textMuted)),
      );
    }
    if (_passport == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final name = (widget.userData['name'] as String?)?.trim() ?? '';
    final skills = List<String>.from(
      widget.userData['skillsOffered'] ?? const [],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: ProfileQrCard(
              data: ReferralService.instance.qrPayload(_passport!, _version),
              name: name.isEmpty ? 'Swapnio member' : name,
              photoUrl: widget.userData['photoUrl'] as String?,
              topSkill: skills.isEmpty ? null : skills.first,
              passportNumber: _passport!,
              verified: widget.userData['verified'] == true,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Anyone can scan this in Swapnio to open your profile. Scanned with a '
            'phone camera, it takes new people to Swapnio - and counts as your invite.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.45,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          PillButton(
            label: 'Save or share image',
            icon: Icons.ios_share_rounded,
            loading: _busy,
            onTap: _busy ? null : _shareImage,
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _reset,
            icon: Icon(Icons.refresh_rounded, size: 18, color: c.textMuted),
            label: Text('Reset my QR', style: TextStyle(color: c.textMuted)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Scan

/// Opens the profile behind a scanned code, or explains why it can't.
Future<void> openScannedProfile(BuildContext context, String raw) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  // The page under the sheet, for messages shown after the sheet closes.
  final pageMessenger = ScaffoldMessenger.of(navigator.context);
  final result = await ReferralService.instance.resolve(raw);
  switch (result.outcome) {
    case ScanOutcome.profile:
      // One QR, two jobs: for an account on its first day, scanning also
      // records who invited it (silently - the server applies every rule).
      if (await ReferralService.instance.isFirstDayUnreferred()) {
        try {
          final name = await ReferralService.instance.claim(
            raw,
            source: 'scan',
          );
          pageMessenger.showSnackBar(
            SnackBar(
              content: Text(
                name.isEmpty
                    ? 'Invite recorded.'
                    : 'Welcome! $name invited you.',
              ),
            ),
          );
        } catch (_) {
          // Not eligible (e.g. already has a session) - just open the profile.
        }
      }
      navigator.pop();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => UserDetailPage(userId: result.userId!),
        ),
      );
    case ScanOutcome.ownCode:
      messenger.showSnackBar(
        const SnackBar(content: Text("That's your own code.")),
      );
    case ScanOutcome.privateProfile:
      messenger.showSnackBar(
        const SnackBar(content: Text('That profile is private.')),
      );
    case ScanOutcome.resetCode:
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'This code was reset by its owner. Ask them for their new one.',
          ),
        ),
      );
    case ScanOutcome.notFound:
      messenger.showSnackBar(
        const SnackBar(
          content: Text("That code doesn't belong to anyone yet."),
        ),
      );
    case ScanOutcome.notSwapnio:
      messenger.showSnackBar(
        const SnackBar(content: Text("That isn't a Swapnio code.")),
      );
  }
}

/// Camera QR scanner with a "scan from gallery" option for screenshots.
/// [onCode] decides what a scanned code does.
class SwapnioScanner extends StatefulWidget {
  final Future<void> Function(BuildContext context, String raw) onCode;
  final String hint;

  const SwapnioScanner({
    super.key,
    required this.onCode,
    this.hint = 'Point at a Swapnio QR, or pick a screenshot of one.',
  });

  @override
  State<SwapnioScanner> createState() => _SwapnioScannerState();
}

class _SwapnioScannerState extends State<SwapnioScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String? raw) async {
    if (_handling || raw == null || raw.isEmpty) return;
    setState(() => _handling = true);
    try {
      await widget.onCode(context, raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is String ? e : 'Could not read that code. Try again.',
            ),
          ),
        );
      }
    }
    // Brief pause so one code held in view isn't handled over and over.
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _handling = false);
  }

  Future<void> _fromGallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final capture = await _controller.analyzeImage(picked.path);
    final raw = capture?.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (!mounted) return;
    if (raw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No QR code found in that image.')),
      );
      return;
    }
    await _handle(raw);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) => _handle(
                      capture.barcodes
                          .map((b) => b.rawValue)
                          .whereType<String>()
                          .firstOrNull,
                    ),
                    errorBuilder: (context, error, child) => ColoredBox(
                      color: c.surfaceLow,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Camera unavailable. Allow camera access, or scan a screenshot from your gallery.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Viewfinder frame in the brand gradient.
                  Center(
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: c.win, width: 3),
                      ),
                    ),
                  ),
                  if (_handling)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.hint,
            style: GoogleFonts.manrope(fontSize: 12.5, color: c.textMuted),
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Scan from gallery',
            icon: Icons.photo_library_rounded,
            color: c.surface,
            foreground: c.text,
            onTap: _handling ? null : _fromGallery,
          ),
        ],
      ),
    );
  }
}
