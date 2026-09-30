import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// The metal a badge's rim is struck in - its rarity at a glance.
enum BadgeMetal { bronze, silver, gold, holo }

/// One earnable badge, drawn as a minted medal (see the "Badge System v3 -
/// Minted" board in the design file): a hexagonal metal rim whose metal is
/// the rarity, an enamel core in the family colour, and a ribbon carrying
/// the [value] ("10 h", "4 wk"). `number` replaces the icon for the swap
/// milestones, so 5 / 10 / 25 read at a glance.
class BadgeSpec {
  final String id;
  final String label;
  final String description;
  final IconData? icon;
  final String? number;
  final Color Function(SwapnioColors) accent;

  /// 0 for one-off badges, 1-3 within a family.
  final int tier;

  /// Short figure shown under the icon, e.g. "10 h".
  final String? value;

  /// Coral-to-violet enamel (the Breadth family - many skills).
  final bool gradientRim;

  /// Rim metal for one-off badges; family badges take it from [tier].
  final BadgeMetal? metalOverride;

  /// The server stat this badge is earned from (see functions/sessions.js)
  /// and the value it needs, so a locked badge can show its progress.
  final String? statKey;
  final num? threshold;

  const BadgeSpec({
    required this.id,
    required this.label,
    required this.description,
    required this.accent,
    this.icon,
    this.number,
    this.tier = 0,
    this.value,
    this.gradientRim = false,
    this.statKey,
    this.threshold,
    this.metalOverride,
  });

  /// Bronze, silver, gold by tier; tiers past gold (the 100- and 365-day
  /// streaks) are holographic.
  BadgeMetal get metal =>
      metalOverride ??
      switch (tier) {
        <= 1 => BadgeMetal.bronze,
        2 => BadgeMetal.silver,
        3 => BadgeMetal.gold,
        _ => BadgeMetal.holo,
      };

  /// The very top badge of a family also gets an outer holographic halo.
  bool get halo => tier >= 5;
}

/// Every badge the Cloud Functions can award, in the order they're shown.
final List<BadgeSpec> kBadgeCatalog = [
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
    icon: Icons.task_alt_rounded,
    accent: _success,
  ),
  BadgeSpec(
    id: 'verified',
    label: 'Verified',
    description: 'Verified your email and phone (+50 points)',
    icon: Icons.verified_user_rounded,
    accent: _blue,
    metalOverride: BadgeMetal.silver,
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
    accent: _give,
    metalOverride: BadgeMetal.silver,
  ),
  BadgeSpec(
    id: '25_swaps',
    label: 'Veteran',
    description: 'Completed 25 swaps',
    number: '25',
    accent: _give,
    metalOverride: BadgeMetal.gold,
  ),
  ..._family('teach', 'teachMinutes', Icons.school_rounded, _give, [
    ('10h', 'Chalk Dust', '10 hours taught', '10 h', 600),
    ('50h', 'Lecturer', '50 hours taught', '50 h', 3000),
    ('100h', 'Luminary', '100 hours taught', '100 h', 6000),
  ]),
  ..._family('learn', 'learnMinutes', Icons.menu_book_rounded, _get, [
    ('5h', 'Curious', '5 hours learned', '5 h', 300),
    ('25h', 'Scholar', '25 hours learned', '25 h', 1500),
    ('50h', 'Lifelong', '50 hours learned', '50 h', 3000),
  ]),
  ..._family('streak', 'bestWeekStreak', Icons.event_repeat_rounded, _rose, [
    ('4w', 'On a Roll', 'A session every week for 4 weeks', '4 wk', 4),
    ('12w', 'Habit', 'A session every week for 12 weeks', '12 wk', 12),
    ('26w', 'Unstoppable', 'A session every week for 26 weeks', '26 wk', 26),
  ]),
  ..._family(
    'day_streak',
    'bestDayStreak',
    Icons.local_fire_department_rounded,
    _flame,
    [
      ('3', 'Spark', '3 days in a row on Swapnio', '3 d', 3),
      ('7', 'Week Warrior', '7 days in a row on Swapnio', '7 d', 7),
      ('30', 'On Fire', '30 days in a row on Swapnio', '30 d', 30),
      ('100', 'Blazing', '100 days in a row on Swapnio', '100 d', 100),
      ('365', 'Eternal Flame', '365 days in a row on Swapnio', '365 d', 365),
    ],
  ),
  ..._family(
    'reliable',
    'bestReliabilityStreak',
    Icons.event_available_rounded,
    _success,
    [
      ('10', 'Dependable', '10 sessions in a row, no no-shows', '10', 10),
      ('25', 'Rock Solid', '25 sessions in a row, no no-shows', '25', 25),
      ('50', 'Clockwork', '50 sessions in a row, no no-shows', '50', 50),
    ],
  ),
  ..._family('five_star', 'fiveStarReviews', Icons.star_rounded, _win, [
    ('5', 'Five Star', '5 five-star written reviews', '5', 5),
    ('15', 'Crowd Favourite', '15 five-star written reviews', '15', 15),
    ('30', 'Legend', '30 five-star written reviews', '30', 30),
  ]),
  ..._family('breadth', 'skillsTaught3h', Icons.hub_rounded, _get, [
    ('2', 'Two Trades', '2 skills taught, 3+ hours each', '2', 2),
    ('3', 'Polymath', '3 skills taught, 3+ hours each', '3', 3),
    ('5', 'Renaissance', '5 skills taught, 3+ hours each', '5', 5),
  ], gradient: true),
  ..._family(
    'referral',
    'referralsQualified',
    Icons.diversity_3_rounded,
    _blue,
    [
      ('1', 'Connector', 'Invited a friend who finished a session', '1', 1),
      ('5', 'Ambassador', '5 invited friends finished a session', '5', 5),
      ('15', 'Web Weaver', '15 invited friends finished a session', '15', 15),
    ],
  ),
];

