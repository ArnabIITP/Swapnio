import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/swap_service.dart';
import '../../theme.dart';
import '../../ui/session_actions.dart';
import '../../ui/swapnio_widgets.dart';

/// Everything about one swap session in one place, built for the moments
/// right before it: a live countdown creates anticipation, and the join
/// action sits where the thumb already is.
class SessionDetailPage extends StatefulWidget {
  final String swapId;

  const SessionDetailPage({super.key, required this.swapId});

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  late final Stream<DocumentSnapshot> _swapStream;
  Timer? _ticker;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _swapStream =
        FirebaseFirestore.instance.collection('swaps').doc(widget.swapId).snapshots();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _swapStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) {
            return SafeArea(
              child: Column(
                children: [
                  _topBar(null),
                  const Expanded(
                    child: Center(child: Text('This session no longer exists.')),
                  ),
                ],
              ),
            );
          }
          return _buildBody(data);
        },
      ),
    );
  }

  Widget _topBar(Map<String, dynamic>? data) {
    final c = context.sw;
    final status = data?['status'] as String?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_rounded, color: c.text),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              'Swap session',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
          ),
          if (data != null && status == SwapSessionService.statusAccepted)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, color: c.text),
              onSelected: (v) {
                if (v == 'reschedule') rescheduleSessionFlow(context, widget.swapId, data);
                if (v == 'noshow') confirmNoShowFlow(context, widget.swapId);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reschedule', child: Text('Reschedule')),
                PopupMenuItem(value: 'noshow', child: Text("Didn't happen")),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final c = context.sw;
    final participants = List<String>.from(data['participants'] ?? []);
    final otherId = participants.firstWhere((p) => p != _uid, orElse: () => '');
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherName = (names[otherId] as String?) ?? 'your partner';
    final firstName = otherName.split(' ').first;
    final sides = swapSidesFor(data, _uid);
    final status = (data['status'] as String?) ?? SwapSessionService.statusPending;
    final link = (data['meetingLink'] as String?)?.trim() ?? '';
    final agenda = _agendaItems((data['agenda'] as String?) ?? '');
    final notes = (data['sessionNotes'] as String?)?.trim() ?? '';
    final when = (data['scheduledFor'] as Timestamp?)?.toDate();

    return SafeArea(
      child: Column(
        children: [
          _topBar(data),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                _hero(status, when, sides, firstName),
                const SizedBox(height: 16),
                if (link.isNotEmpty) ...[
                  _linkCard(link),
                  const SizedBox(height: 16),
                ],
                if (agenda.isNotEmpty) ...[
                  _agendaCard(agenda),
                  const SizedBox(height: 16),
                ],
                if (notes.isNotEmpty)
                  _surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notes', style: AppTheme.display(fontSize: 20, color: c.text)),
                        const SizedBox(height: 8),
                        Text(
                          notes,
                          style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted, height: 1.45),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _actionBar(status, data, participants, link, when),
        ],
      ),
    );
  }

  List<String> _agendaItems(String raw) => raw
      .split(RegExp(r'[\n;•]+'))
      .map((s) => s.replaceFirst(RegExp(r'^\s*[-*\d.)]+\s*'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Widget _hero(
    String status,
    DateTime? when,
    ({String myGive, String myGet}) sides,
    String firstName,
  ) {
    final c = context.sw;
    final now = DateTime.now();
    String eyebrow;
    Widget big;

    TextStyle num = AppTheme.display(fontSize: 46, color: c.win, height: 1);
    TextStyle unit = GoogleFonts.manrope(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: Colors.white.withValues(alpha: 0.5),
    );
    Widget unitPair(String v, String u) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [Text(v, style: num), const SizedBox(width: 2), Text(u, style: unit)],
        );

    if (status == SwapSessionService.statusCompleted) {
      eyebrow = 'COMPLETED';
      big = Text('Swap done', style: num);
    } else if (status == SwapSessionService.statusNoShow) {
      eyebrow = 'DID NOT HAPPEN';
      big = Text('No-show', style: num.copyWith(color: Colors.white70));
    } else if (status == SwapSessionService.statusDeclined) {
      eyebrow = 'DECLINED';
      big = Text('Cancelled', style: num.copyWith(color: Colors.white70));
    } else if (when == null) {
      eyebrow = status == SwapSessionService.statusPending ? 'PROPOSED' : 'SCHEDULED';
      big = Text('Time TBD', style: num);
    } else {
      final diff = when.difference(now);
      if (diff.isNegative) {
        eyebrow = diff.inMinutes > -90 ? 'HAPPENING NOW' : 'WAS SCHEDULED';
        big = Text(diff.inMinutes > -90 ? 'Live' : 'Overdue', style: num);
      } else if (diff.inDays >= 1) {
        eyebrow = 'STARTS IN';
        big = Wrap(spacing: 10, children: [
          unitPair('${diff.inDays}', 'd'),
          unitPair('${diff.inHours % 24}', 'h'),
          unitPair((diff.inMinutes % 60).toString().padLeft(2, '0'), 'm'),
        ]);
      } else {
        eyebrow = 'STARTS IN';
        String two(int v) => v.toString().padLeft(2, '0');
        big = Wrap(spacing: 10, children: [
          unitPair(two(diff.inHours), 'h'),
          unitPair(two(diff.inMinutes % 60), 'm'),
          unitPair(two(diff.inSeconds % 60), 's'),
        ]);
      }
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: AppTheme.label(color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 10),
          big,
          const SizedBox(height: 12),
          if (when != null)
            Text(
              '${_dayLabel(when)} · ${DateFormat.jm().format(when)}',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.white.withValues(alpha: 0.8)),
            ),
          const SizedBox(height: 16),
          SwapSplit(
            giveLabel: 'YOU TEACH',
            giveSkill: sides.myGive,
            getLabel: '${firstName.toUpperCase()} TEACHES',
            getSkill: sides.myGet,
          ),
        ],
      ),
    );
  }

  String _dayLabel(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final delta = day.difference(today).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Tomorrow';
    if (delta == -1) return 'Yesterday';
    return DateFormat.MMMEd().format(when);
  }

  Widget _surfaceCard({required Widget child}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.sw.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  Widget _linkCard(String link) {
    final c = context.sw;
    final host = Uri.tryParse(link)?.host ?? '';
    final label = host.contains('meet.google')
        ? 'Google Meet'
        : host.contains('zoom')
            ? 'Zoom'
            : host.contains('jit.si')
                ? 'Jitsi'
                : 'Meeting link';
    return Pressable(
      onTap: () => copyMeetingLink(context, link),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.get.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.videocam_rounded, color: c.get, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.manrope(
                          fontSize: 13.5, fontWeight: FontWeight.w800, color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                    link.replaceFirst(RegExp(r'^https?://'), ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.copy_rounded, size: 18, color: c.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _agendaCard(List<String> items) {
    final c = context.sw;
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Agenda', style: AppTheme.display(fontSize: 20, color: c.text))),
              Text(
                '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w800, color: c.get),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.surfaceLow,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('${i + 1}',
                        style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w800, color: c.textMuted)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(items[i],
                          style: GoogleFonts.manrope(fontSize: 13.5, color: c.text, height: 1.35)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBar(
    String status,
    Map<String, dynamic> data,
    List<String> participants,
    String link,
    DateTime? when,
  ) {
    final c = context.sw;
    final isMine = data['createdBy'] == _uid;
    Widget bar(List<Widget> children) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Row(children: children),
        );
    Widget big(String label, IconData icon, Color bg, Color fg, VoidCallback onTap) => Expanded(
          child: Pressable(
            onTap: onTap,
            child: Container(
              height: 56,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                  Text(label,
                      style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800, color: fg)),
                ],
              ),
            ),
          ),
        );
    Widget square(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Tooltip(
            message: tip,
            child: Pressable(
              onTap: onTap,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
                child: Icon(icon, color: c.text),
              ),
            ),
          ),
        );

    if (status == SwapSessionService.statusPending) {
      if (isMine) {
        return bar([
          Expanded(
            child: Text('Waiting for them to accept',
                style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted)),
          ),
          TextButton(
            onPressed: () => SwapSessionService.instance
                .updateStatus(widget.swapId, SwapSessionService.statusDeclined),
            child: const Text('Cancel'),
          ),
        ]);
      }
      return bar([
        square(Icons.close_rounded, 'Decline', () {
          SwapSessionService.instance.updateStatus(widget.swapId, SwapSessionService.statusDeclined);
        }),
        big('Accept session', Icons.check_rounded, c.cta, c.onCta, () {
          SwapSessionService.instance.updateStatus(widget.swapId, SwapSessionService.statusAccepted);
        }),
      ]);
    }

    if (status != SwapSessionService.statusAccepted) return const SizedBox(height: 8);

    final started = when != null && DateTime.now().isAfter(when);
    void complete() => completeSessionFlow(context, widget.swapId, participants);
    if (started || link.isEmpty) {
      return bar([
        if (link.isNotEmpty)
          square(Icons.videocam_rounded, 'Copy meeting link', () => copyMeetingLink(context, link))
        else
          square(Icons.event_repeat_rounded, 'Reschedule',
              () => rescheduleSessionFlow(context, widget.swapId, data)),
        big('Mark as completed', Icons.check_circle_rounded, c.win, c.onWin, complete),
      ]);
    }
    return bar([
      square(Icons.event_repeat_rounded, 'Reschedule',
          () => rescheduleSessionFlow(context, widget.swapId, data)),
      big('Join call', Icons.call_rounded, c.win, c.onWin, () => copyMeetingLink(context, link)),
    ]);
  }
}
