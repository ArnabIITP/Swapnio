import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'package:swapnio/providers/app_state.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import '../../ui/fade_slide_in.dart';
import '../../ui/legal_consent.dart';
import '../User/Bottomnav.dart';
import 'login_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({Key? key}) : super(key: key);

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController =
      TextEditingController(); // Added for confirm password

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true; // Added for confirm password visibility
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _acceptedTerms = false;
  bool _ageConfirmed = false;

  bool get _canSubmit => _acceptedTerms && _ageConfirmed;

  @override
  void initState() {
    super.initState();
    // Set status bar to be visible on the light background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            Brightness.dark, // Changed to dark for light background
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose(); // Dispose new controller
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Terms & Privacy Policy and confirm your age.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final success = await appState.signUp(
        _emailController.text.trim(),
        _passwordController.text,
        _nameController.text.trim(),
        acceptedTerms: _acceptedTerms,
        ageConfirmed: _ageConfirmed,
      );

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appState.error),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  /// Google signup, gated the same way the email form is: the consent
  /// checkboxes must already be checked before this can be tapped. Consent
  /// is written as part of the same Google sign-in call (`preAcceptedLegal:
  /// true`) so there's never a window where the account exists without it.
  ///
  /// Navigates explicitly on success rather than relying on the root
  /// auth-state router in main.dart: this page is *pushed* on top of
  /// Startpage, and changing what main.dart's router would build doesn't
  /// pop already-pushed routes out of the way (the same reason
  /// [LoginPage]'s email sign-in pushes BottomNavPage itself instead of
  /// waiting for the root to react).
  Future<void> _signUpWithGoogle() async {
    if (!_canSubmit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the Terms & Privacy Policy and confirm your age.'),
        ),
      );
      return;
    }
    setState(() => _isGoogleLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final success = await appState.signInWithGoogle(preAcceptedLegal: true);
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const BottomNavPage()),
      );
    } else if (appState.error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(appState.error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: FadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _backButton(),
                  const SizedBox(height: 22),
                  Text('Start', style: AppTheme.display(fontSize: 38, color: c.text, height: 1.05)),
                  Text('swapping.',
                      style: AppTheme.display(fontSize: 38, color: c.give, height: 1.05)),
                  const SizedBox(height: 8),
                  Text(
                    'One skill to teach is all you need to begin.',
                    style: GoogleFonts.manrope(fontSize: 14, color: c.textMuted),
                  ),
                  const SizedBox(height: 30),
                  _labelled(
                    'Full name',
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      cursorColor: c.get,
                      style: GoogleFonts.manrope(color: c.text),
                      decoration: _decoration('Your name', Icons.person_outline_rounded),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                  ),
                  _labelled(
                    'Email address',
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      cursorColor: c.get,
                      style: GoogleFonts.manrope(color: c.text),
                      decoration: _decoration('you@example.com', Icons.mail_outline_rounded),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                  ),
                  _labelled(
                    'Password',
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      cursorColor: c.get,
                      style: GoogleFonts.manrope(color: c.text),
                      decoration: _decoration(
                        'At least 6 characters',
                        Icons.lock_outline_rounded,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 19,
                            color: c.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                  ),
                  _labelled(
                    'Confirm password',
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      cursorColor: c.get,
                      style: GoogleFonts.manrope(color: c.text),
                      decoration: _decoration(
                        'Repeat your password',
                        Icons.lock_reset_rounded,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 19,
                            color: c.textMuted,
                          ),
                          onPressed: () => setState(
                              () => _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                  ),
                  LegalConsentCheckboxes(
                    acceptedTerms: _acceptedTerms,
                    ageConfirmed: _ageConfirmed,
                    onTermsChanged: (v) => setState(() => _acceptedTerms = v),
                    onAgeChanged: (v) => setState(() => _ageConfirmed = v),
                  ),
                  const SizedBox(height: 18),
                  PillButton(
                    label: 'Create account',
                    icon: Icons.arrow_forward_rounded,
                    loading: _isLoading,
                    onTap: _canSubmit ? _signUp : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider(color: c.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or',
                            style: GoogleFonts.manrope(fontSize: 12.5, color: c.textMuted)),
                      ),
                      Expanded(child: Divider(color: c.border)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Pressable(
                    onTap: (_canSubmit && !_isGoogleLoading) ? _signUpWithGoogle : null,
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _canSubmit ? c.surface : c.surfaceLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: c.border),
                      ),
                      child: _isGoogleLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(c.text),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Opacity(
                                  opacity: _canSubmit ? 1 : 0.5,
                                  child: SvgPicture.asset('assets/icons/google.svg', height: 18),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Sign up with Google',
                                  style: GoogleFonts.manrope(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: _canSubmit ? c.text : c.textMuted,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Already have an account? ',
                            style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Text(
                            'Log in',
                            style: GoogleFonts.manrope(
                                fontSize: 13.5, fontWeight: FontWeight.w800, color: c.give),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _labelled(String label, Widget field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: AppTheme.label(fontSize: 10, color: context.sw.textMuted)),
          const SizedBox(height: 7),
          field,
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) {
    final c = context.sw;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 19, color: c.textMuted),
      suffixIcon: suffix,
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        borderSide: BorderSide(color: c.get, width: 1.8),
      ),
    );
  }

  Widget _backButton() {
    final c = context.sw;
    return Pressable(
      onTap: () => Navigator.of(context).maybePop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
        child: Icon(Icons.arrow_back_rounded, size: 20, color: c.text, semanticLabel: 'Back'),
      ),
    );
  }
}
