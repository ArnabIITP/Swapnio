import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/safety_service.dart';
import '../../services/match_service.dart';
import '../../theme.dart';
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

  void _showMatchDialog(String name) {
    showCelebrationDialog(
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
          baseColor, AppTheme.tertiaryColor.withValues(alpha: 0.2), -dragPercentageX.clamp(-1.0, 0.0))!;
      final greenColor = Color.lerp(
          baseColor, AppTheme.primaryColor.withValues(alpha: 0.2), dragPercentageX.clamp(0.0, 1.0))!;
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
                  color: AppTheme.primaryColor,
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
    return Scaffold(
      backgroundColor: _dragTintColor ?? Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          "Skill Match",
          style: GoogleFonts.ebGaramond(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 24,
            letterSpacing: 0,
          ),
        ),
        actions: [
          _buildLikesYouBadge(),
          IconButton(
            icon: Icon(_listMode ? Icons.style : Icons.view_list,
                color: AppTheme.primaryColor),
            tooltip: _listMode ? 'Swipe view' : 'List view',
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _listMode = !_listMode);
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryColor),
            onPressed: _isLoading ? null : _loadUsers,
            tooltip: 'Refresh matches',
          ),
        ],
      ),
      body: Stack(
        children: [
          _listMode ? _buildListMode() : _buildDeckMode(),
          if (_showCoachmarks && !_listMode) _buildCoachmarks(),
        ],
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
              prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
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
                borderSide: const BorderSide(color: AppTheme.warmBorder),
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
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
          backgroundImage: (user['photoUrl'] as String?)?.isNotEmpty == true
              ? NetworkImage(user['photoUrl'])
              : null,
          child: (user['photoUrl'] as String?)?.isNotEmpty == true
              ? null
              : const Icon(Icons.person, color: AppTheme.primaryColor),
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
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${percent.round()}%',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor),
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
              color: AppTheme.primaryColor.withValues(alpha: 0.25),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Finding potential matches...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 80, color: AppTheme.warmBorder),
            const SizedBox(height: 24),
            Text(
              "No more matches found",
              style: GoogleFonts.ebGaramond(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Nothing matched "$_searchQuery". Try a different skill or clear the search.'
                  : "You've seen everyone for now. Adding more skills you want to "
                      'learn widens your matches straight away.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildCircleButton(
            actionColor: const Color(0xFFD8D0C8),
            icon: Icons.undo,
            onPressed: _onRewind,
          ),
          _buildCircleButton(
            actionColor: AppTheme.tertiaryColor,
            icon: Icons.close,
            onPressed: _onDislike,
            scale: 1.0 + (0.25 * dislikeProgress),
            activationProgress: dislikeProgress,
          ),
          _buildCircleButton(
            actionColor: const Color(0xFF86A89B),
            icon: Icons.star,
            onPressed: _onFavorite,
            scale: 1.0 + (0.25 * favoriteProgress),
            activationProgress: favoriteProgress,
          ),
          _buildCircleButton(
            actionColor: AppTheme.primaryColor,
            icon: Icons.favorite,
            onPressed: _onLike,
            scale: 1.0 + (0.25 * likeProgress),
            activationProgress: likeProgress,
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required Color actionColor,
    required VoidCallback onPressed,
    double scale = 1.0,
    double activationProgress = 0.0,
  }) {
    final Color backgroundColor =
    Color.lerp(Colors.white, actionColor, activationProgress)!;
    final Color iconColor =
    Color.lerp(actionColor, Colors.white, activationProgress)!;

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.2),
              spreadRadius: 2,
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: backgroundColor,
          shape: const CircleBorder(),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: onPressed,
            child: Center(
              child: Icon(
                icon,
                color: iconColor,
                size: 36,
              ),
            ),
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
                border: Border.all(color: AppTheme.primaryColor, width: 3),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.9)),
            child: Text(
              "LIKE",
              style: GoogleFonts.manrope(
                color: AppTheme.primaryColor,
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
                border: Border.all(color: AppTheme.tertiaryColor, width: 3),
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withValues(alpha: 0.9)),
            child: Text(
              "NOPE",
              style: GoogleFonts.manrope(
                color: AppTheme.tertiaryColor,
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
    final skillsOffered = List<String>.from(user['skillsOffered'] ?? []);
    final skillsWanted = List<String>.from(user['skillsWanted'] ?? []);
    final availability = List<String>.from(user['availability'] ?? []);
    // Never hard-cast a Firestore number: the same field comes back as int
    // or double depending on how it was written, which is exactly what
    // crashed the admin user list in production.
    final rating = (user['rating'] as num?)?.toDouble() ?? 0.0;
    final completedSwaps = (user['completedSwaps'] as num?)?.toInt() ?? 0;

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.87,
      height: MediaQuery.of(context).size.height * 0.62,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.warmBorder, width: 1),
          boxShadow: AppTheme.softShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              CachedNetworkImage(
                imageUrl: user["photoUrl"] ?? '',
                imageBuilder: (context, imageProvider) => CircleAvatar(
                  radius: 64,
                  backgroundImage: imageProvider,
                ),
                placeholder: (context, url) => Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: CircleAvatar(
                    radius: 64,
                    backgroundColor: Colors.grey[300],
                  ),
                ),
                errorWidget: (context, url, error) => CircleAvatar(
                  radius: 64,
                  backgroundColor: Colors.grey[300],
                  child:
                  const Icon(Icons.person, size: 64, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                user["name"] ?? 'Anonymous',
                style: GoogleFonts.ebGaramond(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RatingBar.builder(
                    initialRating: rating,
                    minRating: 0,
                    direction: Axis.horizontal,
                    allowHalfRating: true,
                    itemCount: 5,
                    itemSize: 18,
                    ignoreGestures: true,
                    itemBuilder: (context, _) => const Icon(
                      Icons.star,
                      color: AppTheme.primaryColor,
                    ),
                    onRatingUpdate: (_) {},
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '($completedSwaps)',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (((user['matchPercent'] as double?) ?? 0) > 0)
                _buildMatchBreakdown(user),
              const SizedBox(height: 22),
              Divider(height: 1, color: Colors.grey[200]),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSkillSection('Skills Offered', skillsOffered,
                          Icons.auto_fix_high, AppTheme.primaryColor),
                      const SizedBox(height: 18),
                      _buildSkillSection('Skills Wanted', skillsWanted,
                          Icons.search, AppTheme.tertiaryColor),
                      const SizedBox(height: 18),
                      _buildAvailabilitySection(availability),
                      if (user['bio'] != null &&
                          user['bio'].toString().isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          'About',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user['bio'].toString(),
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontSize: 14,
                            height: 1.4,
                          ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                '${(user['matchPercent'] as double).round()}% match',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: reasons),
          ],
        ],
      ),
    );
  }

  Widget _matchReasonChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillSection(
      String title, List<String> skills, IconData icon, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        skills.isEmpty
            ? Text(
          'None specified',
          style: TextStyle(
              fontStyle: FontStyle.italic, color: Colors.grey[500]),
        )
            : Wrap(
          spacing: 8,
          runSpacing: 8,
          children: skills
              .map((skill) => Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              skill,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildAvailabilitySection(List<String> availability) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.access_time, size: 16, color: AppTheme.tertiaryColor),
            SizedBox(width: 8),
            Text(
              'Availability',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppTheme.tertiaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        availability.isEmpty
            ? Text(
          'None specified',
          style: TextStyle(
              fontStyle: FontStyle.italic, color: Colors.grey[500]),
        )
            : Wrap(
          spacing: 8,
          runSpacing: 8,
          children: availability
              .map((day) => Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.tertiaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppTheme.tertiaryColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              day,
              style: const TextStyle(
                  color: AppTheme.tertiaryColor, fontSize: 12),
            ),
          ))
              .toList(),
        ),
      ],
    );
  }
}