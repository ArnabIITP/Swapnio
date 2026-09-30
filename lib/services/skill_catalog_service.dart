import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// The curated skill list. Profiles may only list skills from it, so that
/// "ML", "machine learning" and "Machine Learning" are one skill everywhere -
/// matching, search and the per-skill hours on the Skill Passport all depend
/// on that.
///
/// The list lives in the `skills` collection (name, category, aliases),
/// seeded from functions/skill_catalog.json by the syncSkillCatalog Cloud
/// Function and extended by admins approving skill requests. A skill that
/// isn't listed can be requested with [requestSkill]; the server also
/// rewrites anything off-list on profile writes, so this class is the
/// friendly front door, not the enforcement.
class SkillCatalogService {
  SkillCatalogService._();

  static final SkillCatalogService instance = SkillCatalogService._();

  /// The catalog version this build expects; bump together with
  /// `version` in functions/skill_catalog.json.
  static const int expectedVersion = 1;

  final List<String> _curated = [];
  final Map<String, List<String>> _byCategory = {};
  // lowercase name or alias -> canonical name.
  final Map<String, String> _lookup = {};
  bool _loaded = false;
  Future<void>? _loading;

  List<String> get curated => List.unmodifiable(_curated);

  /// Every catalog skill.
  List<String> get allKnown => curated;

  /// Category name -> skills, in catalog order.
  Map<String, List<String>> get categories => Map.unmodifiable(_byCategory);

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    try {
      await _read();
      final meta = await FirebaseFirestore.instance
          .collection('meta')
          .doc('skillCatalog')
          .get();
      final version = (meta.data()?['version'] as num?)?.toInt() ?? 0;
      if (_curated.isEmpty || version < expectedVersion) {
        // First run after a deploy: have the server seed / upgrade the
        // catalog, then read it again.
        await FirebaseFunctions.instance
            .httpsCallable('syncSkillCatalog')
            .call();
        await _read();
      }
      _loaded = _curated.isNotEmpty;
    } catch (e) {
      debugPrint('SkillCatalogService load failed: $e');
    }
  }

  Future<void> _read() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('skills')
        .get();
    final docs = snapshot.docs.map((d) => d.data()).toList()
      ..sort(
        (a, b) => ((a['order'] as num?) ?? 1e9).compareTo(
          (b['order'] as num?) ?? 1e9,
        ),
      );
    _curated.clear();
    _byCategory.clear();
    _lookup.clear();
    for (final data in docs) {
      final name = (data['name'] as String?)?.trim() ?? '';
      if (name.isEmpty || _lookup.containsKey(name.toLowerCase())) continue;
      _curated.add(name);
      _lookup[name.toLowerCase()] = name;
      final category = (data['category'] as String?)?.trim();
      _byCategory
          .putIfAbsent(
            category == null || category.isEmpty ? 'Other' : category,
            () => [],
          )
          .add(name);
      for (final alias in List<String>.from(data['aliases'] ?? const [])) {
        _lookup.putIfAbsent(alias.trim().toLowerCase(), () => name);
      }
    }
  }

  /// The catalog name for [input] (by name or alias, any casing), or null
  /// when it isn't in the catalog.
  String? resolve(String input) {
    final key = input.trim().toLowerCase();
    if (key.isEmpty) return null;
    return _lookup[key];
  }

  /// The catalog name when there is one, otherwise the trimmed input.
  String canonicalize(String input) => resolve(input) ?? input.trim();

  /// Up to 8 catalog skills matching [query]. An alias match surfaces its
  /// catalog name ("JS" -> "JavaScript"), since that's what gets added.
  List<String> suggestionsFor(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return _curated.take(8).toList();
    final result = <String>[];
    void add(String name) {
      if (!result.contains(name)) result.add(name);
    }

    final exact = _lookup[lower];
    if (exact != null) add(exact);
    for (final name in _curated) {
      if (name.toLowerCase().startsWith(lower)) add(name);
    }
    for (final entry in _lookup.entries) {
      if (entry.key.contains(lower)) add(entry.value);
    }
    return result.take(8).toList();
  }

  /// Asks admins to add a skill that isn't in the catalog. Once approved it
  /// is added to the requester's profile automatically. If it turns out to
  /// be in the catalog after all, its catalog name is returned instead.
  Future<({String? canonical, bool requested, String? error})> requestSkill(
    String name, {
    required bool offered,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('requestSkill')
          .call({'name': name.trim(), 'side': offered ? 'offered' : 'wanted'});
      final data = Map<String, dynamic>.from(result.data as Map);
      return (
        canonical: data['canonical'] as String?,
        requested: data['requested'] == true,
        error: null,
      );
    } on FirebaseFunctionsException catch (e) {
      return (canonical: null, requested: false, error: e.message);
    } catch (e) {
      return (
        canonical: null,
        requested: false,
        error: 'Could not send the request. Try again.',
      );
    }
  }
}
