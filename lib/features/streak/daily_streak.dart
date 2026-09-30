import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';
import '../../ui/celebration.dart';
import '../../ui/swapnio_widgets.dart';
import 'streak_page.dart';

/// Flame colour for everything daily-streak.
const Color kStreakFlame = Color(0xFFFF7A1A);

/// Streak-freeze colour.
const Color kStreakFreeze = Color(0xFF3FA7F0);

/// A user's daily streak as the app shows it right now.
///
/// The server (functions/streaks.js) only updates the streak when the user
/// does something, so a streak whose last day was a while ago is still
/// stored as-is. This works out what it means *today*: kept, still alive
/// (yesterday kept, or the missed days are covered by freezes), or broken.
class DailyStreak {
  /// Days in a row, as it stands today (0 once broken).
  final int current;
  final int best;

  /// Freezes left after covering any days missed since the last activity.
  final int freezes;
  final bool keptToday;

  /// Missed days that freezes will cover when the user is next active.
  final int coveredByFreeze;

  /// Day numbers (see [dayNumber]) kept, and saved by a freeze.
  final Set<int> days;
  final Set<int> frozen;
  final int today;

  /// day_streak_* badges earned so far.
  final List<String> badges;

  const DailyStreak({
    required this.current,
    required this.best,
    required this.freezes,
    required this.keptToday,
    required this.coveredByFreeze,
    required this.days,
    required this.frozen,
    required this.today,
    required this.badges,
  });

  /// Streak alive but today not kept yet - the "don't lose it" state.
  bool get atRisk => current > 0 && !keptToday;

  /// Whole days since the epoch on this device's clock - the same numbering
  /// the server uses with the time zone the app reports.
  static int dayNumber(DateTime t) =>
      ((t.millisecondsSinceEpoch + t.timeZoneOffset.inMilliseconds) /
              Duration.millisecondsPerDay)
          .floor();

  /// The local calendar date of a day number.
  static DateTime dateOf(int day) {
    final utc = DateTime.utc(1970).add(Duration(days: day));
    return DateTime(utc.year, utc.month, utc.day);
  }

  factory DailyStreak.from(Map<String, dynamic>? gamification, {DateTime? now}) {
    final s = Map<String, dynamic>.from(
      (gamification?['dailyStreak'] as Map?) ?? const {},
    );
    final today = dayNumber(now ?? DateTime.now());
    final lastDay = (s['lastDay'] as num?)?.toInt();
    final stored = (s['current'] as num?)?.toInt() ?? 0;
    var freezes = (s['freezes'] as num?)?.toInt() ?? 1;
    final days = {for (final d in (s['days'] as List? ?? const [])) (d as num).toInt()};
    final frozen = {
      for (final d in (s['frozen'] as List? ?? const [])) (d as num).toInt(),
    };

    var current = 0;
    var covered = 0;
    if (lastDay != null && stored > 0) {
      final missed = today - lastDay - 1;
      if (missed <= 0) {
        current = stored;
      } else if (missed <= freezes) {
        current = stored;
        covered = missed;
        freezes -= missed;
        for (var d = lastDay + 1; d < today; d++) {
          frozen.add(d);
        }
      }
    }
    return DailyStreak(
      current: current,
      best: (s['best'] as num?)?.toInt() ?? 0,
      freezes: freezes,
      keptToday: lastDay == today,
      coveredByFreeze: covered,
      days: days,
      frozen: frozen,
      today: today,
      badges: [
        for (final b in (gamification?['badges'] as List? ?? const []))
          if (b is String && b.startsWith('day_streak_')) b,
      ],
    );
  }
}

class StreakService {
  StreakService._();

  static Stream<DailyStreak> watch(String uid) => FirebaseFirestore.instance
      .collection('gamification')
      .doc(uid)
      .snapshots()
      .map((snap) => DailyStreak.from(snap.data()));

  /// Tells the server this device's time zone, so a "day" ends at the
  /// user's own midnight. Only writes when it changed.
  static Future<void> syncTimezone() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final offset = DateTime.now().timeZoneOffset.inMinutes;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final snap = await ref.get();
      if (snap.data()?['tzOffsetMinutes'] != offset) {
        await ref.update({'tzOffsetMinutes': offset});
      }
    } catch (e) {
      debugPrint('Streak time zone: $e');
    }
  }
}

/// Celebrates while the app is open: a milestone gets the full badge
/// dialog, an ordinary day a short "day N" toast.
class StreakCelebrator {
  StreamSubscription<DailyStreak>? _sub;
  DailyStreak? _last;

  void start(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _sub?.cancel();
    _sub = StreakService.watch(uid).listen((streak) {
      final before = _last;
      _last = streak;
      // The first value is where things stand, not something that happened.
      if (before == null || before.keptToday || !streak.keptToday) return;
      if (!context.mounted) return;
      final newBadge = streak.badges
          .where((b) => !before.badges.contains(b))
          .firstOrNull;
      if (newBadge != null) {
        showCelebrationDialog(
          context,
          icon: Icons.local_fire_department_rounded,
          badgeId: newBadge,
          headline: '${streak.current}-day streak!',
          message:
              "You've shown up ${streak.current} days in a row - "
              'a new badge for your collection.',
          primaryLabel: 'See my streak',
          onPrimary: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StreakPage()),
          ),
          secondaryLabel: 'Keep going',
        );
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  color: kStreakFlame,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    streak.current == 1
                        ? 'Streak started! Come back tomorrow for day 2.'
                        : 'Day ${streak.current} - streak kept!',
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'See',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StreakPage()),
              ),
            ),
          ),
        );
    }, onError: (e) => debugPrint('Streak watch: $e'));
  }

  void dispose() => _sub?.cancel();
}

/// The flame and day count on Home. Lit once today is kept.
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final c = context.sw;
    return StreamBuilder<DailyStreak>(
      stream: StreakService.watch(uid),
      builder: (context, snap) {
        final s = snap.data;
        final lit = s?.keptToday ?? false;
        final count = s?.current ?? 0;
        return Semantics(
          label: lit
              ? '$count-day streak, kept today'
              : count > 0
              ? '$count-day streak, not kept yet today'
              : 'No streak yet',
          button: true,
          child: Pressable(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StreakPage()),
            ),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: lit ? kStreakFlame.withValues(alpha: 0.14) : c.surface,
                borderRadius: BorderRadius.circular(22),
                border: s?.atRisk == true
                    ? Border.all(color: kStreakFlame.withValues(alpha: 0.6))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 22,
                    color: lit ? kStreakFlame : c.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: lit ? kStreakFlame : c.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
