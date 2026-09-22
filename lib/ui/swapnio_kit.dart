import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import 'swapnio_badges.dart';
import 'swapnio_widgets.dart';

/// Screen header used in place of AppBar: a Fraunces title, optional back
/// arrow and one trailing action, sitting on the page background.
class SwapHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final Widget? action;
  final double titleSize;

  const SwapHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.action,
    this.titleSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          if (showBack) ...[
            Pressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                child: Icon(Icons.arrow_back_rounded,
                    size: 20, color: c.text, semanticLabel: 'Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(fontSize: titleSize, color: c.text),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 12.5, color: c.textMuted),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Plain rounded surface panel - the app's default container.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.color,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.sw.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Pressable(scale: 0.985, onTap: onTap, child: card);
  }
}

/// Icon tile + title + subtitle row, used for settings and list entries.
class SlimRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? accent;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  const SlimRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent,
    this.onTap,
    this.trailing,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final tint = danger ? const Color(0xFFD64545) : (accent ?? c.get);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        radius: 18,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: danger ? tint : c.text,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Full-width action button in the app's CTA style.
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final Color? foreground;
  final bool loading;

  const PillButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.color,
    this.foreground,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final bg = color ?? c.cta;
    final fg = foreground ?? (color == null ? c.onCta : Colors.white);
    return Pressable(
      onTap: loading ? null : onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (onTap == null && !loading) ? c.surfaceLow : bg,
          borderRadius: BorderRadius.circular(18),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18, color: fg),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Empty states name the next action instead of dead-ending.
class SwapEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows the two-halves logo motif instead of the hexagon - for empty
  /// states that are about finding people rather than collecting things.
  final bool useSwapMotif;
  final Color? accent;

  const SwapEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.useSwapMotif = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (useSwapMotif)
              const SwapMotif(width: 176)
            else
              HexTile(icon: icon, size: 92, accent: accent),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center,
                style: AppTheme.display(fontSize: 22, color: c.text)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              SizedBox(width: 220, child: PillButton(label: actionLabel!, onTap: onAction)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section heading + optional trailing widget.
class KitSection extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const KitSection(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label.toUpperCase(),
                style: AppTheme.label(color: context.sw.textMuted)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A number that counts up to its value on first paint, and animates again
/// whenever it changes. Movement draws the eye to progress that would
/// otherwise just sit there.
class CountUpText extends StatelessWidget {
  final num value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final int decimals;
  final Duration duration;

  const CountUpText({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.decimals = 0,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        '$prefix${v.toStringAsFixed(decimals)}$suffix',
        style: style,
        maxLines: 1,
      ),
    );
  }
}

/// Shimmering placeholder block in the app's own colours.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.sw.surfaceLow,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps skeleton content in a brand-tinted shimmer. Placeholders shaped like
/// the content that is coming read as "almost there" rather than "waiting".
class SwapSkeleton extends StatefulWidget {
  final Widget child;

  const SwapSkeleton({super.key, required this.child});

  @override
  State<SwapSkeleton> createState() => _SwapSkeletonState();
}

class _SwapSkeletonState extends State<SwapSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          final slide = _controller.value * 2.4 - 0.7;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [c.surfaceLow, c.surface, c.surfaceLow],
            stops: [
              (slide - 0.25).clamp(0.0, 1.0),
              slide.clamp(0.0, 1.0),
              (slide + 0.25).clamp(0.0, 1.0),
            ],
          ).createShader(bounds);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Placeholder that matches the shape of a Discover card.
class DiscoverCardSkeleton extends StatelessWidget {
  const DiscoverCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Center(
      child: SwapSkeleton(
        child: Container(
          width: size.width * 0.88,
          height: size.height * 0.60,
          decoration: BoxDecoration(
            color: context.sw.surface,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(height: 232, radius: 30),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(width: 170, height: 24, radius: 10),
                    const SizedBox(height: 14),
                    Row(
                      children: const [
                        SkeletonBox(width: 110, height: 26, radius: 12),
                        SizedBox(width: 8),
                        SkeletonBox(width: 120, height: 26, radius: 12),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const SkeletonBox(height: 12, radius: 6),
                    const SizedBox(height: 8),
                    const SkeletonBox(width: 200, height: 12, radius: 6),
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

/// Placeholder for a stack of rows (chats, requests, sessions).
class ListSkeleton extends StatelessWidget {
  final int count;

  const ListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return SwapSkeleton(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        itemCount: count,
        itemBuilder: (_, __) => Container(
          height: 96,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.sw.surface,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const SkeletonBox(width: 48, height: 48, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SkeletonBox(width: 140, height: 14, radius: 7),
                    SizedBox(height: 8),
                    SkeletonBox(width: 200, height: 12, radius: 6),
                    SizedBox(height: 10),
                    SkeletonBox(height: 10, radius: 5),
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

/// Placeholder for the profile header while the document loads.
class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SwapSkeleton(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Column(
          children: [
            const SkeletonBox(width: 84, height: 84, radius: 28),
            const SizedBox(height: 14),
            const SkeletonBox(width: 180, height: 26, radius: 10),
            const SizedBox(height: 10),
            const SkeletonBox(width: 120, height: 12, radius: 6),
            const SizedBox(height: 18),
            const SkeletonBox(height: 58, radius: 16),
            const SizedBox(height: 14),
            Row(
              children: const [
                Expanded(child: SkeletonBox(height: 68, radius: 18)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 68, radius: 18)),
                SizedBox(width: 10),
                Expanded(child: SkeletonBox(height: 68, radius: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
