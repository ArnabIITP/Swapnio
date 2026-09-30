import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../ui/session_actions.dart' show swapSidesFor;
import 'swap_service.dart';

/// Skill levels, earned per skill from verified hours taught (and, for the
/// top two, the peer ratings tied to those sessions). Thresholds live in
/// [SkillTier.from] only.
enum SkillTier {
  apprentice('Apprentice', 0),
  practitioner('Practitioner', 600),
  mentor('Mentor', 1800),
  master('Master', 6000);

  final String label;

  /// Minutes taught needed for this level.
  final int minutes;
  const SkillTier(this.label, this.minutes);

  static SkillTier from(int minutesTaught, double? rating) {
    final r = rating ?? 0;
    if (minutesTaught >= master.minutes && r >= 4.7) return master;
    if (minutesTaught >= mentor.minutes && r >= 4.5) return mentor;
    if (minutesTaught >= practitioner.minutes) return practitioner;
    return apprentice;
  }

  SkillTier? get next => this == master ? null : SkillTier.values[index + 1];
}

/// Sessions completed before the session timer existed have no recorded
/// length; they count as the minimum a session can now be. Mirrors
/// LEGACY_SESSION_MINUTES in functions/sessions.js.
const int kLegacySessionMinutes = 30;

/// "30 min", "1.5 h", "12 h".
String formatTeachingTime(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes / 60;
  return '${hours == hours.roundToDouble() || hours >= 10 ? hours.round() : hours.toStringAsFixed(1)} h';
}

/// A skill this user has taught: sessions, the ratings tied to exactly those
/// sessions, and when they first/last taught it.
class SkillPassportEntry {
  final String skill;
  final int sessionsTaught;
  final int minutesTaught;
  final double? averageRating;
  final int ratingsCount;
  final DateTime? firstTaughtAt;
  final SkillTier tier;

  const SkillPassportEntry({
    required this.skill,
    required this.sessionsTaught,
    required this.minutesTaught,
    required this.averageRating,
    required this.ratingsCount,
    required this.firstTaughtAt,
    required this.tier,
  });
}

class LearnedSkill {
  final String skill;
  final int sessions;

  const LearnedSkill({required this.skill, required this.sessions});
}

class PassportReview {
  final String text;
  final double rating;
  final String reviewerFirstName;
  final String skill;

  const PassportReview({
    required this.text,
    required this.rating,
    required this.reviewerFirstName,
    required this.skill,
  });
}

/// Everything on a Skill Passport - built only from data a client can't
/// self-forge: completed `swaps`, the `ratings` collection, the protected
/// reputation fields on `users/{uid}`, and `gamification/{uid}`
/// (Cloud-Function-only writes). `progress` is deliberately never read: it's
/// still self-writable and would undercut the "verified" claim.
class SkillPassport {
  final String uid;

  /// Unique number, e.g. SWP-3NYS-GQDS - see [SkillPassportService.load].
  final String passportNumber;
  final String displayName;
  final String? photoUrl;
  final DateTime? memberSince;
  final int totalVerifiedSessions;
  final int totalLearnedSessions;
  final int totalTeachMinutes;
  final int totalLearnMinutes;
  final int peopleTaught;
  final double? overallRating;
  final int overallRatingsCount;
  final ReliabilityStatus reliability;
  final List<String> badgeIds;
  final int gamificationLevel;
  final int gamificationPoints;
  final List<SkillPassportEntry> skills;
  final List<LearnedSkill> learned;
  final List<MapEntry<String, int>> topTags;
  final PassportReview? topReview;
  final double? goalRate;
  final int goalSample;

  /// Completed sessions (either role) per day for the last [activityDays]
  /// days, oldest first.
  final List<int> dailyActivity;
  final DateTime? firstSwapAt;
  final DateTime? lastActiveAt;

  /// Raw mySwapWeb result for the passport's Swap Web page (own passport
  /// only - the function serves the signed-in user). Null when unavailable.
  final Map<String, dynamic>? web;

  /// Email and phone both verified (server-set, see verification.js).
  final bool verified;

  static const int activityDays = 84;

