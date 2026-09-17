// Progress model: tracks user activity and skill quality
class SkillProgress {
  final String skillName;
  int sessionsCompleted;
  double avgQuizScore;
  int quizCount;
  int streakDays;
  double peerRating; // 0-5
  int peerRatingCount;

  SkillProgress({
    required this.skillName,
    required this.sessionsCompleted,
    required this.avgQuizScore,
    required this.streakDays,
    required this.peerRating,
    this.quizCount = 0,
    this.peerRatingCount = 0,
  });
}

class Progress {
  int totalSessions;
  int totalMessages;
  int totalTasks;
  List<SkillProgress> skills;

  Progress({
    required this.totalSessions,
    required this.totalMessages,
    required this.totalTasks,
    required this.skills,
  });
}
