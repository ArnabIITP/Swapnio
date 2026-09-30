import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_nav.dart';
import '../../theme.dart';
import '../../ui/swapnio_badges.dart';
import '../../ui/swapnio_kit.dart';
import 'daily_streak.dart';

/// Everything about the daily streak: today's state, this week, freezes,
/// milestone badges and what counts.
class StreakPage extends StatelessWidget {
  const StreakPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: StreamBuilder<DailyStreak>(
          stream: StreakService.watch(uid),
          builder: (context, snap) {
            final s = snap.data;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const SwapHeader(title: 'Daily streak'),
                const SizedBox(height: 12),
                if (s == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _Hero(streak: s),
                  const SizedBox(height: 14),
                  _WeekRow(streak: s),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          icon: Icons.emoji_events_rounded,
                          color: kStreakFlame,
                          value: '${s.best}',
                          label: 'Best streak',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.ac_unit_rounded,
                          color: kStreakFreeze,
                          value: '${s.freezes} / 2',
                          label: 'Streak freezes',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const KitSection('Milestones'),
                  const SizedBox(height: 10),
                  _Milestones(streak: s),
                  const SizedBox(height: 22),
                  const KitSection('What keeps your streak'),
                  const SizedBox(height: 10),
                  const _Rules(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final DailyStreak streak;

  const _Hero({required this.streak});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final s = streak;
    final String status;
    if (s.keptToday) {
      status = s.current == 1
          ? 'Streak started! Come back tomorrow for day 2.'
          : 'Kept for today. See you tomorrow for day ${s.current + 1}.';
    } else if (s.current > 0) {
      status = s.coveredByFreeze > 0
          ? 'A freeze is covering the day you missed. Do one thing today to keep going.'
          : 'Do one thing today to keep your streak - it ends at midnight.';
    } else {
      status = 'Send a message, a swap request or book a session to start a streak.';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, v, child) =>
                Transform.scale(scale: v, child: child),
            child: Icon(
              Icons.local_fire_department_rounded,
              size: 84,
              color: s.keptToday
                  ? kStreakFlame
                  : Colors.white.withValues(alpha: 0.28),
            ),
          ),
          CountUpText(
            value: s.current,
            style: AppTheme.display(fontSize: 56, color: Colors.white),
          ),
          Text(
            'day streak',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            status,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          if (!s.keptToday) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Open chats',
                    icon: Icons.chat_bubble_outline_rounded,
                    color: kStreakFlame,
                    foreground: Colors.white,
                    onTap: () => _go(context, AppNav.inbox, AppNav.inboxChats),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PillButton(
                    label: 'Discover',
                    icon: Icons.explore_outlined,
                    color: Colors.white,
                    foreground: c.ink,
                    onTap: () => _go(context, AppNav.discover, null),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _go(BuildContext context, int tab, int? inbox) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    AppNav.go(tab, inboxTab: inbox);
  }
}

/// Monday to Sunday of this week: kept, saved by a freeze, today, missed.
class _WeekRow extends StatelessWidget {
  final DailyStreak streak;

  const _WeekRow({required this.streak});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final s = streak;
    final todayDate = DailyStreak.dateOf(s.today);
    final monday = s.today - (todayDate.weekday - 1);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final day = monday + i;
                  final kept = s.days.contains(day);
                  final frozen = !kept && s.frozen.contains(day);
                  final isToday = day == s.today;
                  final future = day > s.today;
                  final Color fill = kept
                      ? kStreakFlame
                      : frozen
                      ? kStreakFreeze
                      : c.surfaceLow;
                  return Column(
                    children: [
                      Text(
                        letters[i],
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: isToday ? c.text : c.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: future ? Colors.transparent : fill,
                          shape: BoxShape.circle,
                          border: isToday && !kept
                              ? Border.all(color: kStreakFlame, width: 2)
                              : future
                              ? Border.all(color: c.border)
                              : null,
                        ),
                        child: kept || frozen
                            ? Icon(
                                kept
                                    ? Icons.local_fire_department_rounded
                                    : Icons.ac_unit_rounded,
                                size: 19,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTheme.display(fontSize: 22, color: c.text),
                ),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Milestones extends StatelessWidget {
  final DailyStreak streak;

  const _Milestones({required this.streak});

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final specs = kBadgeCatalog
        .where((b) => b.statKey == 'bestDayStreak')
        .toList();
    final next = specs
        .where((b) => !streak.badges.contains(b.id))
        .firstOrNull;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next != null) ...[
            Text(
              'Next: ${next.label} at ${next.threshold!.toInt()} days',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (streak.current / next.threshold!).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: c.surfaceLow,
                valueColor: const AlwaysStoppedAnimation(kStreakFlame),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${streak.current} of ${next.threshold!.toInt()} days',
              style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted),
            ),
            const SizedBox(height: 16),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final spec in specs)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: SwapBadgeTile(
                      spec: spec,
                      size: 62,
                      earned: streak.badges.contains(spec.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    const rows = [
      (Icons.check_circle_rounded, kStreakFlame,
          'Do one real thing a day: send a message or a swap request, propose or accept a session, check in, confirm a session, or leave a review.'),
      (Icons.schedule_rounded, kStreakFlame,
          'Days end at midnight on your phone\'s clock. Just opening the app doesn\'t count.'),
      (Icons.ac_unit_rounded, kStreakFreeze,
          'Miss a day and a streak freeze covers it automatically. You start with one, earn another every 7 days in a row, and can hold two.'),
      (Icons.military_tech_rounded, kStreakFlame,
          'Reach 3, 7, 30, 100 and 365 days for a badge and bonus points.'),
    ];
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Column(
        children: [
          for (final (icon, color, text) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.45,
                        color: c.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
