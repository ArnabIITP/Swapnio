import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The verified mark: a member whose email AND phone are both verified
/// (see functions/verification.js). Two pieces:
///  - [VerifiedRing]: an orange-to-violet ring hugging the avatar (the two
///    sides of a swap), drawn inside the avatar's own box so nothing shifts;
///  - [VerifiedSeal]: a scalloped ink rosette with a lime tick, pinned to
///    the ring's lower-right corner, and also used on its own beside names.

const _ink = Color(0xFF17142B);

/// Scalloped rosette with a tick. [size] is its full diameter.
class VerifiedSeal extends StatelessWidget {
  final double size;

  const VerifiedSeal({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Semantics(
      label: 'Verified',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _SealPainter(give: c.give, get: c.get, tick: c.win),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  final Color give;
  final Color get;
  final Color tick;

  const _SealPainter({
    required this.give,
    required this.get,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rosette = _rosette(center, r, 12, 0.13);
    // Gradient rim, then the ink body just inside it.
    canvas.drawPath(
      rosette,
      Paint()
        ..shader = LinearGradient(
          colors: [give, get],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(_rosette(center, r * 0.8, 12, 0.13), Paint()..color = _ink);
    final t = Path()
      ..moveTo(center.dx - r * 0.34, center.dy + r * 0.02)
      ..lineTo(center.dx - r * 0.09, center.dy + r * 0.27)
      ..lineTo(center.dx + r * 0.36, center.dy - r * 0.24);
    canvas.drawPath(
      t,
      Paint()
        ..color = tick
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, r * 0.2)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _rosette(Offset c, double r, int bumps, double depth) {
    final path = Path();
    const steps = 96;
    for (var i = 0; i <= steps; i++) {
      final a = 2 * math.pi * i / steps - math.pi / 2;
      final rr = r * (1 - depth / 2 + depth / 2 * math.cos(bumps * a));
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.give != give || old.get != get || old.tick != tick;
}

/// Wraps an avatar of [size] with corner [radius] (size / 2 for a circle).
/// The ring and a small gap take [ringWidth] + gap from inside the box; the
/// [child] is laid out smaller so the whole thing stays [size].
class VerifiedRing extends StatelessWidget {
  final double size;
  final double radius;
  final Widget Function(double innerSize, double innerRadius) child;
  final bool showSeal;

  const VerifiedRing({
    super.key,
    required this.size,
    required this.radius,
    required this.child,
    this.showSeal = true,
  });

  static double ringWidthFor(double size) => (size * 0.045).clamp(2.0, 4.5);

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final ring = ringWidthFor(size);
    final gap = (ring * 0.8).clamp(1.5, 3.5);
    final inset = ring + gap;
    final inner = size - inset * 2;
    final innerRadius = math.max(0.0, radius - inset);
    final seal = (size * 0.3).clamp(14.0, 30.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingPainter(
                radius: radius,
                width: ring,
                colors: [c.give, c.get, c.give],
              ),
            ),
          ),
          Positioned(left: inset, top: inset, child: child(inner, innerRadius)),
          if (showSeal)
            Positioned(
              right: -seal * 0.12,
              bottom: -seal * 0.12,
              child: Container(
                padding: EdgeInsets.all(seal * 0.08),
                decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle),
                child: VerifiedSeal(size: seal),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double radius;
  final double width;
  final List<Color> colors;

  const _RingPainter({
    required this.radius,
    required this.width,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect,
        Radius.circular(math.max(0, radius - width / 2)),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = SweepGradient(
          colors: colors,
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius || old.width != width || old.colors != colors;
}

/// True when a user document says both email and phone are verified.
bool isVerifiedUser(Map<String, dynamic>? data) => data?['verified'] == true;
