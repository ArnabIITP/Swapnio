import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme.dart';
import '../../ui/legal_consent.dart';
import '../../ui/swapnio_kit.dart';

/// Shown by the root router (main.dart) whenever a signed-in account hasn't
/// recorded terms + age consent yet - the path for the homepage's
/// "Continue with Google" button, which signs in before there's any earlier
/// moment to show a checkbox. Blocks entry to setup/the main app until both
/// boxes are checked and confirmed.
class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({super.key});

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  bool _acceptedTerms = false;
  bool _ageConfirmed = false;
  bool _submitting = false;

  Future<void> _continue() async {
    setState(() => _submitting = true);
    final appState = context.read<AppState>();
    final ok = await appState.acceptLegalTerms();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appState.error.isNotEmpty ? appState.error : 'Please try again.')),
      );
    }
    // On success, AppState.notifyListeners() flips needsLegalConsent false
    // and the root StreamBuilder in main.dart moves on by itself.
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final canContinue = _acceptedTerms && _ageConfirmed;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('One last thing',
                  style: AppTheme.display(fontSize: 30, color: c.text, height: 1.05)),
              const SizedBox(height: 8),
              Text(
                'Before you start swapping skills, please confirm the following.',
                style: GoogleFonts.manrope(fontSize: 14, color: c.textMuted),
              ),
              const SizedBox(height: 28),
              LegalConsentCheckboxes(
                acceptedTerms: _acceptedTerms,
                ageConfirmed: _ageConfirmed,
                onTermsChanged: (v) => setState(() => _acceptedTerms = v),
                onAgeChanged: (v) => setState(() => _ageConfirmed = v),
              ),
              const Spacer(),
              PillButton(
                label: 'Agree & continue',
                icon: Icons.arrow_forward_rounded,
                loading: _submitting,
                onTap: canContinue ? _continue : null,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => context.read<AppState>().signOut(),
                  child: Text(
                    'Cancel and sign out',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w700, color: c.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
