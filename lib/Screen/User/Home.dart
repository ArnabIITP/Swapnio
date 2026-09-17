/*
 * Swapnio - A Flutter-based skill swapping platform.
 * Copyright (C) 2026 Arnab Das and Manab Kumar Barman
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:provider/provider.dart';
import 'package:swapnio/providers/app_state.dart';
import 'package:swapnio/services/safety_service.dart';
import '../../services/match_service.dart';
import '../../theme.dart';
import 'notifications_page.dart';
import 'user_detail.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> categories = [
    'All', 
    'Design', 
    'Programming', 
    'Music', 
    'Languages',
    'Marketing', 
    'Fitness', 
    'Cooking',
    'Photography',
    'Writing'
  ];
  // Set for multiple category selection, starting with 'All'
  Set<String> selectedCategories = {'All'};
  String searchQuery = '';
  bool isLoading = true;
  List<Map<String, dynamic>> users = [];
  
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  DocumentSnapshot? _lastVisible;
  bool _hasMore = true;
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  List<String> _mySkillsOffered = [];
  List<String> _mySkillsWanted = [];
  List<String> _myAvailability = [];

  @override
  void initState() {
    super.initState();
    _loadMyProfileThenUsers();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadMyProfileThenUsers() async {
    if (currentUserId != null) {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (myDoc.exists) {
        final data = myDoc.data()!;
        _mySkillsOffered = List<String>.from(data['skillsOffered'] ?? []);
        _mySkillsWanted = List<String>.from(data['skillsWanted'] ?? []);
        _myAvailability = List<String>.from(data['availability'] ?? []);
      }
    }
    await _fetchUsers();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        users = [];
        isLoading = true;
        _hasMore = true;
        _lastVisible = null;
      });
    }

    try {
      Query query = FirebaseFirestore.instance.collection('users').limit(30);
      if (loadMore && _lastVisible != null) {
        query = FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, isGreaterThan: _lastVisible!.id)
            .limit(30);
      }
      final QuerySnapshot snapshot = await query.get();
      final hiddenIds = await SafetyService.instance.hiddenUserIds();

      final fetchedUsers = snapshot.docs
          .where((doc) =>
              doc.id != currentUserId && !hiddenIds.contains(doc.id))
          .where((doc) => (doc.data() as Map<String, dynamic>)['isBanned'] != true)
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final skillsOffered = List<String>.from(data['skillsOffered'] ?? []);
            final skillsWanted = List<String>.from(data['skillsWanted'] ?? []);
            final availability = List<String>.from(data['availability'] ?? []);
            final match = MatchService.compute(
              mySkillsOffered: _mySkillsOffered,
              mySkillsWanted: _mySkillsWanted,
              myAvailability: _myAvailability,
              candidateSkillsOffered: skillsOffered,
              candidateSkillsWanted: skillsWanted,
              candidateAvailability: availability,
              candidateRating: (data['rating'] as num?)?.toDouble() ?? 0.0,
            );
            return {
              'id': doc.id,
              'name': data['name'] ?? 'Anonymous',
              'skillsOffered': skillsOffered,
              'skillsWanted': skillsWanted,
              'availability': availability,
              'photoUrl': data['photoUrl'] ?? '',
              'rating': data['rating'] ?? 0.0,
              'completedSwaps': data['completedSwaps'] ?? 0,
              'bio': data['bio'] ?? '',
              'matchPercent': match.percent,
            };
          })
          .toList()
        // Sort within this fetched page by match quality. Pagination still
        // fetches by document id, so this doesn't globally re-rank every user
        // in the database - only the page(s) already loaded.
        ..sort((a, b) =>
            (b['matchPercent'] as double).compareTo(a['matchPercent'] as double));

      setState(() {
        users.addAll(fetchedUsers);
        _lastVisible =
            snapshot.docs.isNotEmpty ? snapshot.docs.last : _lastVisible;
        _hasMore = snapshot.docs.length >= 30;
        isLoading = false;
      });
    } catch (e) {
      print('Error fetching users: $e');
      setState(() => isLoading = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300 &&
        _hasMore &&
        !isLoading) {
      _fetchUsers(loadMore: true);
    }
  }

  List<Map<String, dynamic>> get filteredUsers {
    List<Map<String, dynamic>> result = List.from(users);
    
    // Filter by selected categories
    if (!(selectedCategories.contains('All') || selectedCategories.isEmpty)) {
      // Only filter if 'All' is not selected and categories are not empty
      result = result.where((user) {
        final skillsOffered = (user['skillsOffered'] as List<dynamic>)
            .map((skill) => skill.toString().toLowerCase())
            .toList();
        final skillsWanted = (user['skillsWanted'] as List<dynamic>)
            .map((skill) => skill.toString().toLowerCase())
            .toList();
        
        // Match if any selected category is found in user's skills as a
        // whole word (substring matching let short categories like "R"
        // match almost every skill, e.g. "Marketing").
        return selectedCategories.any((category) {
          final categoryLower = category.toLowerCase();
          final pattern = RegExp(r'\b' + RegExp.escape(categoryLower) + r'\b');
          return skillsOffered.any((skill) => pattern.hasMatch(skill)) ||
                 skillsWanted.any((skill) => pattern.hasMatch(skill));
        });
      }).toList();
    }
    
    // Filter by search query
    if (searchQuery.isNotEmpty) {
      final query = searchQuery.toLowerCase();
      result = result.where((user) {
        final name = user['name'].toString().toLowerCase();
        final bio = user['bio'].toString().toLowerCase();
        final skillsOffered = (user['skillsOffered'] as List<dynamic>)
            .map((skill) => skill.toString().toLowerCase())
            .join(' ');
        final skillsWanted = (user['skillsWanted'] as List<dynamic>)
            .map((skill) => skill.toString().toLowerCase())
            .join(' ');
        
        return name.contains(query) || 
               bio.contains(query) || 
               skillsOffered.contains(query) || 
               skillsWanted.contains(query);
      }).toList();
    }
    
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _getGreeting();
    final username = FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ?? '';
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchUsers,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header: collapses out of the way on scroll-down and snaps
              // back as soon as you scroll up, instead of permanently
              // occupying screen space above the list.
              SliverAppBar(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                elevation: 0,
                pinned: false,
                floating: true,
                snap: true,
                automaticallyImplyLeading: false,
                toolbarHeight: 0,
                collapsedHeight: 0,
                expandedHeight: 320,
                flexibleSpace: FlexibleSpaceBar(
                  background: ClipRect(
                    child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Greeting + notification bell + avatar
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$greeting${username.isNotEmpty ? ', $username' : ''}! 👋',
                                    style: GoogleFonts.ebGaramond(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Find the perfect skill swap match',
                                    style: GoogleFonts.manrope(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildNotificationBell(),
                            const SizedBox(width: 6),
                            _buildAvatar(),
                          ],
                        ),
                        const SizedBox(height: 22),

                        // Search bar
                        Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(30),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search skills or users...',
                              prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
                              suffixIcon: searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          searchQuery = '';
                                        });
                                      },
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppTheme.warmBorder),
                              ),
                              filled: true,
                              fillColor: Theme.of(context).colorScheme.surface,
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                            ),
                            style: GoogleFonts.manrope(fontSize: 16),
                            onChanged: (value) {
                              setState(() {
                                searchQuery = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Filter button
                        Row(
                          children: [
                            Text(
                              'Filter by skills:',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.filter_list, size: 20),
                              label: Text(selectedCategories.contains('All') ? 'All' : '${selectedCategories.length} selected'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _showFilterDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // User count or loading indicator
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: isLoading
                              ? const Text('Loading users...')
                              : Text(
                                  '${filteredUsers.length} users found',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),

              // User cards
              if (isLoading)
                SliverFillRemaining(hasScrollBody: false, child: _buildLoadingShimmer())
              else if (filteredUsers.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (index >= filteredUsers.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(color: AppTheme.primaryColor),
                            ),
                          );
                        }
                        final user = filteredUsers[index];
                        return _buildUserCard(user);
                      },
                      childCount: filteredUsers.length + (_hasMore ? 1 : 0),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    // Create a temporary set to hold selections during dialog
    Set<String> tempSelectedCategories = Set.from(selectedCategories);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Filter Skills'),
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: List.generate(categories.length, (index) {
                      final category = categories[index];
                      final isSelected = tempSelectedCategories.contains(category);
                      
                      return FilterChip(
                        label: Text(category),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryColor,
                        checkmarkColor: Colors.white,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        labelStyle: GoogleFonts.manrope(
                          color: isSelected
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (_) {
                          setDialogState(() {
                            if (category == 'All') {
                              // When selecting "All", clear all other selections
                              tempSelectedCategories.clear();
                              tempSelectedCategories.add('All');
                            } else {
                              // When selecting others, remove "All"
                              tempSelectedCategories.remove('All');
                              
                              // Toggle the selected category
                              if (isSelected) {
                                tempSelectedCategories.remove(category);
                                // If no categories left, reselect "All"
                                if (tempSelectedCategories.isEmpty) {
                                  tempSelectedCategories.add('All');
                                }
                              } else {
                                tempSelectedCategories.add(category);
                              }
                            }
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Clear All'),
                onPressed: () {
                  setDialogState(() {
                    tempSelectedCategories = {'All'};
                  });
                },
              ),
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                child: const Text('Apply'),
                onPressed: () {
                  setState(() {
                    selectedCategories = tempSelectedCategories;
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final skillsOffered = (user['skillsOffered'] as List<dynamic>)
        .map((skill) => skill.toString())
        .toList();
    final skillsWanted = (user['skillsWanted'] as List<dynamic>)
        .map((skill) => skill.toString())
        .toList();
    final availability = (user['availability'] as List<dynamic>)
        .map((day) => day.toString())
        .toList();
    final rating = (user['rating'] as num).toDouble();
    final completedSwaps = user['completedSwaps'] as int;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warmBorder, width: 1),
        boxShadow: AppTheme.softShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserDetailPage(userId: user['id']),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // User photo
                  CachedNetworkImage(
                    imageUrl: user['photoUrl'] ?? '',
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
                  // Name and rating
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'] ?? 'Anonymous',
                          style: GoogleFonts.ebGaramond(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
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
                              style: GoogleFonts.manrope(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (((user['matchPercent'] as double?) ?? 0) > 0) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.bolt, size: 13, color: AppTheme.primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  '${(user['matchPercent'] as double).round()}% match',
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: AppTheme.warmBorder),
              const SizedBox(height: 20),
              // Skills section
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Skills offered
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.auto_fix_high, size: 16, color: AppTheme.primaryColor),
                            SizedBox(width: 4),
                            Text(
                              'OFFERS',
                              style: TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: skillsOffered.map((skill) => _buildSkillChip(skill, true)).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Skills wanted
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.search, size: 16, color: AppTheme.tertiaryColor),
                            SizedBox(width: 4),
                            Text(
                              'WANTS',
                              style: TextStyle(
                                color: AppTheme.tertiaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: skillsWanted.map((skill) => _buildSkillChip(skill, false)).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Availability
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: AppTheme.tertiaryColor),
                  const SizedBox(width: 6),
                  Text(
                    'Available: ${availability.join(", ")}',
                    style: GoogleFonts.manrope(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkillChip(String skill, bool isOffered) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOffered ? AppTheme.primaryColor.withValues(alpha: 0.08) : AppTheme.tertiaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOffered ? AppTheme.primaryColor.withValues(alpha: 0.3) : AppTheme.tertiaryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        skill,
        style: GoogleFonts.manrope(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isOffered ? AppTheme.primaryColor : AppTheme.tertiaryColor,
        ),
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (_, __) => Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(height: 180),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No users found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try changing your search criteria',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    final unread = Provider.of<AppState>(context).unreadNotifications;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none,
              size: 28, color: AppTheme.primaryColor),
          tooltip: 'Notifications',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
        ),
        if (unread > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar() {
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL ?? '';
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.12),
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? const Icon(Icons.person, size: 20, color: AppTheme.primaryColor)
          : null,
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }
}
