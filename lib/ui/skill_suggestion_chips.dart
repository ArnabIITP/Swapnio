import 'package:flutter/material.dart';
import '../services/skill_catalog_service.dart';
import '../theme.dart';

/// Live suggestion chips below a skill text field, sourced from
/// [SkillCatalogService]. Tapping a chip fills in the known canonical
/// spelling/casing instead of the user having to type it exactly - this is
/// what actually prevents "python" and "Python" from silently failing to
/// match each other later.
class SkillSuggestionChips extends StatelessWidget {
  final String query;
  final ValueChanged<String> onSelected;

  /// Skills already on the profile, left out of the suggestions.
  final List<String> exclude;

  const SkillSuggestionChips({
    super.key,
    required this.query,
    required this.onSelected,
    this.exclude = const [],
  });

  @override
  Widget build(BuildContext context) {
    final taken = exclude.map((e) => e.toLowerCase()).toSet();
    final suggestions = SkillCatalogService.instance
        .suggestionsFor(query)
        .where((s) => !taken.contains(s.toLowerCase()))
        .toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: suggestions
            .map(
              (s) => ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 12)),
                onPressed: () => onSelected(s),
                backgroundColor: context.sw.give.withValues(alpha: 0.08),
                side: BorderSide(color: context.sw.give.withValues(alpha: 0.3)),
                visualDensity: VisualDensity.compact,
              ),
            )
            .toList(),
      ),
    );
  }
}
