// Gamification model: points, levels, badges
class Gamification {
  int points;
  int level;
  List<String> badges;

  /// Server-computed totals behind the badge families (teachMinutes,
  /// bestWeekStreak, ...) - see functions/sessions.js. Empty until the
  /// server has computed them once.
  Map<String, num> stats;

  Gamification({
    required this.points,
    required this.level,
    required this.badges,
    this.stats = const {},
  });
}