  const SkillPassport({
    required this.uid,
    required this.passportNumber,
    required this.displayName,
    required this.photoUrl,
    required this.memberSince,
    required this.totalVerifiedSessions,
    required this.totalLearnedSessions,
    required this.totalTeachMinutes,
    required this.totalLearnMinutes,
    required this.peopleTaught,
    required this.overallRating,
    required this.overallRatingsCount,
    required this.reliability,
    required this.badgeIds,
    required this.gamificationLevel,
    required this.gamificationPoints,
    required this.skills,
    required this.learned,
    required this.topTags,
    required this.topReview,
    required this.goalRate,
    required this.goalSample,
    required this.dailyActivity,
    required this.firstSwapAt,
    required this.lastActiveAt,
    this.web,
    this.verified = false,
  });

  int get sessionsInActivityWindow => dailyActivity.fold(0, (a, b) => a + b);

  /// Levels are every 100 points (see awardGamification in functions/index.js).
  int get pointsToNextLevel => gamificationLevel * 100 - gamificationPoints;
}

class SkillPassportService {
  SkillPassportService._();

  static final SkillPassportService instance = SkillPassportService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Soft ceiling on completed swaps / ratings read for one passport, in the
  /// same spirit as `mySessionsStream()`'s limit - sized up because this is
  /// a one-shot load, not a live stream.
  static const int _readLimit = 500;

