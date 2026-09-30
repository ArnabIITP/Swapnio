import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/device_service.dart';
import '../../theme.dart';
import '../../ui/profile_qr.dart';
import '../../ui/swapnio_kit.dart';

/// Settings > Security: devices signed in to this account, recent security
/// activity, and two-factor authentication.
class SecurityPage extends StatefulWidget {
  /// Admins can open another member's security log (read-only).
  final String? userId;

  const SecurityPage({super.key, this.userId});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  String get _uid =>
      widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _isSelf =>
      widget.userId == null ||
      widget.userId == FirebaseAuth.instance.currentUser?.uid;
  String? _thisDevice;
  ({bool enabled, int backupCodesLeft})? _twoFactor;

  /// Re-renders every 30 s so "Active now" / "Last active 3 min ago" stay
  /// true while the page is open.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    DeviceService.instance.deviceId().then((id) {
      if (mounted) setState(() => _thisDevice = id);
    });
    if (_isSelf) _loadTwoFactor();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadTwoFactor() async {
    try {
      final s = await DeviceService.instance.twoFactorStatus();
      if (mounted) setState(() => _twoFactor = s);
    } catch (_) {}
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _signOut(String deviceId, String model) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Sign out $model?'),
        content: const Text(
          'It will be signed out the next time it opens Swapnio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DeviceService.instance.signOutDevice(deviceId);
      _snack('$model will be signed out.');
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not sign that device out.');
    }
  }

  Future<void> _signOutOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Sign out all other devices?'),
        content: const Text(
          'Every device except this one will be signed out the next time it opens Swapnio.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Sign out others'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await DeviceService.instance.signOutOtherDevices();
      _snack(
        n == 0
            ? 'No other devices were signed in.'
            : 'Signed out $n other device${n == 1 ? '' : 's'}.',
      );
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not sign the other devices out.');
    }
  }

  // ------------------------------------------------------------------- 2FA

  Future<void> _setupTwoFactor() async {
    final c = context.sw;
    ({String secret, String otpauth}) setup;
    try {
      setup = await DeviceService.instance.startTwoFactorSetup();
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not start setup.');
      return;
    }
    if (!mounted) return;
    final codeController = TextEditingController();
    final codes = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheet) =>
          _TwoFactorSetupSheet(setup: setup, controller: codeController),
    );
    if (codes == null || !mounted) return;
    await _loadTwoFactor();
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('Save your backup codes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Each works once if you lose your phone. They won\'t be shown again.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              codes.join('\n'),
              style: GoogleFonts.jetBrainsMono(fontSize: 15, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: codes.join('\n')));
              _snack('Backup codes copied.');
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('I saved them'),
          ),
        ],
      ),
    );
  }

  Future<void> _disableTwoFactor() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Turn off two-factor?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: '6-digit code or a backup code',
          ),
          onSubmitted: (v) => Navigator.pop(d, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, controller.text.trim()),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      await DeviceService.instance.disableTwoFactor(code);
      _snack('Two-factor is off.');
      await _loadTwoFactor();
    } on FirebaseFunctionsException catch (e) {
      _snack(e.message ?? 'Could not turn two-factor off.');
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            SwapHeader(
              title: 'Security',
              subtitle: _isSelf
                  ? 'Devices, activity and two-factor'
                  : 'Security log (admin view)',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (_isSelf) ...[
                    _section(context, 'TWO-FACTOR AUTHENTICATION'),
                    _twoFactorCard(context),
                    const SizedBox(height: 20),
                  ],
                  _section(context, 'CONNECTED DEVICES'),
                  _devices(context),
                  const SizedBox(height: 20),
                  _section(context, 'RECENT ACTIVITY'),
                  _activity(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: AppTheme.label(
        color: context.sw.textMuted,
      ).copyWith(letterSpacing: 1.8),
    ),
  );

  Widget _twoFactorCard(BuildContext context) {
    final c = context.sw;
    final tf = _twoFactor;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                tf?.enabled == true
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
                color: tf?.enabled == true ? c.success : c.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tf == null
                      ? 'Checking…'
                      : tf.enabled
                      ? 'On'
                      : 'Off',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: c.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tf?.enabled == true
                ? 'New devices need a code from your authenticator app. ${tf!.backupCodesLeft} backup code${tf.backupCodesLeft == 1 ? '' : 's'} left.'
                : 'Add a code from an authenticator app (like Google Authenticator) whenever your account is used on a new device.',
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              height: 1.45,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (tf != null)
            tf.enabled
                ? OutlinedButton(
                    onPressed: _disableTwoFactor,
                    child: const Text('Turn off'),
                  )
                : PillButton(
                    label: 'Set up two-factor',
                    icon: Icons.lock_rounded,
                    onTap: _setupTwoFactor,
                  ),
        ],
      ),
    );
  }

  Widget _devices(BuildContext context) {
    final c = context.sw;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('devices')
          .snapshots(),
      builder: (context, snap) {
        final docs =
            (snap.data?.docs ?? const [])
                .where((d) => d.data()['revoked'] != true)
                .toList()
              ..sort((a, b) {
                if (a.id == _thisDevice) return -1;
                if (b.id == _thisDevice) return 1;
                final ta =
                    (a.data()['lastSeenAt'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
                final tb =
                    (b.data()['lastSeenAt'] as Timestamp?)
                        ?.millisecondsSinceEpoch ??
                    0;
                return tb.compareTo(ta);
              });
        if (docs.isEmpty) {
          return Text(
            snap.hasData ? 'No devices yet.' : 'Loading…',
            style: TextStyle(color: c.textMuted),
          );
        }
        return Column(
          children: [
            for (final d in docs) _deviceTile(context, d.id, d.data()),
            if (_isSelf && docs.length > 1) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _signOutOthers,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out all other devices'),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _deviceTile(BuildContext context, String id, Map<String, dynamic> d) {
    final c = context.sw;
    final isThis = id == _thisDevice && _isSelf;
    final model = (d['model'] as String?)?.isNotEmpty == true
        ? d['model'] as String
        : 'Unknown device';
    final place = [
      d['city'],
      d['country'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final seen = (d['lastSeenAt'] as Timestamp?)?.toDate();
    // Active = the app is in the foreground there right now: it said so and
    // its heartbeat is recent (a killed app stops beating and ages out).
    final activeNow =
        isThis ||
        (d['online'] == true &&
            seen != null &&
            DateTime.now().difference(seen) < DeviceService.activeWindow);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.smartphone_rounded,
                  color: isThis ? c.get : c.textMuted,
                ),
                if (activeNow)
                  Positioned(
                    right: -2,
                    bottom: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: c.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                      ),
                      if (isThis) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.get.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'This device',
                            style: GoogleFonts.manrope(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: c.get,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    [
                      if ((d['osVersion'] as String?)?.isNotEmpty == true)
                        d['osVersion'],
                      if ((d['appVersion'] as String?)?.isNotEmpty == true)
                        'App ${d['appVersion']}',
                    ].join(' · '),
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: c.textMuted,
                    ),
                  ),
                  Text(
                    '${place.isEmpty ? 'Location unknown' : place} · '
                    '${activeNow
                        ? 'Active now'
                        : seen == null
                        ? 'Never'
                        : 'Last active ${_ago(seen)}'}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (_isSelf && !isThis)
              IconButton(
                tooltip: 'Sign out this device',
                icon: Icon(Icons.logout_rounded, color: c.textMuted),
                onPressed: () => _signOut(id, model),
              ),
          ],
        ),
      ),
    );
  }

  static const _labels = {
    'sign_in': 'Signed in',
    'new_device': 'Signed in on a new device',
    'device_signed_out': 'Device signed out',
    'signed_out_everywhere': 'Signed out all other devices',
    '2fa_enabled': 'Two-factor turned on',
    '2fa_disabled': 'Two-factor turned off',
    '2fa_failed': 'Wrong two-factor code entered',
    'device_verified': 'Device verified with two-factor',
    'account_verified': 'Email and phone verified',
    'verification_lost': 'Verified status removed',
    'backup_code_used': 'Backup code used',
    'referral_claimed': 'Joined through an invite',
    'referral_credited': 'Invite counted',
    'referral_revoked': 'Invite revoked by an admin',
    'banned': 'Account banned',
    'unbanned': 'Account unbanned',
    'admin_granted': 'Admin access granted',
    'admin_removed': 'Admin access removed',
    'account_deleted': 'Account deleted',
    'admin_deleted_user': 'Deleted a member (admin)',
  };

  Widget _activity(BuildContext context) {
    final c = context.sw;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('securityEvents')
          .where('uid', isEqualTo: _uid)
          .orderBy('at', descending: true)
          .limit(40)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError)
          return Text(
            'Could not load activity.',
            style: TextStyle(color: c.textMuted),
          );
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Text(
            snap.hasData ? 'No activity yet.' : 'Loading…',
            style: TextStyle(color: c.textMuted),
          );
        }
        return Column(
          children: [
            for (final d in docs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _iconFor(d.data()['type'] as String? ?? ''),
                  size: 20,
                  color: c.textMuted,
                ),
                title: Text(
                  _labels[d.data()['type']] ??
                      (d.data()['type'] as String? ?? 'Event'),
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                subtitle: Text(
                  [
                    if ((d.data()['detail'] as String?)?.isNotEmpty == true)
                      d.data()['detail'],
                    if (d.data()['at'] is Timestamp)
                      DateFormat.yMMMd().add_jm().format(
                        (d.data()['at'] as Timestamp).toDate(),
                      ),
                  ].join(' · '),
                  style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
                ),
              ),
            Text(
              'Activity is kept for 90 days.',
              style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted),
            ),
          ],
        );
      },
    );
  }

  IconData _iconFor(String type) {
    if (type.startsWith('2fa') ||
        type.contains('verified') ||
        type.contains('backup'))
      return Icons.lock_rounded;
    if (type.contains('device') || type.contains('sign'))
      return Icons.smartphone_rounded;
    if (type.startsWith('referral')) return Icons.card_giftcard_rounded;
    return Icons.shield_rounded;
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return DateFormat.yMMMd().format(t);
  }
}

