import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/safety_service.dart';
import '../../services/match_service.dart';
import '../../theme.dart';
import '../../ui/swapnio_badges.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import '../../ui/celebration.dart';
import 'setup.dart';
import 'user_detail.dart';
import 'dart:math' show pi;

class Swap extends StatefulWidget {
  /// Lets the match celebration jump straight to the Chats tab.
  final ValueChanged<int>? onNavigateToTab;

  const Swap({Key? key, this.onNavigateToTab}) : super(key: key);

  @override
  State<Swap> createState() => _SwapState();
}

class _SwapState extends State<Swap> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _swipedUsers = [];
  int _currentIndex = 0;
  // null = no drag tint active; falls back to the theme's scaffold color.
  Color? _dragTintColor;
  bool _isLoading = true;
  bool _isProcessingAction = false;
  // Ids we already sent a like-request to this session. Rewinding past a
  // liked card and liking it again must not create a duplicate request.
  final Set<String> _likeRequestSentIds = {};
  late AnimationController _animationController;
  Offset _dragStart = Offset.zero;
  double _dragX = 0;
  double _dragY = 0;
  double _dragRotation = 0.0;
  // Browsing used to live in a separate Home tab doing the same job; it's now
  // a mode of Discover for people who'd rather scan a list than swipe.
  bool _listMode = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  // Swipe-up-to-favourite is invisible unless we teach it once.
  bool _showCoachmarks = false;
  // Built once, not in build(): a stream created during build is a new object
  // every rebuild, forcing StreamBuilder to re-subscribe each time.
  Stream<QuerySnapshot>? _likesYouStream;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) {
      _likesYouStream = FirebaseFirestore.instance
          .collection('swipeRequests')
          .where('toUserId', isEqualTo: myUid)
          .snapshots();
    }
    _loadUsers();
    _maybeShowCoachmarks();
  }

  Future<void> _maybeShowCoachmarks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.data()?['hasSeenSwipeCoachmarks'] == true) return;
      if (mounted) setState(() => _showCoachmarks = true);
    } catch (_) {
      // Never block the deck on this.
    }
  }

  Future<void> _dismissCoachmarks() async {
    setState(() => _showCoachmarks = false);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'hasSeenSwipeCoachmarks': true}, SetOptions(merge: true));
    } catch (_) {
      // Worst case they see the hint again next launch.
    }
  }

  List<Map<String, dynamic>> get _searchResults {
    if (_searchQuery.trim().isEmpty) return _users;
    final query = _searchQuery.toLowerCase();
    return _users.where((user) {
      final name = (user['name'] ?? '').toString().toLowerCase();
      final bio = (user['bio'] ?? '').toString().toLowerCase();
      final offered = List<String>.from(user['skillsOffered'] ?? [])
          .join(' ')
          .toLowerCase();
      final wanted =
          List<String>.from(user['skillsWanted'] ?? []).join(' ').toLowerCase();
      return name.contains(query) ||
          bio.contains(query) ||
          offered.contains(query) ||
          wanted.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      List<String> mySkillsWanted = [];
      List<String> mySkillsOffered = [];
      List<String> myAvailability = [];
      if (currentUserDoc.exists) {
        final currentUserData = currentUserDoc.data()!;
        mySkillsWanted = List<String>.from(currentUserData['skillsWanted'] ?? []);
        mySkillsOffered = List<String>.from(currentUserData['skillsOffered'] ?? []);
        myAvailability = List<String>.from(currentUserData['availability'] ?? []);
      }
      // Fetch all users and exclude the current user by document ID
      // in Dart. Firestore's `isNotEqualTo` on an `id` field would silently
      // drop documents that don't store that field (see UserModel.toMap()).
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();
      final requestedSnapshot = await FirebaseFirestore.instance
          .collection('swipeRequests')
          .where('fromUserId', isEqualTo: currentUserId)
          .get();
      // Users we already chat with (accepted match) shouldn't reappear in
      // the swipe deck.
      final chatRoomsSnapshot = await FirebaseFirestore.instance
          .collection('chatRooms')
          .where('users', arrayContains: currentUserId)
          .get();
      final hiddenIds = await SafetyService.instance.hiddenUserIds();
      final requestedUserIds = requestedSnapshot.docs
          .map((doc) => (doc.data()['toUserId'] as String?) ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();
      final matchedUserIds = chatRoomsSnapshot.docs
          .expand((doc) => List<String>.from(doc.data()['users'] ?? []))
          .where((id) => id != currentUserId)
          .toSet();
      final allUsers = snapshot.docs
          .where((doc) => doc.id != currentUserId)
          .map((doc) {
        final data = doc.data();
        final userId = doc.id;
        final skillsOffered = List<String>.from(data['skillsOffered'] ?? []);
        final skillsWanted = List<String>.from(data['skillsWanted'] ?? []);
        final availability = List<String>.from(data['availability'] ?? []);
        final match = MatchService.compute(
          mySkillsOffered: mySkillsOffered,
          mySkillsWanted: mySkillsWanted,
          myAvailability: myAvailability,
          candidateSkillsOffered: skillsOffered,
          candidateSkillsWanted: skillsWanted,
          candidateAvailability: availability,
          candidateRating: (data['rating'] as num?)?.toDouble() ?? 0.0,
        );
        return {
          'id': userId,
          'name': data['name'] ?? 'Anonymous',
          'skillsOffered': skillsOffered,
          'skillsWanted': skillsWanted,
          'availability': availability,
          'photoUrl': data['photoUrl'] ?? '',
          'bio': data['bio'] ?? '',
          'rating': data['rating'] ?? 0.0,
          'completedSwaps': data['completedSwaps'] ?? 0,
          'matchPercent': match.percent,
          'theyTeachIWant': match.theyTeachIWant,
          'iTeachTheyWant': match.iTeachTheyWant,
          'sharedAvailability': match.sharedAvailability,
          'isBanned': data['isBanned'] ?? false,
        };
      }).where((user) =>
          !requestedUserIds.contains(user['id']) &&
          !matchedUserIds.contains(user['id']) &&
          !hiddenIds.contains(user['id']) &&
          user['isBanned'] != true).toList();
      allUsers.sort((a, b) =>
          (b['matchPercent'] as double).compareTo(a['matchPercent'] as double));

      if (mounted) {
        setState(() {
          _users = allUsers;
          _swipedUsers = [];
          _currentIndex = 0;
          _isLoading = false;
          _dragX = 0;
          _dragRotation = 0.0;
          _dragY = 0.0;
        });
      }
    } catch (e) {
      print('Error loading users: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _sendLikeRequest(Map<String, dynamic> toUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final toUserId = toUser['id'] as String?;
    if (toUserId == null || _likeRequestSentIds.contains(toUserId)) return;
    _likeRequestSentIds.add(toUserId);
    try {
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (!currentUserDoc.exists) return;
      final currentUserData = currentUserDoc.data()!;
      await FirebaseFirestore.instance.collection('swipeRequests').add({
        'fromUserId': currentUser.uid,
        'fromName': currentUserData['name'] ?? "Anonymous",
        'fromPhoto': currentUserData['photoUrl'] ?? "",
        'toUserId': toUser["id"],
        'toUserName': toUser["name"],
        'skillsOffered': currentUserData['skillsOffered'] ?? [],
        'skillsWanted': currentUserData['skillsWanted'] ?? [],
        'availability': currentUserData['availability'] ?? [],
        'timestamp': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': toUser["id"],
        'type': 'swap_request',
        'message':
        '${currentUserData['name'] ?? "Someone"} wants to swap skills with you',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'senderId': currentUser.uid,
        'senderName': currentUserData['name'] ?? "Anonymous",
        'senderPhoto': currentUserData['photoUrl'] ?? "",
      });
    } catch (e) {
      _likeRequestSentIds.remove(toUserId); // allow retry after a failure
      print("Error sending request (background): $e");
    }
  }

  Future<void> _addToFavoritesBackend(Map<String, dynamic> favUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final existing = await FirebaseFirestore.instance
          .collection('favorites')
          .where('userId', isEqualTo: currentUser.uid)
          .where('favoriteUserId', isEqualTo: favUser['id'])
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) return; // already favorited
      await FirebaseFirestore.instance.collection('favorites').add({
        'userId': currentUser.uid,
        'favoriteUserId': favUser['id'],
        'favoriteUserName': favUser['name'] ?? '',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error adding favorite (background): $e");
    }
  }

  void _nextUser() {
    if (_currentIndex < _users.length) {
      _swipedUsers.add(_users[_currentIndex]);
      if (mounted) {
        setState(() {
          _currentIndex++;
        });
      }
    }
  }

  /// Checks whether the user we just liked has already liked us back.
  Future<void> _checkForMatch(Map<String, dynamic> toUser) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('swipeRequests')
          .where('fromUserId', isEqualTo: toUser['id'])
          .where('toUserId', isEqualTo: currentUser.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        _showMatchDialog(toUser['name'] ?? 'your match');
      }
    } catch (e) {
      print('Match check failed: $e');
    }
  }

  Future<void> _showMatchDialog(String name) async {
    // A beat of anticipation lands harder than an instant pop-up: two light
    // "heartbeat" taps, then the reveal.
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 180));
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    await showCelebrationDialog(
      context,
      icon: Icons.favorite,
      headline: "It's a Match!",
      message: 'You and $name liked each other. '
          'Say hi before the moment passes.',
      primaryLabel: 'Say hi →',
      onPrimary: () => widget.onNavigateToTab?.call(2),
      secondaryLabel: 'Keep swiping',
    );
  }

  void _handleDragStart(DragStartDetails details) {
    if (_isProcessingAction) return;
    _dragStart = details.globalPosition;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isProcessingAction) return;
    setState(() {
      _dragX = details.globalPosition.dx - _dragStart.dx;
      _dragY = details.globalPosition.dy - _dragStart.dy;
      _dragRotation =
          _dragX / (MediaQuery.of(context).size.width * 0.8) * 0.2;

      // Determine if the drag is predominantly vertical
      final isVerticalDrag = _dragY.abs() > _dragX.abs() * 1.5;

      final screenWidth = MediaQuery.of(context).size.width;
      final dragPercentageX = _dragX / screenWidth;
      final dragPercentageY = _dragY / MediaQuery.of(context).size.height;
      final baseColor = Theme.of(context).scaffoldBackgroundColor;
      final redColor = Color.lerp(
          baseColor, context.sw.get.withValues(alpha: 0.2), -dragPercentageX.clamp(-1.0, 0.0))!;
      final greenColor = Color.lerp(
          baseColor, context.sw.give.withValues(alpha: 0.2), dragPercentageX.clamp(0.0, 1.0))!;
      final blueColor = Color.lerp(
          baseColor, Colors.blue.withValues(alpha: 0.1), -dragPercentageY.clamp(-1.0, 0.0))!;

      if (isVerticalDrag && _dragY < 0) {
        _dragTintColor = blueColor;
      } else if (!isVerticalDrag && _dragX > 0) {
        _dragTintColor = greenColor;
      } else if (!isVerticalDrag && _dragX < 0) {
        _dragTintColor = redColor;
      } else {
        _dragTintColor = null;
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isProcessingAction) return;
    final velocity = details.velocity.pixelsPerSecond;
    final cardWidth = MediaQuery.of(context).size.width * 0.7;
    final cardHeight = MediaQuery.of(context).size.height * 0.4;

    // Stricter check for vertical drag dominance
    final isVerticalDrag = _dragY.abs() > _dragX.abs() * 1.5;

    // Prioritize vertical swipes
    if (isVerticalDrag && (_dragY < -cardHeight * 0.2 || velocity.dy < -800)) {
      HapticFeedback.mediumImpact();
      _animateCardUp();
    }
    // Then check for horizontal swipes
    else if (!isVerticalDrag && (_dragX.abs() > cardWidth * 0.4 || velocity.dx.abs() > 800)) {
      HapticFeedback.mediumImpact();
      _animateCardOut(_dragX > 0);
    }
    // Otherwise, animate back to center
    else {
      _animateCardBack();
    }
  }

  void _animateCardOut(bool isRight) {
    if (_currentIndex >= _users.length) return;
    setState(() => _isProcessingAction = true);
    final screenWidth = MediaQuery.of(context).size.width;
    final startX = _dragX;
    final startRotation = _dragRotation;
    final endX = isRight ? screenWidth * 1.5 : -screenWidth * 1.5;
    final endRotation = isRight ? startRotation + 0.5 : startRotation - 0.5;
    _animationController.reset();
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    animation.addListener(() {
      setState(() {
        _dragX = startX + (endX - startX) * animation.value;
        _dragRotation =
            startRotation + (endRotation - startRotation) * animation.value;
      });
    });
    _animationController.forward(from: 0).whenComplete(() {
      final targetUser = _users[_currentIndex];
      if (isRight) {
        Future.microtask(() => _sendLikeRequest(targetUser));
        Future.microtask(() => _checkForMatch(targetUser));
      }
      _nextUser();
      if (mounted) {
        setState(() {
          _dragX = 0;
          _dragY = 0;
          _dragRotation = 0.0;
          _dragTintColor = null;
          _isProcessingAction = false;
        });
      }
    });
  }

  void _animateCardUp() {
    if (_currentIndex >= _users.length) return;
    setState(() => _isProcessingAction = true);
    final screenHeight = MediaQuery.of(context).size.height;
    final startY = _dragY;
    final endY = -screenHeight * 1.5;
    final startRotation = _dragRotation;
    _animationController.reset();
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    animation.addListener(() {
      setState(() {
        _dragY = startY + (endY - startY) * animation.value;
        _dragRotation = startRotation * (1 - animation.value);
      });
    });
    _animationController.forward(from: 0).whenComplete(() {
      final targetUser = _users[_currentIndex];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Added ${targetUser['name']} to favorites")),
        );
      }
      Future.microtask(() => _addToFavoritesBackend(targetUser));
      _nextUser();
      if (mounted) {
        setState(() {
          _dragX = 0;
          _dragY = 0;
          _dragRotation = 0.0;
          _dragTintColor = null;
          _isProcessingAction = false;
        });
      }
    });
  }

  void _animateCardBack() {
    setState(() => _isProcessingAction = true);
    final startX = _dragX;
    final startY = _dragY;
    final startRotation = _dragRotation;
    _animationController.reset();
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    animation.addListener(() {
      setState(() {
        _dragX = startX * (1 - animation.value);
        _dragY = startY * (1 - animation.value);
        _dragRotation = startRotation * (1 - animation.value);
      });
    });
    _animationController.forward(from: 0).whenComplete(() {
      if (mounted) {
        setState(() {
          _dragX = 0;
          _dragY = 0;
          _dragRotation = 0.0;
          _dragTintColor = null;
          _isProcessingAction = false;
        });
      }
    });
  }

  void _onRewind() {
    if (!_isProcessingAction && _currentIndex > 0) {
      if (_swipedUsers.isNotEmpty) {
        _swipedUsers.removeLast();
      }
      setState(() {
        _currentIndex--;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Rewinded to the previous card")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No more cards to rewind")),
      );
    }
  }

  void _onDislike() {
    if (_isLoading || _isProcessingAction || _currentIndex >= _users.length) return;
    HapticFeedback.mediumImpact();
    _animateCardOut(false);
  }

  void _onFavorite() {
    if (_isLoading || _isProcessingAction || _currentIndex >= _users.length) return;
    HapticFeedback.mediumImpact();
    _animateCardUp();
  }

  void _onLike() {
    if (_isLoading || _isProcessingAction || _currentIndex >= _users.length) return;
    HapticFeedback.mediumImpact();
    _animateCardOut(true);
  }

  /// Live count of people who've already liked the current user, so the
  /// deck isn't the only way to discover interest - visible even before
  /// swiping past those exact profiles.
  Widget _buildLikesYouBadge() {
    if (_likesYouStream == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot>(
      stream: _likesYouStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$count ${count == 1 ? 'person likes' : 'people like'} you! '
                    'Check the Requests tab to match back.',
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: context.sw.give,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sw;
    return Scaffold(
      backgroundColor: _dragTintColor ?? c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Discover',
                        style: AppTheme.display(fontSize: 34, color: c.text)),
                  ),
                  _buildLikesYouBadge(),
                  const SizedBox(width: 8),
                  _headerButton(
                    icon: _listMode ? Icons.style_rounded : Icons.view_list_rounded,
                    tooltip: _listMode ? 'Swipe view' : 'List view',
                    onTap: () => setState(() => _listMode = !_listMode),
                  ),
                  const SizedBox(width: 8),
                  _headerButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Refresh matches',
                    onTap: _isLoading ? null : _loadUsers,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  _listMode ? _buildListMode() : _buildDeckMode(),
                  if (_showCoachmarks && !_listMode) _buildCoachmarks(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final c = context.sw;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
          child: Icon(icon,
              size: 20, color: onTap == null ? c.textMuted : c.text, semanticLabel: tooltip),
        ),
      ),
    );
  }

  Widget _buildDeckMode() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final isVerticalDrag = _dragY.abs() > _dragX.abs() * 1.5;

        // Calculate progress from 0.0 to 1.0 based on how far the card is dragged
        final likeProgress = !isVerticalDrag ? (_dragX / (screenWidth * 0.5)).clamp(0.0, 1.0) : 0.0;
        final dislikeProgress = !isVerticalDrag ? (-_dragX / (screenWidth * 0.5)).clamp(0.0, 1.0) : 0.0;
        final favoriteProgress = isVerticalDrag ? (-_dragY / (screenHeight * 0.4)).clamp(0.0, 1.0) : 0.0;

        return _isLoading
            ? _buildLoadingState()
            : _users.isEmpty || _currentIndex >= _users.length
            ? _buildEmptyState()
            : Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_currentIndex + 1 < _users.length)
                    _buildSwipeCard(
                      _users[_currentIndex + 1],
                      isBackCard: true,
                    ),
                  _buildSwipeCard(_users[_currentIndex]),
                ],
              ),
            ),
            _buildActionButtons(
              likeProgress: likeProgress,
              dislikeProgress: dislikeProgress,
              favoriteProgress: favoriteProgress,
            ),
          ],
        );
      },
    );
  }

  /// Browse/search mode - the old Home feed, folded in here so discovery
  /// lives in exactly one place.
  Widget _buildListMode() {
    if (_isLoading) return _buildLoadingState();
    final results = _searchResults;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search people or skills...',
              prefixIcon: Icon(Icons.search, color: context.sw.give),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.sw.border),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final user = results[index];
                    // Stagger-fade so the list assembles rather than snapping in.
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(user['id']),
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 250 + (index % 6) * 60),
                      curve: Curves.easeOut,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - value)),
                          child: child,
                        ),
                      ),
                      child: _buildListTile(user),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildListTile(Map<String, dynamic> user) {
    final offered = List<String>.from(user['skillsOffered'] ?? []);
    final percent = (user['matchPercent'] as double?) ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: Hero(
          tag: 'avatar_${user['id']}',
          child: CircleAvatar(
            radius: 24,
            backgroundColor: context.sw.give.withValues(alpha: 0.12),
            backgroundImage: (user['photoUrl'] as String?)?.isNotEmpty == true
                ? NetworkImage(user['photoUrl'])
                : null,
            child: (user['photoUrl'] as String?)?.isNotEmpty == true
                ? null
                : Icon(Icons.person, color: context.sw.give),
          ),
        ),
        title: Text(user['name'] ?? 'Anonymous',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          offered.isEmpty ? 'No skills listed' : 'Teaches ${offered.join(', ')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: percent > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.sw.give.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${percent.round()}%',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: context.sw.give),
                ),
              )
            : null,
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserDetailPage(userId: user['id']),
            ),
          );
        },
      ),
    );
  }

  /// One-time gesture tutorial. Swipe-up-to-favourite in particular is
  /// impossible to discover without being told.
  Widget _buildCoachmarks() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _dismissCoachmarks,
        child: Container(
          color: Colors.black.withValues(alpha: 0.78),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.swipe, color: Colors.white, size: 54),
              const SizedBox(height: 22),
              const Text(
                'How to swap',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 26),
              _coachRow(Icons.arrow_forward, 'Swipe right to send a request'),
              _coachRow(Icons.arrow_back, 'Swipe left to pass'),
              _coachRow(Icons.arrow_upward, 'Swipe up to save as a favourite'),
              _coachRow(Icons.undo, 'Tap undo to bring back the last card'),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _dismissCoachmarks,
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coachRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: context.sw.give.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    // A card-shaped placeholder instead of a spinner: the wait reads as
    // "almost there" rather than "nothing is happening".
    return _listMode ? const ListSkeleton() : const DiscoverCardSkeleton();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SwapMotif(width: 180),
            const SizedBox(height: 26),
            Text(
              'No more matches found',
              style: AppTheme.display(fontSize: 23, color: context.sw.text),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Nothing matched "$_searchQuery". Try a different skill or clear the search.'
                  : "You've seen everyone for now. Adding more skills you want to "
                      'learn widens your matches straight away.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.sw.textMuted),
            ),
            const SizedBox(height: 32),
            // Every empty state should name the next action, not dead-end.
            ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
                );
              },
              icon: const Icon(Icons.edit),
              label: const Text('Update my skills'),
              style: ElevatedButton.styleFrom(
                padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _loadUsers,
              icon: const Icon(Icons.refresh),
              label: const Text("Refresh"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons({
    required double likeProgress,
    required double dislikeProgress,
    required double favoriteProgress,
  }) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircleButton(
            actionColor: c.textMuted,
            icon: Icons.undo_rounded,
            label: 'Undo last swipe',
            onPressed: _onRewind,
            size: 48,
          ),
          _buildCircleButton(
            actionColor: c.text,
            icon: Icons.close_rounded,
            label: 'Pass',
            onPressed: _onDislike,
            scale: 1.0 + (0.22 * dislikeProgress),
            activationProgress: dislikeProgress,
          ),
          _buildCircleButton(
            actionColor: c.get,
            icon: Icons.star_rounded,
            label: 'Save as favourite',
            onPressed: _onFavorite,
            scale: 1.0 + (0.22 * favoriteProgress),
            activationProgress: favoriteProgress,
          ),
          _buildCircleButton(
            actionColor: c.give,
            icon: Icons.favorite_rounded,
            label: 'Send swap request',
            onPressed: _onLike,
            scale: 1.0 + (0.22 * likeProgress),
            activationProgress: likeProgress,
            size: 70,
            filled: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String label,
    required Color actionColor,
    required VoidCallback onPressed,
    double scale = 1.0,
    double activationProgress = 0.0,
    double size = 58,
    bool filled = false,
  }) {
    final c = context.sw;
    final base = filled ? actionColor : c.surface;
    final backgroundColor = Color.lerp(base, actionColor, activationProgress)!;
    final iconColor = filled
        ? Colors.white
        : Color.lerp(actionColor, Colors.white, activationProgress)!;

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      child: Tooltip(
        message: label,
        child: Pressable(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (filled ? actionColor : Colors.black).withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: size * 0.42, semanticLabel: label),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeCard(Map<String, dynamic> user, {bool isBackCard = false}) {
    final dragPercentageX =
        _dragX.abs() / (MediaQuery.of(context).size.width * 0.4);
    final dragPercentageY =
        _dragY.abs() / (MediaQuery.of(context).size.height * 0.4);
    final dragPercentage = (dragPercentageX + dragPercentageY).clamp(0.0, 1.0);
    final scale = 0.9 + (0.1 * (1 - dragPercentage));
    final backCardTransform = Matrix4.identity()..scale(scale);
    final currentCardTransform = Matrix4.identity()
      ..translate(_dragX, _dragY)
      ..rotateZ(_dragRotation);

    final isVerticalDrag = _dragY.abs() > _dragX.abs() * 1.5;
    final showFavoriteOverlay = isVerticalDrag && _dragY < 0;

    Widget card = _buildCardContent(user);

    if (isBackCard) {
      return Transform(
        key: ValueKey("back_${user['id']}"),
        transform: backCardTransform,
        alignment: Alignment.center,
        child: card,
      );
    }

    return GestureDetector(
      key: ValueKey(user['id']),
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onVerticalDragStart: _handleDragStart,
      onVerticalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onVerticalDragEnd: _handleDragEnd,
      child: Transform(
        transform: currentCardTransform,
        alignment: Alignment.center,
        child: Stack(
          children: [
            card,
            if (!isVerticalDrag && _dragX > 0) _buildLikeOverlay(),
            if (!isVerticalDrag && _dragX < 0) _buildDislikeOverlay(),
            if (showFavoriteOverlay) _buildFavoriteOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildLikeOverlay() {
    final opacity =
    (_dragX / (MediaQuery.of(context).size.width * 0.4)).clamp(0.0, 1.0);
    return Positioned(
      top: 40,
      left: 20,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: -pi / 12.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                border: Border.all(color: context.sw.give, width: 3),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.9)),
            child: Text(
              "LIKE",
              style: GoogleFonts.manrope(
                color: context.sw.give,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDislikeOverlay() {
    final opacity =
    (-_dragX / (MediaQuery.of(context).size.width * 0.4)).clamp(0.0, 1.0);
    return Positioned(
      top: 40,
      right: 20,
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: pi / 12.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                border: Border.all(color: context.sw.get, width: 3),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.9)),
            child: Text(
              "NOPE",
              style: GoogleFonts.manrope(
                color: context.sw.get,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteOverlay() {
    final opacity =
    (_dragY.abs() / (MediaQuery.of(context).size.height * 0.3))
        .clamp(0.0, 1.0);
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Opacity(
          opacity: opacity,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF86A89B), width: 3),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.9)),
            child: Text(
              "FAVORITE",
              style: GoogleFonts.manrope(
                color: const Color(0xFF86A89B),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(Map<String, dynamic> user) {
    final c = context.sw;
    final skillsOffered = List<String>.from(user['skillsOffered'] ?? []);
    final skillsWanted = List<String>.from(user['skillsWanted'] ?? []);
    final availability = List<String>.from(user['availability'] ?? []);
    // Never hard-cast a Firestore number: the same field comes back as int
    // or double depending on how it was written, which is exactly what
    // crashed the admin user list in production.
    final rating = (user['rating'] as num?)?.toDouble() ?? 0.0;
    final completedSwaps = (user['completedSwaps'] as num?)?.toInt() ?? 0;
    final matchPercent = (user['matchPercent'] as num?)?.toDouble() ?? 0;
    final name = (user['name'] ?? 'Anonymous').toString();
    final photo = (user['photoUrl'] ?? '').toString();
    final bio = (user['bio'] ?? '').toString().trim();
    // What each side would get out of it, in the viewer's own terms.
    final theyTeach = List<String>.from(user['theyTeachIWant'] ?? []);
    final iTeach = List<String>.from(user['iTeachTheyWant'] ?? []);
    final youGet = theyTeach.isNotEmpty ? theyTeach.first : (skillsOffered.isNotEmpty ? skillsOffered.first : '');
    final youGive = iTeach.isNotEmpty ? iTeach.first : (skillsWanted.isNotEmpty ? skillsWanted.first : '');

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.88,
      height: MediaQuery.of(context).size.height * 0.60,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 232,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photo.isEmpty)
                      Container(
                        color: c.surfaceLow,
                        child: Icon(Icons.person_rounded, size: 76, color: c.textMuted),
                      )
                    else
                      CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: c.surfaceLow,
                          highlightColor: c.surface,
                          child: Container(color: c.surfaceLow),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: c.surfaceLow,
                          child: Icon(Icons.person_rounded, size: 76, color: c.textMuted),
                        ),
                      ),
                    if (matchPercent > 0)
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: c.win,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, size: 14, color: c.onWin),
                              const SizedBox(width: 4),
                              CountUpText(
                                value: matchPercent.round(),
                                suffix: '% match',
                                duration: const Duration(milliseconds: 700),
                                style: GoogleFonts.manrope(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: c.onWin),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.display(fontSize: 25, color: c.text)),
                          ),
                          if (completedSwaps > 0) ...[
                            Icon(Icons.verified_rounded, size: 15, color: c.success),
                            const SizedBox(width: 4),
                            Text(
                              '$completedSwaps swap${completedSwaps == 1 ? '' : 's'}'
                              '${rating > 0 ? ' · ${rating.toStringAsFixed(1)}★' : ''}',
                              style: GoogleFonts.manrope(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: c.success),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (youGet.isNotEmpty)
                            TintTag('You get: $youGet', color: c.get),
                          if (youGive.isNotEmpty)
                            TintTag('You give: $youGive', color: c.give),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (bio.isNotEmpty)
                                Text(bio,
                                    style: GoogleFonts.manrope(
                                        fontSize: 13, color: c.textMuted, height: 1.45)),
                              if (matchPercent > 0) _buildMatchBreakdown(user),
                              if (skillsOffered.length > 1 || skillsWanted.length > 1) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final skill in skillsOffered.take(4))
                                      _plainChip(skill, c.get),
                                    for (final skill in skillsWanted.take(3))
                                      _plainChip(skill, c.give),
                                  ],
                                ),
                              ],
                              if (availability.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.schedule_rounded, size: 14, color: c.textMuted),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text('Free ${availability.join(', ')}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.manrope(
                                              fontSize: 12, color: c.textMuted)),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plainChip(String label, Color color) {
    final c = context.sw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.surfaceLow,
        borderRadius: BorderRadius.circular(11),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(label,
          style: GoogleFonts.manrope(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: c.text)),
    );
  }

  /// "Why this match" breakdown: shows every reason MatchService found, not
  /// just what they teach - reciprocal interest and shared availability are
  /// just as much a reason to like someone back, and users can't tell the
  /// algorithm is doing anything smart if it's invisible.
  Widget _buildMatchBreakdown(Map<String, dynamic> user) {
    final theyTeach = List<String>.from(user['theyTeachIWant'] ?? []);
    final iTeach = List<String>.from(user['iTeachTheyWant'] ?? []);
    final sharedAvailability = List<String>.from(user['sharedAvailability'] ?? []);
    final reasons = <Widget>[];

    if (theyTeach.isNotEmpty) {
      reasons.add(_matchReasonChip(
          Icons.auto_fix_high, 'Teaches ${theyTeach.join(', ')}'));
    }
    if (iTeach.isNotEmpty) {
      reasons.add(
          _matchReasonChip(Icons.favorite_border, 'Wants ${iTeach.join(', ')}'));
    }
    if (sharedAvailability.isNotEmpty) {
      reasons.add(_matchReasonChip(Icons.access_time,
          'Free ${sharedAvailability.join(', ')}'));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reasons.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: reasons),
        ],
      ),
    );
  }

  Widget _matchReasonChip(IconData icon, String label) {
    final c = context.sw;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.get.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c.get),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.manrope(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c.get)),
        ],
      ),
    );
  }

}