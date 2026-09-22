import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:swapnio/Screen/Auth/signup_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme.dart';
import '../../providers/app_state.dart';
import '../../ui/fade_slide_in.dart';
import '../../ui/swapnio_widgets.dart';
import 'login_page.dart';

class StarterPage extends StatefulWidget {
  const StarterPage({Key? key}) : super(key: key);

  @override
  State<StarterPage> createState() => _StarterPageState();
}

class _StarterPageState extends State<StarterPage> {
  bool _isGoogleLoading = false;

  // Public aggregate written by the onUserCreated Cloud Function - the only
  // activity signal a signed-out visitor is allowed to read.
  late final Future<DocumentSnapshot> _publicStats = FirebaseFirestore.instance
      .collection('stats')
      .doc('public')
      .get();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Future<void> _onGoogleContinuePressed() async {
    final appState = context.read<AppState>();
    setState(() => _isGoogleLoading = true);

    final success = await appState.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
    if (!success && appState.error.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(appState.error)));
    }
  }

  /// Social proof, gated: "Join 14 people" reads as an empty room, which is
  /// worse than saying nothing - so it only appears once the number is
  /// genuinely persuasive.
  Widget _buildSocialProof() {
    final c = context.sw;
    return FutureBuilder<DocumentSnapshot>(
      future: _publicStats,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final count = (data?['userCount'] as num?)?.toInt() ?? 0;
        if (count < 100) {
          return Text(
            'Swap skills one-to-one. No money, just people.',
            style: GoogleFonts.manrope(fontSize: 14, color: c.textMuted),
          );
        }
        return Text(
          'Join $count people swapping skills',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: c.give,
          ),
        );
      },
    );
  }

  /// A scatter of real skills, in the give/get colours, so the idea of the
  /// app lands before a single word is read.
  Widget _buildSkillCloud(double width) {
    final c = context.sw;
    final chips = <(String, Color, Color, double, double, double)>[
      ('Guitar', c.give, Colors.white, 0.02, 12, -0.14),
      ('Python', c.get, Colors.white, 0.50, 0, 0.10),
      ('Figma', c.win, c.onWin, 0.10, 78, 0.07),
      ('Spanish', c.get, Colors.white, 0.53, 72, -0.09),
      ('Excel', c.give, Colors.white, 0.38, 140, -0.05),
      ('Photography', c.surface, c.text, 0.01, 162, 0.12),
      ('Public speaking', c.ink, Colors.white, 0.34, 212, -0.07),
    ];
    return SizedBox(
      height: 268,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < chips.length; i++)
            Positioned(
              left: chips[i].$4 * width,
              top: chips[i].$5,
              child: FadeSlideIn(
                delay: Duration(milliseconds: 60 * i),
                child: Transform.rotate(
                  angle: chips[i].$6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: chips[i].$2,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Text(
                      chips[i].$1,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: chips[i].$3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headline(String text, Color color) => Text(
        text,
        style: AppTheme.display(fontSize: 38, color: color, height: 1.06),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final width = math.min(MediaQuery.of(context).size.width, 520.0) - 48;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSkillCloud(width),
              const SizedBox(height: 8),
              FadeSlideIn(
                delay: const Duration(milliseconds: 420),
                child: Text(
                  'SWAPNIO',
                  style: AppTheme.label(fontSize: 12.5, color: c.textMuted),
                ),
              ),
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: const Duration(milliseconds: 470),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _headline('Teach what', c.text),
                    _headline('you know.', c.give),
                    _headline('Learn what', c.text),
                    _headline('you want.', c.get),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 540),
                child: _buildSocialProof(),
              ),
              const SizedBox(height: 26),
              FadeSlideIn(
                delay: const Duration(milliseconds: 600),
                child: Column(
                  children: [
                    Pressable(
                      onTap: _isGoogleLoading ? null : _onGoogleContinuePressed,
                      child: Container(
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.cta,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _isGoogleLoading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation<Color>(c.onCta),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SvgPicture.asset('assets/icons/google.svg', height: 20.0),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Continue with Google',
                                    style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: c.onCta,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Pressable(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
                      child: Container(
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mail_outline_rounded, size: 19, color: c.text),
                            const SizedBox(width: 10),
                            Text(
                              'Log in with email',
                              style: GoogleFonts.manrope(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: c.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupPage()),
                      ),
                      child: Text(
                        'New here? Create an account',
                        style: GoogleFonts.manrope(
                          color: c.give,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
