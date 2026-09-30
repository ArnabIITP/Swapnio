import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:cloud_functions/cloud_functions.dart';

import '../Screen/User/calendar_settings_page.dart';
import '../services/google_calendar_service.dart';
import '../services/swap_service.dart';
import '../theme.dart';
import 'celebration.dart';
import 'rate_session_sheet.dart';
import 'session_time_picker.dart';
import 'swapnio_kit.dart';
import 'swapnio_widgets.dart';

/// Copies the meeting link. The app deliberately doesn't bundle a video SDK -
/// organisers paste their own Meet/Zoom/Jitsi link.
Future<void> copyMeetingLink(BuildContext context, String link) async {
  HapticFeedback.mediumImpact();
  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Meeting link copied: $link')));
}

/// A pending clash: show what overlaps and let the person go ahead anyway.
Future<bool> confirmClashWarnings(
  BuildContext context,
  List<String> warnings,
) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('This overlaps a pending session'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $w'),
            ),
          const SizedBox(height: 4),
          const Text(
            "It isn't confirmed yet, so you can still go ahead - whichever "
            'is accepted first keeps the slot.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('Pick another time'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(d, true),
          child: const Text('Go ahead'),
        ),
      ],
    ),
  );
  return go == true;
}

void _toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      backgroundColor: error ? Colors.redAccent : null,
    ),
  );
}

/// Picks a new time on the busy-aware timeline and asks the other person
/// to move the session (or moves your own unanswered proposal directly).
Future<void> rescheduleSessionFlow(
  BuildContext context,
  String swapId,
  Map<String, dynamic> data,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final participants = List<String>.from(data['participants'] ?? const []);
  final otherId = participants.firstWhere((p) => p != uid, orElse: () => '');
  final otherName =
      ((data['participantNames'] as Map?)?[otherId] as String? ?? 'They')
          .split(' ')
          .first;
  final slot = await showSessionTimePicker(
    context,
    otherUserId: otherId.isEmpty ? null : otherId,
    otherName: otherName,
    initial: (data['scheduledFor'] as Timestamp?)?.toDate(),
    initialMinutes: (data['plannedMinutes'] as num?)?.toInt() ?? 60,
    excludeSwapId: swapId,
    title: 'New time',
  );
  if (slot == null || !context.mounted) return;
  Future<void> send({bool force = false}) async {
    final r = await SwapSessionService.instance.requestReschedule(
      swapId,
      newTime: slot.start,
      plannedMinutes: slot.minutes,
      force: force,
    );
    if (!context.mounted) return;
    if (r.needsConfirm) {
      if (await confirmClashWarnings(context, r.warnings) && context.mounted) {
        await send(force: true);
      }
      return;
    }
    if (!r.isOk) return _toast(context, r.error!, error: true);
    _toast(
      context,
      r.data['applied'] == true
          ? 'Moved to ${DateFormat('EEE d MMM, h:mm a').format(slot.start)}'
          : 'Asked $otherName to move it to ${DateFormat('EEE d MMM, h:mm a').format(slot.start)}. '
                'The current time stays booked until they answer.',
    );
  }

  await send();
}

/// Accept or keep the current time when the other person asked to move.
Future<void> answerRescheduleFlow(
  BuildContext context,
  String swapId, {
  required bool accept,
}) async {
  final r = await SwapSessionService.instance.respondReschedule(
    swapId,
    accept: accept,
  );
  if (!context.mounted) return;
  if (!r.isOk) return _toast(context, r.error!, error: true);
  _toast(context, accept ? 'Session moved.' : 'Kept the original time.');
}

/// Your own Google Calendar isn't connected: explain why it's needed and
/// send the person to the one place Swapnio asks for it.
Future<void> showConnectCalendarGate(
  BuildContext context, {
  String? message,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFC08A1E)),
      title: const Text('Connect Google Calendar'),
      content: Text(
        message ??
            'Booking a session needs Google Calendar for both of you: it puts '
                'the session in your calendars with a Google Meet link, and keeps '
                'you from double-booking.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('Not now'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(d, true),
          icon: const Icon(Icons.calendar_month_rounded, size: 18),
          label: const Text('Connect'),
        ),
      ],
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CalendarSettingsPage()),
    );
  }
}

