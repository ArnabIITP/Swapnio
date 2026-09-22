import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// One earnable badge. `number` is used instead of an icon for the swap
/// milestones, so 5 / 10 / 25 read at a glance.
class BadgeSpec {
  final String id;
  final String label;
  final String description;
  final IconData? icon;
  final String? number;
  final Color Function(SwapnioColors) accent;

  const BadgeSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.accent,
    this.icon,
    this.number,
  });
}

/// Every badge the Cloud Functions can award, in the order they're shown.
const List<BadgeSpec> kBadgeCatalog = [
  BadgeSpec(
    id: 'welcome',
    label: 'First steps',
    description: 'Joined Swapnio',
    icon: Icons.waving_hand_rounded,
    accent: _get,
  ),
  BadgeSpec(
    id: 'profile_complete',
    label: 'All set',
    description: 'Completed your profile',
    icon: Icons.verified_rounded,
    accent: _success,
  ),
  BadgeSpec(
    id: 'first_message',
    label: 'Icebreaker',
    description: 'Sent your first message',
    icon: Icons.forum_rounded,
    accent: _win,
  ),
  BadgeSpec(
    id: 'first_swap',
    label: 'First swap',
    description: 'Completed one swap session',
    icon: Icons.swap_horiz_rounded,
    accent: _give,
  ),
  BadgeSpec(
    id: '5_swaps',
    label: 'Regular',
    description: 'Completed 5 swaps',
    number: '5',
    accent: _give,
  ),
  BadgeSpec(
    id: '10_swaps',
    label: 'Committed',
    description: 'Completed 10 swaps',
    number: '10',
    accent: _get,
  ),
  BadgeSpec(
    id: '25_swaps',
    label: 'Veteran',
    description: 'Completed 25 swaps',
    number: '25',
    accent: _win,
  ),
];

Color _give(SwapnioColors c) => c.give;
Color _get(SwapnioColors c) => c.get;
Color _win(SwapnioColors c) => c.win;
Color _success(SwapnioColors c) => c.success;

BadgeSpec badgeSpecFor(String id) => kBadgeCatalog.firstWhere(
      (b) => b.id == id,
      orElse: () => BadgeSpec(
        id: id,
        label: id.replaceAll('_', ' '),
        description: 'Earned on Swapnio',
        icon: Icons.military_tech_rounded,
        accent: _get,
      ),
    );

/// Pointy-top hexagon with rounded corners - the shape every badge shares.
class _HexPath {
  static Path build(Size size, double radius) {
    final w = size.width;
    final h = size.height;
    final points = <Offset>[
      Offset(w * 0.5, 0),
      Offset(w, h * 0.25),
      Offset(w, h * 0.75),
      Offset(w * 0.5, h),
      Offset(0, h * 0.75),
      Offset(0, h * 0.25),
    ];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final prev = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];

      final toPrev = prev - current;
      final toNext = next - current;
      final lenPrev = toPrev.distance;
      final lenNext = toNext.distance;
      final r = math.min(radius, math.min(lenPrev, lenNext) / 2);

      final start = current + toPrev / lenPrev * r;
      final end = current + toNext / lenNext * r;

      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.quadraticBezierTo(current.dx, current.dy, end.dx, end.dy);
    }
    path.close();
    return path;
  }
}

class _HexPainter extends CustomPainter {
  final Color rim;
  final Color core;

  const _HexPainter({required this.rim, required this.core});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _HexPath.build(size, size.width * 0.1),
      Paint()..color = rim,
    );
    final inset = size.width * 0.076;
    canvas.save();
    canvas.translate(inset, inset * (size.height / size.width));
    canvas.drawPath(
      _HexPath.build(
        Size(size.width - inset * 2, size.height - inset * 2 * (size.height / size.width)),
        size.width * 0.08,
      ),
      Paint()..color = core,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.rim != rim || old.core != core;
}

