import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/skill_catalog_service.dart';
import '../services/swap_service.dart';
import '../theme.dart';
import 'session_actions.dart';
import 'session_time_picker.dart';
import 'swapnio_kit.dart';
import 'swapnio_widgets.dart';

/// Propose a session: a two-way swap, or just teaching / just learning,
/// with a time picked on the busy-aware timeline. Returns true when sent.
Future<bool> showProposeSessionSheet(
  BuildContext context, {
  required String otherUserId,
  required String otherName,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final profiles = await Future.wait([
    FirebaseFirestore.instance.collection('users').doc(uid).get(),
    FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
  ]);
  await SkillCatalogService.instance.ensureLoaded();
  if (!context.mounted) return false;
  // Google Calendar is required of both people before anything else.
  bool connected(DocumentSnapshot doc) =>
      (doc.data() as Map<String, dynamic>?)?['calendarConnected'] == true;
  if (!connected(profiles[0])) {
    await showConnectCalendarGate(context);
    return false;
  }
  if (!connected(profiles[1])) {
    await showPartnerCalendarGate(
      context,
      otherUserId: otherUserId,
      otherName: otherName.split(' ').first,
    );
    return false;
  }
  List<String> offeredBy(DocumentSnapshot doc) => List<String>.from(
    (doc.data() as Map<String, dynamic>?)?['skillsOffered'] ?? const [],
  );
  // You teach one of yours and learn one of theirs, so the hours land on the
  // right skill on each Skill Passport; with an empty profile, the catalog.
  final catalog = SkillCatalogService.instance.curated;
  final mine = offeredBy(profiles[0]);
  final theirs = offeredBy(profiles[1]);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProposeSheet(
      otherUserId: otherUserId,
      otherName: otherName,
      teachOptions: mine.isNotEmpty ? mine : catalog,
      learnOptions: theirs.isNotEmpty ? theirs : catalog,
    ),
  );
  return sent == true;
}

class _ProposeSheet extends StatefulWidget {
  final String otherUserId;
  final String otherName;
  final List<String> teachOptions;
  final List<String> learnOptions;

  const _ProposeSheet({
    required this.otherUserId,
    required this.otherName,
    required this.teachOptions,
    required this.learnOptions,
  });

  @override
  State<_ProposeSheet> createState() => _ProposeSheetState();
}

class _ProposeSheetState extends State<_ProposeSheet> {
  String _type = 'swap';
  String? _teach;
  String? _learn;
  SessionSlot? _slot;
  final _agenda = TextEditingController();
  bool _busy = false;
  String? _error;

  String get _first => widget.otherName.split(' ').first;

  @override
  void initState() {
    super.initState();
    if (widget.teachOptions.length == 1) _teach = widget.teachOptions.first;
    if (widget.learnOptions.length == 1) _learn = widget.learnOptions.first;
  }

  @override
  void dispose() {
    _agenda.dispose();
    super.dispose();
  }

  bool get _ready =>
      _slot != null &&
      (_type == 'learn' || _teach != null) &&
      (_type == 'teach' || _learn != null);

  Future<void> _pickTime() async {
    final slot = await showSessionTimePicker(
      context,
      otherUserId: widget.otherUserId,
      otherName: _first,
      initial: _slot?.start,
      initialMinutes: _slot?.minutes ?? 60,
    );
    if (slot != null && mounted) setState(() => _slot = slot);
  }

  Future<void> _send({bool force = false}) async {
    final slot = _slot;
    if (slot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await SwapSessionService.instance.proposeSession(
      otherUserId: widget.otherUserId,
      type: _type,
      skillOffered: _type == 'learn' ? '' : _teach ?? '',
      skillWanted: _type == 'teach' ? '' : _learn ?? '',
      scheduledFor: slot.start,
      plannedMinutes: slot.minutes,
      agenda: _agenda.text.trim(),
      force: force,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.needsConfirm) {
      final go = await confirmClashWarnings(context, r.warnings);
      if (go && mounted) await _send(force: true);
      return;
    }
    if (await handleCalendarError(
      context,
      r,
      otherUserId: widget.otherUserId,
      otherName: _first,
    )) {
      return;
    }
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => _error = r.error);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final slot = _slot;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Session with $_first',
                style: AppTheme.display(fontSize: 22, color: c.text),
              ),
              const SizedBox(height: 14),
              _typeSwitch(c),
              const SizedBox(height: 14),
              if (_type != 'learn')
                _skillField(
                  label: 'You teach',
                  value: _teach,
                  options: widget.teachOptions,
                  onChanged: (v) => setState(() => _teach = v),
                ),
              if (_type == 'swap') const SizedBox(height: 10),
              if (_type != 'teach')
                _skillField(
                  label: 'You learn from $_first',
                  value: _learn,
                  options: widget.learnOptions,
                  onChanged: (v) => setState(() => _learn = v),
                ),
              const SizedBox(height: 14),
              SurfaceCard(
                onTap: _pickTime,
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded, color: c.give),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot == null
                                ? 'Pick a time'
                                : DateFormat(
                                    'EEE d MMM · h:mm a',
                                  ).format(slot.start),
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                              color: c.text,
                            ),
                          ),
                          Text(
                            slot == null
                                ? "See when you and $_first are free"
                                : '${slot.minutes} min · ends ${DateFormat.jm().format(slot.start.add(Duration(minutes: slot.minutes)))}',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: c.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textMuted),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _agenda,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Agenda (optional)',
                  hintText: 'What do you want to cover?',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              PillButton(
                label: 'Propose session',
                icon: Icons.send_rounded,
                loading: _busy,
                onTap: _ready && !_busy ? () => _send() : null,
              ),
              const SizedBox(height: 6),
              Text(
                'The calendar invite and Meet link are created when $_first accepts.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeSwitch(SwapnioColors c) {
    Widget seg(String type, String label, IconData icon) {
      final on = _type == type;
      return Expanded(
        child: Pressable(
          onTap: () => setState(() => _type = type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? c.cta : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(icon, size: 18, color: on ? c.onCta : c.textMuted),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: on ? c.onCta : c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          seg('swap', 'Swap', Icons.swap_horiz_rounded),
          seg('teach', 'I teach', Icons.school_rounded),
          seg('learn', 'I learn', Icons.menu_book_rounded),
        ],
      ),
    );
  }

  Widget _skillField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) => DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final s in options)
        DropdownMenuItem(
          value: s,
          child: Text(s, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  );
}
