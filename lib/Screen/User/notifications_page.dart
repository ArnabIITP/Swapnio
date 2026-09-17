import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:swapnio/providers/app_state.dart';
import '../../theme.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Mark all notifications as read when the page opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AppState>(context, listen: false).markNotificationsAsRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: userId)
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off,
                      size: 72, color: AppTheme.warmBorder),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: GoogleFonts.ebGaramond(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            );
          }
          final docs = snapshot.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 76),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final message = data['message'] ?? '';
              final type = data['type'] ?? 'info';
              final senderPhoto = data['senderPhoto'] ?? '';
              final timestamp = data['timestamp'] as Timestamp?;
              final time = timestamp != null
                  ? DateFormat.yMMMd().add_jm().format(timestamp.toDate())
                  : '';
              final icon = _iconForType(type);
              final showAvatar = senderPhoto.isNotEmpty &&
                  type == 'swap_request' &&
                  index.isEven == false;
              return ListTile(
                leading: showAvatar
                    ? CircleAvatar(
                        radius: 24,
                        backgroundImage: NetworkImage(senderPhoto),
                        onBackgroundImageError: (_, __) {},
                      )
                    : CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            AppTheme.primaryColor.withValues(alpha: 0.12),
                        child: Icon(icon, color: AppTheme.primaryColor),
                      ),
                title: Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  time,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'swap_request':
        return Icons.swap_horiz;
      case 'request_accepted':
        return Icons.favorite;
      case 'rating':
        return Icons.star;
      case 'session_reminder':
        return Icons.event_available;
      case 'session_proposed':
      case 'session_rescheduled':
        return Icons.event;
      default:
        return Icons.notifications;
    }
  }
}