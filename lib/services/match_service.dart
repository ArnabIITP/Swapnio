/// Computes how good a potential skill-swap match is between the current
/// user and a candidate.
///
/// This replaces the old "count of exact skillsOffered/skillsWanted string
/// matches" used by the Swap deck (and never used at all by Home), which had
/// two problems: it was case-sensitive (so "Python" and "python" never
/// matched), and it only scored one direction (what THEY teach that I want) -
/// ignoring whether they'd actually want to swap with ME back.
///
/// The score weighs three things:
///  - what they teach that I want to learn (most important - directly
///    satisfies my need)
///  - what I teach that they want to learn (mutual benefit - makes them more
///    likely to accept my request)
///  - overlapping availability, and a small rating tie-breaker
class MatchResult {
  final int rawScore;
  final double percent; // 0-100
  final List<String> theyTeachIWant;
  final List<String> iTeachTheyWant;
  final List<String> sharedAvailability;

  const MatchResult({
    required this.rawScore,
    required this.percent,
    required this.theyTeachIWant,
    required this.iTeachTheyWant,
    required this.sharedAvailability,
  });

  bool get hasAnyOverlap =>
      theyTeachIWant.isNotEmpty || iTeachTheyWant.isNotEmpty;
}

class MatchService {
  MatchService._();

  static Set<String> _normalized(List<String> items) =>
      items.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toSet();

  static MatchResult compute({
    required List<String> mySkillsOffered,
    required List<String> mySkillsWanted,
    required List<String> myAvailability,
    required List<String> candidateSkillsOffered,
    required List<String> candidateSkillsWanted,
    required List<String> candidateAvailability,
    double candidateRating = 0.0,
  }) {
    final myWanted = _normalized(mySkillsWanted);
    final myOffered = _normalized(mySkillsOffered);
    final myAvail = _normalized(myAvailability);
    final theirOffered = _normalized(candidateSkillsOffered);
    final theirWanted = _normalized(candidateSkillsWanted);
    final theirAvail = _normalized(candidateAvailability);

    final theyTeachIWant = theirOffered.intersection(myWanted);
    final iTeachTheyWant = myOffered.intersection(theirWanted);
    final sharedAvailability = myAvail.intersection(theirAvail);

    const teachWeight = 3;
    const learnWeight = 2;
    const availabilityWeight = 1;
    const maxAvailabilityCredit = 3;
    const maxRatingBonus = 2;

    final rawScore = teachWeight * theyTeachIWant.length +
        learnWeight * iTeachTheyWant.length +
        availabilityWeight *
            sharedAvailability.length.clamp(0, maxAvailabilityCredit) +
        (candidateRating.clamp(0, 5) / 5 * maxRatingBonus).round();

    // Normalize against the best this candidate COULD score given how many
    // skills I'm actually looking for/offering, so wanting 2 skills and
    // getting both matched scores much higher than wanting 10 and getting 1.
    final maxPossible = teachWeight * myWanted.length.clamp(1, 10) +
        learnWeight * myOffered.length.clamp(1, 10) +
        availabilityWeight * maxAvailabilityCredit +
        maxRatingBonus;

    final percent = maxPossible == 0
        ? 0.0
        : (rawScore / maxPossible * 100).clamp(0, 100).toDouble();

    return MatchResult(
      rawScore: rawScore,
      percent: percent,
      theyTeachIWant: theyTeachIWant.toList(),
      iTeachTheyWant: iTeachTheyWant.toList(),
      sharedAvailability: sharedAvailability.toList(),
    );
  }
}