  Future<SkillPassport> load(String uid) async {
    // Backfill this user's server-side stats and badges (hours, streaks...)
    // before reading them. Best effort: the passport still loads without it.
    if (uid == FirebaseAuth.instance.currentUser?.uid) {
      try {
        await FirebaseFunctions.instance
            .httpsCallable('refreshMyStats')
            .call()
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    final results = await Future.wait([
      _firestore.collection('users').doc(uid).get(),
      _firestore
          .collection('swaps')
          .where('participants', arrayContains: uid)
          .where('status', isEqualTo: 'completed')
          .limit(_readLimit)
          .get(),
      _firestore
          .collection('ratings')
          .where('toUserId', isEqualTo: uid)
          .limit(_readLimit)
          .get(),
      _firestore.collection('gamification').doc(uid).get(),
    ]);

    final userData =
        (results[0] as DocumentSnapshot).data() as Map<String, dynamic>? ?? {};
    final swaps = (results[1] as QuerySnapshot).docs;
    final ratings = (results[2] as QuerySnapshot).docs;
    final gamificationData =
        (results[3] as DocumentSnapshot).data() as Map<String, dynamic>? ?? {};
    // Same two Cloud-Function-written fields myReliability() reads, but for
    // [uid] rather than whoever is signed in.
    final reliability = ReliabilityStatus(
      attended: (userData['sessionsAttended'] as num?)?.toInt() ?? 0,
      noShows: (userData['noShowCount'] as num?)?.toInt() ?? 0,
    );

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final taughtSwapIds = <String, Set<String>>{};
    final taughtMinutes = <String, double>{};
    var teachMinutes = 0.0;
    var learnMinutes = 0.0;
    final firstTaught = <String, DateTime>{};
    final learnedCounts = <String, int>{};
    final taughtSkillBySwap = <String, String>{};
    final namesBySwap = <String, Map<String, dynamic>>{};
    final partnersTaught = <String>{};
    final daily = List<int>.filled(SkillPassport.activityDays, 0);
    var goalHits = 0;
    var goalSample = 0;
    var learnedSessions = 0;
    DateTime? firstSwapAt;
    DateTime? lastActiveAt;

    for (final doc in swaps) {
      final data = doc.data() as Map<String, dynamic>;
      final sides = swapSidesFor(data, uid);
      final when =
          _dateOf(data['completedAt']) ?? _dateOf(data['scheduledFor']);
      namesBySwap[doc.id] = Map<String, dynamic>.from(
        data['participantNames'] ?? const {},
      );

      final taught = sides.myGive.trim();
      final learnedSkill = sides.myGet.trim();
      // A swap is an exchange: with both skills set, the time is split
      // evenly between teaching and learning (same rule as the server).
      final length =
          (data['durationMinutes'] as num?)?.toDouble() ??
          kLegacySessionMinutes.toDouble();
      final share = taught.isNotEmpty && learnedSkill.isNotEmpty
          ? length / 2
          : length;
      if (taught.isNotEmpty) {
        taughtMinutes[taught] = (taughtMinutes[taught] ?? 0) + share;
        teachMinutes += share;
        taughtSwapIds.putIfAbsent(taught, () => <String>{}).add(doc.id);
        taughtSkillBySwap[doc.id] = taught;
        for (final p in List<String>.from(data['participants'] ?? const [])) {
          if (p != uid) partnersTaught.add(p);
        }
        if (when != null &&
            (firstTaught[taught] == null ||
                when.isBefore(firstTaught[taught]!))) {
          firstTaught[taught] = when;
        }
      }

      final learned = learnedSkill;
      if (learned.isNotEmpty) {
        learnMinutes += share;
        learnedCounts[learned] = (learnedCounts[learned] ?? 0) + 1;
        learnedSessions++;
      }

      if (data['goalAchieved'] is bool) {
        goalSample++;
        if (data['goalAchieved'] == true) goalHits++;
      }

      if (when != null) {
        if (firstSwapAt == null || when.isBefore(firstSwapAt))
          firstSwapAt = when;
        if (lastActiveAt == null || when.isAfter(lastActiveAt))
          lastActiveAt = when;
        final dayIndex = today
            .difference(DateTime(when.year, when.month, when.day))
            .inDays;
        if (dayIndex >= 0 && dayIndex < SkillPassport.activityDays) {
          daily[SkillPassport.activityDays - 1 - dayIndex]++;
        }
      }
    }

    // Ratings: per-skill averages need a swapId (the only live write path,
    // chat_page's rating flow, always sets one; legacy rows without it are
    // left out of per-skill numbers but still count toward the overall
    // rating read from users/{uid} below). Tags don't need a swapId.
    final ratingsBySwap = <String, List<double>>{};
    final tagCounts = <String, int>{};
    QueryDocumentSnapshot? bestReviewDoc;
    for (final doc in ratings) {
      final data = doc.data() as Map<String, dynamic>;
      final rating = (data['rating'] as num?)?.toDouble();
      final swapId = data['swapId'] as String?;
      if (rating != null && swapId != null && swapId.isNotEmpty) {
        ratingsBySwap.putIfAbsent(swapId, () => <double>[]).add(rating);
      }
      for (final tag in List<String>.from(data['tags'] ?? const [])) {
        tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
      }
      final review = (data['review'] as String?)?.trim() ?? '';
      if (rating != null && review.isNotEmpty && _beats(data, bestReviewDoc)) {
        bestReviewDoc = doc;
      }
    }

    final skills =
        <SkillPassportEntry>[
          for (final e in taughtSwapIds.entries)
            () {
              final values = [for (final id in e.value) ...?ratingsBySwap[id]];
              final avg = values.isEmpty
                  ? null
                  : values.reduce((a, b) => a + b) / values.length;
              final minutes = (taughtMinutes[e.key] ?? 0).round();
              return SkillPassportEntry(
                skill: e.key,
                sessionsTaught: e.value.length,
                minutesTaught: minutes,
                averageRating: avg,
                ratingsCount: values.length,
                firstTaughtAt: firstTaught[e.key],
                tier: SkillTier.from(minutes, avg),
              );
            }(),
        ]..sort((a, b) {
          final byTier = b.tier.index.compareTo(a.tier.index);
          return byTier != 0
              ? byTier
              : b.minutesTaught.compareTo(a.minutesTaught);
        });

    final learned = [
      for (final e in learnedCounts.entries)
        LearnedSkill(skill: e.key, sessions: e.value),
    ]..sort((a, b) => b.sessions.compareTo(a.sessions));

    final topTags = tagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    PassportReview? topReview;
    if (bestReviewDoc != null) {
      final data = bestReviewDoc.data() as Map<String, dynamic>;
      final swapId = data['swapId'] as String? ?? '';
      final fullName =
          (namesBySwap[swapId]?[data['fromUserId']] as String?)?.trim() ?? '';
      topReview = PassportReview(
        text: (data['review'] as String).trim(),
        rating: (data['rating'] as num).toDouble(),
        reviewerFirstName: fullName.isEmpty
            ? 'A swap partner'
            : fullName.split(' ').first,
        skill: taughtSkillBySwap[swapId] ?? '',
      );
    }

    final ratingsCount = (userData['ratingsCount'] as num?)?.toInt() ?? 0;
    final name = (userData['name'] as String?)?.trim() ?? '';

    Map<String, dynamic>? web;
    if (uid == FirebaseAuth.instance.currentUser?.uid) {
      try {
        final r = await FirebaseFunctions.instance
            .httpsCallable('mySwapWeb')
            .call({
              'filters': {'depth': 2},
            })
            .timeout(const Duration(seconds: 8));
        web = Map<String, dynamic>.from(r.data as Map);
      } catch (_) {
        // The passport still works without its web page.
      }
    }

    return SkillPassport(
      uid: uid,
      passportNumber: await _passportNumber(uid, userData),
      displayName: name.isNotEmpty
          ? name
          : (FirebaseAuth.instance.currentUser?.displayName ?? 'Swapnio user'),
      photoUrl: userData['photoUrl'] as String?,
      memberSince: _dateOf(userData['memberSince']),
      totalVerifiedSessions: taughtSkillBySwap.length,
      totalLearnedSessions: learnedSessions,
      totalTeachMinutes: teachMinutes.round(),
      totalLearnMinutes: learnMinutes.round(),
      peopleTaught: partnersTaught.length,
      overallRating: ratingsCount == 0
          ? null
          : (userData['rating'] as num?)?.toDouble(),
      overallRatingsCount: ratingsCount,
      reliability: reliability,
      badgeIds: List<String>.from(gamificationData['badges'] ?? const []),
      gamificationLevel: (gamificationData['level'] as num?)?.toInt() ?? 1,
      gamificationPoints: (gamificationData['points'] as num?)?.toInt() ?? 0,
      skills: skills,
      learned: learned,
      topTags: topTags,
      topReview: topReview,
      goalRate: goalSample == 0 ? null : goalHits / goalSample,
      goalSample: goalSample,
      dailyActivity: daily,
      firstSwapAt: firstSwapAt,
      lastActiveAt: lastActiveAt,
      web: web,
      verified: userData['verified'] == true,
    );
  }

  /// The number issued to this user by the issuePassportNumber Cloud
  /// Function, which reserves each number so no two users share one. Users
  /// who signed up before numbers were issued get one the first time they
  /// open their own passport. If the function can't be reached, the number
  /// it would try first (derived from the uid) is shown instead.
  Future<String> _passportNumber(
    String uid,
    Map<String, dynamic> userData,
  ) async {
    final issued = userData['passportNumber'] as String?;
    if (issued != null && issued.isNotEmpty) return issued;
    if (uid == FirebaseAuth.instance.currentUser?.uid) {
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('issuePassportNumber')
            .call();
        final number = (result.data as Map?)?['passportNumber'] as String?;
        if (number != null && number.isNotEmpty) return number;
      } catch (_) {
        // Offline or not deployed yet - fall through to the derived number.
      }
    }
    final clean = uid
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase()
        .padRight(8, 'X');
    return 'SWP-${clean.substring(0, 4)}-${clean.substring(4, 8)}';
  }

  static DateTime? _dateOf(dynamic value) =>
      value is Timestamp ? value.toDate() : null;

  /// Higher rating wins; ties go to the more recent review.
  static bool _beats(
    Map<String, dynamic> candidate,
    QueryDocumentSnapshot? current,
  ) {
    if (current == null) return true;
    final other = current.data() as Map<String, dynamic>;
    final a = (candidate['rating'] as num).toDouble();
    final b = (other['rating'] as num).toDouble();
    if (a != b) return a > b;
    final ta = _dateOf(candidate['timestamp']);
    final tb = _dateOf(other['timestamp']);
    if (ta == null) return false;
    if (tb == null) return true;
    return ta.isAfter(tb);
  }
}