/// The other person hasn't connected yet: say so, and offer to ask them.
Future<void> showPartnerCalendarGate(
  BuildContext context, {
  required String otherUserId,
  required String otherName,
  String? message,
  bool alreadyAsked = false,
}) async {
  final ask = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.event_busy_rounded),
      title: Text('$otherName needs to connect'),
      content: Text(
        message ??
            "$otherName hasn't connected Google Calendar yet, so you can't book "
                'a session with them. Both people need it for the Meet link and '
                'calendar invites.',
      ),
      actions: [
        if (alreadyAsked)
          ElevatedButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('OK'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(d, true),
            icon: const Icon(Icons.notifications_active_rounded, size: 18),
            label: const Text('Let them know'),
          ),
        ],
      ],
    ),
  );
  if (ask != true || !context.mounted) return;
  try {
    await FirebaseFunctions.instance.httpsCallable('askToConnectCalendar').call(
      {'otherUserId': otherUserId},
    );
    if (context.mounted) {
      _toast(context, "We've asked $otherName to connect Google Calendar.");
    }
  } catch (_) {
    if (context.mounted) {
      _toast(context, 'Could not send the reminder.', error: true);
    }
  }
}

/// Handles a scheduling error that's about Google Calendar. Returns true if
/// it was one (and has been shown), false otherwise.
Future<bool> handleCalendarError(
  BuildContext context,
  SessionResult r, {
  required String otherUserId,
  required String otherName,
}) async {
  if (r.code == GoogleCalendarService.requiredMarker) {
    await showConnectCalendarGate(context, message: r.error);
    return true;
  }
  if (r.code == GoogleCalendarService.partnerMarker) {
    await showPartnerCalendarGate(
      context,
      otherUserId: otherUserId,
      otherName: otherName,
      message: r.error,
      alreadyAsked: true,
    );
    return true;
  }
  return false;
}

/// Accept or decline a proposal. Accepting needs Google Calendar on BOTH
/// accounts; if one is missing, say which and point to the fix.
Future<void> answerProposalFlow(
  BuildContext context,
  String swapId, {
  required bool accept,
  String otherUserId = '',
  String otherName = 'They',
}) async {
  final r = await SwapSessionService.instance.respond(swapId, accept: accept);
  if (!context.mounted) return;
  if (await handleCalendarError(
    context,
    r,
    otherUserId: otherUserId,
    otherName: otherName,
  )) {
    return;
  }
  if (r.error != null) return _toast(context, r.error!, error: true);
  _toast(
    context,
    accept
        ? 'Accepted - it is in both calendars with a Meet link.'
        : 'Session declined.',
  );
}

/// The session's video call link (from its calendar event).
String sessionMeetLink(Map<String, dynamic> data) {
  final cal = data['calendar'];
  final link = cal is Map ? (cal['meetLink'] as String? ?? '') : '';
  return link.isNotEmpty ? link : (data['meetingLink'] as String? ?? '').trim();
}

/// Opens the call in the Meet app (or browser) at Google's join screen.
Future<void> openMeetLink(BuildContext context, String link) async {
  final ok = await launchUrl(
    Uri.parse(link),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) {
    _toast(
      context,
      "Couldn't open the call. Is Google Meet installed?",
      error: true,
    );
  }
}

