import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/device_service.dart';
import '../theme.dart';
import 'swapnio_kit.dart';
import 'swapnio_widgets.dart';

/// Full-screen lock shown on a device that hasn't passed two-factor yet:
/// a 6-digit authenticator code, or one of the 8-character backup codes.
class TwoFactorGate extends StatefulWidget {
  final VoidCallback onVerified;

  const TwoFactorGate({super.key, required this.onVerified});

  @override
  State<TwoFactorGate> createState() => _TwoFactorGateState();
}

class _TwoFactorGateState extends State<TwoFactorGate> {
  final _code = TextEditingController();
  bool _backup = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DeviceService.instance.verifyThisDevice(_code.text.trim());
      widget.onVerified();
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? 'Could not check that code.');
    } catch (_) {
      setState(
        () => _error = 'Could not check that code. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SwapnioMark(size: 64)),
              const SizedBox(height: 24),
              Text(
                'Confirm it\'s you',
                textAlign: TextAlign.center,
                style: AppTheme.display(fontSize: 28, color: c.text),
              ),
              const SizedBox(height: 8),
              Text(
                _backup
                    ? 'Enter one of your 8-character backup codes. Each one works once.'
                    : 'Two-factor is on for this account. Enter the 6-digit code from your authenticator app.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _code,
                autofocus: true,
                // Keep the Verify button in view above the keyboard.
                scrollPadding: const EdgeInsets.only(bottom: 120),
                textAlign: TextAlign.center,
                keyboardType: _backup
                    ? TextInputType.text
                    : TextInputType.number,
                textCapitalization: TextCapitalization.characters,
                maxLength: _backup ? 8 : 6,
                inputFormatters: [
                  _backup
                      ? FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        )
                      : FilteringTextInputFormatter.digitsOnly,
                ],
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 26,
                  letterSpacing: 8,
                  color: c.text,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: _backup ? 'XXXXXXXX' : '000000',
                  errorText: _error,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 20),
              PillButton(
                label: 'Verify',
                icon: Icons.lock_open_rounded,
                loading: _busy,
                onTap: _busy ? null : _verify,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _backup = !_backup;
                  _code.clear();
                  _error = null;
                }),
                child: Text(
                  _backup
                      ? 'Use authenticator code instead'
                      : 'Use a backup code',
                ),
              ),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: Text('Sign out', style: TextStyle(color: c.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