/// A single badge mark. Locked badges keep the same silhouette in muted
/// colours, so the set reads as a collection with gaps to fill.
class SwapBadge extends StatelessWidget {
  final BadgeSpec spec;
  final bool earned;
  final double size;

  const SwapBadge({
    super.key,
    required this.spec,
    this.earned = true,
    this.size = 82,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final accent = earned ? spec.accent(c) : c.textMuted;
    final rim = earned ? spec.accent(c) : c.border;
    final core = earned ? c.ink : c.surfaceLow;

    return Semantics(
      label: '${spec.label}: ${earned ? spec.description : 'not earned yet'}',
      child: SizedBox(
        width: size,
        height: size * 1.087,
        child: CustomPaint(
          painter: _HexPainter(rim: rim, core: core),
          child: Center(
            child: spec.number != null
                ? Text(
                    spec.number!,
                    style: AppTheme.display(fontSize: size * 0.35, color: accent),
                  )
                : Icon(spec.icon, size: size * 0.35, color: accent),
          ),
        ),
      ),
    );
  }
}

/// Badge with its name underneath, used in grids.
class SwapBadgeTile extends StatelessWidget {
  final BadgeSpec spec;
  final bool earned;
  final double size;

  const SwapBadgeTile({
    super.key,
    required this.spec,
    this.earned = true,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwapBadge(spec: spec, earned: earned, size: size),
        const SizedBox(height: 8),
        SizedBox(
          width: size + 16,
          child: Text(
            spec.label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: earned ? c.text : c.textMuted,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

/// The whole set, earned first, with the rest shown locked so there is
/// something visible left to collect.
class BadgeCollection extends StatelessWidget {
  final List<String> earnedIds;

  const BadgeCollection({super.key, required this.earnedIds});

  @override
  Widget build(BuildContext context) {
    final earned = <BadgeSpec>[];
    final locked = <BadgeSpec>[];
    for (final spec in kBadgeCatalog) {
      (earnedIds.contains(spec.id) ? earned : locked).add(spec);
    }
    // Badges awarded by a future release still show up, at the end.
    for (final id in earnedIds) {
      if (!kBadgeCatalog.any((b) => b.id == id)) earned.add(badgeSpecFor(id));
    }

    return Wrap(
      spacing: 14,
      runSpacing: 16,
      children: [
        for (final spec in earned) SwapBadgeTile(spec: spec),
        for (final spec in locked) SwapBadgeTile(spec: spec, earned: false),
      ],
    );
  }
}

/// The badge hexagon on its own, used as artwork for empty states so they
/// share the app's geometry instead of showing a generic icon in a box.
class HexTile extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? accent;

  const HexTile({super.key, required this.icon, this.size = 96, this.accent});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final tint = accent ?? c.get;
    return SizedBox(
      width: size,
      height: size * 1.087,
      child: CustomPaint(
        painter: _HexPainter(rim: tint, core: c.ink),
        child: Center(child: Icon(icon, size: size * 0.36, color: tint)),
      ),
    );
  }
}

/// The logo's two halves, pulled apart with the swap knot between them.
/// Used where an empty state is specifically about finding people.
class SwapMotif extends StatelessWidget {
  final double width;

  const SwapMotif({super.key, this.width = 188});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final blockW = width * 0.3;
    final blockH = width * 0.62;
    return SizedBox(
      width: width,
      height: blockH * 1.28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(
              angle: -0.1,
              child: Container(
                width: blockW,
                height: blockH,
                decoration: BoxDecoration(
                  color: c.give,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(blockW * 0.5),
                    right: Radius.circular(blockW * 0.2),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: -0.1,
              child: Container(
                width: blockW,
                height: blockH,
                decoration: BoxDecoration(
                  color: c.get,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(blockW * 0.2),
                    right: Radius.circular(blockW * 0.5),
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: width * 0.26,
            height: width * 0.26,
            decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            child: Icon(Icons.swap_horiz_rounded,
                size: width * 0.15, color: c.win),
          ),
        ],
      ),
    );
  }
}
