import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../Screen/Auth/legal_page.dart';

/// The two checkboxes required before an account can be created: accepting
/// the Terms & Privacy Policy, and confirming the person is 18 or older.
/// Shared between the Signup page (collected before the account exists) and
/// [LegalConsentPage] (collected right after, for the homepage's
/// Google-first flow where there's no earlier moment to ask).
class LegalConsentCheckboxes extends StatefulWidget {
  final bool acceptedTerms;
  final bool ageConfirmed;
  final ValueChanged<bool> onTermsChanged;
  final ValueChanged<bool> onAgeChanged;

  const LegalConsentCheckboxes({
    super.key,
    required this.acceptedTerms,
    required this.ageConfirmed,
    required this.onTermsChanged,
    required this.onAgeChanged,
  });

  @override
  State<LegalConsentCheckboxes> createState() => _LegalConsentCheckboxesState();
}

class _LegalConsentCheckboxesState extends State<LegalConsentCheckboxes> {
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()
    ..onTap = () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LegalPage()),
        );

  @override
  void dispose() {
    _termsTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(
          context,
          value: widget.acceptedTerms,
          onChanged: widget.onTermsChanged,
          // The label contains its own tappable link (to LegalPage), so this
          // row does not also make the label toggle the checkbox - only the
          // checkbox itself does. See the "Terms of Service..." span below.
          toggleOnTapText: false,
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.manrope(fontSize: 13, color: c.text, height: 1.4),
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Terms of Service & Privacy Policy',
                  style: TextStyle(fontWeight: FontWeight.w800, color: c.give),
                  recognizer: _termsTap,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _row(
          context,
          value: widget.ageConfirmed,
          onChanged: widget.onAgeChanged,
          child: Text(
            'I confirm that I am 18 years of age or older',
            style: GoogleFonts.manrope(fontSize: 13, color: c.text, height: 1.4),
          ),
        ),
      ],
    );
  }

  // The checkbox and the label text each own their own tap handler rather
  // than sharing one outer InkWell - nesting a tappable Checkbox inside a
  // tappable ancestor risks both recognizers firing for a single tap on the
  // checkbox itself, toggling the value twice (a no-op that looks broken).
  Widget _row(
    BuildContext context, {
    required bool value,
    required ValueChanged<bool> onChanged,
    required Widget child,
    bool toggleOnTapText = true,
  }) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: c.give,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: toggleOnTapText
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(!value),
                    child: child,
                  )
                : child,
          ),
        ],
      ),
    );
  }
}
