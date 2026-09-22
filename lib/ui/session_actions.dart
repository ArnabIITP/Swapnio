import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/swap_service.dart';
import '../theme.dart';
import 'celebration.dart';

/// Copies the meeting link. The app deliberately doesn't bundle a video SDK -
/// organisers paste their own Meet/Zoom/Jitsi link.
Future<void> copyMeetingLink(BuildContext context, String link) async {
  HapticFeedback.mediumImpact();
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Meeting link copied: $link')));
}

/// Date + time pickers, then reschedules and notifies the partner.
Future<void> rescheduleSessionFlow(
  BuildContext context,
  String swapId,
  Map<String, dynamic> data,
) async {
  final current = data['scheduledFor'] as Timestamp?;
  final initial = current?.toDate() ?? DateTime.now().add(const Duration(days: 1));
  final now = DateTime.now();

  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(now) ? now : initial,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null || !context.mounted) return;

  final newTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  final messenger = ScaffoldMessenger.of(context);
  final myName = FirebaseAuth.instance.currentUser?.displayName ?? 'Swapnio user';
  final ok = await SwapSessionService.instance.rescheduleSession(
    swapId: swapId,
    swapData: data,
    myName: myName,
    newTime: newTime,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        ok
            ? 'Session rescheduled to ${DateFormat.yMMMd().add_jm().format(newTime)}'
            : 'Could not reschedule the session. Please try again.',
      ),
      backgroundColor: ok ? null : Colors.redAccent,
    ),
  );
}

/// Completing captures what actually happened - notes and whether the goal
/// was met - then celebrates, because finishing a session is the end of the
/// core loop and should feel like an achievement.
Future<void> completeSessionFlow(
  BuildContext context,
  String swapId,
  List<String> participants, {
  VoidCallback? onRate,
}) async {
  final notesController = TextEditingController();
  bool goalAchieved = true;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('How did it go?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Session notes (optional)',
                hintText: 'What did you cover? What is next?',
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: goalAchieved,
              onChanged: (value) => setDialogState(() => goalAchieved = value ?? true),
              title: const Text('We covered what we planned'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final ok = await SwapSessionService.instance.completeSession(
    swapId,
    participants,
    sessionNotes: notesController.text.trim(),
    goalAchieved: goalAchieved,
  );
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not complete the session. Please try again.'),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }

  final completedCount = await _completedSessionCount();
  if (!context.mounted) return;
  // Show the badge itself when this swap crossed a milestone.
  const milestoneBadges = {1: 'first_swap', 5: '5_swaps', 10: '10_swaps', 25: '25_swaps'};
  await showCelebrationDialog(
    context,
    icon: Icons.workspace_premium,
    badgeId: milestoneBadges[completedCount],
    headline: completedCount <= 1
        ? 'Your first swap is done!'
        : 'Swap #$completedCount complete!',
    message: 'You both earned points. Leave a rating while it is fresh - '
        'it is what makes reputation here mean something.',
    extra: const AnimatedPointsBadge(points: 25),
    primaryLabel: 'Rate this swap',
    onPrimary: onRate ?? () {},
    secondaryLabel: 'Later',
  );
}

Future<int> _completedSessionCount() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 0;
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('swaps')
        .where('participants', arrayContains: uid)
        .where('status', isEqualTo: 'completed')
        .get();
    return snapshot.docs.length;
  } catch (_) {
    return 0;
  }
}

Future<void> confirmNoShowFlow(BuildContext context, String swapId) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text("Didn't happen?"),
      content: const Text(
        'This marks the session as a no-show. No points are awarded and '
        "it won't unlock a rating for either of you.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.warmMutedText,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Mark as no-show'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await SwapSessionService.instance.markNoShow(swapId);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        ok ? 'Session marked as a no-show.' : 'Could not update the session. Please try again.',
      ),
      backgroundColor: ok ? null : Colors.redAccent,
    ),
  );
}

/// Which skill each side teaches, from the viewer's perspective.
/// `skillOffered` is what the organiser (`createdBy`) teaches.
({String myGive, String myGet}) swapSidesFor(Map<String, dynamic> data, String uid) {
  final offered = (data['skillOffered'] ?? '').toString();
  final wanted = (data['skillWanted'] ?? '').toString();
  return data['createdBy'] == uid
      ? (myGive: offered, myGet: wanted)
      : (myGive: wanted, myGet: offered);
}
