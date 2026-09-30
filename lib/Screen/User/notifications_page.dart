import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:swapnio/providers/app_state.dart';
import 'package:swapnio/providers/user_data_provider.dart';
import '../../services/app_nav.dart';
import '../../theme.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import '../../features/streak/daily_streak.dart';
import '../../features/streak/streak_page.dart';
import 'calendar_settings_page.dart';
import 'chat_page.dart';
import 'invite_friends_page.dart';
import 'security_page.dart';
import 'session_detail.dart';

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
        .where(
          'userId',
          isEqualTo: FirebaseAuth.instance.currentUser?.uid ?? '',
        )
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
                      message:
                          'Requests, accepted swaps and session reminders '
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
                      final senderPhoto = (data['senderPhoto'] ?? '')
                          .toString();
                      final senderName = (data['senderName'] ?? '').toString();
                      final timestamp = data['timestamp'] as Timestamp?;
                      final time = timestamp != null
                          ? _ago(timestamp.toDate())
                          : '';
                      final accent = _accentForType(type, c);
                      final doc = docs[index];

                      // Swipe right to delete.
                      return Dismissible(
                        key: ValueKey(doc.id),
                        direction: DismissDirection.startToEnd,
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.only(left: 22),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (_) =>
                            doc.reference.delete().catchError((_) => null),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SurfaceCard(
                            onTap: () => _open(data),
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
                                    child: Icon(
                                      _iconForType(type),
                                      size: 19,
                                      color: accent,
                                    ),
                                  ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        Text(
                                          time,
                                          style: GoogleFonts.manrope(
                                            fontSize: 11.5,
                                            color: c.textMuted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

  /// Opens whatever the notification is about.
  void _open(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    final swapId = (data['swapId'] as String?) ?? '';
    final senderId = (data['senderId'] as String?) ?? '';
    final senderName = (data['senderName'] as String?) ?? '';
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final nav = Navigator.of(context);

    void push(Widget page) => nav.push(MaterialPageRoute(builder: (_) => page));
    void tab(int bottom, {int? inbox}) {
      nav.popUntil((r) => r.isFirst);
      AppNav.go(bottom, inboxTab: inbox);
    }

    if (type.startsWith('session_')) {
      if (swapId.isNotEmpty) return push(SessionDetailPage(swapId: swapId));
      return tab(AppNav.inbox, inbox: AppNav.inboxSessions);
    }
    switch (type) {
      case 'swap_request':
        return tab(AppNav.inbox, inbox: AppNav.inboxRequests);
      case 'request_accepted':
      case 'rating':
        if (senderId.isNotEmpty && senderId != me && senderId != 'system') {
          return push(
            ChatPage(
              chatRoomId: me.compareTo(senderId) < 0
                  ? '${me}_$senderId'
                  : '${senderId}_$me',
              otherUserName: senderName.isEmpty ? 'Chat' : senderName,
              otherUserPhoto: (data['senderPhoto'] as String?) ?? '',
              otherUserId: senderId,
            ),
          );
        }
        return tab(AppNav.inbox, inbox: AppNav.inboxChats);
      case 'calendar_required':
        return push(const CalendarSettingsPage());
      case 'security':
        return push(const SecurityPage());
      case 'referral':
        return push(
          InviteFriendsPage(
            userData:
                context.read<UserDataProvider>().userData ??
                const <String, dynamic>{},
          ),
        );
      case 'skill_request':
        return tab(AppNav.profile);
      case 'streak':
        return push(const StreakPage());
    }
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
      case 'streak':
        return kStreakFlame;
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
      case 'streak':
        return Icons.local_fire_department_rounded;
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
