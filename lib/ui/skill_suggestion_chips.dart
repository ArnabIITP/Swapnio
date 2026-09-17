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

  const SkillSuggestionChips({
    super.key,
    required this.query,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = SkillCatalogService.instance.suggestionsFor(query);
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: suggestions
            .map((s) => ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () => onSelected(s),
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                  visualDensity: VisualDensity.compact,
                ))
            .toList(),
      ),
    );
  }
}