/// One tiered badge family. Ids are `<prefix>_<suffix>` and must match
/// BADGE_FAMILIES in functions/sessions.js (MILESTONES in streaks.js for
/// the daily streak). Tiers past 3 keep the tier-3 rings.
List<BadgeSpec> _family(
  String prefix,
  String statKey,
  IconData icon,
  Color Function(SwapnioColors) accent,
  List<(String, String, String, String, num)> tiers, {
  bool gradient = false,
}) => [
  for (var i = 0; i < tiers.length; i++)
    BadgeSpec(
      id: '${prefix}_${tiers[i].$1}',
      label: tiers[i].$2,
      description: tiers[i].$3,
      value: tiers[i].$4,
      threshold: tiers[i].$5,
      statKey: statKey,
      icon: icon,
      accent: accent,
      tier: i + 1,
      gradientRim: gradient,
    ),
];

/// Human progress for a locked family badge, e.g. "32 of 50 h".
String? badgeProgressLabel(BadgeSpec spec, Map<String, num> stats) {
  final key = spec.statKey;
  final target = spec.threshold;
  if (key == null || target == null) return null;
  final current = stats[key] ?? 0;
  if (key.endsWith('Minutes')) {
    String h(num m) =>
        (m / 60).toStringAsFixed(m % 60 == 0 || m >= 600 ? 0 : 1);
    return '${h(current)} of ${h(target)} h';
  }
  return '${current.toInt()} of ${target.toInt()}';
}

double? badgeProgress(BadgeSpec spec, Map<String, num> stats) {
  final key = spec.statKey;
  final target = spec.threshold;
  if (key == null || target == null || target == 0) return null;
  return ((stats[key] ?? 0) / target).clamp(0.0, 1.0).toDouble();
}

Color _give(SwapnioColors c) => c.give;
Color _get(SwapnioColors c) => c.get;
Color _win(SwapnioColors c) => c.win;
Color _success(SwapnioColors c) => c.success;
Color _flame(SwapnioColors c) => const Color(0xFFFF7A1A);
Color _rose(SwapnioColors c) => const Color(0xFFE8457C);
Color _blue(SwapnioColors c) => const Color(0xFF2F7FE0);

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
Path badgeHexPath(Size size, double radius) => _HexPath.build(size, radius);

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