class _TwoFactorSetupSheet extends StatefulWidget {
  final ({String secret, String otpauth}) setup;
  final TextEditingController controller;

  const _TwoFactorSetupSheet({required this.setup, required this.controller});

  @override
  State<_TwoFactorSetupSheet> createState() => _TwoFactorSetupSheetState();
}

class _TwoFactorSetupSheetState extends State<_TwoFactorSetupSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await DeviceService.instance.confirmTwoFactorSetup(
        widget.controller.text.trim(),
      );
      if (mounted) Navigator.pop(context, codes);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? 'That code isn\'t right.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final secret = widget.setup.secret
        .replaceAllMapped(RegExp(r'.{4}'), (m) => '${m[0]} ')
        .trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set up two-factor',
              style: AppTheme.display(fontSize: 22, color: c.text),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Open Google Authenticator (or any authenticator app) and scan this code.\n'
              '2. Enter the 6-digit code it shows.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.5,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SwapnioQrCode(data: widget.setup.otpauth, size: 220),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Can\'t scan? Enter this key:',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
            ),
            SelectableText(
              secret,
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(fontSize: 14, color: c.text),
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: widget.setup.secret)),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy key'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: widget.controller,
              keyboardType: TextInputType.number,
              // Keep the "Turn on" button in view above the keyboard.
              scrollPadding: const EdgeInsets.only(bottom: 120),
              maxLength: 6,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.jetBrainsMono(
                fontSize: 24,
                letterSpacing: 8,
                color: c.text,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000000',
                errorText: _error,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 14),
            PillButton(
              label: 'Turn on',
              icon: Icons.lock_rounded,
              loading: _busy,
              onTap: _busy ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}
