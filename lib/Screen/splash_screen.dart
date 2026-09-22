/*
 * Swapnio - A Flutter-based skill swapping platform.
 * Copyright (C) 2026 Arnab Das and Manab Kumar Barman
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../ui/swapnio_widgets.dart';

/// Animated splash screen shown on app launch.
///
/// Sequence:
///   0–800 ms  → Logo fades in + scales up (elastic curve)
///   400–1200 ms → App name slides up + fades in
///   800–1600 ms → Tagline fades in
///   ~2500 ms  → Entire screen fades out, then [onFinished] is called.
class SplashScreen extends StatefulWidget {
  /// Called once the splash animation completes so the caller can navigate away.
  final VoidCallback onFinished;

  const SplashScreen({Key? key, required this.onFinished}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────────
  late final AnimationController _logoController;
  late final AnimationController _nameController;
  late final AnimationController _taglineController;
  late final AnimationController _exitController;

  // ── Animations ───────────────────────────────────────────────────────
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _nameSlide;
  late final Animation<double> _nameOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();

    // Make status bar transparent during splash.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    // ── 1. Logo ────────────────────────────────────────────────────────
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // ── 2. App name ────────────────────────────────────────────────────
    _nameController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _nameSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _nameController, curve: Curves.easeOutCubic),
    );
    _nameOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _nameController, curve: Curves.easeIn),
    );

    // ── 3. Tagline ─────────────────────────────────────────────────────
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _taglineController, curve: Curves.easeIn),
    );

    // ── 4. Exit fade ───────────────────────────────────────────────────
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeInCubic),
    );

    // ── Kick off the staggered sequence ────────────────────────────────
    _runSequence();
  }

  Future<void> _runSequence() async {
    // Stage 1 – logo
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));

    // Stage 2 – name
    _nameController.forward();
    await Future.delayed(const Duration(milliseconds: 400));

    // Stage 3 – tagline
    _taglineController.forward();
    await Future.delayed(const Duration(milliseconds: 1200));

    // Stage 4 – exit
    await _exitController.forward();
    widget.onFinished();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _nameController.dispose();
    _taglineController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = context.sw.bg;
    final textColor = context.sw.text;

    return FadeTransition(
      opacity: _exitOpacity,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo ───────────────────────────────────────────────
              FadeTransition(
                opacity: _logoOpacity,
                child: const AnimatedSwapnioMark(size: 122),
              ),

              const SizedBox(height: 28),

              // ── App name ───────────────────────────────────────────
              SlideTransition(
                position: _nameSlide,
                child: FadeTransition(
                  opacity: _nameOpacity,
                  child: Text(
                    'Swapnio',
                    style: GoogleFonts.fraunces(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Tagline ────────────────────────────────────────────
              FadeTransition(
                opacity: _taglineOpacity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Teach',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.sw.give,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.swap_horiz_rounded, size: 17, color: context.sw.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Learn',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: context.sw.get,
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
