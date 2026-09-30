import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/user_data_provider.dart';
import '../../theme.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import 'verification_provider.dart';

/// Get verified: email + phone. Both are needed for the verified ring (see
/// functions/verification.js for what the server does with it).
class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => VerificationProvider(),
      child: const _VerificationBody(),
    );
  }
}

class _VerificationBody extends StatefulWidget {
  const _VerificationBody();

  @override
  State<_VerificationBody> createState() => _VerificationBodyState();
}

class _VerificationBodyState extends State<_VerificationBody>
    with WidgetsBindingObserver {
  bool _changingPhone = false;
  bool _checkingEmail = false;
  bool? _wasVerified;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Catch up with anything verified elsewhere (e.g. the email link).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the mail app after tapping the link.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final provider = context.read<VerificationProvider>();
    await provider.reload();
    _celebrateIfNew(provider);
  }

  void _celebrateIfNew(VerificationProvider provider) {
    final v = provider.verification;
    if (!mounted || v == null) return;
    final now = v.emailVerified && v.phoneVerified;
    if (_wasVerified == false && now) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.lastRewarded
                ? "You're verified! +50 points and the Verified badge."
                : "You're verified!",
          ),
        ),
      );
    }
    _wasVerified = now;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final provider = context.watch<VerificationProvider>();
    final v = provider.verification;
    final user = context.watch<UserDataProvider>().userData ?? const {};
    final name = (user['name'] ?? '').toString();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    if (v != null) _wasVerified ??= v.emailVerified && v.phoneVerified;
    final done = v != null && v.emailVerified && v.phoneVerified;
    final stepsLeft = v == null
        ? 2
        : (v.emailVerified ? 0 : 1) + (v.phoneVerified ? 0 : 1);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: v == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const SwapHeader(
                    title: 'Get verified',
                    subtitle: 'Email and phone - both, to earn the ring',
                  ),
                  const SizedBox(height: 18),
                  _hero(c, name, user['photoUrl'] as String?, done, stepsLeft),
                  const SizedBox(height: 22),
                  Text('STEPS', style: AppTheme.label(color: c.textMuted)),
                  const SizedBox(height: 10),
                  _StepCard(
                    number: 1,
                    title: 'Email',
                    done: v.emailVerified,
                    detail: v.emailVerified
                        ? email
                        : 'We\'ll email a link to $email. Tap it, then come back.',
                    child: v.emailVerified
                        ? null
                        : Row(
                            children: [
                              Expanded(
                                child: PillButton(
                                  label: 'Send link',
                                  icon: Icons.mail_outline_rounded,
                                  onTap: () async {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    final sent = await provider
                                        .sendEmailVerification();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          sent
                                              ? 'Link sent to $email.'
                                              : 'Could not send the link. Try again in a minute.',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                onPressed: _checkingEmail
                                    ? null
                                    : () async {
                                        setState(() => _checkingEmail = true);
                                        await _refresh();
                                        if (mounted) {
                                          setState(
                                            () => _checkingEmail = false,
                                          );
                                        }
                                      },
                                child: Text(
                                  _checkingEmail ? 'Checking…' : 'I tapped it',
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  _StepCard(
                    number: 2,
                    title: 'Phone',
                    done: v.phoneVerified,
                    detail: v.phoneVerified
                        ? (provider.maskedPhone ?? 'Verified')
                        : 'We\'ll text a 6-digit code to your number.',
                    trailing: v.phoneVerified && !_changingPhone
                        ? TextButton(
                            onPressed: () =>
                                setState(() => _changingPhone = true),
                            child: const Text('Change'),
                          )
                        : null,
                    child: !v.phoneVerified || _changingPhone
                        ? _PhoneForm(
                            onCancel: v.phoneVerified
                                ? () {
                                    provider.resetPhoneVerification();
                                    setState(() => _changingPhone = false);
                                  }
                                : null,
                            onDone: () {
                              setState(() => _changingPhone = false);
                              _celebrateIfNew(provider);
                            },
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: c.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'One number can verify only one Swapnio account. Your '
                          'number is never shown to anyone - people only see the ring.',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            height: 1.45,
                            color: c.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _hero(
    SwapnioColors c,
    String name,
    String? photoUrl,
    bool done,
    int stepsLeft,
  ) {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      radius: 26,
      child: Column(
        children: [
          Row(
            children: [
              // Unverified: a faint preview of the ring they'll get.
              Opacity(
                opacity: done ? 1 : 0.45,
                child: SwapAvatar(
                  name: name.isEmpty ? '?' : name,
                  photoUrl: photoUrl,
                  size: 76,
                  radius: 26,
                  verified: true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? 'You\'re verified' : 'Earn the verified ring',
                      style: AppTheme.display(fontSize: 21, color: c.text),
                    ),
                    const SizedBox(height: 6),
                    done
                        ? TintTag(
                            'Email + phone',
                            color: c.success,
                            icon: Icons.check_rounded,
                          )
                        : TintTag(
                            '$stepsLeft step${stepsLeft == 1 ? '' : 's'} left',
                            color: c.give,
                          ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _perk(
            c,
            Icons.auto_awesome_rounded,
            'The ring on your photo, everywhere',
          ),
          _perk(c, Icons.trending_up_rounded, 'Shown earlier in Discover'),
          _perk(
            c,
            Icons.filter_alt_outlined,
            'Included when people filter "Verified only"',
          ),
          _perk(
            c,
            Icons.military_tech_rounded,
            '+50 points, a badge and a passport seal',
          ),
        ],
      ),
    );
  }

  Widget _perk(SwapnioColors c, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Icon(icon, size: 17, color: c.get),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.text,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final bool done;
  final String detail;
  final Widget? child;
  final Widget? trailing;

  const _StepCard({
    required this.number,
    required this.title,
    required this.done,
    required this.detail,
    this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? c.success : c.surfaceLow,
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Colors.white,
                      )
                    : Text(
                        '$number',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      done ? '$title verified' : title,
                      style: GoogleFonts.manrope(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.4,
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
  }
}

/// Number entry, then the SMS code. Numbers without a "+" get +91.
class _PhoneForm extends StatefulWidget {
  final VoidCallback? onCancel;
  final VoidCallback onDone;

  const _PhoneForm({this.onCancel, required this.onDone});

  @override
  State<_PhoneForm> createState() => _PhoneFormState();
}

class _PhoneFormState extends State<_PhoneForm> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _e164 {
    final raw = _phone.text.replaceAll(RegExp(r'[\s\-()]'), '');
    if (raw.startsWith('+')) return raw;
    return '+91${raw.replaceFirst(RegExp(r'^0+'), '')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final p = context.watch<VerificationProvider>();
    final error = p.verificationError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!p.codeSent) ...[
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-()]')),
            ],
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '98765 43210',
              prefixText: _phone.text.startsWith('+') ? null : '+91 ',
              helperText: 'Outside India? Start with + and your country code.',
              helperMaxLines: 2,
              errorText: error,
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Send code',
            icon: Icons.sms_outlined,
            loading: p.phoneVerificationInProgress,
            onTap:
                p.phoneVerificationInProgress || _phone.text.trim().length < 6
                ? null
                : () => p.startPhoneVerification(_e164),
          ),
        ] else ...[
          Text(
            'Code sent to $_e164',
            style: GoogleFonts.manrope(fontSize: 12.5, color: c.textMuted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autofocus: true,
            textAlign: TextAlign.center,
            scrollPadding: const EdgeInsets.only(bottom: 120),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: GoogleFonts.jetBrainsMono(
              fontSize: 24,
              letterSpacing: 8,
              color: c.text,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              errorText: error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          PillButton(
            label: 'Verify',
            icon: Icons.check_rounded,
            loading: p.phoneVerificationInProgress,
            onTap: p.phoneVerificationInProgress
                ? null
                : () async {
                    if (_code.text.trim().length != 6) return;
                    final ok = await p.verifyOTP(_code.text.trim());
                    if (ok) widget.onDone();
                  },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: p.phoneVerificationInProgress
                    ? null
                    : () {
                        _code.clear();
                        p.resetPhoneVerification();
                      },
                child: const Text('Different number'),
              ),
              TextButton(
                onPressed: p.phoneVerificationInProgress
                    ? null
                    : () => p.startPhoneVerification(_e164),
                child: const Text('Resend code'),
              ),
            ],
          ),
        ],
        if (widget.onCancel != null)
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}