/// Cancel with an optional reason (required close to the start). Works for
/// your own proposal, an accepted session, or a running one in its first
/// 30 minutes; the server has the final say on each.
Future<void> cancelSessionFlow(
  BuildContext context,
  String swapId,
  Map<String, dynamic> data,
) async {
  final scheduled = (data['scheduledFor'] as Timestamp?)?.toDate();
  final running = data['startedAt'] != null;
  final late =
      !running &&
      data['status'] == 'accepted' &&
      scheduled != null &&
      scheduled.difference(DateTime.now()) <
          const Duration(hours: SwapSessionService.lateCancelHours);
  final controller = TextEditingController();
  String? picked;
  const quick = [
    'Something came up',
    'Not feeling well',
    'Need to prepare more',
    'Wrong topic',
  ];
  final go = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(running ? 'Stop this session?' : 'Cancel this session?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                running
                    ? 'It ends now and no time is counted for either of you.'
                    : late
                    ? "It starts in under ${SwapSessionService.lateCancelHours} hours, so please say why - it's shared with your partner."
                    : 'Your partner is told, and the time is freed on both calendars.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in quick)
                    ChoiceChip(
                      label: Text(q, style: const TextStyle(fontSize: 12)),
                      selected: picked == q,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => set(() {
                        picked = picked == q ? null : q;
                        controller.text = picked ?? '';
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLength: 300,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: late || running
                      ? 'Reason${late ? '' : ' (optional)'}'
                      : 'Reason (optional)',
                ),
                onChanged: (_) => set(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep it'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: late && controller.text.trim().isEmpty
                ? null
                : () => Navigator.pop(d, true),
            child: Text(running ? 'Stop session' : 'Cancel session'),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  final r = await SwapSessionService.instance.cancel(
    swapId,
    reason: controller.text.trim(),
  );
  if (!context.mounted) return;
  if (!r.isOk) return _toast(context, r.error!, error: true);
  _toast(context, running ? 'Session stopped.' : 'Session cancelled.');
}

/// Confirming captures what actually happened - notes and whether the goal
/// was met. A session only counts once both people have confirmed it AND
/// rated each other, so the first confirmation shows a "waiting for your
/// partner" note and the second opens the rating straight away.
Future<void> completeSessionFlow(
  BuildContext context,
  String swapId,
  Map<String, dynamic> swapData,
) async {
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
              onChanged: (value) =>
                  setDialogState(() => goalAchieved = value ?? true),
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final result = await SwapSessionService.instance.confirmCompletion(
    swapId,
    sessionNotes: notesController.text.trim(),
    goalAchieved: goalAchieved,
    swapData: swapData,
  );
  if (!result.ok) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.error ?? 'Could not complete the session. Please try again.',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
    return;
  }
  if (!result.awaitingRatings) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          "Confirmed. Once your partner confirms too, you'll both rate the "
          "session - we'll remind them.",
        ),
        duration: Duration(seconds: 5),
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await rateSessionFlow(context, swapId, swapData);
}

/// Opens the rating for a confirmed session, then celebrates if that was
/// the rating that made it count.
Future<void> rateSessionFlow(
  BuildContext context,
  String swapId,
  Map<String, dynamic> swapData,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final completed = await showRateSessionSheet(
    context,
    swapId: swapId,
    otherName: sessionOtherFirstName(swapData),
  );
  if (!context.mounted) return;
  if (completed) {
    await celebrateCompletedSession(context);
    return;
  }
  // Closed without rating, or rated first: either way it isn't counted yet.
  final rated = await SwapSessionService.instance.hasRated(swapId);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        rated
            ? "Thanks! It's added once ${sessionOtherFirstName(swapData)} rates too."
            : 'No rush - you can add your rating from the session anytime.',
      ),
      duration: const Duration(seconds: 5),
    ),
  );
}

/// The payoff once both have rated: the session now counts.
Future<void> celebrateCompletedSession(BuildContext context) async {
  final completedCount = await _completedSessionCount();
  if (!context.mounted) return;
  // Show the badge itself when this swap crossed a milestone.
  const milestoneBadges = {
    1: 'first_swap',
    5: '5_swaps',
    10: '10_swaps',
    25: '25_swaps',
  };
  await showCelebrationDialog(
    context,
    icon: Icons.workspace_premium,
    badgeId: milestoneBadges[completedCount],
    headline: completedCount <= 1
        ? 'Your first swap is done!'
        : 'Swap #$completedCount complete!',
    message:
        "You've both rated it, so it now counts - hours, badges and your "
        'Skill Passport are updated, and you both earned points.',
    extra: const AnimatedPointsBadge(points: 25),
    primaryLabel: 'Nice',
  );
}

/// The live state of an accepted session: check in, the running clock, and
/// completion. Every step is enforced by the server (see functions/
/// sessions.js); this panel only reflects it and explains what's next.
class SessionTimerPanel extends StatefulWidget {
  final String swapId;
  final Map<String, dynamic> data;

  const SessionTimerPanel({
    super.key,
    required this.swapId,
    required this.data,
  });

  @override
  State<SessionTimerPanel> createState() => _SessionTimerPanelState();
}

