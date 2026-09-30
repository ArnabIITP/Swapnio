import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../services/skill_passport_service.dart';
import '../theme.dart';
import 'skill_passport_widgets.dart';
import 'swapnio_badges.dart';
import 'swap_web_graph.dart';
import 'verified_badge.dart';

// The Skill Passport drawn as a physical booklet: a cover, a data page, stamp
// pages and an endorsements page, each a fixed-size sheet of security paper.
// Pages are laid out at a fixed logical size so they read the same in the
// app, in the two-page spread and in every exported image.

/// One passport page, in logical pixels (roughly a real passport's ratio).
const Size kPassportPageSize = Size(300, 420);

const Color _coverColor = Color(0xFF6C5CE7);
const Color _coverDeep = Color(0xFF4A3CC0);
const Color _paper = Color(0xFFF7F2E6);
const Color _paperShade = Color(0xFFE8E1D0);
const Color _ink = Color(0xFF17142B);
const Color _inkMuted = Color(0xFF6E6A7C);

/// Where the page is bound - the fold gets a soft shadow on that side.
enum PassportSpine { none, left, right }

TextStyle _mono(
  double size,
  Color color, {
  double spacing = 1.2,
  FontWeight weight = FontWeight.w600,
}) => GoogleFonts.jetBrainsMono(
  fontSize: size,
  color: color,
  fontWeight: weight,
  letterSpacing: spacing,
  // JetBrains Mono merges "<<" into an arrow glyph by default, which
  // wrecks the machine-readable-zone strip.
  fontFeatures: const [
    FontFeature.disable('liga'),
    FontFeature.disable('calt'),
  ],
);

TextStyle _fieldLabel() =>
    _mono(7.5, _inkMuted, spacing: 1.4, weight: FontWeight.w700);

/// Stable per-string number, for deterministic stamp tilts across runs.
int _seed(String s) => s.codeUnits.fold(7, (a, b) => (a * 31 + b) & 0x7fffffff);

// --------------------------------------------------------------------------
// Paper, frames and the spread
// --------------------------------------------------------------------------

/// Security-print background: fine wavy lines across the sheet plus faint
/// concentric arcs from one corner, like the guilloche on a real passport.
class _PaperPainter extends CustomPainter {
  final Color lines;
  final Color arcs;

  const _PaperPainter({required this.lines, required this.arcs});

