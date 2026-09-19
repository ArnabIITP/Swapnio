import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Celebration overlay used at the app's two emotional peaks: a new match,
/// and finishing a swap session.
///
/// People remember the peak and the end of an experience, and both of those
/// moments used to be plain dialogs. Confetti is hand-rolled with a
/// CustomPainter rather than pulled from a package - it's a few dozen lines
/// and avoids another dependency for one effect.
class _ConfettiPiece {
  final double startX;
  final double startY;
  final double horizontalDrift;
  final double rotationSpeed;
  final double size;
  final Color color;
  final double delay;

  const _ConfettiPiece({
    required this.startX,
    required this.startY,
    required this.horizontalDrift,
    required this.rotationSpeed,
    required this.size,
    required this.color,
    required this.delay,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;

  _ConfettiPainter({required this.pieces, required this.progress})
      : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final piece in pieces) {
      // Each piece starts a little later than the last, so the burst reads
      // as a shower rather than a single flat wave.
      final local = ((progress - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;

      // Gravity-ish easing: rises briefly, then accelerates downward.
      final dy = (local * local * 1.6 - local * 0.35) * size.height * 1.3;
      final dx = piece.horizontalDrift * local * size.width * 0.5;
      final opacity = local > 0.75 ? (1 - (local - 0.75) / 0.25).clamp(0.0, 1.0) : 1.0;

      paint.color = piece.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(piece.startX * size.width + dx, piece.startY * size.height + dy);
      canvas.rotate(local * piece.rotationSpeed * math.pi * 2);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.size,
          height: piece.size * 0.55,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class ConfettiOverlay extends StatefulWidget {
  final Widget child;

  const ConfettiOverlay({super.key, required this.child});

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  static const _palette = [
    AppTheme.primaryColor,
    AppTheme.tertiaryColor,
    Color(0xFFE29A63),
    Color(0xFF86A89B),
    Color(0xFFF2C14E),
  ];

  @override
  void initState() {
    super.initState();
    final random = math.Random();
    _pieces = List.generate(40, (index) {
      return _ConfettiPiece(
        startX: random.nextDouble(),
        startY: 0.15 + random.nextDouble() * 0.2,
        horizontalDrift: random.nextDouble() * 2 - 1,
        rotationSpeed: 0.5 + random.nextDouble() * 2,
        size: 7 + random.nextDouble() * 9,
        color: _palette[random.nextInt(_palette.length)],
        delay: random.nextDouble() * 0.35,
      );
    });
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: _ConfettiPainter(
                  pieces: _pieces,
                  progress: _controller.value,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A celebratory modal: elastic scale-in, confetti, heavy haptic.
///
/// [headline] is the payoff line, [message] the supporting detail, and
/// [primaryLabel]/[onPrimary] the single obvious next action - celebrations
/// should point somewhere, not just dismiss.
Future<void> showCelebrationDialog(
  BuildContext context, {
  required IconData icon,
  required String headline,
  required String message,
  required String primaryLabel,
  VoidCallback? onPrimary,
  String? secondaryLabel,
  Widget? extra,
}) {
  HapticFeedback.heavyImpact();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => ConfettiOverlay(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 620),
        curve: Curves.elasticOut,
        builder: (context, value, child) => Transform.scale(
          scale: value.clamp(0.0, 1.2),
          child: child,
        ),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).colorScheme.surface,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, size: 46, color: AppTheme.primaryColor),
                ),
                const SizedBox(height: 16),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(dialogContext).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.75),
                  ),
                ),
                if (extra != null) ...[
                  const SizedBox(height: 16),
                  extra,
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      onPrimary?.call();
                    },
                    child: Text(primaryLabel),
                  ),
                ),
                if (secondaryLabel != null)
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(secondaryLabel),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// A points counter that animates up from its previous value, so earning
/// points reads as something that *happened* rather than a number that was
/// always there.
class AnimatedPointsBadge extends StatelessWidget {
  final int points;
  final String label;

  const AnimatedPointsBadge({
    super.key,
    required this.points,
    this.label = 'points earned',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: points.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars, size: 18, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text(
              '+${value.round()} $label',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