class _SessionTimerPanelState extends State<SessionTimerPanel> {
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // One tick a second keeps the clock and the unlock countdown live; it's
    // cheap and only runs while the panel is on screen.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    final error = await SwapSessionService.instance.checkIn(widget.swapId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
    }
  }

  /// One tap: check in (the clock starts once both have) and open the call.
  Future<void> _join(String link) async {
    setState(() => _busy = true);
    final error = await SwapSessionService.instance.checkIn(widget.swapId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
      );
      return;
    }
    await openMeetLink(context, link);
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    await completeSessionFlow(context, widget.swapId, widget.data);
    if (mounted) setState(() => _busy = false);
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final data = widget.data;
    final participants = List<String>.from(data['participants'] ?? const []);
    final partnerId = participants.firstWhere(
      (p) => p != _uid,
      orElse: () => '',
    );
    final names = Map<String, dynamic>.from(
      data['participantNames'] ?? const {},
    );
    final partner = ((names[partnerId] as String?) ?? 'your partner')
        .split(' ')
        .first;
    final checkIns = Map<String, dynamic>.from(data['checkIns'] ?? const {});
    final confirmations = Map<String, dynamic>.from(
      data['completionConfirmations'] ?? const {},
    );
    final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
    final endedAt = (data['endedAt'] as Timestamp?)?.toDate();
    final scheduled = (data['scheduledFor'] as Timestamp?)?.toDate();
    final now = DateTime.now();
    const minimum = Duration(minutes: SwapSessionService.minSessionMinutes);

    String eyebrow;
    String headline;
    String detail;
    String? action;
    VoidCallback? onAction;
    double? progress;
    Color accent = c.get;
    // The ✕ beside the locked Complete button: a running session can be
    // stopped only before the 30-minute minimum is reached.
    var canStop = false;

    if (!checkIns.containsKey(_uid)) {
      final opensAt = scheduled?.subtract(
        const Duration(minutes: SwapSessionService.checkInEarlyMinutes),
      );
      final notYet = opensAt != null && now.isBefore(opensAt);
      eyebrow = 'STEP 1 OF 3 · CHECK IN';
      headline = notYet ? 'Check-in opens soon' : 'Check in when you join';
      detail = notYet
          ? 'Opens at ${DateFormat.jm().format(opensAt)}, ${SwapSessionService.checkInEarlyMinutes} minutes '
                'before the session. The clock starts once you both check in.'
          : 'The clock starts once you and $partner have both checked in.'
                '${checkIns.containsKey(partnerId) ? ' $partner is already here.' : ''}';
      final link = sessionMeetLink(data);
      if (link.isNotEmpty) {
        detail = notYet
            ? 'Join opens at ${DateFormat.jm().format(opensAt)}. One tap checks you in '
                  'and opens Google Meet - the clock starts once you both join.'
            : 'One tap checks you in and opens Google Meet. The clock starts once '
                  'you and $partner have both joined.'
                  '${checkIns.containsKey(partnerId) ? ' $partner is already here.' : ''}';
        action = notYet ? null : 'Join session';
        onAction = notYet ? null : () => _join(link);
      } else {
        action = notYet ? null : "I'm in the session";
        onAction = notYet ? null : _checkIn;
      }
    } else if (startedAt == null) {
      eyebrow = 'STEP 1 OF 3 · CHECK IN';
      headline = 'Waiting for $partner';
      detail =
          "You're checked in. The clock starts as soon as $partner checks in too.";
    } else if (!confirmations.containsKey(_uid)) {
      final elapsed = (endedAt ?? now).difference(startedAt);
      final unlocked = endedAt != null || elapsed >= minimum;
      accent = unlocked ? c.success : c.give;
      progress = (elapsed.inSeconds / minimum.inSeconds).clamp(0.0, 1.0);
      eyebrow = 'STEP 2 OF 3 · IN SESSION';
      headline = _clock(elapsed);
      if (confirmations.containsKey(partnerId)) {
        detail =
            '$partner marked the session as done. Confirm it so it counts for you both.';
        action = 'Confirm session';
      } else if (unlocked) {
        detail =
            'The ${SwapSessionService.minSessionMinutes}-minute minimum is done. '
            'Complete it when you finish - up to 2 hours is counted.';
        action = 'Complete session';
      } else {
        final left = minimum - elapsed;
        detail =
            'Sessions count after ${SwapSessionService.minSessionMinutes} minutes - '
            '${left.inMinutes + 1} min to go.';
        action = 'Complete unlocks in ${_clock(left)}';
        canStop = confirmations.isEmpty;
      }
      onAction = unlocked ? _complete : null;
    } else {
      final minutes = (data['durationMinutes'] as num?)?.toInt() ?? 0;
      accent = c.success;
      eyebrow = 'STEP 3 OF 3 · CONFIRMED';
      headline = '$minutes min counted';
      detail =
          'Waiting for $partner to confirm - it counts once you both have. '
          "We'll remind them.";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                eyebrow,
                style: AppTheme.label(
                  fontSize: 10.5,
                  color: c.textMuted,
                ).copyWith(letterSpacing: 1.6),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: AppTheme.display(
              fontSize: progress != null ? 40 : 22,
              color: c.text,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: c.surfaceLow,
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            detail,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.45,
              color: c.textMuted,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: action,
                    icon: onAction == null
                        ? Icons.lock_clock_rounded
                        : Icons.check_circle_rounded,
                    loading: _busy,
                    onTap: _busy ? null : onAction,
                  ),
                ),
                if (onAction == null &&
                    !canStop &&
                    sessionMeetLink(data).isNotEmpty &&
                    checkIns.containsKey(_uid) &&
                    !confirmations.containsKey(_uid)) ...[
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Back to the call',
                    child: Pressable(
                      onTap: () => openMeetLink(context, sessionMeetLink(data)),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: c.win,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.videocam_rounded,
                          color: c.onWin,
                          semanticLabel: 'Back to the call',
                        ),
                      ),
                    ),
                  ),
                ],
                if (canStop) ...[
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'Stop and cancel this session',
                    child: Pressable(
                      onTap: _busy
                          ? null
                          : () => cancelSessionFlow(
                              context,
                              widget.swapId,
                              widget.data,
                            ),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.redAccent,
                          semanticLabel: 'Stop and cancel this session',
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
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
        ok
            ? 'Session marked as a no-show.'
            : 'Could not update the session. Please try again.',
      ),
      backgroundColor: ok ? null : Colors.redAccent,
    ),
  );
}

