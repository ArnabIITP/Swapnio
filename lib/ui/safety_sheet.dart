import 'package:flutter/material.dart';
import '../../theme.dart';
import '../services/safety_service.dart';

/// Bottom sheet offering the trust & safety actions for another user:
/// block (with confirmation) and report (reason + optional details).
Future<void> showSafetySheet(
  BuildContext context, {
  required String userId,
  required String displayName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: sheetContext.sw.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined,
                      color: sheetContext.sw.give, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Safety options for $displayName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.block, color: sheetContext.sw.get),
              title: const Text('Block user'),
              subtitle: const Text(
                  'Hides them from your feed and removes pending requests'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _confirmAndBlock(context,
                    userId: userId, displayName: displayName);
              },
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined,
                  color: sheetContext.sw.get),
              title: const Text('Report user'),
              subtitle: const Text('Sends a report to the Swapnio moderators'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showReportDialog(context,
                    userId: userId, displayName: displayName);
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    ),
  );
}

Future<void> _confirmAndBlock(
  BuildContext context, {
  required String userId,
  required String displayName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Block $displayName?'),
      content: const Text(
        'They will disappear from your feed and any pending requests between '
        'you will be removed. You can unblock them later from Privacy settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: dialogContext.sw.get,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Block'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await SafetyService.instance
      .blockUser(userId, displayName: displayName);
  messenger.showSnackBar(
    SnackBar(
      content: Text(ok
          ? '$displayName has been blocked'
          : 'Could not block $displayName. Please try again.'),
      backgroundColor: ok ? context.sw.give : Colors.redAccent,
    ),
  );
}

Future<void> showReportDialog(
  BuildContext context, {
  required String userId,
  required String displayName,
}) async {
  String reason = SafetyService.reportReasons.first;
  final detailsController = TextEditingController();

  final submitted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Report $displayName'),
      content: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final option in SafetyService.reportReasons)
              RadioListTile<String>(
                value: option,
                groupValue: reason,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(option, style: const TextStyle(fontSize: 14)),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => reason = value);
                  }
                },
              ),
            const SizedBox(height: 8),
            TextField(
              controller: detailsController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Submit report'),
        ),
      ],
    ),
  );

  if (submitted != true) return;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await SafetyService.instance.reportUser(
    reportedUserId: userId,
    reason: reason,
    details: detailsController.text.trim(),
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(ok
          ? 'Thanks - our moderators will review this report.'
          : 'Could not send the report. Please try again.'),
      backgroundColor: ok ? context.sw.give : Colors.redAccent,
    ),
  );
}