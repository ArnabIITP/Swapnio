import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/app_state.dart';
import '../../services/swap_service.dart';
import '../../theme.dart';
import '../../ui/session_actions.dart';
import '../../ui/swapnio_badges.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import 'session_detail.dart';
import 'chat_page.dart';

class RequestPage extends StatefulWidget {
  /// Lets empty states send people to Discover instead of dead-ending.
  final ValueChanged<int>? onNavigateToTab;

  const RequestPage({super.key, this.onNavigateToTab});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage>
    with SingleTickerProviderStateMixin {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  late TabController _tabController;
  // Streams are built once here rather than inside build(): .snapshots()
  // returns a new Stream each call, so building them in build() makes
  // StreamBuilder re-subscribe (and flash its loading state) on every rebuild.
  // Requests declined but still inside their undo window.
  final Set<String> _hiddenRequestIds = {};

  // Each collection is watched by exactly one subscription for the whole
  // life of this page, with the latest snapshot cached here. Both the header
  // count and the tab body read this same field. Two separate StreamBuilders
  // bound to the same Firestore `.snapshots()` stream - one for the header,
  // one for the tab - used to each subscribe independently; a subscriber
  // that (re)attaches after the single snapshot event has already fired
  // never receives it and waits forever for a change that was never coming,
  // which is exactly what made the Requests tab hang on a second visit.
  QuerySnapshot? _requestsSnapshot;
  QuerySnapshot? _chatsSnapshot;
  QuerySnapshot? _sessionsSnapshot;
  StreamSubscription<QuerySnapshot>? _requestsSub;
  StreamSubscription<QuerySnapshot>? _chatsSub;
  StreamSubscription<QuerySnapshot>? _sessionsSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _requestsSub = FirebaseFirestore.instance
        .collection('swipeRequests')
        .where('toUserId', isEqualTo: currentUserId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _requestsSnapshot = snap);
    });
    _chatsSub = FirebaseFirestore.instance
        .collection('chatRooms')
        .where('users', arrayContains: currentUserId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .listen((snap) {
      if (mounted) setState(() => _chatsSnapshot = snap);
    });
    _sessionsSub = SwapSessionService.instance.mySessionsStream().listen((snap) {
      if (mounted) setState(() => _sessionsSnapshot = snap);
    });

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
    _requestsSub?.cancel();
    _chatsSub?.cancel();
    _sessionsSub?.cancel();
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
    final chatRoomRef = FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(chatRoomId);
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
      'unreadCount': {currentUserId: 0, data["fromUserId"]: 1},
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
    batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
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
      FirebaseFirestore.instance.collection('swipeRequests').doc(docId),
    );
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

  /// Undo instead of a confirm dialog: less friction, same safety. The
  /// request is hidden immediately and only deleted once the undo window
  /// closes - it can't be re-created after the fact, because the rules only
  /// let the *sender* create a request.
  void _rejectRequest(String docId) {
    HapticFeedback.selectionClick();
    setState(() => _hiddenRequestIds.add(docId));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Request declined'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () {
                if (mounted) setState(() => _hiddenRequestIds.remove(docId));
              },
            ),
          ),
        )
        .closed
        .then((reason) {
          if (reason == SnackBarClosedReason.action) return;
          FirebaseFirestore.instance
              .collection('swipeRequests')
              .doc(docId)
              .delete()
              .catchError((_) {});
        });
  }

  Future<void> _acceptFromSwipe(String docId, Map<String, dynamic> data) async {
    HapticFeedback.mediumImpact();
    try {
      await _acceptRequest(docId, data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenRequestIds.remove(docId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not accept - please try again.')),
      );
    }
  }

  Widget _swipeBackground({
    required Color color,
    required Color foreground,
    required IconData icon,
    required String label,
    required bool alignLeft,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 26),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.manrope(color: foreground, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  /// A specific reason ("Teaches Figma, wants your Python") earns far more
  /// accepts than a generic "wants to connect" - the specificity is what
  /// makes the request feel credible.
  String _matchReason(Map<String, dynamic> data) {
    final me = Provider.of<AppState>(context, listen: false).currentUser;
    List<String> list(dynamic v) => v is List
        ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
        : (v is String && v.trim().isNotEmpty ? [v] : <String>[]);
    final theyTeach = list(data['skillsOffered']);
    final theyWant = list(data['skillsWanted']);
    if (me == null) {
      return theyTeach.isNotEmpty ? 'Teaches ${theyTeach.first}' : 'Liked your profile';
    }
    final myWant = me.skillsWanted.map((e) => e.toLowerCase()).toSet();
    final myTeach = me.skillsOffered.map((e) => e.toLowerCase()).toSet();
    final give = theyTeach.where((t) => myWant.contains(t.toLowerCase())).toList();
    final get = theyWant.where((t) => myTeach.contains(t.toLowerCase())).toList();
    if (give.isNotEmpty && get.isNotEmpty) return 'Teaches ${give.first}, wants your ${get.first}';
    if (give.isNotEmpty) return 'Teaches ${give.first} - on your wishlist';
    if (get.isNotEmpty) return 'Wants to learn your ${get.first}';
    if (theyTeach.isNotEmpty) return 'Teaches ${theyTeach.first}';
    return 'Liked your profile';
  }

  String _shortAgo(Timestamp? ts) {
    if (ts == null) return '';
    final d = DateTime.now().difference(ts.toDate());
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return DateFormat.MMMd().format(ts.toDate());
  }

  String _getChatRoomId(String userId1, String userId2) {
    // Create a consistent chat room ID regardless of order
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_${userId2}'
        : '${userId2}_${userId1}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: currentUserId.isEmpty
            ? const Center(child: Text('Please log in to view requests and chats.'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text('Inbox', style: AppTheme.display(fontSize: 34, color: c.text)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Builder(builder: (context) {
                      final n = (_requestsSnapshot?.docs ?? const [])
                          .where((d) => !_hiddenRequestIds.contains(d.id))
                          .length;
                      return Text(
                        n == 0
                            ? 'Requests, chats and sessions in one place'
                            : '$n ${n == 1 ? 'person wants' : 'people want'} to swap with you',
                        style: GoogleFonts.manrope(fontSize: 13, color: c.textMuted),
                      );
                    }),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.surfaceLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: c.cta,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerHeight: 0,
                      labelColor: c.onCta,
                      unselectedLabelColor: c.textMuted,
                      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13.5),
                      unselectedLabelStyle:
                          GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5),
                      splashBorderRadius: BorderRadius.circular(12),
                      tabs: const [
                        Tab(height: 40, text: 'Requests'),
                        Tab(height: 40, text: 'Chats'),
                        Tab(height: 40, text: 'Sessions'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRequestsTab(),
                        _buildChatsTab(),
                        _buildSessionsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _rescheduleSession(String swapId, Map<String, dynamic> data) =>
      rescheduleSessionFlow(context, swapId, data);

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
            Icon(Icons.hourglass_empty, size: 16, color: context.sw.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Waiting for them to accept',
                style: TextStyle(fontSize: 13, color: context.sw.textMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                SwapSessionService.instance.updateStatus(swapId, 'declined');
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                SwapSessionService.instance.updateStatus(swapId, 'declined');
              },
              child: const Text('Decline'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                SwapSessionService.instance.updateStatus(swapId, 'accepted');
              },
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
              onPressed: () =>
                  _completeSessionWithOutcome(swapId, participants),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Mark as completed'),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: rawData == null
                      ? null
                      : () => _rescheduleSession(swapId, rawData),
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: const Text('Reschedule'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _confirmNoShow(swapId),
                  style: TextButton.styleFrom(
                    foregroundColor: context.sw.textMuted,
                  ),
                  icon: const Icon(Icons.event_busy, size: 18),
                  label: const Text("Didn't happen"),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (status == 'completed') {
      return Row(
        children: [
          Icon(Icons.verified, size: 16, color: context.sw.get),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Swap finished - open the chat to leave a rating',
              style: TextStyle(fontSize: 13, color: context.sw.textMuted),
            ),
          ),
        ],
      );
    }

    if (status == 'no_show') {
      return Row(
        children: [
          Icon(Icons.event_busy, size: 16, color: context.sw.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Marked as a no-show - no points or rating for this session',
              style: TextStyle(fontSize: 13, color: context.sw.textMuted),
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _completeSessionWithOutcome(String swapId, List<String> participants) =>
      completeSessionFlow(context, swapId, participants, onRate: () => _tabController.animateTo(1));

  Future<void> _confirmNoShow(String swapId) => confirmNoShowFlow(context, swapId);

  Widget _buildSessionsTab() {
    if (_sessionsSnapshot == null) {
      return const ListSkeleton();
    }
    final docs = _sessionsSnapshot?.docs ?? [];
    if (docs.isEmpty) {
      return _buildEmptyState(
        icon: Icons.event_available_rounded,
        title: 'No swap sessions yet',
        message:
            'Open a chat and tap "Propose swap session" to schedule your '
            'first skill exchange.',
        actionLabel: 'Find someone to swap with',
        onAction: () => widget.onNavigateToTab?.call(1),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
      itemCount: docs.length,
      itemBuilder: (context, index) =>
          _buildSessionCard(docs[index].id, docs[index].data()),
    );
  }

  Widget _buildSessionCard(String swapId, dynamic rawData) {
    final c = context.sw;
    final data = rawData as Map<String, dynamic>;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final participants = List<String>.from(data['participants'] ?? []);
    final otherId = participants.firstWhere((p) => p != uid, orElse: () => '');
    final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
    final otherName = (names[otherId] as String?) ?? 'Your swap partner';
    final sides = swapSidesFor(data, uid);
    final status = (data['status'] ?? 'pending').toString();
    final isMine = data['createdBy'] == uid;
    final scheduledFor = (data['scheduledFor'] as Timestamp?)?.toDate();

    late final Color statusColor;
    late final String statusLabel;
    switch (status) {
      case 'accepted':
        statusColor = c.success;
        statusLabel = 'Accepted';
        break;
      case 'completed':
        statusColor = c.get;
        statusLabel = 'Completed';
        break;
      case 'declined':
        statusColor = c.textMuted;
        statusLabel = 'Declined';
        break;
      case 'no_show':
        statusColor = c.textMuted;
        statusLabel = 'No-show';
        break;
      default:
        statusColor = c.give;
        statusLabel = 'Pending';
    }

    String whenText;
    if (scheduledFor == null) {
      whenText = 'Time to be agreed';
    } else {
      final diff = scheduledFor.difference(DateTime.now());
      if (!diff.isNegative && diff.inHours < 24) {
        whenText = diff.inMinutes < 60
            ? 'In ${diff.inMinutes} min'
            : 'In ${diff.inHours}h · ${DateFormat.jm().format(scheduledFor)}';
      } else {
        whenText = DateFormat.MMMEd().add_jm().format(scheduledFor);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Pressable(
        scale: 0.985,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SessionDetailPage(swapId: swapId)),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SwapAvatar(name: otherName, size: 40, radius: 14),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(otherName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                            fontSize: 15.5, fontWeight: FontWeight.w800, color: c.text)),
                  ),
                  TintTag(statusLabel, color: statusColor),
                ],
              ),
              const SizedBox(height: 14),
              SwapSplit(giveSkill: sides.myGive, getSkill: sides.myGet),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 15, color: c.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(whenText,
                        style: GoogleFonts.manrope(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  Text('Details',
                      style: GoogleFonts.manrope(
                          fontSize: 12, fontWeight: FontWeight.w800, color: c.get)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.get),
                ],
              ),
              if ((data['sessionNotes'] as String? ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(data['sessionNotes'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, fontStyle: FontStyle.italic, color: c.textMuted)),
              ],
              const SizedBox(height: 12),
              _buildSessionActions(swapId, status, isMine, participants, rawData: data),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_requestsSnapshot == null) {
      return _buildLoadingShimmer();
    }
    final requests = (_requestsSnapshot?.docs ?? const [])
        .where((d) => !_hiddenRequestIds.contains(d.id))
        .toList();
    if (requests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.favorite_border_rounded,
        useSwapMotif: true,
        title: 'No requests yet',
        message: 'Requests show up here when someone likes you. Liking people '
            'first is the fastest way to get there.',
        actionLabel: 'Start discovering',
        onAction: () => widget.onNavigateToTab?.call(1),
      );
    }
    final c = context.sw;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
      itemCount: requests.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Row(
              children: [
                Icon(Icons.west_rounded, size: 14, color: c.textMuted),
                const SizedBox(width: 4),
                Text('Swipe to decline',
                    style: GoogleFonts.manrope(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: c.textMuted)),
                const Spacer(),
                Text('Swipe to accept',
                    style: GoogleFonts.manrope(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: c.give)),
                const SizedBox(width: 4),
                Icon(Icons.east_rounded, size: 14, color: c.give),
              ],
            ),
          );
        }
        final doc = requests[index - 1];
        final data = doc.data() as Map<String, dynamic>;
        final docId = doc.id;

        // Swipe right to accept, left to decline. The item is hidden
        // synchronously in onDismissed so it is never still in the tree
        // after dismissal.
        return Dismissible(
          key: ValueKey('request_$docId'),
          background: _swipeBackground(
            color: c.win,
            foreground: c.onWin,
            icon: Icons.check_rounded,
            label: 'Accept',
            alignLeft: true,
          ),
          secondaryBackground: _swipeBackground(
            color: c.surfaceLow,
            foreground: c.textMuted,
            icon: Icons.close_rounded,
            label: 'Decline',
            alignLeft: false,
          ),
          onDismissed: (direction) {
            if (direction == DismissDirection.startToEnd) {
              setState(() => _hiddenRequestIds.add(docId));
              _acceptFromSwipe(docId, data);
            } else {
              _rejectRequest(docId);
            }
          },
          child: _requestCard(docId, data),
        );
      },
    );
  }

  Widget _requestCard(String docId, Map<String, dynamic> data) {
    final c = context.sw;
    final rawName = (data['fromName'] as String?)?.trim() ?? '';
    final name = rawName.isEmpty ? 'Swapnio user' : rawName;
    final rawAvailability = data['availability'];
    final availability = rawAvailability is List
        ? rawAvailability.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).join(', ')
        : (rawAvailability ?? '').toString().trim();
    Widget button(String label, Color bg, Color fg, VoidCallback onTap) => Expanded(
          child: Pressable(
            onTap: onTap,
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Text(label,
                  style: GoogleFonts.manrope(
                      fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
            ),
          ),
        );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwapAvatar(name: name, photoUrl: data['fromPhoto'] as String?, size: 48, radius: 16),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                            fontSize: 15.5, fontWeight: FontWeight.w800, color: c.text)),
                    const SizedBox(height: 6),
                    TintTag(_matchReason(data), color: c.get, icon: Icons.bolt_rounded),
                    if (availability.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Free: $availability',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted)),
                    ],
                  ],
                ),
              ),
              Text(_shortAgo(data['timestamp'] as Timestamp?),
                  style: GoogleFonts.manrope(fontSize: 11.5, color: c.textMuted)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              button('Decline', c.surfaceLow, c.textMuted, () => _rejectRequest(docId)),
              const SizedBox(width: 10),
              button('Accept', c.cta, c.onCta, () {
                setState(() => _hiddenRequestIds.add(docId));
                _acceptFromSwipe(docId, data);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatsTab() {
    if (_chatsSnapshot == null) {
      return _buildLoadingShimmer();
    }
    final chatRooms = _chatsSnapshot?.docs ?? const [];
    if (chatRooms.isEmpty) {
      return _buildEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        useSwapMotif: true,
        title: 'No chats yet',
        message: 'Chats open up once you and someone else both say yes. '
            'Find someone whose skills match yours.',
        actionLabel: 'Start discovering',
        onAction: () => widget.onNavigateToTab?.call(1),
      );
    }
    final c = context.sw;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 16),
      itemCount: chatRooms.length,
      itemBuilder: (context, index) {
        final data = chatRooms[index].data() as Map<String, dynamic>;
        final chatRoomId = chatRooms[index].id;
        final users = List<String>.from(data['users'] ?? []);
        final otherUserId = users.firstWhere((id) => id != currentUserId, orElse: () => '');
        if (otherUserId.isEmpty) return const SizedBox.shrink();

        final userNames = data['userNames'] as Map<String, dynamic>?;
        final userPhotos = data['userPhotos'] as Map<String, dynamic>?;
        final otherUserName = (userNames?[otherUserId] ?? 'User').toString();
        final otherUserPhoto = (userPhotos?[otherUserId] ?? '').toString();
        final lastMessage = (data['lastMessage'] as String?) ?? 'No messages yet';
        final lastMessageTime = data['lastMessageTime'] as Timestamp?;
        final unreadCount =
            ((data['unreadCount'] as Map<String, dynamic>?)?[currentUserId] as num?)?.toInt() ??
                0;
        final unread = unreadCount > 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          child: Pressable(
            scale: 0.98,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatPage(
                  chatRoomId: chatRoomId,
                  otherUserName: otherUserName,
                  otherUserPhoto: otherUserPhoto,
                  otherUserId: otherUserId,
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration:
                  BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  SwapAvatar(
                      name: otherUserName, photoUrl: otherUserPhoto, size: 50, radius: 17),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(otherUserName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: c.text)),
                            ),
                            Text(_shortAgo(lastMessageTime),
                                style: GoogleFonts.manrope(
                                    fontSize: 11.5,
                                    fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                                    color: unread ? c.give : c.textMuted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                                      color: unread ? c.text : c.textMuted)),
                            ),
                            if (unread) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                    color: c.give, borderRadius: BorderRadius.circular(10)),
                                child: Text(unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
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
  }

  Widget _buildLoadingShimmer() => const ListSkeleton();

  /// Empty states name the next action rather than dead-ending on
  /// "nothing here yet" - an empty screen with no way forward is where
  /// new users quietly give up.
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    bool useSwapMotif = false,
  }) {
    final c = context.sw;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (useSwapMotif)
              const SwapMotif(width: 176)
            else
              HexTile(icon: icon, size: 92),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center,
                style: AppTheme.display(fontSize: 22, color: c.text)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13.5, color: c.textMuted, height: 1.45),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 22),
              Pressable(
                onTap: onAction,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
                  decoration:
                      BoxDecoration(color: c.cta, borderRadius: BorderRadius.circular(16)),
                  child: Text(actionLabel,
                      style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w800, color: c.onCta)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

}
