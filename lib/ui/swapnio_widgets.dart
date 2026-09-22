import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

/// Shrinks slightly while pressed so every tap gets an immediate physical
/// response, even before the action it triggers has finished.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The two sides of a swap side by side: vermilion for what you give,
/// violet for what you get, joined by a swap knot.
class SwapSplit extends StatelessWidget {
  final String giveLabel;
  final String giveSkill;
  final String getLabel;
  final String getSkill;
  final Color? knotColor;

  const SwapSplit({
    super.key,
    this.giveLabel = 'YOU GIVE',
    required this.giveSkill,
    this.getLabel = 'YOU GET',
    required this.getSkill,
    this.knotColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    Widget half(String label, String skill, Color color, bool left) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(left ? 16 : 4),
              right: Radius.circular(left ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.label(
                  fontSize: 9,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                skill.isEmpty ? '—' : skill,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        half(giveLabel, giveSkill, c.give, true),
        Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: knotColor ?? c.ink,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.swap_horiz_rounded, size: 17, color: c.win),
        ),
        half(getLabel, getSkill, c.get, false),
      ],
    );
  }
}

/// Small spaced-caps heading used above groups of content.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: AppTheme.label(color: context.sw.textMuted),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Rounded pill tag, tinted with [color].
class TintTag extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const TintTag(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Initial-letter avatar on a colored rounded square, or a photo when one
/// exists.
class SwapAvatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  final Color? color;
  final double? radius;

  const SwapAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 46,
    this.color,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius ?? size * 0.34);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color ?? context.sw.get, borderRadius: r),
      child: Text(
        initial,
        style: AppTheme.display(fontSize: size * 0.4, color: Colors.white),
      ),
    );
    if (photoUrl == null || photoUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: r,
      child: Image.network(
        photoUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// The Swapnio mark: two offset blocks (what you give, what you get) joined
/// by a swap knot. Drawn rather than bitmapped so it stays sharp at any size.
class SwapnioMark extends StatelessWidget {
  final double size;

  const SwapnioMark({super.key, this.size = 112});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final k = size / 512;
    const ink = Color(0xFF17142B);
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(114 * k),
        child: ColoredBox(
          color: ink,
          child: Stack(
            children: [
              Positioned(
                left: 84 * k,
                top: 70 * k,
                child: Container(
                  width: 152 * k,
                  height: 300 * k,
                  decoration: BoxDecoration(
                    color: c.give,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(76 * k),
                      right: Radius.circular(30 * k),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 276 * k,
                top: 142 * k,
                child: Container(
                  width: 152 * k,
                  height: 300 * k,
                  decoration: BoxDecoration(
                    color: c.get,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(30 * k),
                      right: Radius.circular(76 * k),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 194 * k,
                top: 194 * k,
                child: Container(
                  width: 124 * k,
                  height: 124 * k,
                  decoration: const BoxDecoration(color: ink, shape: BoxShape.circle),
                  child: Icon(Icons.swap_horiz_rounded, size: 68 * k, color: c.win),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mark, assembling itself: the two halves slide in from opposite sides
/// (the swap), the knot pops, and the glyph spins into place. The logo
/// performs the idea of the app rather than just appearing.
class AnimatedSwapnioMark extends StatefulWidget {
  final double size;
  final Duration duration;

  const AnimatedSwapnioMark({
    super.key,
    this.size = 118,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<AnimatedSwapnioMark> createState() => _AnimatedSwapnioMarkState();
}

class _AnimatedSwapnioMarkState extends State<AnimatedSwapnioMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  late final Animation<double> _tile = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _blocks = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.15, 0.62, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _knot = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 0.86, curve: Curves.elasticOut),
  );
  late final Animation<double> _glyph = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.62, 1.0, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final size = widget.size;
    final k = size / 512;
    const ink = Color(0xFF17142B);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final travel = size * 0.38;
        return Transform.scale(
          scale: 0.86 + 0.14 * _tile.value,
          child: Opacity(
            opacity: _tile.value.clamp(0.0, 1.0),
            child: SizedBox(
              width: size,
              height: size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(114 * k),
                child: ColoredBox(
                  color: ink,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 84 * k - travel * (1 - _blocks.value),
                        top: 70 * k,
                        child: Opacity(
                          opacity: _blocks.value.clamp(0.0, 1.0),
                          child: Container(
                            width: 152 * k,
                            height: 300 * k,
                            decoration: BoxDecoration(
                              color: c.give,
                              borderRadius: BorderRadius.horizontal(
                                left: Radius.circular(76 * k),
                                right: Radius.circular(30 * k),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 276 * k + travel * (1 - _blocks.value),
                        top: 142 * k,
                        child: Opacity(
                          opacity: _blocks.value.clamp(0.0, 1.0),
                          child: Container(
                            width: 152 * k,
                            height: 300 * k,
                            decoration: BoxDecoration(
                              color: c.get,
                              borderRadius: BorderRadius.horizontal(
                                left: Radius.circular(30 * k),
                                right: Radius.circular(76 * k),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 194 * k,
                        top: 194 * k,
                        child: Transform.scale(
                          scale: _knot.value.clamp(0.0, 1.25),
                          child: Container(
                            width: 124 * k,
                            height: 124 * k,
                            decoration:
                                const BoxDecoration(color: ink, shape: BoxShape.circle),
                            child: Transform.rotate(
                              angle: (1 - _glyph.value) * 3.14159,
                              child: Opacity(
                                opacity: _glyph.value.clamp(0.0, 1.0),
                                child: Icon(Icons.swap_horiz_rounded,
                                    size: 68 * k, color: c.win),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
