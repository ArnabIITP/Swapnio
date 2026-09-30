import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/skill_passport_service.dart';
import '../theme.dart';

const Color _masterGold = Color(0xFFC08A1E);

Color tierColor(BuildContext context, SkillTier tier) {
  final c = context.sw;
  switch (tier) {
    case SkillTier.apprentice:
      return c.get;
    case SkillTier.practitioner:
      return c.success;
    case SkillTier.mentor:
      return c.give;
    case SkillTier.master:
      return _masterGold;
  }
}

class _StampRingPainter extends CustomPainter {
  final Color color;

  const _StampRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2 - 2;
    canvas.drawCircle(
      center,
      outer,
      Paint()..color = color.withValues(alpha: 0.06),
    );
    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..color = color.withValues(alpha: 0.9),
    );
    // Dashed inner ring - the perforated edge of a rubber stamp.
    final inner = outer - 7;
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = color.withValues(alpha: 0.7);
    const segments = 36;
    const sweep = 2 * math.pi / segments;
    final rect = Rect.fromCircle(center: center, radius: inner);
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, dash);
    }
  }

  @override
  bool shouldRepaint(_StampRingPainter old) => old.color != color;
}

/// A taught skill rendered as an ink stamp: tier on top, skill in the
/// middle, sessions and rating below, first-taught date at the base. Each
/// stamp gets a small deterministic tilt so a page of them looks hand-made.
class SkillStamp extends StatelessWidget {
  final SkillPassportEntry entry;
  final double size;

  const SkillStamp({super.key, required this.entry, this.size = 150});

  @override
  Widget build(BuildContext context) {
    final color = tierColor(context, entry.tier);
    final tilt = ((entry.skill.hashCode % 13) - 6) * math.pi / 180;
    final since = entry.firstTaughtAt == null
        ? ''
        : 'SINCE ${DateFormat('MMM yyyy').format(entry.firstTaughtAt!).toUpperCase()}';
    // A circle is narrowest near its top and bottom, so each line gets a
    // width that fits the ring at its own height and scales down to fit it,
    // instead of wrapping or poking through the ring.
    Widget line(double widthFactor, Text text) => SizedBox(
      width: size * widthFactor,
      child: FittedBox(fit: BoxFit.scaleDown, child: text),
    );

    // Size the skill name from its longest word so a long word never has to
    // break mid-word ("Visua-lisation"); Fraunces runs ~0.56em per glyph.
    final nameWidth = size * 0.64;
    final longestWord = entry.skill
        .split(RegExp(r'\s+'))
        .fold<int>(1, (m, w) => math.max(m, w.length));
    final nameSize = math.min(size * 0.118, nameWidth / (longestWord * 0.56));

    return Transform.rotate(
      angle: tilt,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _StampRingPainter(color),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                line(
                  0.46,
                  Text(
                    entry.tier.label.toUpperCase(),
                    maxLines: 1,
                    style: AppTheme.label(
                      fontSize: size * 0.058,
                      color: color,
                    ).copyWith(letterSpacing: 1.6),
                  ),
                ),
                SizedBox(height: size * 0.03),
                // The name wraps freely at a fixed width, and the whole block
                // then shrinks to fit its slot - so a long name like "Data
                // Visualisation & Storytelling" is never cut off, just smaller.
                SizedBox(
                  width: nameWidth,
                  height: size * 0.3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: nameWidth,
                      child: Text(
                        entry.skill,
                        textAlign: TextAlign.center,
                        style: AppTheme.display(
                          fontSize: nameSize,
                          color: color,
                        ).copyWith(height: 1.05),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: size * 0.04),
                line(
                  0.58,
                  Text(
                    '${formatTeachingTime(entry.minutesTaught).toUpperCase()} TAUGHT'
                    '${entry.averageRating == null ? '' : ' · ${entry.averageRating!.toStringAsFixed(1)}★'}',
                    maxLines: 1,
                    style: AppTheme.label(
                      fontSize: size * 0.056,
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                if (since.isNotEmpty) ...[
                  SizedBox(height: size * 0.02),
                  line(
                    0.46,
                    Text(
                      since,
                      maxLines: 1,
                      style: AppTheme.label(
                        fontSize: size * 0.048,
                        color: color.withValues(alpha: 0.6),
                      ).copyWith(letterSpacing: 1.1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A faint, empty stamp outline - a slot waiting to be filled, so a new
/// passport shows what's coming rather than a blank space.
class EmptyStampSlot extends StatelessWidget {
  final double size;
  final String? label;

  const EmptyStampSlot({super.key, this.size = 100, this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StampRingPainter(
          c.textMuted.withValues(alpha: label == null ? 0.16 : 0.38),
        ),
        child: label == null
            ? null
            : Center(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.2),
                  child: Text(
                    label!,
                    textAlign: TextAlign.center,
                    style: AppTheme.label(
                      fontSize: size * 0.075,
                      color: c.textMuted,
                    ).copyWith(letterSpacing: 1.2, height: 1.3),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Exported content is always drawn in the light palette, so a shared image
/// looks the same whether the sharer uses light or dark mode.
class LightDocument extends StatelessWidget {
  final WidgetBuilder builder;

  const LightDocument({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.lightTheme,
    child: Builder(builder: builder),
  );
}
