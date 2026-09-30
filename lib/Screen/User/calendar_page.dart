import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../theme.dart';
import '../../ui/session_actions.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import 'session_detail.dart';

/// Every session on one calendar: a month grid with a dot per day, and the
/// chosen day's sessions underneath. Pending proposals, accepted sessions,
/// sessions waiting for a confirmation and completed ones each read
/// differently; cancelled ones are hidden unless asked for. Live - a
/// cancellation or an accepted new time shows up at once.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  bool _showCancelled = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance
          .collection('swaps')
          .where('participants', arrayContains: _uid)
          .orderBy('createdAt', descending: true)
          .limit(300)
          .snapshots();

  static const _hidden = {'declined'};

  /// What a session looks like on the calendar.
  ({String label, Color color, bool dashed, bool struck}) _style(
    SwapnioColors c,
    Map<String, dynamic> d,
  ) {
    final status = d['status'] as String? ?? 'pending';
    final confirmations = (d['completionConfirmations'] as Map?) ?? const {};
    switch (status) {
      case 'completed':
        return (label: 'Completed', color: c.get, dashed: false, struck: false);
      case 'awaiting_ratings':
        return (
          label: 'Waiting for ratings',
          color: c.get,
          dashed: false,
          struck: false,
        );
      case 'cancelled':
        return (
          label: 'Cancelled',
          color: c.textMuted,
          dashed: false,
          struck: true,
        );
      case 'no_show':
        return (
          label: 'No-show',
          color: c.textMuted,
          dashed: false,
          struck: true,
        );
      case 'accepted':
        if (confirmations.isNotEmpty) {
          return (
            label: confirmations.containsKey(_uid)
                ? 'Waiting for them to confirm'
                : 'Confirm it happened',
            color: const Color(0xFFC08A1E),
            dashed: false,
            struck: false,
          );
        }
        if (d['startedAt'] != null) {
          return (
            label: 'In session',
            color: c.success,
            dashed: false,
            struck: false,
          );
        }
        return (
          label: d['pendingReschedule'] != null ? 'New time asked' : 'Accepted',
          color: c.success,
          dashed: false,
          struck: false,
        );
      default:
        return (
          label: d['createdBy'] == _uid ? 'Proposed' : 'Needs your answer',
          color: c.give,
          dashed: true,
          struck: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snap) {
            final all = [
              for (final doc
                  in snap.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                if (!_hidden.contains(doc.data()['status']) &&
                    doc.data()['scheduledFor'] is Timestamp)
                  (id: doc.id, data: doc.data()),
            ];
            final byDay =
                <DateTime, List<({String id, Map<String, dynamic> data})>>{};
            for (final s in all) {
              if (!_showCancelled &&
                  const {'cancelled', 'no_show'}.contains(s.data['status'])) {
                continue;
              }
              final day = DateUtils.dateOnly(
                (s.data['scheduledFor'] as Timestamp).toDate(),
              );
              (byDay[day] ??= []).add(s);
            }
            for (final list in byDay.values) {
              list.sort(
                (a, b) => (a.data['scheduledFor'] as Timestamp).compareTo(
                  b.data['scheduledFor'] as Timestamp,
                ),
              );
            }
            final today = byDay[_day] ?? const [];
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                SwapHeader(
                  title: 'Calendar',
                  subtitle: 'All your sessions in one place',
                  action: IconButton(
                    tooltip: 'Today',
                    onPressed: () => setState(() {
                      final now = DateTime.now();
                      _month = DateTime(now.year, now.month);
                      _day = DateUtils.dateOnly(now);
                    }),
                    icon: Icon(Icons.today_rounded, color: c.text),
                  ),
                ),
                const SizedBox(height: 14),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                  child: _monthGrid(c, byDay),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateUtils.isSameDay(_day, DateTime.now())
                            ? 'Today'
                            : DateFormat('EEEE d MMMM').format(_day),
                        style: AppTheme.display(fontSize: 20, color: c.text),
                      ),
                    ),
                    FilterChip(
                      label: const Text(
                        'Cancelled',
                        style: TextStyle(fontSize: 12),
                      ),
                      selected: _showCancelled,
                      visualDensity: VisualDensity.compact,
                      onSelected: (v) => setState(() => _showCancelled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (today.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'Nothing on this day.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(color: c.textMuted),
                    ),
                  )
                else
                  for (final s in today) _sessionTile(c, s.id, s.data),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _monthGrid(
    SwapnioColors c,
    Map<DateTime, List<({String id, Map<String, dynamic> data})>> byDay,
  ) {
    final first = _month;
    final daysInMonth = DateUtils.getDaysInMonth(first.year, first.month);
    final lead = (first.weekday + 6) % 7;
    final cells = lead + daysInMonth;
    final rows = (cells / 7).ceil();
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                DateFormat.yMMMM().format(_month),
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Row(
          children: [
            for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: AppTheme.label(fontSize: 10, color: c.textMuted),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _dayCell(c, r * 7 + col - lead + 1, byDay)),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(
    SwapnioColors c,
    int dayNumber,
    Map<DateTime, List<({String id, Map<String, dynamic> data})>> byDay,
  ) {
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 46);
    }
    final day = DateTime(_month.year, _month.month, dayNumber);
    final selected = DateUtils.isSameDay(day, _day);
    final isToday = DateUtils.isSameDay(day, DateTime.now());
    final sessions = byDay[day] ?? const [];
    final colors = {for (final s in sessions.take(3)) _style(c, s.data).color};
    return GestureDetector(
      onTap: () => setState(() => _day = day),
      child: Container(
        height: 46,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? c.cta : null,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !selected ? Border.all(color: c.give) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNumber',
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected ? c.onCta : c.text,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final col in colors)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: selected ? c.win : col,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionTile(SwapnioColors c, String id, Map<String, dynamic> d) {
    final style = _style(c, d);
    final start = (d['scheduledFor'] as Timestamp).toDate();
    final minutes = (d['plannedMinutes'] as num?)?.toInt() ?? 60;
    final end =
        (d['endsAt'] as Timestamp?)?.toDate() ??
        start.add(Duration(minutes: minutes));
    final participants = List<String>.from(d['participants'] ?? const []);
    final other = participants.firstWhere((p) => p != _uid, orElse: () => '');
    final name =
        ((d['participantNames'] as Map?)?[other] as String?) ?? 'Your partner';
    final strike = style.struck ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SessionDetailPage(swapId: id)),
        ),
        child: CustomPaint(
          foregroundPainter: style.dashed
              ? _DashedBorder(style.color, 18)
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: style.dashed
                  ? null
                  : Border(left: BorderSide(color: style.color, width: 4)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat.jm().format(start),
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                          decoration: strike,
                        ),
                      ),
                      Text(
                        DateFormat.jm().format(end),
                        style: GoogleFonts.manrope(
                          fontSize: 11.5,
                          color: c.textMuted,
                          decoration: strike,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                          decoration: strike,
                        ),
                      ),
                      Text(
                        sessionSummary(d, _uid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: c.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TintTag(style.label, color: style.color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorder(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 6), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