/// A plain rim-and-core hexagon, for empty-state artwork ([HexTile]).
class _HexPainter extends CustomPainter {
  final Color rim;
  final Color core;

  const _HexPainter({required this.rim, required this.core});

  void _hexAt(
    Canvas canvas,
    Size size,
    double insetFraction,
    double radius,
    Paint paint,
  ) {
    final inset = size.width * insetFraction;
    final ratio = size.height / size.width;
    canvas.save();
    canvas.translate(inset, inset * ratio);
    canvas.drawPath(
      _HexPath.build(
        Size(size.width - inset * 2, size.height - inset * 2 * ratio),
        radius,
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _hexAt(canvas, size, 0, size.width * 0.1, Paint()..color = rim);
    _hexAt(canvas, size, 0.076, size.width * 0.08, Paint()..color = core);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.rim != rim || old.core != core;
}

/// A single badge: a minted medal. Locked badges keep the silhouette in
/// plain pewter, so the set reads as a collection with gaps to fill.
///
/// Laid out on a 128-unit grid matching the design file; [size] is the
/// medal's width, and it is a little taller than wide to fit the ribbon.
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
    final u = size / 128;
    final accent = spec.accent(c);
    // Glyphs are white on the enamel, except on light enamel (lime).
    final light = accent.computeLuminance() > 0.5;
    final ink = earned
        ? (light ? const Color(0xFF17142B) : Colors.white)
        : c.textMuted;
    final glyphShadow = earned
        ? [
            const Shadow(
              color: Color(0x44000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ]
        : null;
    final hasRibbon = spec.value != null;

    Widget glyph;
    if (spec.number != null) {
      glyph = Text(
        spec.number!,
        textAlign: TextAlign.center,
        style: AppTheme.display(
          fontSize: (spec.number!.length > 1 ? 32 : 38) * u,
          color: ink,
        ).copyWith(height: 1, shadows: glyphShadow),
      );
    } else {
      glyph = Icon(
        spec.icon ?? Icons.military_tech_rounded,
        size: (hasRibbon ? 36 : 44) * u,
        color: ink,
        shadows: glyphShadow,
      );
    }

    return Semantics(
      label: '${spec.label}: ${earned ? spec.description : 'not earned yet'}',
      child: SizedBox(
        width: size,
        height: 138 * u,
        child: CustomPaint(
          painter: _MedalPainter(
            metal: spec.metal,
            enamel: accent,
            gradientEnamel: spec.gradientRim,
            halo: spec.halo,
            earned: earned,
            lockedRim: c.border,
            lockedCore: c.surfaceLow,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 20 * u,
                width: 88 * u,
                top: (hasRibbon ? 40 : 18) * u,
                height: hasRibbon ? 38 * u : 94 * u,
                child: Center(child: glyph),
              ),
              if (hasRibbon)
                Positioned(
                  left: 24 * u,
                  top: 104 * u,
                  width: 80 * u,
                  height: 28 * u,
                  child: _Ribbon(
                    text: spec.value!,
                    metal: spec.metal,
                    earned: earned,
                    u: u,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _metals = <BadgeMetal, List<Color>>{
  BadgeMetal.bronze: [
    Color(0xFF6E4220),
    Color(0xFFE7AD74),
    Color(0xFF8A5528),
    Color(0xFFF2C08E),
  ],
  BadgeMetal.silver: [
    Color(0xFF6F7784),
    Color(0xFFFFFFFF),
    Color(0xFF8E97A4),
    Color(0xFFE3E7EC),
  ],
  BadgeMetal.gold: [
    Color(0xFF8A5A00),
    Color(0xFFFFE89A),
    Color(0xFFB7860F),
    Color(0xFFFFD35C),
  ],
};

const _holo = [
  Color(0xFFFF5A36),
  Color(0xFFFFD35C),
  Color(0xFFD4F25A),
  Color(0xFF4CC3FF),
  Color(0xFF8B7DFF),
  Color(0xFFFF7AD9),
  Color(0xFFFF5A36),
];

/// The metal as a gradient: diagonal for struck metal, a sweep of the whole
/// palette for holographic.
Gradient _metalGradient(BadgeMetal metal, {bool reversed = false}) {
  if (metal == BadgeMetal.holo) {
    return SweepGradient(
      colors: _holo,
      transform: GradientRotation(reversed ? math.pi : 0),
    );
  }
  return LinearGradient(
    begin: reversed ? Alignment.bottomRight : Alignment.topLeft,
    end: reversed ? Alignment.topLeft : Alignment.bottomRight,
    colors: _metals[metal]!,
    stops: const [0, 0.33, 0.66, 1],
  );
}

class _Ribbon extends StatelessWidget {
  final String text;
  final BadgeMetal metal;
  final bool earned;
  final double u;

  const _Ribbon({
    required this.text,
    required this.metal,
    required this.earned,
    required this.u,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 4 * u),
      decoration: BoxDecoration(
        color: earned ? null : c.border,
        gradient: earned
            ? (metal == BadgeMetal.holo
                  ? const LinearGradient(colors: _holo)
                  : LinearGradient(colors: _metals[metal]!))
            : null,
        borderRadius: BorderRadius.circular(8 * u),
        boxShadow: earned
            ? [
                BoxShadow(
                  color: const Color(0x4417142B),
                  blurRadius: 6 * u,
                  offset: Offset(0, 3 * u),
                ),
              ]
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: AppTheme.display(
            fontSize: 15 * u,
            color: earned ? const Color(0xFF17142B) : c.textMuted,
          ).copyWith(fontWeight: FontWeight.w800, height: 1.1),
        ),
      ),
    );
  }
}

/// Everything behind the glyph: glow, halo, rim, bevel, enamel, inner line,
/// shine and sparkles - on the design file's 128-unit grid.
class _MedalPainter extends CustomPainter {
  final BadgeMetal metal;
  final Color enamel;
  final bool gradientEnamel;
  final bool halo;
  final bool earned;
  final Color lockedRim;
  final Color lockedCore;

  const _MedalPainter({
    required this.metal,
    required this.enamel,
    required this.gradientEnamel,
    required this.halo,
    required this.earned,
    required this.lockedRim,
    required this.lockedCore,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 128;
    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * u, y * u, w * u, h * u);
    Path hexIn(Rect rect, double radius) =>
        _HexPath.build(rect.size, radius * u).shift(rect.topLeft);

    final rimRect = r(8, 4, 112, 122);
    final rim = hexIn(rimRect, 12);

    if (!earned) {
      canvas.drawPath(rim, Paint()..color = lockedRim);
      canvas.drawPath(
        hexIn(r(20, 17.5, 88, 95), 9),
        Paint()..color = lockedCore,
      );
      return;
    }

    final top = metal == BadgeMetal.gold || metal == BadgeMetal.holo;
    if (top) {
      final glowRect = r(-6, -6, 140, 140);
      final glow = metal == BadgeMetal.holo
          ? const Color(0x558B7DFF)
          : const Color(0x55FFD35C);
      canvas.drawOval(
        glowRect,
        Paint()
          ..shader = RadialGradient(
            colors: [glow, glow.withValues(alpha: 0)],
          ).createShader(glowRect),
      );
    }
    if (halo) {
      final haloRect = r(2, -2, 124, 134);
      canvas.drawPath(
        hexIn(haloRect, 14),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * u
          ..shader = _metalGradient(BadgeMetal.holo).createShader(haloRect),
      );
    }

    // Rim with its drop shadow, then the bevel in the opposite direction.
    canvas.drawPath(
      rim.shift(Offset(0, 8 * u)),
      Paint()
        ..color = const Color(0x4017142B)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * u),
    );
    canvas.drawPath(
      rim,
      Paint()..shader = _metalGradient(metal).createShader(rimRect),
    );
    final bevelRect = r(16, 13, 96, 104);
    canvas.drawPath(
      hexIn(bevelRect, 10),
      Paint()
        ..shader = _metalGradient(
          metal,
          reversed: true,
        ).createShader(bevelRect),
    );

    // Enamel: the family colour, lit from the top left.
    final enamelRect = r(20, 17.5, 88, 95);
    final Gradient enamelGradient = gradientEnamel
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF7A5C), Color(0xFF8B5CF6), Color(0xFF2B1F5C)],
            stops: [0, 0.6, 1],
          )
        : RadialGradient(
            center: const Alignment(-0.3, -0.4),
            radius: 1.0,
            colors: [
              Color.lerp(enamel, Colors.white, 0.45)!,
              enamel,
              const Color(0xFF17142B),
            ],
            stops: const [0, 0.55, 1],
          );
    canvas.drawPath(
      hexIn(enamelRect, 9),
      Paint()..shader = enamelGradient.createShader(enamelRect),
    );

    if (metal != BadgeMetal.bronze) {
      final lineRect = r(28, 26, 72, 78);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * u;
      if (metal == BadgeMetal.holo) {
        line.color = const Color(0xAAFFFFFF);
      } else {
        line.shader = _metalGradient(metal).createShader(lineRect);
      }
      canvas.drawPath(hexIn(lineRect, 7), line);
    }

    // One soft highlight.
    canvas.save();
    canvas.translate(30 * u, 24 * u);
    canvas.rotate(-20 * math.pi / 180);
    final shineRect = Rect.fromLTWH(0, 0, 44 * u, 22 * u);
    canvas.drawOval(
      shineRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
        ).createShader(shineRect),
    );
    canvas.restore();

    if (top) {
      final spark = Paint()
        ..color = metal == BadgeMetal.holo
            ? const Color(0xFF8B7DFF)
            : const Color(0xFFE0A93A);
      for (final (x, y, s) in const [
        (2.0, 22.0, 14.0),
        (108.0, 6.0, 18.0),
        (112.0, 72.0, 11.0),
      ]) {
        canvas.drawPath(
          _sparkle(Offset((x + s / 2) * u, (y + s / 2) * u), s / 2 * u),
          spark,
        );
      }
    }
  }

  /// A four-point sparkle centred on [c].
  static Path _sparkle(Offset c, double r) {
    final k = r * 0.22;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.metal != metal ||
      old.enamel != enamel ||
      old.gradientEnamel != gradientEnamel ||
      old.halo != halo ||
      old.earned != earned ||
      old.lockedRim != lockedRim ||
      old.lockedCore != lockedCore;
}

/// Badge with its name underneath, used in grids.
class SwapBadgeTile extends StatelessWidget {
  final BadgeSpec spec;
  final bool earned;
  final double size;

  /// For a locked family badge: how far along the user is, and as text.
  final double? progress;
  final String? progressLabel;

  const SwapBadgeTile({
    super.key,
    required this.spec,
    this.earned = true,
    this.size = 76,
    this.progress,
    this.progressLabel,
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
        if (!earned && progress != null && progress! > 0) ...[
          const SizedBox(height: 5),
          SizedBox(
            width: size * 0.8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: c.surfaceLow,
                valueColor: AlwaysStoppedAnimation(spec.accent(c)),
              ),
            ),
          ),
          if (progressLabel != null) ...[
            const SizedBox(height: 3),
            Text(
              progressLabel!,
              style: GoogleFonts.manrope(fontSize: 10, color: c.textMuted),
            ),
          ],
        ],
      ],
    );
  }
}

/// The whole set, earned first, with the rest shown locked so there is
/// something visible left to collect.
class BadgeCollection extends StatelessWidget {
  final List<String> earnedIds;

  /// Server stats (Gamification.stats), used to show progress on locked
  /// family badges.
  final Map<String, num> stats;

  const BadgeCollection({
    super.key,
    required this.earnedIds,
    this.stats = const {},
  });

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
        for (final spec in locked)
          SwapBadgeTile(
            spec: spec,
            earned: false,
            progress: badgeProgress(spec, stats),
            progressLabel: badgeProgressLabel(spec, stats),
          ),
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
        child: Center(
          child: Icon(icon, size: size * 0.36, color: tint),
        ),
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
            child: Icon(
              Icons.swap_horiz_rounded,
              size: width * 0.15,
              color: c.win,
            ),
          ),
        ],
      ),
    );
  }
}