  @override
  void paint(Canvas canvas, Size size) {
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = lines;
    for (double y = 8; y < size.height; y += 11) {
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 5) {
        path.lineTo(x, y + 2.2 * math.sin(x / 21 + y / 29));
      }
      canvas.drawPath(path, wave);
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = arcs;
    final origin = Offset(size.width * 1.08, size.height * 1.04);
    for (var r = 70.0; r < size.height * 1.35; r += 15) {
      canvas.drawCircle(origin, r, ring);
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.lines != lines || old.arcs != arcs;
}

/// A blank page of passport paper with an optional folio number and a fold
/// shadow on its bound edge. [child] is laid out inside the page margins.
class PassportPaper extends StatelessWidget {
  final Widget child;
  final PassportSpine spine;
  final int? folio;

  const PassportPaper({
    super.key,
    required this.child,
    this.spine = PassportSpine.none,
    this.folio,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return SizedBox.fromSize(
      size: kPassportPageSize,
      child: ColoredBox(
        color: _paper,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PaperPainter(
                  lines: c.get.withValues(alpha: 0.075),
                  arcs: c.give.withValues(alpha: 0.07),
                ),
              ),
            ),
            if (spine != PassportSpine.none)
              Positioned(
                top: 0,
                bottom: 0,
                left: spine == PassportSpine.left ? 0 : null,
                right: spine == PassportSpine.right ? 0 : null,
                width: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: spine == PassportSpine.left
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      end: spine == PassportSpine.left
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      colors: [
                        _ink.withValues(alpha: 0.13),
                        _ink.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            // Watermark: the booklet's seal, barely there, behind the content.
            Center(
              child: _Seal(
                size: 220,
                rim: 'SWAPNIO ★ SKILL PASSPORT ★ ',
                color: c.get.withValues(alpha: 0.05),
                center: Icon(
                  Icons.swap_horiz_rounded,
                  size: 70,
                  color: c.get.withValues(alpha: 0.05),
                ),
              ),
            ),
            // Microprint along the top edge - reads as a line until you zoom.
            Positioned(
              top: 7,
              left: 16,
              right: 16,
              child: Text(
                'SWAPNIO SKILL PASSPORT ' * 14,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: _mono(3.8, c.get.withValues(alpha: 0.45), spacing: 0.6),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: child,
            ),
            if (folio != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Text(
                  '— $folio —',
                  textAlign: TextAlign.center,
                  style: _mono(
                    7.5,
                    _inkMuted.withValues(alpha: 0.7),
                    spacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single page shown inside the booklet's cover, bound on its left like a
/// right-hand page. The cover itself is shown on its own, unframed.
class PassportFramedPage extends StatelessWidget {
  final Widget page;
  final bool isCover;

  const PassportFramedPage({
    super.key,
    required this.page,
    this.isCover = false,
  });

  static const double _edge = 9;
  static const Size size = Size(300 + _edge + 3, 420 + _edge * 2);

  @override
  Widget build(BuildContext context) {
    const shadow = [BoxShadow(color: _ink, offset: Offset(7, 7))];
    if (isCover) {
      return Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(6),
            right: Radius.circular(18),
          ),
          boxShadow: shadow,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(6),
            right: Radius.circular(18),
          ),
          child: FittedBox(fit: BoxFit.fill, child: page),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(3, _edge, _edge, _edge),
      decoration: const BoxDecoration(
        color: _coverColor,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(6),
          right: Radius.circular(18),
        ),
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(2),
          right: Radius.circular(10),
        ),
        child: page,
      ),
    );
  }
}

/// The booklet held open: two pages side by side inside the cover, with the
/// fold shadow meeting in the middle.
class PassportSpread extends StatelessWidget {
  final Widget left;
  final Widget right;

  const PassportSpread({super.key, required this.left, required this.right});

  static const Size size = Size(300 * 2 + 18, 420 + 18);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size.width,
      height: size.height,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: _coverColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: _ink, offset: Offset(8, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Row(children: [left, right]),
            // The stitched fold between the two pages.
            Positioned(
              top: 0,
              bottom: 0,
              left: 300 - 0.5,
              child: Container(width: 1, color: _ink.withValues(alpha: 0.18)),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Stamps
// --------------------------------------------------------------------------

/// Text set around a circle, starting at the top and spread evenly all the
/// way round - the lettering on a rubber stamp's rim.
class _RimTextPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final double radius;

  const _RimTextPainter({
    required this.text,
    required this.style,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final glyphs = [
      for (final ch in text.split(''))
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    if (glyphs.isEmpty) return;
    final used = glyphs.fold<double>(0, (sum, g) => sum + g.width);
    final gap = math.max(0.0, (2 * math.pi * radius - used) / glyphs.length);
    var angle = -math.pi / 2;
    for (final g in glyphs) {
      final a = angle + g.width / 2 / radius;
      canvas
        ..save()
        ..translate(
          center.dx + radius * math.cos(a),
          center.dy + radius * math.sin(a),
        )
        ..rotate(a + math.pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
      canvas.restore();
      angle += (g.width + gap) / radius;
    }
  }

  @override
  bool shouldRepaint(_RimTextPainter old) =>
      old.text != text || old.style != style || old.radius != radius;
}

class _RimRingPainter extends CustomPainter {
  final Color color;
  final bool dashed;

  /// Badge stamps draw their own hexagon instead of the inner circle.
  final bool inner;

  const _RimRingPainter(this.color, {this.dashed = false, this.inner = true});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 1.5;
    final innerRadius = size.shortestSide * 0.29;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color;
    void ring(double r, double width) {
      paint.strokeWidth = width;
      if (!dashed) {
        canvas.drawCircle(center, r, paint);
        return;
      }
      const segments = 30;
      const sweep = 2 * math.pi / segments;
      final rect = Rect.fromCircle(center: center, radius: r);
      for (var i = 0; i < segments; i++) {
        canvas.drawArc(rect, i * sweep, sweep * 0.5, false, paint);
      }
    }

    ring(outer, 2);
    if (inner) ring(innerRadius, 1.2);
  }

  @override
  bool shouldRepaint(_RimRingPainter old) =>
      old.color != color || old.dashed != dashed || old.inner != inner;
}

/// Uneven ink: specks of paper showing through and a couple of worn arcs on
/// the rim, as a real rubber stamp never inks perfectly. Seeded, so a stamp
/// looks the same every time it's drawn.
class _InkGrainPainter extends CustomPainter {
  final int seed;

  const _InkGrainPainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final speck = Paint()..color = _paper.withValues(alpha: 0.65);
    final count = (size.shortestSide * 1.4).round();
    for (var i = 0; i < count; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final d = radius * math.sqrt(rnd.nextDouble());
      canvas.drawCircle(
        center + Offset(math.cos(a) * d, math.sin(a) * d),
        0.25 + rnd.nextDouble() * 0.55,
        speck,
      );
    }
    final worn = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = _paper.withValues(alpha: 0.6);
    for (var k = 0; k < 2; k++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1.5),
        rnd.nextDouble() * 2 * math.pi,
        0.2 + rnd.nextDouble() * 0.35,
        false,
        worn,
      );
    }
  }

  @override
  bool shouldRepaint(_InkGrainPainter old) => old.seed != seed;
}

Widget _inked(Widget stamp, String key) =>
    CustomPaint(foregroundPainter: _InkGrainPainter(_seed(key)), child: stamp);

/// The badge's own hexagon, drawn as an ink outline inside the stamp's
/// rings - tier 2 adds an inner hexagon, tier 3 a second ring - so a stamp
/// reads as the same badge people see in the app.
class _BadgeInkPainter extends CustomPainter {
  final Color color;
  final int tier;
  final bool dashed;

  const _BadgeInkPainter(this.color, {this.tier = 0, this.dashed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color;
    void hex(double width, double stroke) {
      final w = size.width * width;
      final h = w * 1.087;
      canvas.save();
      canvas.translate((size.width - w) / 2, (size.height - h) / 2);
      canvas.drawPath(
        badgeHexPath(Size(w, h), w * 0.1),
        paint..strokeWidth = stroke,
      );
      canvas.restore();
    }

    if (dashed) {
      hex(0.44, 1.2);
      return;
    }
    hex(0.46, size.width * 0.028);
    if (tier >= 2) hex(0.34, size.width * 0.014);
    if (tier >= 3) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.shortestSide * 0.315,
        paint..strokeWidth = size.width * 0.012,
      );
    }
  }

  @override
  bool shouldRepaint(_BadgeInkPainter old) =>
      old.color != color || old.tier != tier || old.dashed != dashed;
}

/// A badge as a passport stamp: its real art (hexagon, icon, figure) inked
/// inside a rubber-stamp ring with its name around the rim. Locked badges
/// are a faint dashed outline.
class PassportBadgeStamp extends StatelessWidget {
  final BadgeSpec spec;
  final bool earned;
  final double size;

  const PassportBadgeStamp({
    super.key,
    required this.spec,
    required this.earned,
    this.size = 80,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    var color = earned ? spec.accent(c) : _inkMuted.withValues(alpha: 0.3);
    // Lime is the brand's highlight colour but disappears on cream paper,
    // so lime stamps are inked in black instead.
    if (earned && color == c.win) color = _ink;
    final tilt = earned ? ((_seed(spec.id) % 15) - 7) * math.pi / 180 : 0.0;

    Widget glyph;
    if (spec.value != null) {
      glyph = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: size * 0.12, color: color),
          Text(
            spec.value!,
            maxLines: 1,
            style: AppTheme.display(
              fontSize: size * 0.105,
              color: color,
            ).copyWith(height: 1.05),
          ),
        ],
      );
    } else if (spec.number != null) {
      glyph = Text(
        spec.number!,
        style: AppTheme.display(
          fontSize: size * 0.17,
          color: color,
        ).copyWith(height: 1),
      );
    } else {
      glyph = Icon(
        spec.icon ?? Icons.military_tech_rounded,
        size: size * 0.17,
        color: color,
      );
    }

    final stamp = Transform.rotate(
      angle: tilt,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RimRingPainter(color, dashed: !earned, inner: false),
          foregroundPainter: earned
              ? _RimTextPainter(
                  text: '${spec.label.toUpperCase()} ★ SWAPNIO ★ ',
                  style: GoogleFonts.manrope(
                    fontSize: size * 0.078,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                  radius: size * 0.405,
                )
              : null,
          child: CustomPaint(
            painter: _BadgeInkPainter(color, tier: spec.tier, dashed: !earned),
            child: Center(
              child: SizedBox(
                width: size * 0.3,
                child: FittedBox(fit: BoxFit.scaleDown, child: glyph),
              ),
            ),
          ),
        ),
      ),
    );
    return earned ? _inked(stamp, spec.id) : stamp;
  }
}

class _StampRow {
  final double height;
  final Widget child;

  const _StampRow(this.height, this.child);
}

Widget _slots(int count, List<Widget> items) => Row(
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    for (var i = 0; i < count; i++)
      Expanded(child: Center(child: i < items.length ? items[i] : null)),
  ],
);

Widget _groupLabel(String text, Color accent) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Row(
    children: [
      Container(width: 10, height: 2, color: accent),
      const SizedBox(width: 6),
      Text(text, style: _fieldLabel()),
    ],
  ),
);

/// Lays out every stamp and splits them across as many pages as they need:
/// taught skills (large), then earned milestones, then the milestones still
/// to earn as small faint outlines. Each group's label travels with its
/// first row, so a label is never stranded at the bottom of a page.
List<List<_StampRow>> _stampPageRows(SkillPassport p, SwapnioColors c) {
  const labelHeight = 20.0;
  const skillSize = 110.0;
  const skillRow = 118.0;
  const earnedSize = 76.0;
  const earnedRow = 82.0;
  const lockedSize = 40.0;
  const lockedRow = 46.0;
  final rows = <_StampRow>[];

  void group(String label, Color accent, List<_StampRow> groupRows) {
    for (var i = 0; i < groupRows.length; i++) {
      final row = groupRows[i];
      rows.add(
        i > 0
            ? row
            : _StampRow(
                labelHeight + row.height,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: labelHeight,
                      child: _groupLabel(label, accent),
                    ),
                    SizedBox(height: row.height, child: row.child),
                  ],
                ),
              ),
      );
    }
  }

  group('TEACHING STAMPS', c.give, [
    if (p.skills.isEmpty)
      _StampRow(
        skillRow,
        _slots(2, const [
          EmptyStampSlot(size: skillSize, label: 'YOUR FIRST\nTEACHING\nSTAMP'),
          EmptyStampSlot(size: skillSize),
        ]),
      ),
    for (var i = 0; i < p.skills.length; i += 2)
      _StampRow(
        skillRow,
        // A lone stamp sits centred rather than in the left half.
        _slots(p.skills.length == 1 ? 1 : 2, [
          for (final s in p.skills.skip(i).take(2))
            _inked(SkillStamp(entry: s, size: skillSize), s.skill),
        ]),
      ),
  ]);

  final earnedIds = p.badgeIds.toSet();
  final earned = [for (final id in earnedIds) badgeSpecFor(id)];
  // "Still to earn" shows the next goal in each family (its lowest locked
  // tier) plus any starter badge still missing - not every locked badge.
  // One row at most: family goals first, then missing starter badges.
  final seenFamilies = <String>{};
  final familyGoals = <BadgeSpec>[];
  final starterGoals = <BadgeSpec>[];
  for (final spec in kBadgeCatalog) {
    if (earnedIds.contains(spec.id)) continue;
    final family = spec.statKey;
    if (family == null) {
      starterGoals.add(spec);
    } else if (seenFamilies.add(family)) {
      familyGoals.add(spec);
    }
  }
  final locked = [...familyGoals, ...starterGoals].take(6).toList();
  group('MILESTONES', c.get, [
    for (var i = 0; i < earned.length; i += 3)
      _StampRow(
        earnedRow,
        _slots(3, [
          for (final b in earned.skip(i).take(3))
            PassportBadgeStamp(spec: b, earned: true, size: earnedSize),
        ]),
      ),
  ]);
  group('STILL TO EARN', _inkMuted, [
    for (var i = 0; i < locked.length; i += 6)
      _StampRow(
        lockedRow,
        _slots(6, [
          for (final b in locked.skip(i).take(6))
            PassportBadgeStamp(spec: b, earned: false, size: lockedSize),
        ]),
      ),
  ]);

  // Page body height left after the margins and the page header.
  const budget = 343.0;
  final pages = <List<_StampRow>>[[]];
  var used = 0.0;
  for (final row in rows) {
    if (used + row.height > budget && pages.last.isNotEmpty) {
      pages.add([]);
      used = 0;
    }
    pages.last.add(row);
    used += row.height;
  }
  return pages;
}

