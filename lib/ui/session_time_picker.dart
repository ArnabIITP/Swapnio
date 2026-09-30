import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/swap_service.dart';
import '../theme.dart';
import 'swapnio_kit.dart';
import 'swapnio_widgets.dart';

/// A chosen session slot.
typedef SessionSlot = ({DateTime start, int minutes});

/// Day timeline for picking a session time, with both people's busy blocks
/// drawn in: yours labelled ("With Riya"), theirs only as "Busy". A slot that
/// overlaps an accepted session (or someone's shared Google busy time) can't
/// be picked; one that overlaps a pending proposal shows a warning. The
/// server checks again when the session is proposed or moved.
Future<SessionSlot?> showSessionTimePicker(
  BuildContext context, {
  String? otherUserId,
  String otherName = 'They',
  DateTime? initial,
  int initialMinutes = 60,
  String? excludeSwapId,
  String title = 'Pick a time',
}) {
  return showModalBottomSheet<SessionSlot>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TimePickerSheet(
      otherUserId: otherUserId,
      otherName: otherName,
      initial: initial,
      initialMinutes: initialMinutes,
      excludeSwapId: excludeSwapId,
      title: title,
    ),
  );
}

class _TimePickerSheet extends StatefulWidget {
  final String? otherUserId;
  final String otherName;
  final DateTime? initial;
  final int initialMinutes;
  final String? excludeSwapId;
  final String title;

  const _TimePickerSheet({
    required this.otherUserId,
    required this.otherName,
    required this.initial,
    required this.initialMinutes,
    required this.excludeSwapId,
    required this.title,
  });

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  // The whole day, midnight to midnight.
  static const int _firstHour = 0;
  static const int _lastHour = 24;
  static const int _step = 15;
  static const double _rowHeight = 22;
  static const int _days = 28;

  late DateTime _day;
  late int _minutes;
  DateTime? _start;
  BusyTimes _busy = const BusyTimes([], []);
  bool _loading = true;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    final today = DateUtils.dateOnly(DateTime.now());
    _day = init != null && !init.isBefore(today)
        ? DateUtils.dateOnly(init)
        : today;
    _minutes = SwapSessionService.plannedLengths.contains(widget.initialMinutes)
        ? widget.initialMinutes
        : 60;
    _start = init != null && init.isAfter(DateTime.now()) ? init : null;
    _load(scrollTo: _start);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({DateTime? scrollTo}) async {
    setState(() => _loading = true);
    final busy = await SwapSessionService.instance.busyTimes(
      from: _day,
      to: _day.add(const Duration(days: 1)),
      otherUserId: widget.otherUserId,
      excludeSwapId: widget.excludeSwapId,
    );
    if (!mounted) return;
    setState(() {
      _busy = busy;
      _loading = false;
    });
    // Open near the chosen time, or the next hour today, or mid-morning.
    final target =
        scrollTo ??
        (DateUtils.isSameDay(_day, DateTime.now())
            ? DateTime.now()
            : _day.add(const Duration(hours: 9)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final rows =
          ((target.hour - _firstHour) * 60 + target.minute) / _step - 2;
      _scroll.jumpTo(
        (rows * _rowHeight).clamp(0.0, _scroll.position.maxScrollExtent),
      );
    });
  }

  DateTime _at(int row) =>
      _day.add(Duration(minutes: _firstHour * 60 + row * _step));

  int get _rowCount => (_lastHour - _firstHour) * 60 ~/ _step;

  static bool _overlaps(DateTime s, DateTime e, BusyBlock b) {
    const pad = Duration(minutes: 10);
    return s.isBefore(b.end.add(pad)) && b.start.subtract(pad).isBefore(e);
  }

  /// null = fine; otherwise why this slot is blocked or risky.
  ({bool blocked, String message})? _problem(DateTime start) {
    final end = start.add(Duration(minutes: _minutes));
    for (final b in _busy.mine) {
      if (_overlaps(start, end, b)) {
        return (
          blocked: b.isFirm,
          message: b.isFirm
              ? 'You already have a session ${b.label?.toLowerCase() ?? ''} then.'
              : 'Overlaps your pending session ${b.label?.toLowerCase() ?? ''}.',
        );
      }
    }
    for (final b in _busy.theirs) {
      if (_overlaps(start, end, b)) {
        return (
          blocked: b.isFirm,
          message: b.isFirm
              ? '${widget.otherName} is busy then.'
              : '${widget.otherName} has a pending session then.',
        );
      }
    }
    return null;
  }

