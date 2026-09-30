import 'package:flutter/material.dart';

import '../services/skill_catalog_service.dart';

/// Resolves what someone typed to a catalog skill. When it isn't in the
/// catalog, offers to request it from the admins instead of adding free
/// text. Returns the catalog name to add, or null when nothing should be
/// added right now (unknown, requested, or cancelled).
Future<String?> resolveOrRequestSkill(
  BuildContext context,
  String input, {
  required bool offered,
}) async {
  final typed = input.trim();
  if (typed.isEmpty) return null;
  final catalog = SkillCatalogService.instance;
  await catalog.ensureLoaded();
  final hit = catalog.resolve(typed);
  if (hit != null) return hit;
  if (!context.mounted) return null;

  final request = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Not in the skill list yet'),
      content: Text(
        '"$typed" isn\'t one of our listed skills. Pick one of the suggestions, '
        'or ask us to add it - once it\'s approved it goes straight onto your '
        'profile as a skill you ${offered ? 'teach' : 'want to learn'}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Request it'),
        ),
      ],
    ),
  );
  if (request != true || !context.mounted) return null;

  final messenger = ScaffoldMessenger.of(context);
  final result = await catalog.requestSkill(typed, offered: offered);
  if (result.canonical != null) return result.canonical;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.error ??
            'Requested "$typed". You\'ll get a notification when it\'s added.',
      ),
    ),
  );
  return null;
}