Widget _pageHeader(String title, Widget trailing) => Column(
  children: [
    Row(
      children: [
        Text(
          title,
          style: _mono(10, _ink, spacing: 1.6, weight: FontWeight.w800),
        ),
        const Spacer(),
        trailing,
      ],
    ),
    const SizedBox(height: 7),
    Container(height: 1, color: _ink.withValues(alpha: 0.75)),
  ],
);

// --------------------------------------------------------------------------
// Pages
// --------------------------------------------------------------------------

/// A circle of lettering with a mark in the middle - the embossed seal on
/// the cover and the "verified" seal over the photo.
class _Seal extends StatelessWidget {
  final double size;
  final String rim;
  final Color color;
  final Widget center;

  const _Seal({
    required this.size,
    required this.rim,
    required this.color,
    required this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RimRingPainter(color),
        foregroundPainter: _RimTextPainter(
          text: rim,
          style: GoogleFonts.manrope(
            fontSize: size * 0.078,
            fontWeight: FontWeight.w800,
            color: color,
          ),
          radius: size * 0.385,
        ),
        child: Center(child: center),
      ),
    );
  }
}

class _StitchPainter extends CustomPainter {
  final Color color;

  const _StitchPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (double y = 0; y < size.height; y += 9) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, math.min(y + 5, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StitchPainter old) => old.color != color;
}

