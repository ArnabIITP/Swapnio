import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:intl/intl.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../services/chat_service.dart';
import '../../services/google_calendar_service.dart';
import '../../services/swap_service.dart';
import '../../theme.dart';
import '../../ui/swapnio_widgets.dart';
import '../../ui/safety_sheet.dart';

class ChatPage extends StatefulWidget {
  final String chatRoomId;
  final String otherUserName;
  final String otherUserPhoto;
  final String otherUserId;

  const ChatPage({
    Key? key,
    required this.chatRoomId,
    required this.otherUserName,
    required this.otherUserPhoto,
    required this.otherUserId,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final currentUser = FirebaseAuth.instance.currentUser;
  bool _showRatingDialog = false;
  double _rating = 0;
  bool _sendFailed = false;
  String _failedText = '';
  String? _completedSwapId;
  final TextEditingController _reviewController = TextEditingController();
  final Set<String> _selectedFeedbackTags = {};
  // Created once, NOT inside build(): calling .snapshots() during build
  // returns a new Stream object each time, so StreamBuilder would tear down
  // and re-subscribe on every rebuild - which is what made the chat flash a
  // loading spinner constantly.
  late final Stream<QuerySnapshot> _messagesStream;
  // The room doc carries presence-style state (who's typing, when each side
  // last read) so it can be watched separately from the message list.
  late final Stream<DocumentSnapshot> _roomStream;
  late final Future<DocumentSnapshot> _otherUserFuture;
  final FocusNode _messageFocusNode = FocusNode();
  int _lastMessageCount = 0;
  bool _showScrollToBottom = false;
  Timer? _typingClearTimer;
  DateTime? _lastTypingWrite;
  // Only messages that arrive while the chat is open get the send/arrive
  // animation - replaying it on the whole history at open would be noise.
  final Set<String> _knownMessageIds = {};
  bool _historyLoaded = false;
  // Tracked separately from the message count: the typing bubble also
  // changes the list's length, and needs its own scroll handling.
  bool _typingVisible = false;
  Timer? _typingExpiryTimer;

  DocumentReference get _roomRef =>
      FirebaseFirestore.instance.collection('chatRooms').doc(widget.chatRoomId);

  static const List<String> _feedbackTagOptions = [
    'Punctual',
    'Clear teacher',
    'Patient',
    'Friendly',
    'Well prepared',
    'Great listener',
  ];

  @override
  void initState() {
    super.initState();
    // includeMetadataChanges lets a just-sent message show as "sending" and
    // then flip to "sent" once the server confirms it - Firestore already
    // renders local writes instantly, so this is optimistic send for free.
    _messagesStream = _roomRef
        .collection('messages')
        .orderBy('timestamp')
        .snapshots(includeMetadataChanges: true);
    _roomStream = _roomRef.snapshots();
    _otherUserFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .get();
    _messageController.addListener(_onTypingChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMessagesAsRead();
      _loadCompletedSession();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final farFromBottom = position.maxScrollExtent - position.pixels > 300;
    if (farFromBottom != _showScrollToBottom) {
      setState(() => _showScrollToBottom = farFromBottom);
    }
  }

  /// Publishes "I'm typing" at most every few seconds, and clears it shortly
  /// after the user stops - so the other side sees a live indicator without
  /// a Firestore write per keystroke.
  void _onTypingChanged() {
    final uid = currentUser?.uid;
    if (uid == null) return;
    if (_messageController.text.trim().isEmpty) {
      _clearTyping();
      return;
    }
    final now = DateTime.now();
    if (_lastTypingWrite == null ||
        now.difference(_lastTypingWrite!) > const Duration(seconds: 3)) {
      _lastTypingWrite = now;
      _roomRef
          .update({'typing.$uid': FieldValue.serverTimestamp()})
          .catchError((_) {});
    }
    _typingClearTimer?.cancel();
    _typingClearTimer = Timer(const Duration(seconds: 4), _clearTyping);
  }

  void _clearTyping() {
    final uid = currentUser?.uid;
    _typingClearTimer?.cancel();
    if (uid == null || _lastTypingWrite == null) return;
    _lastTypingWrite = null;
    _roomRef.update({'typing.$uid': FieldValue.delete()}).catchError((_) {});
  }

  /// Ratings are only unlocked once a swap session has been completed.
  Future<void> _loadCompletedSession() async {
    final swapId = await SwapSessionService.instance.completedSessionWith(
      widget.otherUserId,
    );
    if (!mounted) return;
    setState(() => _completedSwapId = swapId);
  }

  @override
  void dispose() {
    _clearTyping();
    _typingExpiryTimer?.cancel();
    _messageController.removeListener(_onTypingChanged);
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  /// Clears the unread badge and stamps when I last read - the other side
  /// uses that timestamp to show "Seen" under their latest message.
  void _markMessagesAsRead() async {
    if (currentUser == null) return;
    try {
      await _roomRef.update({
        'unreadCount.${currentUser!.uid}': 0,
        'lastReadAt.${currentUser!.uid}': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // A missing room (e.g. deleted by a moderator) shouldn't crash the page.
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || currentUser == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();
    _clearTyping();
    HapticFeedback.lightImpact();

    try {
      // Add message to the chat room's messages collection
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
            'senderId': currentUser!.uid,
            'text': messageText,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'text',
          });

      // Update the chat room document with the last message info
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .update({
            'lastMessage': messageText,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'lastMessageSenderId': currentUser!.uid,
            // Increment unread count for other user
            'unreadCount.${widget.otherUserId}': FieldValue.increment(1),
          });

      // Add a delay before scrolling to ensure the message is rendered
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    } catch (e) {
      print('Error sending message: $e');
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = messageText;
      }
      setState(() {
        _sendFailed = true;
        _failedText = messageText;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message. Tap retry below to resend.'),
        ),
      );
    }
  }

  Future<void> _submitRating() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a rating')));
      return;
    }

    try {
      // Duplicate guard: one rating per rater per completed session.
      if (_completedSwapId != null) {
        final existing = await FirebaseFirestore.instance
            .collection('ratings')
            .where('fromUserId', isEqualTo: currentUser!.uid)
            .where('swapId', isEqualTo: _completedSwapId)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You already rated this swap session.'),
            ),
          );
          return;
        }
      }

      // Add rating document
      await FirebaseFirestore.instance.collection('ratings').add({
        'fromUserId': currentUser!.uid,
        'toUserId': widget.otherUserId,
        'swapId': _completedSwapId,
        'rating': _rating,
        'review': _reviewController.text.trim(),
        'tags': _selectedFeedbackTags.toList(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Recompute the average from the actual rating count (NOT completedSwaps,
      // which counts swaps, not ratings - both participants rate separately).
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;
        final currentRating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
        final ratingsCount = (userData['ratingsCount'] as num?)?.toInt() ?? 0;

        final newRating =
            ((currentRating * ratingsCount) + _rating) / (ratingsCount + 1);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.otherUserId)
            .update({'rating': newRating, 'ratingsCount': ratingsCount + 1});
      }

      // Add system message about the rating
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
            'senderId': 'system',
            'text':
                '${currentUser!.displayName} rated this skill exchange ${_rating.toStringAsFixed(1)} stars',
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'rating',
            'rating': _rating,
          });

      // Reset rating dialog state
      setState(() {
        _showRatingDialog = false;
        _rating = 0;
        _reviewController.clear();
        _selectedFeedbackTags.clear();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you for your rating!')),
      );
    } catch (e) {
      print('Error submitting rating: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to submit rating: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 1,
        backgroundColor: Theme.of(context).colorScheme.surface,
        titleSpacing: 0,
        title: Row(
          children: [
            SwapAvatar(
              name: widget.otherUserName,
              photoUrl: widget.otherUserPhoto,
              size: 40,
              radius: 14,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.otherUserName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  color: context.sw.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.event_available,
              color: context.sw.give,
            ),
            tooltip: 'Propose swap session',
            onPressed: _showProposeSessionDialog,
          ),
          IconButton(
            icon: Icon(
              Icons.star_rate,
              color: _completedSwapId == null
                  ? Colors.grey
                  : context.sw.give,
            ),
            tooltip: _completedSwapId == null
                ? 'Complete a swap session to unlock ratings'
                : 'Rate this user',
            onPressed: () {
              if (_completedSwapId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Finish a swap session together first - then you can rate '
                      'each other.',
                    ),
                  ),
                );
                return;
              }
              setState(() {
                _showRatingDialog = true;
              });
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'safety') {
                showSafetySheet(
                  context,
                  userId: widget.otherUserId,
                  displayName: widget.otherUserName,
                );
              } else if (value == 'unmatch') {
                _confirmUnmatch();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'safety',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Block or report'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'unmatch',
                child: Row(
                  children: [
                    Icon(Icons.heart_broken_outlined, size: 18, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Unmatch', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showRatingDialog) _buildRatingDialog(),
          // Messages
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _roomStream,
              builder: (context, roomSnapshot) {
                final room =
                    (roomSnapshot.data?.data() as Map<String, dynamic>?) ?? {};
                return Stack(
                  children: [
                    _buildMessageList(room),
                    if (_showScrollToBottom)
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: FloatingActionButton.small(
                          heroTag: 'chat_scroll_bottom',
                          backgroundColor: context.sw.give,
                          foregroundColor: Colors.white,
                          tooltip: 'Jump to latest',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _scrollToBottom();
                          },
                          child: const Icon(Icons.keyboard_arrow_down),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // Failed-message retry banner
          if (_sendFailed)
            Material(
              color: Colors.red.shade50,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _sendFailed = false;
                    _failedText = '';
                  });
                  _sendMessage();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.error_outline,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Message failed to send',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                      Text(
                        'Tap to retry',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Message Input - replaced by a banner once either side unmatches.
          StreamBuilder<DocumentSnapshot>(
            stream: _roomStream,
            builder: (context, roomSnapshot) {
              final room =
                  (roomSnapshot.data?.data() as Map<String, dynamic>?) ?? {};
              if (room['unmatched'] == true) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  color: Theme.of(context).colorScheme.surface,
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Icon(Icons.heart_broken_outlined,
                            size: 18, color: context.sw.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You unmatched - you can no longer message each other.',
                            style: TextStyle(fontSize: 13, color: context.sw.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 8.0,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.13),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).scaffoldBackgroundColor,
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Pressable(
                        onTap: _sendMessage,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: context.sw.give,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.arrow_upward_rounded,
                              color: Colors.white, semanticLabel: 'Send'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnmatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Unmatch ${widget.otherUserName}?'),
        content: const Text(
          "You'll no longer be able to message each other and this chat "
          'will disappear from both your inboxes. Any pending swap request '
          'between you is also cleared. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Unmatch'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await ChatService.instance.unmatch(
      widget.chatRoomId,
      widget.otherUserId,
    );
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not unmatch. Please try again.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('You unmatched ${widget.otherUserName}.')),
    );
    navigator.pop();
  }

  Future<void> _showProposeSessionDialog() async {
    // Blocked users get told why and how to recover, instead of hitting an
    // opaque permission-denied from the security rule.
    final reliability = await SwapSessionService.instance.myReliability();
    if (!reliability.canBookSessions) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Session booking paused'),
          content: Text(
            'You\'ve missed ${reliability.noShows} of your last '
            '${reliability.total} sessions (${reliability.showUpRate}% show-up rate).\n\n'
            'Booking is paused until that improves. Turn up to the sessions '
            'you\'ve already agreed to, and it unlocks automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }

    final offeredController = TextEditingController();
    final wantedController = TextEditingController();
    final agendaController = TextEditingController();
    DateTime scheduled = DateTime.now().add(const Duration(days: 1));

    // Google-auth accounts usually already have a cached Google session on
    // this device, so calendar access can be picked up without a prompt.
    // Email/password accounts fall through to the "Connect" button below.
    bool calendarConnected = await GoogleCalendarService.instance.ensureConnected();
    bool connectingCalendar = false;

    final proposed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Propose a swap session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: offeredController,
                  decoration: const InputDecoration(
                    labelText: 'What will you teach?',
                    hintText: 'e.g. Intro to Flutter',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: wantedController,
                  decoration: const InputDecoration(
                    labelText: 'What do you want to learn?',
                    hintText: 'e.g. Guitar basics',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.event,
                      size: 18,
                      color: dialogContext.sw.give,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMd().add_jm().format(scheduled),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: scheduled,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date == null) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(scheduled),
                        );
                        if (time == null) return;
                        setDialogState(() {
                          scheduled = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (calendarConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: dialogContext.sw.give.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: dialogContext.sw.give),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Google Calendar connected - a Meet link and calendar '
                            'invite will be created automatically.',
                            style: TextStyle(fontSize: 12.5, color: dialogContext.sw.give),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: connectingCalendar
                          ? null
                          : () async {
                              setDialogState(() => connectingCalendar = true);
                              final ok = await GoogleCalendarService.instance.connect();
                              setDialogState(() {
                                calendarConnected = ok;
                                connectingCalendar = false;
                              });
                              if (!ok && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not connect Google Calendar. You can still '
                                      'propose the session without a meeting link.',
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: connectingCalendar
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.calendar_month, size: 16),
                      label: Text(
                        connectingCalendar ? 'Connecting...' : 'Connect Google Calendar',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dialogContext.sw.give,
                        side: BorderSide(color: dialogContext.sw.give),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: agendaController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Agenda (optional)',
                    hintText: 'What do you want to cover in this session?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Propose'),
            ),
          ],
        ),
      ),
    );

    if (proposed != true) return;

    final offered = offeredController.text.trim();
    final wanted = wantedController.text.trim();
    if (offered.isEmpty || wanted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe both skills')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final agenda = agendaController.text.trim();

    // Only attempt event creation if calendar access is actually connected -
    // otherwise the session still gets proposed, just without a meeting link.
    String meetingLink = '';
    if (calendarConnected) {
      meetingLink = await GoogleCalendarService.instance.createSwapEvent(
            title: 'Swapnio swap session with ${widget.otherUserName}',
            start: scheduled,
            description: agenda.isEmpty ? 'Swap session arranged via Swapnio.' : agenda,
          ) ??
          '';
    }

    final ok = await SwapSessionService.instance.proposeSession(
      otherUserId: widget.otherUserId,
      otherUserName: widget.otherUserName,
      myName: currentUser?.displayName ?? 'Swapnio user',
      skillOffered: offered,
      skillWanted: wanted,
      scheduledFor: scheduled,
      meetingLink: meetingLink,
      agenda: agenda,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? 'Could not propose the session. Please try again.'
              : calendarConnected && meetingLink.isEmpty
                  ? 'Session proposed, but the Meet link could not be created - '
                      'you can add one later from the session details.'
                  : 'Session proposed - they can accept it from the Requests tab',
        ),
        backgroundColor: ok ? context.sw.give : Colors.redAccent,
      ),
    );
  }

  /// A blank thread is where new matches stall: the first message is the
  /// hard part. Naming why you matched and offering an opener (which the
  /// person can edit before sending) removes most of that friction.
  Widget _buildChatEmptyState() {
    final c = context.sw;
    return FutureBuilder<DocumentSnapshot>(
      future: _otherUserFuture,
      builder: (context, snapshot) {
        final other = snapshot.data?.data() as Map<String, dynamic>?;
        final theyTeach = List<String>.from(other?['skillsOffered'] ?? []);
        final theyWant = List<String>.from(other?['skillsWanted'] ?? []);
        final me = Provider.of<AppState>(context, listen: false).currentUser;
        final myWant = me?.skillsWanted.map((e) => e.toLowerCase()).toSet() ?? <String>{};
        final myTeach = me?.skillsOffered.map((e) => e.toLowerCase()).toSet() ?? <String>{};

        String pick(List<String> theirs, Set<String> mine) {
          for (final skill in theirs) {
            if (mine.contains(skill.toLowerCase())) return skill;
          }
          return theirs.isNotEmpty ? theirs.first : '';
        }

        final youGet = pick(theyTeach, myWant);
        final youGive = pick(theyWant, myTeach);
        final firstName = widget.otherUserName.split(' ').first;
        final openers = <String>[
          if (youGet.isNotEmpty)
            'Hey $firstName! How did you get into $youGet?'
          else
            'Hey $firstName! What are you hoping to learn right now?',
          if (youGive.isNotEmpty)
            'I could walk you through $youGive - what level are you at?'
          else
            'Want to set up a short intro call this week?',
          'Want to start with a 30-minute intro session?',
        ];

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.win,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.handshake_rounded, color: c.onWin, size: 28),
              ),
              const SizedBox(height: 16),
              Text(
                youGet.isNotEmpty && youGive.isNotEmpty
                    ? 'A perfect swap, both ways'
                    : 'You matched',
                textAlign: TextAlign.center,
                style: AppTheme.display(fontSize: 24, color: c.text),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap a question to fill it in - you can edit it before sending.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13, color: c.textMuted, height: 1.4),
              ),
              if (youGet.isNotEmpty || youGive.isNotEmpty) ...[
                const SizedBox(height: 18),
                SwapSplit(
                  giveLabel: 'YOU TEACH',
                  giveSkill: youGive.isEmpty ? 'Your skills' : youGive,
                  getLabel: '${firstName.toUpperCase()} TEACHES',
                  getSkill: youGet.isEmpty ? 'Their skills' : youGet,
                ),
              ],
              const SizedBox(height: 18),
              for (final opener in openers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Pressable(
                    onTap: () {
                      _messageController.text = opener;
                      _messageController.selection = TextSelection.fromPosition(
                        TextPosition(offset: opener.length),
                      );
                      _messageFocusNode.requestFocus();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 14, color: c.give),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(opener,
                                style: GoogleFonts.manrope(fontSize: 13, color: c.text)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDateChip(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(date.year, date.month, date.day);
    final label = _isSameDay(today, thatDay)
        ? 'Today'
        : _isSameDay(today, thatDay.subtract(const Duration(days: 1)))
        ? 'Yesterday'
        : DateFormat.yMMMd().format(date);
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static const List<String> _reactionOptions = [
    '👍',
    '❤️',
    '😂',
    '🎉',
    '🙏',
    '💡',
  ];

  Widget _buildMessageList(Map<String, dynamic> room) {
    return StreamBuilder<QuerySnapshot>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        // Only the very first load shows a spinner. Re-checking `waiting` on
        // every build is what made the chat appear to reload constantly.
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // A brand-new room already contains the "swap matched" system
        // message, so an empty *conversation* is not an empty collection.
        final allDocs = snapshot.data?.docs ?? const [];
        final hasRealMessage = allDocs.any((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;
          return data['type']?.toString() != 'system' &&
              data['senderId']?.toString() != 'system';
        });
        if (!hasRealMessage) {
          return _buildChatEmptyState();
        }

        // A just-sent message has a null server timestamp until confirmed,
        // and Firestore orders nulls first - which would flash it at the top
        // of the chat. Sort pending messages to the bottom instead.
        final messages = [...snapshot.data!.docs]
          ..sort((a, b) {
            final rawA = (a.data() as Map<String, dynamic>?)?['timestamp'];
            final rawB = (b.data() as Map<String, dynamic>?)?['timestamp'];
            final ta = rawA is Timestamp ? rawA : null;
            final tb = rawB is Timestamp ? rawB : null;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return ta.compareTo(tb);
          });

        final newIds = messages
            .map((d) => d.id)
            .where((id) => !_knownMessageIds.contains(id))
            .toSet();
        final animateIds = _historyLoaded ? newIds : <String>{};
        _knownMessageIds.addAll(newIds);
        _historyLoaded = true;

        if (messages.length != _lastMessageCount) {
          final lastData = messages.last.data() as Map<String, dynamic>;
          final lastIsMine = lastData['senderId'] == currentUser?.uid;
          _lastMessageCount = messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Don't yank someone reading history back to the bottom because
            // the other person sent something - the jump button covers that.
            if (lastIsMine || !_showScrollToBottom) _scrollToBottom();
            if (!lastIsMine) _markMessagesAsRead();
          });
        }

        final readMap = room['lastReadAt'];
        final readValue = readMap is Map ? readMap[widget.otherUserId] : null;
        final otherReadAt = readValue is Timestamp ? readValue : null;
        final lastMineIndex = messages.lastIndexWhere(
          (d) =>
              (d.data() as Map<String, dynamic>)['senderId'] ==
                  currentUser?.uid &&
              ((d.data() as Map<String, dynamic>)['type'] ?? 'text') == 'text',
        );

        final items = <Widget>[];
        DateTime? lastDay;
        for (var i = 0; i < messages.length; i++) {
          final doc = messages[i];
          // Each message is built in isolation: they're constructed eagerly
          // inside this builder, so a single malformed document used to throw
          // here and blank the entire conversation grey.
          try {
            final message = doc.data() as Map<String, dynamic>;
            final ts = message['timestamp'] as Timestamp?;
            if (ts != null) {
              final date = ts.toDate();
              final day = DateTime(date.year, date.month, date.day);
              if (lastDay == null || !_isSameDay(lastDay, day)) {
                items.add(_buildDateChip(date));
                lastDay = day;
              }
            }
            final isCurrentUser = message['senderId'] == currentUser?.uid;
            final messageType = message['type'] as String? ?? 'text';
            Widget bubble;
            if (messageType == 'system' || messageType == 'rating') {
              bubble = _buildSystemMessage(message);
            } else {
              final seen =
                  i == lastMineIndex &&
                  ts != null &&
                  otherReadAt != null &&
                  otherReadAt.compareTo(ts) >= 0;
              bubble = _buildChatMessage(
                message,
                isCurrentUser,
                docId: doc.id,
                pending: doc.metadata.hasPendingWrites,
                seen: seen,
              );
            }
            items.add(
              animateIds.contains(doc.id)
                  ? _ArriveAnimation(
                      key: ValueKey('anim_${doc.id}'),
                      fromRight: isCurrentUser,
                      child: bubble,
                    )
                  : bubble,
            );
          } catch (error, stack) {
            FirebaseCrashlytics.instance.recordError(
              error,
              stack,
              reason:
                  'chat message render failed: ${widget.chatRoomId}/${doc.id}',
            );
            items.add(_buildUnreadableMessage());
          }
        }

        final typingNow = _isOtherTyping(room);
        if (typingNow) {
          items.add(_buildTypingIndicator());
          // If their app dies mid-sentence the flag is never cleared, and
          // nothing would rebuild to let it expire - so re-check shortly.
          _typingExpiryTimer?.cancel();
          _typingExpiryTimer = Timer(const Duration(seconds: 9), () {
            if (mounted) setState(() {});
          });
        }
        if (typingNow != _typingVisible) {
          _typingVisible = typingNow;
          // Bring the bubble into view when it appears, and settle back
          // smoothly when it goes - but only if the reader is already near
          // the bottom, never while they're scrolled up reading history.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_showScrollToBottom) _scrollToBottom();
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          itemCount: items.length,
          itemBuilder: (context, index) => items[index],
        );
      },
    );
  }

  Widget _buildUnreadableMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          'This message could not be displayed',
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: context.sw.textMuted,
          ),
        ),
      ),
    );
  }

  bool _isOtherTyping(Map<String, dynamic> room) {
    final typing = room['typing'];
    final ts = typing is Map ? typing[widget.otherUserId] : null;
    if (ts is! Timestamp) return false;
    // Stale "typing" (app killed mid-sentence) expires on its own.
    return DateTime.now().difference(ts.toDate()) < const Duration(seconds: 8);
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _TypingDots(),
            const SizedBox(width: 8),
            Text(
              '${widget.otherUserName.split(' ').first} is typing',
              style: TextStyle(fontSize: 12, color: context.sw.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press sheet: react, or copy. Reactions are one per person per
  /// message - picking the same emoji again removes it.
  Future<void> _showMessageActions(
    String docId,
    String text,
    Map<String, dynamic> reactions,
  ) async {
    HapticFeedback.mediumImpact();
    final uid = currentUser?.uid;
    if (uid == null) return;
    final mine = reactions[uid] as String?;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _reactionOptions.map((emoji) {
                  final selected = emoji == mine;
                  return InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      HapticFeedback.selectionClick();
                      _roomRef
                          .collection('messages')
                          .doc(docId)
                          .update({
                            'reactions.$uid': selected
                                ? FieldValue.delete()
                                : emoji,
                          })
                          .catchError((_) {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? sheetContext.sw.give.withValues(alpha: 0.18)
                            : Colors.transparent,
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy message'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Message copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessage(
    Map<String, dynamic> message,
    bool isCurrentUser, {
    required String docId,
    bool pending = false,
    bool seen = false,
  }) {
    final text = message['text']?.toString() ?? '';
    final rawTs = message['timestamp'];
    final timestamp = rawTs is Timestamp ? rawTs : null;
    final time = timestamp != null
        ? DateFormat.jm().format(timestamp.toDate())
        : '';
    final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});

    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            child: GestureDetector(
              onLongPress: () => _showMessageActions(docId, text, reactions),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isCurrentUser
                      ? context.sw.give.withValues(alpha: 0.13)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(isCurrentUser ? 16 : 4),
                    topRight: Radius.circular(isCurrentUser ? 4 : 16),
                    bottomLeft: const Radius.circular(16),
                    bottomRight: const Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: context.sw.textMuted,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 4),
                          Icon(
                            pending ? Icons.schedule : Icons.check,
                            size: 13,
                            color: const Color(0xFF9A9088),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (reactions.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.sw.border),
                ),
                child: Text(
                  reactions.values.toSet().join(' ') +
                      (reactions.length > 1 ? ' ${reactions.length}' : ''),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (seen)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: Text(
                'Seen',
                style: TextStyle(fontSize: 10.5, color: context.sw.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(Map<String, dynamic> message) {
    final text = message['text']?.toString() ?? '';
    final type = message['type']?.toString() ?? 'system';
    final rating = type == 'rating' ? (message['rating'] ?? 0.0) : 0.0;

    return Container(
      alignment: Alignment.center,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (type == 'rating')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RatingBar.builder(
                    initialRating: rating.toDouble(),
                    minRating: 1,
                    direction: Axis.horizontal,
                    allowHalfRating: true,
                    itemCount: 5,
                    itemSize: 16,
                    ignoreGestures: true,
                    itemBuilder: (context, _) =>
                        Icon(Icons.star, color: context.sw.give),
                    onRatingUpdate: (_) {},
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRatingDialog() {
    return Container(
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Rate Your Experience',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _showRatingDialog = false;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'How was your skill exchange with ${widget.otherUserName}?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: RatingBar.builder(
              initialRating: _rating,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemBuilder: (context, _) =>
                  Icon(Icons.star, color: context.sw.give),
              onRatingUpdate: (rating) {
                setState(() {
                  _rating = rating;
                });
              },
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _feedbackTagOptions.map((tag) {
              final selected = _selectedFeedbackTags.contains(tag);
              return FilterChip(
                label: Text(tag, style: const TextStyle(fontSize: 12)),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedFeedbackTags.add(tag);
                    } else {
                      _selectedFeedbackTags.remove(tag);
                    }
                  });
                },
                selectedColor: context.sw.give.withValues(alpha: 0.2),
                checkmarkColor: context.sw.give,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _reviewController,
            decoration: InputDecoration(
              hintText: 'Write a review (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.sw.border),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: context.sw.give,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _submitRating,
              child: const Text('Submit Rating'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides a newly arrived message in from its side and settles it, so a
/// message feels sent/received rather than just appearing.
class _ArriveAnimation extends StatelessWidget {
  final Widget child;
  final bool fromRight;

  const _ArriveAnimation({
    super.key,
    required this.child,
    required this.fromRight,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(
            (fromRight ? 24 : -24) * (1 - value),
            14 * (1 - value),
          ),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Three dots pulsing in sequence - the universal "someone is typing" cue.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_controller.value - i * 0.18) % 1.0;
          final lift = phase < 0.4
              ? (1 - (phase - 0.2).abs() / 0.2).clamp(0.0, 1.0)
              : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Transform.translate(
              offset: Offset(0, -3 * lift),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: context.sw.give.withValues(
                    alpha: 0.45 + 0.55 * lift,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
