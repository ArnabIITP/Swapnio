import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/app_state.dart';
import '../../services/swap_service.dart';
import '../../theme.dart';
import 'chat_page.dart';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> with SingleTickerProviderStateMixin {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Mark notifications as read when opening this page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      if (appState.unreadNotifications > 0) {
        appState.markNotificationsAsRead();
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _acceptRequest(String docId, Map<String, dynamic> data) async {
    // First create a chat room between the users
    final chatRoomId = _getChatRoomId(currentUserId, data["fromUserId"]);
    final myName = FirebaseAuth.instance.currentUser?.displayName ?? "You";
    final myPhoto = FirebaseAuth.instance.currentUser?.photoURL ?? "";

    // The chat room MUST be committed on its own first: the security rules for
    // `chatRooms/{id}/messages` reads the room with get(), which sees only the
    // pre-batch database state. Writing the room + message in one batch made
    // the message create fail (permission-denied) for brand-new rooms.
    final chatRoomRef =
        FirebaseFirestore.instance.collection('chatRooms').doc(chatRoomId);
    await chatRoomRef.set({
      'users': [currentUserId, data["fromUserId"]],
      'userNames': {
        currentUserId: myName,
        data["fromUserId"]: data["fromName"],
      },
      'userPhotos': {
        currentUserId: myPhoto,
        data["fromUserId"]: data["fromPhoto"],
      },
      'lastMessage': "Swap request accepted! You can start chatting now.",
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUserId,
      'unreadCount': {
        currentUserId: 0,
        data["fromUserId"]: 1,
      },
    }, SetOptions(merge: true));

    // Everything else is atomic now that the room exists.
    final batch = FirebaseFirestore.instance.batch();

    // Initial system message
    batch.set(chatRoomRef.collection('messages').doc(), {
      'senderId': 'system',
      'text': 'Skill swap matched! $myName accepted the swap request.',
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'system',
    });

    // Notification for the other user
    batch.set(
        FirebaseFirestore.instance.collection('notifications').doc(), {
      'userId': data["fromUserId"],
      'type': 'request_accepted',
      'message': '$myName accepted your skill swap request!',
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
      'senderName': myName,
      'senderPhoto': myPhoto,
    });

    // Delete the request being accepted, plus the reverse request if the
    // other user had also liked us first (a mutual match otherwise leaves a
    // stale, meaningless request sitting in their Requests tab forever).
    batch.delete(
        FirebaseFirestore.instance.collection('swipeRequests').doc(docId));
    final reverseSnapshot = await FirebaseFirestore.instance
        .collection('swipeRequests')
        .where('fromUserId', isEqualTo: currentUserId)
        .where('toUserId', isEqualTo: data["fromUserId"])
        .get();
    for (final doc in reverseSnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
    
    // Navigate to chat
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          chatRoomId: chatRoomId,
          otherUserName: data["fromName"],
          otherUserPhoto: data["fromPhoto"],
          otherUserId: data["fromUserId"],
        ),
      ),
    );
  }
  
  Future<void> _rejectRequest(String docId) async {
    await FirebaseFirestore.instance.collection('swipeRequests').doc(docId).delete();
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Request rejected")),
    );
  }
  
  String _getChatRoomId(String userId1, String userId2) {
    // Create a consistent chat room ID regardless of order
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_${userId2}'
        : '${userId2}_${userId1}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          "My Connections",
          style: GoogleFonts.ebGaramond(
            fontWeight: FontWeight.w800,
            color: AppTheme.darkTextColor,
            fontSize: 24,
            letterSpacing: 0,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey,
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(width: 4.0, color: AppTheme.primaryColor),
                insets: EdgeInsets.symmetric(horizontal: 32.0),
              ),
              labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: const [
                Tab(text: "REQUESTS"),
                Tab(text: "CHATS"),
                Tab(text: "SESSIONS"),
              ],
            ),
          ),
        ),
      ),
      body: currentUserId.isEmpty
          ? const Center(child: Text("Please log in to view requests and chats."))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRequestsTab(),
                _buildChatsTab(),
                _buildSessionsTab(),
              ],
            ),
    );
  }
  
  /// Opens date+time pickers and reschedules an accepted session, notifying
  /// the partner via a notification document.
  Future<void> _rescheduleSession(
      String swapId, Map<String, dynamic> data) async {
    final current = data['scheduledFor'] as Timestamp?;
    final initial = current?.toDate() ?? DateTime.now().add(const Duration(days: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

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
        content: Text(ok
            ? 'Session rescheduled to ${DateFormat.yMMMd().add_jm().format(newTime)}'
            : 'Could not reschedule the session. Please try again.'),
        backgroundColor: ok ? AppTheme.primaryColor : Colors.redAccent,
      ),
    );
  }

  Widget _buildSessionActions(
    String swapId,
    String status,
    bool isMine,
    List<String> participants, {
    Map<String, dynamic>? rawData,
  }) {
    if (status == 'pending') {
      if (isMine) {
        return Row(
          children: [
            Icon(Icons.hourglass_empty, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Waiting for them to accept',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ),
            TextButton(
              onPressed: () =>
                  SwapSessionService.instance.updateStatus(swapId, 'declined'),
              child: const Text('Cancel'),
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () =>
                  SwapSessionService.instance.updateStatus(swapId, 'declined'),
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () =>
                  SwapSessionService.instance.updateStatus(swapId, 'accepted'),
              child: const Text('Accept'),
            ),
          ),
        ],
      );
    }

    if (status == 'accepted') {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await SwapSessionService.instance
                    .completeSession(swapId, participants);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Completed! You both earned 25 points - now you can rate each other.'
                        : 'Could not complete the session. Please try again.'),
                    backgroundColor: ok ? AppTheme.primaryColor : Colors.redAccent,
                  ),
                );
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Mark as completed'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: rawData == null
                ? null
                : () => _rescheduleSession(swapId, rawData),
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('Reschedule'),
          ),
        ],
      );
    }

    if (status == 'completed') {
      return Row(
        children: [
          Icon(Icons.verified, size: 16, color: AppTheme.tertiaryColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Swap finished - open the chat to leave a rating',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSessionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: SwapSessionService.instance.mySessionsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.event_available,
            title: 'No swap sessions yet',
            message:
                'Open a chat and tap "Propose swap session" to schedule your '
                'first skill exchange.',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildSessionCard(
            docs[index].id,
            docs[index].data(),
          ),
        );
      },
    );
  }

  Widget _buildSessionCard(String swapId, dynamic rawData) {
    final data = rawData as Map<String, dynamic>;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final participants = List<String>.from(data['participants'] ?? []);
    final otherId = participants.firstWhere((p) => p != uid, orElse: () => '');
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherName = (names[otherId] as String?) ?? 'Your swap partner';
    final offered = data['skillOffered'] ?? '';
    final wanted = data['skillWanted'] ?? '';
    final status = data['status'] ?? 'pending';
    final createdBy = data['createdBy'] ?? '';
    final scheduledFor = data['scheduledFor'] as Timestamp?;
    final scheduledText = scheduledFor != null
        ? DateFormat.yMMMd().add_jm().format(scheduledFor.toDate())
        : 'Time to be agreed';
    final isMine = createdBy == uid;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'accepted':
        statusColor = AppTheme.primaryColor;
        statusLabel = 'Accepted';
        break;
      case 'completed':
        statusColor = AppTheme.tertiaryColor;
        statusLabel = 'Completed';
        break;
      case 'declined':
        statusColor = Colors.grey;
        statusLabel = 'Declined';
        break;
      default:
        statusColor = Colors.orange.shade700;
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warmBorder),
        boxShadow: AppTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  otherName,
                  style: GoogleFonts.ebGaramond(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkTextColor,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSkillItem('Teaches', offered, Icons.auto_fix_high),
          const SizedBox(height: 6),
          _buildSkillItem('Learns', wanted, Icons.search),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.event, size: 16, color: AppTheme.tertiaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scheduledText,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppTheme.darkTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSessionActions(swapId, status, isMine, participants,
              rawData: data),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('swipeRequests')
          .where('toUserId', isEqualTo: currentUserId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingShimmer();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.person_add_disabled,
            title: "No requests yet",
            message: "When someone wants to swap skills with you, their requests will appear here.",
          );
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final data = requests[index].data() as Map<String, dynamic>;
            final docId = requests[index].id;
            
            final timestamp = data['timestamp'] as Timestamp?;
            final formattedDate = timestamp != null 
                ? DateFormat.yMMMd().add_jm().format(timestamp.toDate())
                : 'Recently';

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.warmBorder, width: 1),
                boxShadow: AppTheme.softShadow,
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CachedNetworkImage(
                          imageUrl: data["fromPhoto"] ?? "",
                          imageBuilder: (context, imageProvider) => CircleAvatar(
                            radius: 32,
                            backgroundImage: imageProvider,
                          ),
                          placeholder: (context, url) => CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.grey[300],
                            child: const Icon(Icons.person, size: 32, color: Colors.grey),
                          ),
                          errorWidget: (context, url, error) => CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.grey[300],
                            child: const Icon(Icons.person, size: 32, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data["fromName"] ?? "User",
                                style: GoogleFonts.ebGaramond(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.darkTextColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formattedDate,
                                style: GoogleFonts.manrope(
                                  color: AppTheme.darkTextColor.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, color: Colors.grey[200]),
                    const SizedBox(height: 14),
                    _buildSkillItem("Offers", data["skillsOffered"], Icons.auto_fix_high),
                    const SizedBox(height: 8),
                    _buildSkillItem("Wants", data["skillsWanted"], Icons.search),
                    const SizedBox(height: 8),
                    _buildSkillItem("Available", data["availability"], Icons.access_time),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _rejectRequest(docId),
                          icon: const Icon(Icons.close, color: AppTheme.tertiaryColor),
                          label: const Text('Decline', style: TextStyle(color: AppTheme.tertiaryColor, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.tertiaryColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _acceptRequest(docId, data),
                          icon: const Icon(Icons.check),
                          label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildChatsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chatRooms')
          .where('users', arrayContains: currentUserId)
          .orderBy('lastMessageTime', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingShimmer();
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.chat_bubble_outline,
            title: "No chats yet",
            message: "When you connect with someone, your conversations will appear here.",
          );
        }

        final chatRooms = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: chatRooms.length,
          itemBuilder: (context, index) {
            final data = chatRooms[index].data() as Map<String, dynamic>;
            final chatRoomId = chatRooms[index].id;
            
            // Find the other user ID
            final users = List<String>.from(data['users'] ?? []);
            final otherUserId = users.firstWhere(
              (id) => id != currentUserId,
              orElse: () => "",
            );
            
            if (otherUserId.isEmpty) return const SizedBox.shrink();
            
            final userNames = data['userNames'] as Map<String, dynamic>?;
            final userPhotos = data['userPhotos'] as Map<String, dynamic>?;
            
            final otherUserName = userNames?[otherUserId] ?? "User";
            final otherUserPhoto = userPhotos?[otherUserId] ?? "";
            
            final lastMessage = data['lastMessage'] as String? ?? "No messages yet";
            final lastMessageTime = data['lastMessageTime'] as Timestamp?;
            final formattedTime = lastMessageTime != null
                ? _formatLastMessageTime(lastMessageTime.toDate())
                : "";
                
            final unreadCount = (data['unreadCount'] as Map<String, dynamic>?)?[currentUserId] ?? 0;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.warmBorder, width: 1),
                boxShadow: AppTheme.softShadow,
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                leading: CachedNetworkImage(
                  imageUrl: otherUserPhoto,
                  imageBuilder: (context, imageProvider) => CircleAvatar(
                    radius: 26,
                    backgroundImage: imageProvider,
                  ),
                  placeholder: (context, url) => CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.grey[300],
                    child: const Icon(Icons.person, color: Colors.grey),
                  ),
                  errorWidget: (context, url, error) => CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.grey[300],
                    child: const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
                title: Text(
                  otherUserName,
                  style: GoogleFonts.ebGaramond(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.darkTextColor),
                ),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          color: unreadCount > 0 ? AppTheme.primaryColor : AppTheme.darkTextColor.withValues(alpha: 0.7),
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (formattedTime.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          formattedTime,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppTheme.darkTextColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                  ],
                ),
                trailing: unreadCount > 0
                    ? Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatPage(
                        chatRoomId: chatRoomId,
                        otherUserName: otherUserName,
                        otherUserPhoto: otherUserPhoto,
                        otherUserId: otherUserId,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoadingShimmer() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: ListView.builder(
          itemCount: 5,
          itemBuilder: (_, __) => Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        height: 12,
                        color: Colors.white,
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: AppTheme.warmBorder),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.ebGaramond(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(color: AppTheme.darkTextColor.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSkillItem(String label, dynamic value, IconData icon) {
    final displayValue = value is List ? value.join(', ') : value.toString();
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "$label:",
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.primaryColor,
                ),
              ),
              Text(
                displayValue,
                style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.darkTextColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  String _formatLastMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat.yMMMd().format(dateTime);
    }
  }
}
