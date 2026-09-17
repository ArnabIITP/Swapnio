import 'package:cloud_firestore/cloud_firestore.dart';

/// Skill-name suggestions and canonicalization, so that "python", "Python"
/// and "python3" don't end up as three different strings that MatchService's
/// exact (if case-insensitive) comparison then fails to line up across users.
///
/// Three sources are merged:
///  - the admin-curated `skills` collection (Admin > Skills tab) - the
///    authoritative source when populated, shown first in suggestions.
///  - each curated skill's optional `aliases` list (e.g. "JavaScript" with
///    aliases ["JS", "ECMAScript"]) - true synonym mapping, not just
///    case/whitespace drift: typing an alias resolves to the canonical name.
///  - skill strings already used across real user profiles - since the
///    curated list may be sparse or empty for a small/new deployment, this
///    bootstraps useful suggestions/canonical casing from day one without
///    requiring an admin to pre-seed anything.
class SkillCatalogService {
  SkillCatalogService._();

  static final SkillCatalogService instance = SkillCatalogService._();

  final List<String> _curated = [];
  // lowercase alias -> canonical curated name.
  final Map<String, String> _aliasToCanonical = {};
  // lowercase -> {display casing -> usage count}, so the most common casing
  // used by real profiles wins when canonicalizing.
  final Map<String, Map<String, int>> _usageCasing = {};
  bool _loaded = false;
  bool _loading = false;

  List<String> get curated => List.unmodifiable(_curated);

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('skills')
            .orderBy('name')
            .limit(500)
            .get(),
        FirebaseFirestore.instance.collection('users').limit(200).get(),
      ]);

      final skillsSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
      for (final doc in skillsSnapshot.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        if (!_curated.contains(name)) _curated.add(name);

        final aliases = data['aliases'];
        if (aliases is List) {
          for (final raw in aliases) {
            final alias = raw.toString().trim();
            if (alias.isEmpty) continue;
            _aliasToCanonical[alias.toLowerCase()] = name;
          }
        }
      }

      final usersSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
      for (final doc in usersSnapshot.docs) {
        final data = doc.data();
        for (final field in ['skillsOffered', 'skillsWanted']) {
          final list = data[field];
          if (list is! List) continue;
          for (final raw in list) {
            final name = raw.toString().trim();
            if (name.isEmpty) continue;
            final key = name.toLowerCase();
            final casings = _usageCasing.putIfAbsent(key, () => {});
            casings[name] = (casings[name] ?? 0) + 1;
          }
        }
      }
    } catch (_) {
      // Best-effort: an empty catalog just means no suggestions, free text
      // still works everywhere this is used.
    }
    _loaded = true;
    _loading = false;
  }

  /// Every known skill name (curated first), deduped case-insensitively.
  List<String> get allKnown => _allKnown;

  List<String> get _allKnown {
    final seenLower = <String>{};
    final result = <String>[];
    for (final name in _curated) {
      if (seenLower.add(name.toLowerCase())) result.add(name);
    }
    for (final key in _usageCasing.keys) {
      if (seenLower.add(key)) result.add(_mostCommonCasing(key) ?? key);
    }
    return result;
  }

  String? _mostCommonCasing(String lowerKey) {
    final casings = _usageCasing[lowerKey];
    if (casings == null || casings.isEmpty) return null;
    return casings.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  /// Up to 6 suggestions for the given (possibly partial) query. An alias
  /// match (e.g. "JS" -> "JavaScript") surfaces its canonical name, not the
  /// alias itself, since that's what should actually get added.
  List<String> suggestionsFor(String query) {
    final known = _allKnown;
    if (query.trim().isEmpty) return known.take(6).toList();
    final lower = query.trim().toLowerCase();

    final aliasMatches = _aliasToCanonical.entries
        .where((e) => e.key.contains(lower))
        .map((e) => e.value);
    final startsWith = known.where((n) => n.toLowerCase().startsWith(lower));
    final contains = known.where((n) =>
        !n.toLowerCase().startsWith(lower) && n.toLowerCase().contains(lower));

    final seen = <String>{};
    final result = <String>[];
    for (final name in [...aliasMatches, ...startsWith, ...contains]) {
      if (seen.add(name.toLowerCase())) result.add(name);
      if (result.length >= 6) break;
    }
    return result;
  }

  /// Resolves input to a known skill's canonical name/casing: an exact alias
  /// match wins first (true synonym mapping, e.g. "JS" -> "JavaScript"), then
  /// a curated name match case-insensitively, then the most common casing
  /// already used by real profiles; otherwise returns the trimmed input
  /// unchanged - the catalog assists, it never blocks a skill that isn't in
  /// it yet.
  String canonicalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    final lower = trimmed.toLowerCase();
    final aliasHit = _aliasToCanonical[lower];
    if (aliasHit != null) return aliasHit;
    for (final name in _curated) {
      if (name.toLowerCase() == lower) return name;
    }
    return _mostCommonCasing(lower) ?? trimmed;
  }
}