/// "Arnab teaches Guitar", "Swap: Guitar ↔ Python" - how a session reads for
/// the viewer, covering one-way sessions (one skill empty).
String sessionSummary(Map<String, dynamic> data, String uid) {
  final sides = swapSidesFor(data, uid);
  if (sides.myGive.isNotEmpty && sides.myGet.isNotEmpty) {
    return 'You teach ${sides.myGive} · you learn ${sides.myGet}';
  }
  if (sides.myGive.isNotEmpty) return 'You teach ${sides.myGive}';
  if (sides.myGet.isNotEmpty) return 'You learn ${sides.myGet}';
  return 'Swap session';
}

/// Which skill each side teaches, from the viewer's perspective.
/// `skillOffered` is what the organiser (`createdBy`) teaches.
({String myGive, String myGet}) swapSidesFor(
  Map<String, dynamic> data,
  String uid,
) {
  final offered = (data['skillOffered'] ?? '').toString();
  final wanted = (data['skillWanted'] ?? '').toString();
  return data['createdBy'] == uid
      ? (myGive: offered, myGet: wanted)
      : (myGive: wanted, myGet: offered);
}

/// Shown on an accepted session while a new time is waiting for an answer:
/// the other person sees Accept / Keep current time; the asker sees that
/// the current time still holds.
class RescheduleRequestBanner extends StatelessWidget {
  final String swapId;
  final Map<String, dynamic> data;

  const RescheduleRequestBanner({
    super.key,
    required this.swapId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final r = data['pendingReschedule'];
    if (r is! Map) return const SizedBox.shrink();
    final c = context.sw;
    final at = (r['at'] as Timestamp?)?.toDate();
    if (at == null) return const SizedBox.shrink();
    final minutes = (r['plannedMinutes'] as num?)?.toInt() ?? 60;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final mine = r['by'] == uid;
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final asker = ((names[r['by']] as String?) ?? 'Your partner')
        .split(' ')
        .first;
    final when = '${DateFormat('EEE d MMM, h:mm a').format(at)} ($minutes min)';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.get.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.get.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_calendar_rounded, size: 18, color: c.get),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mine
                      ? 'You asked to move this to $when'
                      : '$asker asked to move this to $when',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            mine
                ? 'The current time stays booked until they answer.'
                : 'The current time stays booked unless you accept.',
            style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
          ),
          if (!mine) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        answerRescheduleFlow(context, swapId, accept: false),
                    child: const Text('Keep current'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        answerRescheduleFlow(context, swapId, accept: true),
                    child: const Text('Accept new time'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The other participant's id, from the viewer's side.
String sessionOtherId(Map<String, dynamic> data) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return List<String>.from(
    data['participants'] ?? const [],
  ).firstWhere((p) => p != uid, orElse: () => '');
}

/// The other participant's first name.
String sessionOtherFirstName(Map<String, dynamic> data) {
  final name =
      (data['participantNames'] as Map?)?[sessionOtherId(data)] as String?;
  return (name ?? 'They').split(' ').first;
}
