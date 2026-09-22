import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:swapnio/providers/app_state.dart';
import '../../theme.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Built once: a stream created inside build() is a new object on every
  // rebuild, so StreamBuilder would re-subscribe and flash its loading state.
  late final Stream<QuerySnapshot> _notificationsStream;

  @override
  void initState() {
    super.initState();
    _notificationsStream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
    // Mark all notifications as read when the page opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).markNotificationsAsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SwapHeader(title: 'Notifications'),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _notificationsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const SwapEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'Nothing new yet',
                      message: 'Requests, accepted swaps and session reminders '
                          'will show up here.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final message = (data['message'] ?? '').toString();
                      final type = (data['type'] ?? 'info').toString();
                      final senderPhoto = (data['senderPhoto'] ?? '').toString();
                      final senderName = (data['senderName'] ?? '').toString();
                      final timestamp = data['timestamp'] as Timestamp?;
                      final time = timestamp != null ? _ago(timestamp.toDate()) : '';
                      final accent = _accentForType(type, c);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SurfaceCard(
                          padding: const EdgeInsets.all(14),
                          radius: 18,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (senderPhoto.isNotEmpty)
                                SwapAvatar(
                                  name: senderName.isEmpty ? '?' : senderName,
                                  photoUrl: senderPhoto,
                                  size: 40,
                                  radius: 14,
                                )
                              else
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.13),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(_iconForType(type), size: 19, color: accent),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message,
                                      style: GoogleFonts.manrope(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: c.text,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (time.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(time,
                                          style: GoogleFonts.manrope(
                                              fontSize: 11.5, color: c.textMuted)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime when) {
    final d = DateTime.now().difference(when);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat.MMMd().add_jm().format(when);
  }

  Color _accentForType(String type, SwapnioColors c) {
    switch (type) {
      case 'swap_request':
      case 'request_accepted':
        return c.give;
      case 'rating':
        return c.success;
      case 'session_reminder':
      case 'session_proposed':
      case 'session_rescheduled':
        return c.get;
      default:
        return c.textMuted;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'swap_request':
        return Icons.swap_horiz_rounded;
      case 'request_accepted':
        return Icons.favorite_rounded;
      case 'rating':
        return Icons.star_rounded;
      case 'session_reminder':
        return Icons.event_available_rounded;
      case 'session_proposed':
      case 'session_rescheduled':
        return Icons.event_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}