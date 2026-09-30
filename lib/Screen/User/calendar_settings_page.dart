import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/google_calendar_service.dart';
import '../../theme.dart';
import '../../ui/swapnio_kit.dart';

/// Settings > Google Calendar - the ONE place Swapnio asks for Google
/// permissions. A single Connect grants everything (calendar events with Meet
/// links, and free/busy); it's required of both people to book a session.
/// Sharing busy times with others is a separate choice, off by default.
class CalendarSettingsPage extends StatefulWidget {
  const CalendarSettingsPage({super.key});

  @override
  State<CalendarSettingsPage> createState() => _CalendarSettingsPageState();
}

class _CalendarSettingsPageState extends State<CalendarSettingsPage> {
  final _cal = GoogleCalendarService.instance;
  ({bool connected, String email, bool freeBusy, bool shareBusy})? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _cal.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _run(Future<String?> Function() action, String done) async {
    setState(() => _busy = true);
    final error = await action();
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? done),
        backgroundColor: error == null ? null : Colors.redAccent,
      ),
    );
  }

  Future<void> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Disconnect Google Calendar?'),
        content: const Text(
          "You won't be able to book or accept sessions until you connect "
          'again. Sessions already in your calendar stay there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Keep connected'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(_cal.disconnect, 'Disconnected.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    final s = _status;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const SwapHeader(
              title: 'Google Calendar',
              subtitle: 'Meet links, invites and busy times',
              titleSize: 24,
            ),
            const SizedBox(height: 18),
            if (s == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              SurfaceCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          s.connected
                              ? Icons.event_available_rounded
                              : Icons.event_busy_rounded,
                          color: s.connected ? c.success : c.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.connected ? 'Connected' : 'Not connected',
                            style: AppTheme.display(
                              fontSize: 20,
                              color: c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (s.email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        s.email,
                        style: GoogleFonts.manrope(color: c.textMuted),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      s.connected && !s.freeBusy
                          ? 'Partly connected: busy times weren\'t allowed. Tap below '
                                'and allow everything so your busy times are greyed out '
                                'when picking a session time.'
                          : 'Required to book sessions - for you and the person you swap '
                                'with. Accepted sessions go into both calendars with a '
                                'Google Meet link; reschedules and cancellations update them '
                                'automatically, and your busy times are greyed out when '
                                'picking a time.',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        height: 1.45,
                        color: c.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!s.connected || !s.freeBusy)
                      PillButton(
                        label: s.connected
                            ? 'Allow everything'
                            : 'Connect Google Calendar',
                        icon: Icons.link_rounded,
                        loading: _busy,
                        onTap: _busy
                            ? null
                            : () => _run(
                                _cal.connect,
                                'Google Calendar connected.',
                              ),
                      ),
                    if (s.connected) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy ? null : _confirmDisconnect,
                        icon: const Icon(Icons.link_off_rounded, size: 18),
                        label: const Text('Disconnect'),
                        style: TextButton.styleFrom(
                          foregroundColor: c.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (s.connected && s.freeBusy) ...[
                const SizedBox(height: 14),
                SurfaceCard(
                  padding: const EdgeInsets.all(18),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: s.shareBusy,
                    onChanged: _busy
                        ? null
                        : (v) => _run(
                            () => _cal.setBusySharing(v),
                            v
                                ? 'Sharing busy times.'
                                : 'Stopped sharing busy times.',
                          ),
                    title: Text(
                      'Share busy times with people I swap with',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                    subtitle: Text(
                      'They see "Busy" blocks when picking a time with you - '
                      'start and end only, never what the event is. Off by default.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: c.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