class PassportCoverPage extends StatelessWidget {
  final SkillPassport passport;

  const PassportCoverPage({super.key, required this.passport});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final foil = c.win;
    return SizedBox.fromSize(
      size: kPassportPageSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_coverColor, _coverDeep],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PaperPainter(
                  lines: Colors.white.withValues(alpha: 0.035),
                  arcs: foil.withValues(alpha: 0.07),
                ),
              ),
            ),
            // Embossed inner border.
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: foil.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            // Stitched binding down the spine.
            Positioned(
              left: 7,
              top: 8,
              bottom: 8,
              width: 2,
              child: CustomPaint(
                painter: _StitchPainter(foil.withValues(alpha: 0.5)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 34, 24, 26),
              child: Column(
                children: [
                  Text(
                    'SWAPNIO',
                    style: AppTheme.label(
                      fontSize: 13,
                      color: foil,
                    ).copyWith(letterSpacing: 7),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'SKILL SWAP NETWORK',
                    style: AppTheme.label(
                      fontSize: 7.5,
                      color: foil.withValues(alpha: 0.7),
                    ).copyWith(letterSpacing: 3),
                  ),
                  const Spacer(),
                  _Seal(
                    size: 132,
                    rim: 'TEACH ★ LEARN ★ SWAP ★ VERIFY ★ ',
                    color: foil,
                    center: Icon(
                      Icons.swap_horiz_rounded,
                      size: 42,
                      color: foil,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'SKILL\nPASSPORT',
                    textAlign: TextAlign.center,
                    style: AppTheme.display(
                      fontSize: 36,
                      color: foil,
                    ).copyWith(height: 1.05, letterSpacing: 3),
                  ),
                  const SizedBox(height: 20),
                  // The e-passport chip symbol.
                  Container(
                    width: 30,
                    height: 20,
                    decoration: BoxDecoration(
                      border: Border.all(color: foil, width: 1.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: foil, width: 1.4),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      passport.displayName.toUpperCase(),
                      maxLines: 1,
                      style: AppTheme.label(
                        fontSize: 9,
                        color: foil.withValues(alpha: 0.8),
                      ).copyWith(letterSpacing: 2.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Passport photo: the real one when there is one, otherwise a halftone
/// block with initials.
class _PassportPhoto extends StatelessWidget {
  final SkillPassport passport;

  const _PassportPhoto({required this.passport});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final initials = passport.displayName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final fallback = ColoredBox(
      color: c.give,
      child: CustomPaint(
        painter: _HalftonePainter(_ink.withValues(alpha: 0.22)),
        child: Center(
          child: Text(
            initials.isEmpty ? 'YOU' : initials,
            style: AppTheme.display(fontSize: 26, color: Colors.white),
          ),
        ),
      ),
    );
    final url = passport.photoUrl;
    final photo = Container(
      width: 84,
      height: 104,
      decoration: BoxDecoration(border: Border.all(color: _ink, width: 1.6)),
      child: url == null || url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
    if (!passport.verified) return photo;
    // Verified holders get the seal pressed over the photo's corner.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        photo,
        const Positioned(right: -9, bottom: -9, child: VerifiedSeal(size: 28)),
      ],
    );
  }
}

class _HalftonePainter extends CustomPainter {
  final Color color;

  const _HalftonePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = color;
    for (double y = 4; y < size.height; y += 7) {
      for (double x = (y ~/ 7).isEven ? 4 : 7.5; x < size.width; x += 7) {
        canvas.drawCircle(Offset(x, y), 1.3, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_HalftonePainter old) => old.color != color;
}

Widget _field(String label, Widget value) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(label, style: _fieldLabel()),
    const SizedBox(height: 2),
    value,
  ],
);

/// A value set in the display face that wraps to at most [lines] lines and
/// only then shrinks, rather than truncating. It takes just the height it
/// needs, so a one-line value doesn't leave a gap under it.
Widget _fitted(String text, TextStyle style, {int lines = 2}) => LayoutBuilder(
  builder: (context, constraints) {
    final s = style.copyWith(height: 1.1);
    final painter = TextPainter(
      text: TextSpan(text: text, style: s),
      textDirection: TextDirection.ltr,
      maxLines: lines,
    )..layout(maxWidth: constraints.maxWidth);
    if (!painter.didExceedMaxLines) return Text(text, style: s);
    return SizedBox(
      width: constraints.maxWidth,
      height: (style.fontSize ?? 14) * 1.1 * lines + 2,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Text(text, style: s),
        ),
      ),
    );
  },
);

/// The identity page: photo, name, what they teach and learn, level and the
/// machine-readable zone.
class PassportDataPage extends StatelessWidget {
  final SkillPassport passport;
  final PassportSpine spine;

  const PassportDataPage({
    super.key,
    required this.passport,
    this.spine = PassportSpine.left,
  });

  String _mrz() {
    String clean(String s) => s
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '<')
        .replaceAll(RegExp(r'^<+|<+$'), '');
    final line1 = 'P<SWP<${clean(passport.displayName)}'.padRight(36, '<');
    final line2 =
        '${passport.passportNumber.replaceAll('-', '')}'
                '<<${passport.totalVerifiedSessions.toString().padLeft(3, '0')}'
                '<<LV${passport.gamificationLevel}<<TEACH<LEARN'
            .padRight(36, '<');
    return '${line1.substring(0, 36)}\n${line2.substring(0, 36)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final teaches = passport.skills.map((s) => s.skill).take(3).join(', ');
    final learning = passport.learned.map((s) => s.skill).take(3).join(', ');
    final level = passport.gamificationLevel;
    final intoLevel = (passport.gamificationPoints - (level - 1) * 100).clamp(
      0,
      100,
    );
    return PassportPaper(
      spine: spine,
      folio: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(
            'SKILL PASSPORT',
            Text('SWP', style: _mono(10, c.get, weight: FontWeight.w800)),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                height: 116,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _PassportPhoto(passport: passport),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Opacity(
                          opacity: 0.85,
                          child: _Seal(
                            size: 54,
                            rim: 'VERIFIED ★ SWAPNIO ★ ',
                            color: c.success,
                            center: Icon(
                              Icons.check_rounded,
                              size: 15,
                              color: c.success,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(
                      'NAME',
                      _fitted(
                        passport.displayName,
                        AppTheme.display(fontSize: 18, color: _ink),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _field(
                      'TEACHES',
                      _fitted(
                        teaches.isEmpty ? 'First stamp pending' : teaches,
                        AppTheme.display(
                          fontSize: 14.5,
                          color: teaches.isEmpty ? _inkMuted : c.give,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _field(
                      'LEARNING',
                      _fitted(
                        learning.isEmpty ? '—' : learning,
                        AppTheme.display(
                          fontSize: 14.5,
                          color: learning.isEmpty ? _inkMuted : c.get,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text("HOLDER'S SIGNATURE", style: _fieldLabel()),
          Container(
            height: 30,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: _ink.withValues(alpha: 0.35)),
              ),
            ),
            alignment: Alignment.bottomLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Text(
                // Signed the way people sign, not in capitals.
                passport.displayName
                    .split(RegExp(r'\s+'))
                    .where((w) => w.isNotEmpty)
                    .map(
                      (w) => w[0].toUpperCase() + w.substring(1).toLowerCase(),
                    )
                    .join(' '),
                maxLines: 1,
                style: GoogleFonts.getFont(
                  'Mrs Saint Delafield',
                  fontSize: 30,
                  height: 1.2,
                  color: const Color(0xFF26358C),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border.all(color: c.get, width: 1.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '$level',
                      style: AppTheme.display(
                        fontSize: 40,
                        color: c.get,
                      ).copyWith(height: 1),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LEVEL',
                          style: _mono(
                            8,
                            c.get,
                            spacing: 1.6,
                            weight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${passport.gamificationPoints} PTS',
                          style: _mono(14, _ink, weight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Ghost image: a faint second copy of the photo, as on
                    // a real passport's data page.
                    Opacity(
                      opacity: 0.22,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0, 0, 0, 1, 0,
                        ]),
                        child: SizedBox(
                          width: 34,
                          height: 42,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: _PassportPhoto(passport: passport),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      border: Border.all(color: c.get, width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: intoLevel / 100,
                      child: ColoredBox(color: c.get),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${passport.pointsToNextLevel.clamp(0, 100)} PTS TO LEVEL ${level + 1}',
                  style: _mono(8, _inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 11,
                child: _field(
                  'PASSPORT NO.',
                  Text(
                    passport.passportNumber,
                    style: _mono(9.5, _ink, spacing: 0.4),
                  ),
                ),
              ),
              Expanded(
                flex: 9,
                child: _field(
                  'ISSUED',
                  Text(
                    DateFormat(
                      'dd MMM yy',
                    ).format(DateTime.now()).toUpperCase(),
                    style: _mono(9.5, _ink, spacing: 0.4),
                  ),
                ),
              ),
              Expanded(
                flex: 8,
                child: _field(
                  'MEMBER',
                  Text(
                    passport.memberSince == null
                        ? '—'
                        : DateFormat(
                            'MMM yy',
                          ).format(passport.memberSince!).toUpperCase(),
                    style: _mono(9.5, _ink, spacing: 0.4),
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _mrz(),
              style: _mono(
                8.6,
                _ink.withValues(alpha: 0.55),
                spacing: 1.2,
              ).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// One page of stamps. [pageIndex] picks which slice of the stamp layout
/// this page shows; see [passportStampPageCount].
class PassportStampsPage extends StatelessWidget {
  final SkillPassport passport;
  final int pageIndex;
  final int folio;
  final PassportSpine spine;

  const PassportStampsPage({
    super.key,
    required this.passport,
    this.pageIndex = 0,
    this.folio = 2,
    this.spine = PassportSpine.left,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final pages = _stampPageRows(passport, c);
    final rows = pages[pageIndex.clamp(0, pages.length - 1)];
    final earned = passport.skills.length + passport.badgeIds.toSet().length;
    return PassportPaper(
      spine: spine,
      folio: folio,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeader(
            pageIndex == 0 ? 'STAMPS' : 'STAMPS · CONT.',
            Text(
              '$earned EARNED',
              style: _mono(10, c.get, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows)
            SizedBox(height: row.height, child: row.child),
        ],
      ),
    );
  }
}

int passportStampPageCount(SkillPassport passport) =>
    _stampPageRows(passport, SwapnioColors.light).length;

/// What swap partners say: headline numbers, feedback tags, the best written
/// review and recent activity.
class PassportEndorsementsPage extends StatelessWidget {
  final SkillPassport passport;
  final int folio;
  final PassportSpine spine;

  const PassportEndorsementsPage({
    super.key,
    required this.passport,
    required this.folio,
    this.spine = PassportSpine.left,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final review = passport.topReview;
    final tags = passport.topTags.take(4).toList();
    return PassportPaper(
      spine: spine,
      folio: folio,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeader(
            'ENDORSEMENTS',
            Row(
              children: [
                Icon(Icons.verified_rounded, size: 11, color: c.success),
                const SizedBox(width: 3),
                Text(
                  'VERIFIED',
                  style: _mono(9, c.success, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PassportStatLedger(passport: passport),
          if (passport.goalRate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.flag_rounded, size: 12, color: c.success),
                const SizedBox(width: 4),
                Text(
                  '${(passport.goalRate! * 100).round()}% of sessions hit their goal',
                  style: GoogleFonts.manrope(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  '  · ${passport.goalSample} rated',
                  style: GoogleFonts.manrope(fontSize: 10, color: _inkMuted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text('PARTNERS SAY', style: _fieldLabel()),
          const SizedBox(height: 6),
          SizedBox(
            height: 52,
            child: ClipRect(
              child: tags.isEmpty
                  ? Text(
                      'Feedback tags appear after your first rated session.',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: _inkMuted,
                      ),
                    )
                  : Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (var i = 0; i < tags.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: i == 0 ? c.win : Colors.transparent,
                              border: Border.all(color: _ink, width: 1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              tags[i].value > 1
                                  ? '${tags[i].key} ×${tags[i].value}'
                                  : tags[i].key,
                              style: GoogleFonts.manrope(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: c.give, width: 3)),
            ),
            child: review == null
                ? Text(
                    'No written reviews yet. When a swap partner writes one after a '
                    'session, the best one is quoted here.',
                    style: GoogleFonts.manrope(
                      fontSize: 10.5,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: _inkMuted,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${review.text}”',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '— ${review.reviewerFirstName}${review.skill.isEmpty ? '' : ', on ${review.skill}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                          ),
                          for (var i = 0; i < 5; i++)
                            Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: i < review.rating.round()
                                  ? c.give
                                  : _paperShade,
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          const Spacer(),
          Text('LAST 12 WEEKS', style: _fieldLabel()),
          const SizedBox(height: 6),
          _MiniHeatmap(passport: passport),
          const SizedBox(height: 10),
          Text(
            'Built from verified swaps and peer ratings.',
            style: GoogleFonts.manrope(fontSize: 8.5, color: _inkMuted),
          ),
        ],
      ),
    );
  }
}

/// The four headline numbers in a ruled ledger row.
class PassportStatLedger extends StatelessWidget {
  final SkillPassport passport;

  const PassportStatLedger({super.key, required this.passport});

  @override
  Widget build(BuildContext context) {
    final rel = passport.reliability;
    final stats = <(String, String)>[
      (formatTeachingTime(passport.totalTeachMinutes), 'TIME\nTAUGHT'),
      ('${passport.peopleTaught}', 'PEOPLE\nTAUGHT'),
      (
        passport.overallRating == null
            ? '—'
            : '${passport.overallRating!.toStringAsFixed(1)}★',
        'PEER\nRATING',
      ),
      (rel.total == 0 ? 'New' : '${rel.showUpRate}%', 'SHOW-UP\nRATE'),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _ink, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                Container(width: 1, color: _ink.withValues(alpha: 0.25)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 2,
                  ),
                  child: Column(
                    children: [
                      // Fixed height: inside IntrinsicHeight a scaled-down
                      // FittedBox reports its unscaled height, which made
                      // the whole row tall when a value ("15 min") had to
                      // shrink.
                      SizedBox(
                        height: 22,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            stats[i].$1,
                            style: AppTheme.display(
                              fontSize: 19,
                              color: _ink,
                            ).copyWith(height: 1.1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stats[i].$2,
                        textAlign: TextAlign.center,
                        style: _mono(
                          6.8,
                          _inkMuted,
                          spacing: 0.8,
                          weight: FontWeight.w700,
                        ).copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniHeatmap extends StatelessWidget {
  final SkillPassport passport;

  const _MiniHeatmap({required this.passport});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final days = passport.dailyActivity;
    const weeks = SkillPassport.activityDays ~/ 7;
    const cell = 8.0;
    const gap = 2.5;
    Color colorFor(int n) {
      if (n <= 0) return _paperShade;
      if (n == 1) return c.give.withValues(alpha: 0.4);
      if (n == 2) return c.give.withValues(alpha: 0.7);
      return c.give;
    }

    final count = passport.sessionsInActivityWindow;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : gap),
            child: Column(
              children: [
                for (var d = 0; d < 7; d++)
                  Container(
                    width: cell,
                    height: cell,
                    margin: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                    decoration: BoxDecoration(
                      color: colorFor(days[w * 7 + d]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: AppTheme.display(
                  fontSize: 22,
                  color: _ink,
                ).copyWith(height: 1),
              ),
              Text(
                'session${count == 1 ? '' : 's'} in 12 weeks',
                style: GoogleFonts.manrope(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              if (passport.firstSwapAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  'First swap ${DateFormat('MMM yyyy').format(passport.firstSwapAt!)}',
                  style: GoogleFonts.manrope(fontSize: 9, color: _inkMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------------
// Feed card
// --------------------------------------------------------------------------

/// A single 4:5 image for feeds (1080 x 1350 at 3x): the passport's cover
/// colour framing one sheet of passport paper with the holder, their best
/// stamps and the headline numbers.
class PassportFeedCard extends StatelessWidget {
  final SkillPassport passport;

  static const Size size = Size(360, 450);

  const PassportFeedCard({super.key, required this.passport});

  List<Widget> _stamps() {
    final skills = passport.skills.take(2).toList();
    final badges = passport.badgeIds
        .toSet()
        .map(badgeSpecFor)
        .take(3 - skills.length)
        .toList();
    if (skills.isEmpty && badges.isEmpty) {
      return const [
        EmptyStampSlot(size: 104, label: 'YOUR FIRST\nTEACHING\nSTAMP'),
      ];
    }
    return [
      for (final s in skills)
        _inked(
          SkillStamp(entry: s, size: skills.length == 1 ? 120 : 104),
          s.skill,
        ),
      for (final b in badges)
        PassportBadgeStamp(spec: b, earned: true, size: 78),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final foil = c.win;
    final teaches = passport.skills.map((s) => s.skill).take(3).join(', ');
    final learning = passport.learned.map((s) => s.skill).take(2).join(', ');
    final stamps = _stamps();
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_coverColor, _coverDeep],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _PaperPainter(
                  lines: Colors.white.withValues(alpha: 0.035),
                  arcs: foil.withValues(alpha: 0.07),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'SKILL PASSPORT',
                        style: AppTheme.label(
                          fontSize: 11,
                          color: foil,
                        ).copyWith(letterSpacing: 3),
                      ),
                      const Spacer(),
                      Text(
                        'SWAPNIO',
                        style: AppTheme.label(
                          fontSize: 9,
                          color: foil.withValues(alpha: 0.75),
                        ).copyWith(letterSpacing: 3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ColoredBox(
                        color: _paper,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _PaperPainter(
                                  lines: c.get.withValues(alpha: 0.075),
                                  arcs: c.give.withValues(alpha: 0.07),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 76,
                                        height: 90,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            SizedBox(
                                              width: 68,
                                              height: 84,
                                              child: FittedBox(
                                                child: _PassportPhoto(
                                                  passport: passport,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              right: -6,
                                              bottom: -4,
                                              child: Transform.rotate(
                                                angle: -0.2,
                                                child: _Seal(
                                                  size: 42,
                                                  rim: 'VERIFIED ★ SWAPNIO ★ ',
                                                  color: c.success,
                                                  center: Icon(
                                                    Icons.check_rounded,
                                                    size: 12,
                                                    color: c.success,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _field(
                                              'NAME',
                                              _fitted(
                                                passport.displayName,
                                                AppTheme.display(
                                                  fontSize: 19,
                                                  color: _ink,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            _field(
                                              'TEACHES',
                                              _fitted(
                                                teaches.isEmpty
                                                    ? 'First stamp pending'
                                                    : teaches,
                                                AppTheme.display(
                                                  fontSize: 14,
                                                  color: teaches.isEmpty
                                                      ? _inkMuted
                                                      : c.give,
                                                ),
                                              ),
                                            ),
                                            if (learning.isNotEmpty) ...[
                                              const SizedBox(height: 6),
                                              _field(
                                                'LEARNING',
                                                _fitted(
                                                  learning,
                                                  AppTheme.display(
                                                    fontSize: 14,
                                                    color: c.get,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (
                                              var i = 0;
                                              i < stamps.length;
                                              i++
                                            ) ...[
                                              if (i > 0)
                                                const SizedBox(width: 6),
                                              stamps[i],
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  PassportStatLedger(passport: passport),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        passport.passportNumber,
                        style: _mono(
                          10,
                          foil,
                          spacing: 1.4,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.verified_rounded, size: 11, color: foil),
                      const SizedBox(width: 4),
                      Text(
                        'Verified from real sessions',
                        style: GoogleFonts.manrope(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: foil,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Assembled booklet
// --------------------------------------------------------------------------

/// Every page of a passport in reading order, with a short name for each.
List<(String, Widget)> passportPages(
  SkillPassport passport, {
  PassportSpine spine = PassportSpine.left,
}) {
  final stampPages = passportStampPageCount(passport);
  return [
    ('Cover', PassportCoverPage(passport: passport)),
    ('Identity', PassportDataPage(passport: passport, spine: spine)),
    for (var i = 0; i < stampPages; i++)
      (
        stampPages == 1 ? 'Stamps' : 'Stamps ${i + 1}',
        PassportStampsPage(
          passport: passport,
          pageIndex: i,
          folio: 2 + i,
          spine: spine,
        ),
      ),
    (
      'Endorsements',
      PassportEndorsementsPage(
        passport: passport,
        folio: 2 + stampPages,
        spine: spine,
      ),
    ),
    if (passport.web != null)
      (
        'Swap Web',
        PassportWebPage(
          web: SwapWebData.fromMap(passport.web!),
          folio: 3 + stampPages,
          spine: spine,
        ),
      ),
  ];
}

/// The holder's Swap Web: everyone they've taught or learned from, and where
/// those skills went next, drawn from verified sessions.
class PassportWebPage extends StatelessWidget {
  final SwapWebData web;
  final int folio;
  final PassportSpine spine;

  const PassportWebPage({
    super.key,
    required this.web,
    required this.folio,
    this.spine = PassportSpine.left,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return PassportPaper(
      spine: spine,
      folio: folio,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeader(
            'SWAP WEB',
            Text(
              '${web.people} ${web.people == 1 ? 'PERSON' : 'PEOPLE'}',
              style: _mono(10, c.get, weight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: web.people == 0
                ? Center(
                    child: Text(
                      'The web grows with every verified session.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: _inkMuted,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) => SwapWebCanvas(
                      data: web,
                      size: Size(box.maxWidth, box.maxHeight),
                      showNames: false,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatWebMinutes(web.taughtMinutes)} TAUGHT · ${formatWebMinutes(web.learnedMinutes)} LEARNED',
            textAlign: TextAlign.center,
            style: _mono(8.5, _ink, spacing: 1.2, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Solid = mutual swap. Dashed = one way, arrow from teacher to learner.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 8.5, color: _inkMuted),
          ),
        ],
      ),
    );
  }
}

/// Swipeable booklet for the app: one page at a time, turning with a slight
/// 3D fold. Always drawn in the light palette, like the exports.
class SkillPassportBooklet extends StatefulWidget {
  final SkillPassport passport;

  const SkillPassportBooklet({super.key, required this.passport});

  @override
  State<SkillPassportBooklet> createState() => _SkillPassportBookletState();
}

class _SkillPassportBookletState extends State<SkillPassportBooklet> {
  final PageController _controller = PageController(initialPage: 1);
  int _page = 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The hint under the dots follows the app theme; the pages never do.
    final c = context.sw;
    return LightDocument(
      builder: (_) {
        final list = passportPages(widget.passport);
        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: list.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    var delta = 0.0;
                    if (_controller.hasClients &&
                        _controller.position.haveDimensions) {
                      delta = (_controller.page ?? _page.toDouble()) - i;
                    }
                    return Transform(
                      alignment: delta > 0
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(delta.clamp(-1.0, 1.0) * 0.55),
                      child: child,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 26, 14),
                    child: FittedBox(
                      child: PassportFramedPage(
                        page: list[i].$2,
                        isCover: i == 0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < list.length; i++)
                  GestureDetector(
                    onTap: () => _controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? _coverColor
                            : _inkMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Builder(
              builder: (_) => Text(
                '${list[_page.clamp(0, list.length - 1)].$1} · swipe to turn the page',
                style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted),
              ),
            ),
          ],
        );
      },
    );
  }
}
