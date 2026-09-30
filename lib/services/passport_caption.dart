import 'skill_passport_service.dart';

/// Ready-to-post captions for a shared Skill Passport, written from the
/// passport's own verified numbers so nothing in them is made up.
///
/// LinkedIn (and a few other apps) drop the text that comes with a shared
/// image, so the page copies the chosen caption to the clipboard as well -
/// these are written to read well pasted in as the post body.
class PassportCaption {
  PassportCaption._();

  static List<String> variants(SkillPassport p) {
    final skills = p.skills.map((s) => s.skill).take(3).toList();
    final learned = p.learned.map((l) => l.skill).take(2).toList();
    final hashtags = _hashtags([...skills, ...learned]);

    if (p.totalVerifiedSessions == 0) {
      final learning = learned.isEmpty
          ? ''
          : ' Already picked up ${_list(learned)} along the way.';
      return [
        'Just opened my Skill Passport on Swapnio 🛂\n\n'
            "It's a record of what I teach that can't be faked: every stamp comes from a real, "
            'completed session and a rating from the person I taught.$learning\n\n'
            'First stamp loading... who wants to swap skills?\n\n$hashtags',
        "I'm trading skills, not money. 🤝\n\n"
            'My new Skill Passport on Swapnio fills up only with verified sessions and peer '
            'ratings - no self-reported badges.\n\n'
            "If there's something you could teach me, I've probably got something to teach you. "
            "Let's swap!\n\n$hashtags",
      ];
    }

    final sessions = _count(p.totalVerifiedSessions, 'verified session');
    final time = formatTeachingTime(p.totalTeachMinutes);
    final people = _count(p.peopleTaught, 'person', plural: 'people');
    final rating = p.overallRating?.toStringAsFixed(1);
    final showUp = p.reliability.total == 0 ? null : p.reliability.showUpRate;
    final topTag = p.topTags.isEmpty ? null : p.topTags.first.key;
    final teaches = _list(skills);

    return [
      // Achievement
      "🎓 I've taught $teaches on Swapnio - $time across $sessions"
          '${rating == null ? '' : ' - rated $rating★ by the people I taught'}.\n\n'
          'Every stamp in this Skill Passport comes from a real completed session and a '
          'rating from my swap partner. Nothing self-reported.\n\n'
          'Want to trade skills? Find me on Swapnio.\n\n$hashtags',
      // Checklist
      'New stamps in my Skill Passport 🛂\n\n'
          '✅ $time taught across $sessions\n'
          '🤝 $people taught\n'
          '${rating == null ? '' : '⭐ $rating peer rating\n'}'
          '${showUp == null ? '' : '📅 $showUp% show-up rate\n'}'
          '${topTag == null ? '' : '💬 Partners say: "$topTag"\n'}'
          '\nSkills I teach: $teaches\n'
          'Passport no. ${p.passportNumber}\n\n$hashtags',
      // Story
      'Teaching is the fastest way to learn.\n\n'
          "So far I've swapped $teaches with $people"
          '${learned.isEmpty ? '' : ' - and learned ${_list(learned)} in return'}. '
          'No fees, no courses: just people trading what they know.\n\n'
          'My Skill Passport on Swapnio is built only from verified sessions and peer '
          'ratings, so every number on it is earned.\n\n$hashtags',
      // Invitation
      "I teach $teaches in exchange for things I'd like to learn. 🔁\n\n"
          '$sessions so far'
          '${showUp == null ? '' : ', $showUp% show-up'}'
          '${rating == null ? '' : ', $rating★ from partners'}'
          " - all verified on my Skill Passport.\n\n"
          "If you've got a skill to swap, let's connect on Swapnio!\n\n$hashtags",
    ];
  }

  static String _count(int n, String singular, {String? plural}) =>
      '$n ${n == 1 ? singular : (plural ?? '${singular}s')}';

  static String _list(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  /// Brand tags plus up to three skill tags, e.g. "Machine Learning" ->
  /// #MachineLearning. Skills that leave nothing usable are skipped.
  static String _hashtags(List<String> skills) {
    final tags = <String>['#SkillSwap', '#PeerLearning', '#Swapnio'];
    for (final skill in skills) {
      final tag = skill
          .split(RegExp(r'[^A-Za-z0-9]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join();
      if (tag.isEmpty || RegExp(r'^\d+$').hasMatch(tag)) continue;
      final hashtag = '#$tag';
      if (!tags.contains(hashtag)) tags.add(hashtag);
      if (tags.length >= 6) break;
    }
    return tags.join(' ');
  }
}
