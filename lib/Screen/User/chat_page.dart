import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../services/swap_service.dart';
import '../../theme.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markMessagesAsRead();
      _loadCompletedSession();
    });
  }

  /// Ratings are only unlocked once a swap session has been completed.
  Future<void> _loadCompletedSession() async {
    final swapId = await SwapSessionService.instance
        .completedSessionWith(widget.otherUserId);
    if (!mounted) return;
    setState(() => _completedSwapId = swapId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  void _markMessagesAsRead() async {
    if (currentUser == null) return;
    
    // Update unread count to 0 for current user
    await FirebaseFirestore.instance
        .collection('chatRooms')
        .doc(widget.chatRoomId)
        .update({
      'unreadCount.${currentUser!.uid}': 0,
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating')),
      );
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
                content: Text('You already rated this swap session.')),
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
            .update({
          'rating': newRating,
          'ratingsCount': ratingsCount + 1,
        });
      }
      
      // Add system message about the rating
      await FirebaseFirestore.instance
          .collection('chatRooms')
          .doc(widget.chatRoomId)
          .collection('messages')
          .add({
        'senderId': 'system',
        'text': '${currentUser!.displayName} rated this skill exchange ${_rating.toStringAsFixed(1)} stars',
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit rating: $e')),
      );
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
            CachedNetworkImage(
              imageUrl: widget.otherUserPhoto,
              imageBuilder: (context, imageProvider) => CircleAvatar(
                radius: 20,
                backgroundImage: imageProvider,
              ),
              placeholder: (context, url) => CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[300],
                child: const Icon(Icons.person, size: 20, color: Colors.grey),
              ),
              errorWidget: (context, url, error) => CircleAvatar(
                radius: 20,
                backgroundColor: Colors.grey[300],
                child: const Icon(Icons.person, size: 20, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 14),
            Text(
              widget.otherUserName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_available, color: AppTheme.primaryColor),
            tooltip: 'Propose swap session',
            onPressed: _showProposeSessionDialog,
          ),
          IconButton(
            icon: Icon(
              Icons.star_rate,
              color: _completedSwapId == null
                  ? Colors.grey
                  : AppTheme.primaryColor,
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
            icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.onSurface),
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'safety') {
                showSafetySheet(
                  context,
                  userId: widget.otherUserId,
                  displayName: widget.otherUserName,
                );
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
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showRatingDialog)
            _buildRatingDialog(),
          // Messages
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chatRooms')
                  .doc(widget.chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No messages yet. Start a conversation!'),
                  );
                }
                final messages = snapshot.data!.docs;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });
                final items = <Widget>[];
                DateTime? lastDay;
                for (final doc in messages) {
                  final message = doc.data() as Map<String, dynamic>;
                  final ts = message['timestamp'] as Timestamp?;
                  if (ts != null) {
                    final day = DateTime(
                      ts.toDate().year,
                      ts.toDate().month,
                      ts.toDate().day,
                    );
                    if (lastDay == null || !_isSameDay(lastDay, day)) {
                      items.add(_buildDateChip(ts.toDate()));
                      lastDay = day;
                    }
                  }
                  final senderId = message['senderId'] as String;
                  final isCurrentUser = senderId == currentUser?.uid;
                  final messageType = message['type'] as String? ?? 'text';
                  if (messageType == 'system' || messageType == 'rating') {
                    items.add(_buildSystemMessage(message));
                  } else {
                    items.add(_buildChatMessage(message, isCurrentUser));
                  }
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  itemCount: items.length,
                  itemBuilder: (context, index) => items[index],
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: const [
                      Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Message failed to send',
                          style: TextStyle(fontSize: 13, color: Colors.redAccent),
                        ),
                      ),
                      Text(
                        'Tap to retry',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Message Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).scaffoldBackgroundColor,
                      ),
                      style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 2,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
    final meetingLinkController = TextEditingController();
    final agendaController = TextEditingController();
    DateTime scheduled = DateTime.now().add(const Duration(days: 1));

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
                    const Icon(Icons.event,
                        size: 18, color: AppTheme.primaryColor),
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
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (date == null) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(scheduled),
                        );
                        if (time == null) return;
                        setDialogState(() {
                          scheduled = DateTime(date.year, date.month, date.day,
                              time.hour, time.minute);
                        });
                      },
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: meetingLinkController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Meeting link (optional)',
                    hintText: 'Google Meet / Zoom / Jitsi URL',
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
    final ok = await SwapSessionService.instance.proposeSession(
      otherUserId: widget.otherUserId,
      otherUserName: widget.otherUserName,
      myName: currentUser?.displayName ?? 'Swapnio user',
      skillOffered: offered,
      skillWanted: wanted,
      scheduledFor: scheduled,
      meetingLink: meetingLinkController.text.trim(),
      agenda: agendaController.text.trim(),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Session proposed - they can accept it from the Requests tab'
            : 'Could not propose the session. Please try again.'),
        backgroundColor: ok ? AppTheme.primaryColor : Colors.redAccent,
      ),
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
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildChatMessage(Map<String, dynamic> message, bool isCurrentUser) {
    final text = message['text'] as String;
    final timestamp = message['timestamp'] as Timestamp?;
    final time = timestamp != null
        ? DateFormat.jm().format(timestamp.toDate())
        : '';

    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        child: GestureDetector(
          onLongPress: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Message copied'),
                duration: Duration(seconds: 1),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isCurrentUser
                  ? AppTheme.primaryColor.withValues(alpha: 0.13)
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
                      color: Colors.grey[600],
                    ),
                  ),
                  if (isCurrentUser) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.check, size: 13, color: Color(0xFF9A9088)),
                  ],
                ],
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
  Widget _buildSystemMessage(Map<String, dynamic> message) {
    final text = message['text'] as String;
    final type = message['type'] as String? ?? 'system';
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
                    itemBuilder: (context, _) => const Icon(
                      Icons.star,
                      color: AppTheme.primaryColor,
                    ),
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
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 18),
          Center(
            child: RatingBar.builder(
              initialRating: _rating,
              minRating: 1,
              direction: Axis.horizontal,
              allowHalfRating: true,
              itemCount: 5,
              itemBuilder: (context, _) => const Icon(
                Icons.star,
                color: AppTheme.primaryColor,
              ),
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
                selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                checkmarkColor: AppTheme.primaryColor,
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
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