  void _pick(int row) {
    final start = _at(row);
    if (start.isBefore(DateTime.now())) return;
    HapticFeedback.selectionClick();
    setState(() => _start = start);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final start = _start;
    final problem = start == null ? null : _problem(start);
    final end = start?.add(Duration(minutes: _minutes));
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.9,
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTheme.display(fontSize: 22, color: c.text),
                  ),
                ),
                Text(
                  DateFormat.MMMM().format(_day),
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _dayStrip(c),
          _lengthRow(c),
          _legend(c),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _timeline(c),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (problem != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          problem.blocked
                              ? Icons.block_rounded
                              : Icons.warning_amber_rounded,
                          size: 16,
                          color: problem.blocked
                              ? Colors.redAccent
                              : const Color(0xFFC08A1E),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            problem.message,
                            style: GoogleFonts.manrope(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: problem.blocked
                                  ? Colors.redAccent
                                  : const Color(0xFFC08A1E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                PillButton(
                  label: start == null
                      ? 'Tap a free time above'
                      : '${DateFormat('EEE d MMM, h:mm').format(start)} – ${DateFormat.jm().format(end!)}',
                  icon: Icons.check_rounded,
                  onTap: start == null || problem?.blocked == true
                      ? null
                      : () => Navigator.pop(context, (
                          start: start,
                          minutes: _minutes,
                        )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayStrip(SwapnioColors c) {
    final today = DateUtils.dateOnly(DateTime.now());
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _days,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final day = today.add(Duration(days: i));
          final on = DateUtils.isSameDay(day, _day);
          return Pressable(
            onTap: () {
              if (on) return;
              setState(() {
                _day = day;
                _start = null;
              });
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 50,
              decoration: BoxDecoration(
                color: on ? c.cta : c.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    i == 0 ? 'Today' : DateFormat.E().format(day),
                    style: GoogleFonts.manrope(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: on ? c.onCta : c.textMuted,
                    ),
                  ),
                  Text(
                    '${day.day}',
                    style: GoogleFonts.manrope(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: on ? c.onCta : c.text,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _lengthRow(SwapnioColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
    child: Row(
      children: [
        Text('LENGTH', style: AppTheme.label(fontSize: 10, color: c.textMuted)),
        const SizedBox(width: 12),
        for (final m in SwapSessionService.plannedLengths)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('$m min', style: const TextStyle(fontSize: 12)),
              selected: _minutes == m,
              visualDensity: VisualDensity.compact,
              selectedColor: c.get.withValues(alpha: 0.18),
              onSelected: (_) => setState(() => _minutes = m),
            ),
          ),
      ],
    ),
  );

  Widget _legend(SwapnioColors c) {
    Widget dot(Color color, String label, {bool faint = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: faint ? 0.25 : 0.55),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.manrope(fontSize: 11, color: c.textMuted),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          dot(c.get, 'You'),
          if (widget.otherUserId != null) dot(c.give, widget.otherName),
          dot(c.textMuted, 'Pending', faint: true),
        ],
      ),
    );
  }

  Widget _timeline(SwapnioColors c) {
    const labelWidth = 56.0;
    final start = _start;
    return LayoutBuilder(
      builder: (context, box) {
        final laneWidth = box.maxWidth - labelWidth - 32;
        final showTheirs = widget.otherUserId != null;
        final lane = showTheirs ? (laneWidth - 6) / 2 : laneWidth;
        // Measured from the start of the day, so a block from the evening
        // before (or running past midnight) lands in the right place.
        double top(DateTime t) =>
            (t.difference(_day).inMinutes - _firstHour * 60) /
            _step *
            _rowHeight;
        Widget block(BusyBlock b, double left, Color color, String text) {
          // Clip to this day: a block from the night before starts at the
          // top, one running past midnight stops at the bottom.
          final total = _rowCount * _rowHeight;
          final y = top(b.start).clamp(0.0, total).toDouble();
          final double h = math.max(
            8.0,
            math.min(top(b.end), total) - y,
          );
          final pending = !b.isFirm;
          return Positioned(
            left: labelWidth + left,
            top: y,
            width: lane,
            height: h,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: pending ? 0.14 : 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: color.withValues(alpha: pending ? 0.35 : 0.7),
                  ),
                ),
                child: Text(
                  pending ? '$text (pending)' : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            height: _rowCount * _rowHeight,
            child: Stack(
              children: [
                for (var row = 0; row < _rowCount; row++)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: row * _rowHeight,
                    height: _rowHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pick(row),
                      child: Row(
                        children: [
                          SizedBox(
                            width: labelWidth,
                            child: row % 4 == 0
                                ? Text(
                                    DateFormat.j().format(_at(row)),
                                    style: GoogleFonts.manrope(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: _at(row).isBefore(DateTime.now())
                                          ? c.border
                                          : c.textMuted,
                                    ),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: _at(row).isBefore(DateTime.now())
                                    ? c.surfaceLow.withValues(alpha: 0.6)
                                    : null,
                                border: Border(
                                  top: BorderSide(
                                    color: c.border.withValues(
                                      alpha: row % 4 == 0 ? 0.9 : 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final b in _busy.mine)
                  block(b, 0, c.get, b.label ?? 'You'),
                if (showTheirs)
                  for (final b in _busy.theirs)
                    block(
                      b,
                      lane + 6,
                      c.give,
                      b.kind == 'external' ? 'Busy (calendar)' : 'Busy',
                    ),
                if (start != null && DateUtils.isSameDay(start, _day))
                  Positioned(
                    left: labelWidth - 4,
                    right: -4,
                    top: top(start),
                    height: _minutes / _step * _rowHeight,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.win.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.text, width: 2),
                        ),
                        alignment: Alignment.topLeft,
                        padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                        child: Text(
                          '${DateFormat.jm().format(start)} · $_minutes min',
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
