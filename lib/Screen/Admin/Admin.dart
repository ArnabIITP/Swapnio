import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import '../../theme.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};
  List<DocumentSnapshot> _allUsers = [];
  List<Map<String, dynamic>> _adminSkills = [];
  List<Map<String, dynamic>> _reports = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  StreamSubscription<QuerySnapshot>? _usersSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // The add-skill FAB only makes sense on the Skills tab - shown on every
    // tab it sat permanently over the Users list, covering each row's
    // ban/delete buttons as you scrolled.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _setupRealtimeUpdates();
    _fetchAdminStats();
    _loadSkills();
    _loadReports();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _usersSubscription?.cancel();
    super.dispose();
  }

  void _setupRealtimeUpdates() {
    _usersSubscription?.cancel();
    _usersSubscription = _firestore.collection('users').snapshots().listen((snapshot) {
      setState(() {
        _allUsers = snapshot.docs;
        _isLoading = false;
      });
      _fetchAdminStats();
    }, onError: (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error in real-time updates: $e")),
      );
    });
  }

  Future<void> _fetchAllUsers() async {
    setState(() => _isLoading = true);
    _setupRealtimeUpdates();
  }

  Future<void> _fetchAdminStats() async {
    try {
      final userCount = await _firestore.collection('users').count().get();
      final swapsCount = await _firestore.collection('swaps').count().get();
      final users = await _firestore.collection('users').get();
      Set<String> uniqueSkills = {};
      int totalSkillsOffered = 0;
      for (var doc in users.docs) {
        final data = doc.data();
        final skills = List<String>.from(data['skillsOffered'] ?? []);
        uniqueSkills.addAll(skills);
        totalSkillsOffered += skills.length;
      }
      setState(() {
        _stats = {
          'userCount': userCount.count,
          'swapsCount': swapsCount.count,
          'uniqueSkillsCount': uniqueSkills.length,
          'totalSkillsOffered': totalSkillsOffered,
        };
      });
    } catch (e) {
      print("Error fetching admin stats: $e");
    }
  }

  /// Deleting a user has to happen server-side: the Auth login can only be
  /// removed with the Admin SDK, and one user may not delete another's
  /// documents under the security rules. Deleting only `users/{uid}` from
  /// here left the account able to sign back in with the same uid - and with
  /// every old chat and swap still attached to it.
  String? _deletingUid;

  Future<void> _deleteUser(String uid) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deletingUid = uid);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('adminDeleteUser');
      final result = await callable.call<Map<String, dynamic>>({'uid': uid});
      final authDeleted = result.data['authDeleted'] == true;
      messenger.showSnackBar(
        SnackBar(
          content: Text(authDeleted
              ? 'User and all their data deleted.'
              : 'Data deleted. No login existed for this account.'),
        ),
      );
      _fetchAllUsers();
      _fetchAdminStats();
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not delete user: ${e.message ?? e.code}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not delete user: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingUid = null);
    }
  }

  void _confirmDelete(String uid, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text(
          "This permanently removes $name's login and every chat, swap, "
          'request and rating attached to it. It cannot be undone.',
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
            onPressed: () {
              Navigator.pop(context);
              _deleteUser(uid);
            },
          ),
        ],
      ),
    );
  }

  List<DocumentSnapshot> get _filteredUsers {
    if (_searchQuery.isEmpty) return _allUsers;
    return _allUsers.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final email = (data['email'] ?? '').toString().toLowerCase();
      final skills = (data['skillsOffered'] as List?)?.join(" ").toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || email.contains(query) || skills.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: context.sw.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 150,
            pinned: true,
            backgroundColor: context.sw.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Pressable(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  decoration:
                      BoxDecoration(color: context.sw.surface, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_back_rounded,
                      size: 20, color: context.sw.text, semanticLabel: 'Back'),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 52, 20, 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ADMIN',
                          style: AppTheme.label(fontSize: 10, color: context.sw.give)),
                      const SizedBox(height: 4),
                      Text('Dashboard',
                          style: AppTheme.display(fontSize: 32, color: context.sw.text)),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Pressable(
                  onTap: () {
                    _fetchAllUsers();
                    _fetchAdminStats();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration:
                        BoxDecoration(color: context.sw.surface, shape: BoxShape.circle),
                    child: Icon(Icons.refresh_rounded,
                        size: 20, color: context.sw.text, semanticLabel: 'Refresh'),
                  ),
                ),
              ),
            ],
          ),
          // Stats + search scroll away with the banner instead of
          // permanently sitting above every tab's content regardless of
          // scroll position or which tab is selected.
          if (!_isLoading) SliverToBoxAdapter(child: _buildStatsSection()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search users by name, email or skills',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  filled: true,
                  fillColor: context.sw.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: context.sw.surfaceLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: context.sw.cta,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerHeight: 0,
                labelColor: context.sw.onCta,
                unselectedLabelColor: context.sw.textMuted,
                labelStyle:
                    GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 13.5),
                unselectedLabelStyle:
                    GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13.5),
                splashBorderRadius: BorderRadius.circular(12),
                tabs: const [
                  Tab(height: 40, text: 'Users'),
                  Tab(height: 40, text: 'Skills'),
                  Tab(height: 40, text: 'Reports'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildUsersTab(),
                  _buildSkillsTab(),
                  _buildReportsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              onPressed: () {
                _showAddSkillDialog();
              },
              child: const Icon(Icons.add),
              elevation: 6,
            )
          : null,
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard Overview',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: context.sw.give,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.people,
                value: _stats['userCount']?.toString() ?? '0',
                label: 'Total Users',
                color: context.sw.give,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.swap_horiz,
                value: _stats['swapsCount']?.toString() ?? '0',
                label: 'Total Swaps',
                color: context.sw.get,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.lightbulb,
                value: _stats['uniqueSkillsCount']?.toString() ?? '0',
                label: 'Unique Skills',
                color: context.sw.get,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.auto_awesome,
                value: _stats['totalSkillsOffered']?.toString() ?? '0',
                label: 'Skills Offered',
                color: context.sw.win,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: context.sw.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: context.sw.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_allUsers.isEmpty) {
      return const Center(child: Text("No users found"));
    }
    final filteredUsers = _filteredUsers;
    if (filteredUsers.isEmpty) {
      return const Center(child: Text("No matching users found"));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        final data = user.data() as Map<String, dynamic>;
        final uid = user.id;
        final name = data['name'] ?? 'Unnamed';
        final email = data['email'] ?? 'No email';
        final skills = (data['skillsOffered'] as List?)?.join(", ") ?? 'None';
        final photoUrl = data['photoUrl'] as String?;
        // Firestore returns whole-number ratings (e.g. 0, 5) as int, not
        // double - a direct `as double` cast throws for any such user and
        // was breaking the entire list's rendering.
        final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
        final isAdmin = (data['isAdmin'] ?? false) as bool;
        return SurfaceCard(
          margin: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: context.sw.give.withValues(alpha: 0.13),
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? Icon(Icons.person, size: 32, color: context.sw.give)
                      : null,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isAdmin)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: context.sw.get.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Admin',
                                style: TextStyle(
                                  color: context.sw.get,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(color: context.sw.textMuted),
                      ),
                      const SizedBox(height: 8),
                      if (skills != 'None')
                        Text(
                          'Skills: $skills',
                          style: const TextStyle(fontSize: 15),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.star, color: context.sw.give, size: 17),
                              const SizedBox(width: 4),
                              Text('${rating.toStringAsFixed(1)} Rating'),
                            ],
                          ),
                          Row(
                            children: [
                              _buildUserActionButton(
                                icon: Icons.block,
                                color: context.sw.get,
                                onTap: () => _confirmBanUser(uid, null),
                              ),
                              const SizedBox(width: 8),
                              _buildUserActionButton(
                                icon: _deletingUid == uid
                                    ? Icons.hourglass_top_rounded
                                    : Icons.delete,
                                color: Colors.red,
                                onTap: _deletingUid == null
                                    ? () => _confirmDelete(uid, name)
                                    : () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 17),
      ),
    );
  }

  Widget _buildSkillsTab() {
    Map<String, int> skillCounts = {};
    for (final user in _allUsers) {
      final data = user.data() as Map<String, dynamic>;
      final skills = List<String>.from(data['skillsOffered'] ?? []);
      for (final skill in skills) {
        skillCounts[skill] = (skillCounts[skill] ?? 0) + 1;
      }
    }
    final sortedSkills = skillCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        ..._buildCuratedSkillsSection(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text(
                'Most Popular Skills',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.sw.give,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: sortedSkills.isEmpty ? 1 : sortedSkills.length,
            itemBuilder: (context, index) {
              if (sortedSkills.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text("No skills found in the system"),
                  ),
                );
              }
              final skill = sortedSkills[index].key;
              final count = sortedSkills[index].value;
              final percentage = _allUsers.isEmpty ? 0.0 : (count / _allUsers.length) * 100;
              final hue = (skill.hashCode % 360).toDouble();
              final color = HSLColor.fromAHSL(1.0, hue, 0.6, 0.5).toColor();
              return SurfaceCard(
                margin: const EdgeInsets.only(bottom: 13),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.auto_awesome, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  skill,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '$count ${count == 1 ? "user" : "users"} (${percentage.toStringAsFixed(1)}%)',
                                  style: TextStyle(
                                    color: context.sw.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, color: context.sw.give),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Edit skill feature coming soon")),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _allUsers.isEmpty
                              ? 0
                              : (count / _allUsers.length).clamp(0.0, 1.0),
                          backgroundColor: context.sw.border,
                          color: color,
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReportsTab() {
    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.verified_user_outlined,
                size: 80, color: context.sw.border),
            const SizedBox(height: 16),
            Text(
              'All clear',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.sw.give,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No open reports right now.',
              style: TextStyle(color: context.sw.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_reports.length} open report${_reports.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.sw.give,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadReports,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(
                  foregroundColor: context.sw.give,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _reports.length,
            itemBuilder: (context, index) => _buildReportCard(_reports[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final reason = (report['reason'] ?? 'Report') as String;
    final details = (report['details'] ?? '') as String;
    final reportedId = (report['reportedUserId'] ?? '') as String;
    final reporterId = (report['reporterId'] ?? '') as String;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 13),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.sw.get.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.flag_outlined,
                      color: context.sw.get),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reason,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Reported: $reportedId',
                        style: TextStyle(
                            color: context.sw.textMuted, fontSize: 12),
                      ),
                      Text(
                        'Reporter: $reporterId',
                        style: TextStyle(
                            color: context.sw.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(details, style: const TextStyle(fontSize: 14)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () =>
                      _updateReport(report['id'] as String?, 'dismissed'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.sw.textMuted,
                    side: BorderSide(color: context.sw.border),
                  ),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _confirmBanUser(
                      reportedId, report['id'] as String?),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Suspend'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.sw.get,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
          Future<void> _loadSkills() async {
    try {
      final snapshot = await _firestore
          .collection('skills')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      if (!mounted) return;
      setState(() {
        _adminSkills = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'name': data['name'] ?? '',
            'description': data['description'] ?? '',
            'aliases': List<String>.from(data['aliases'] ?? []),
          };
        }).toList();
      });
    } catch (e) {
      print("Error loading skills: $e");
    }
  }

  Future<void> _loadReports() async {
    try {
      final snapshot = await _firestore
          .collection('reports')
          .where('status', isEqualTo: 'open')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      if (!mounted) return;
      setState(() {
        _reports =
            snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
      });
    } catch (e) {
      print('Error loading reports: $e');
    }
  }

  Future<void> _updateReport(String? reportId, String status) async {
    if (reportId == null) return;
    try {
      await _firestore.collection('reports').doc(reportId).update({
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      _loadReports();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report marked as $status')),
      );
    } catch (e) {
      print('Error updating report: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update report: $e')),
      );
    }
  }

  void _confirmBanUser(String? userId, String? reportId) {
    if (userId == null || userId.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Suspend this user?'),
        content: Text(
          'Account $userId will be flagged as suspended and hidden from the '
          'community. It can be reverted manually in Firestore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dialogContext.sw.get,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await _firestore
                    .collection('users')
                    .doc(userId)
                    .update({'isBanned': true});
              } catch (e) {
                print('Error suspending user: $e');
              }
              await _updateReport(reportId, 'actioned');
            },
            child: const Text('Suspend'),
          ),
        ],
      ),
    );
  }

  Future<bool> _addSkill(String name, String description, List<String> aliases) async {
    try {
      await _firestore.collection('skills').add({
        'name': name,
        'description': description,
        'aliases': aliases,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print("Error adding skill: $e");
      return false;
    }
  }

  Future<bool> _updateSkill(
      String docId, String name, String description, List<String> aliases) async {
    try {
      await _firestore.collection('skills').doc(docId).update({
        'name': name,
        'description': description,
        'aliases': aliases,
      });
      return true;
    } catch (e) {
      print("Error updating skill: $e");
      return false;
    }
  }

  Future<void> _deleteSkill(String docId, String name) async {
    try {
      await _firestore.collection('skills').doc(docId).delete();
      _loadSkills();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Skill '$name' deleted")),
      );
    } catch (e) {
      print("Error deleting skill: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete skill: $e")),
      );
    }
  }

  void _confirmDeleteSkill(String docId, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Skill"),
        content: Text("Remove skill '$name' from the curated list?"),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Delete"),
            onPressed: () {
              Navigator.pop(context);
              _deleteSkill(docId, name);
            },
          ),
        ],
      ),
    );
  }

  void _showAddSkillDialog() => _showSkillDialog();

  /// Add or edit a curated skill. Aliases power true synonym matching in
  /// [SkillCatalogService] (e.g. "JS"/"ECMAScript" both resolving to
  /// "JavaScript"), which case/whitespace canonicalization alone can't do -
  /// there's no textual relationship between "JS" and "JavaScript" to
  /// normalize, it has to be an explicit mapping an admin defines.
  void _showSkillDialog({Map<String, dynamic>? existing}) {
    final isEditing = existing != null;
    final skillNameController =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final skillDescriptionController =
        TextEditingController(text: existing?['description'] as String? ?? '');
    final aliasesController = TextEditingController(
      text: (List<String>.from(existing?['aliases'] ?? [])).join(', '),
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Edit Skill' : 'Add New Skill'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: skillNameController,
                decoration: const InputDecoration(
                  labelText: 'Skill Name',
                  hintText: 'e.g., JavaScript',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: skillDescriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Skill Description (Optional)',
                  hintText: 'Provide details about this skill',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: aliasesController,
                decoration: const InputDecoration(
                  labelText: 'Aliases (Optional)',
                  hintText: 'e.g., JS, ECMAScript',
                  helperText: 'Comma-separated. Typing an alias will match this skill.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final skillName = skillNameController.text.trim();
              if (skillName.isEmpty) return;
              final aliases = aliasesController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              Navigator.pop(dialogContext);
              final ok = isEditing
                  ? await _updateSkill(existing['id'] as String, skillName,
                      skillDescriptionController.text.trim(), aliases)
                  : await _addSkill(
                      skillName, skillDescriptionController.text.trim(), aliases);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? "Skill '$skillName' ${isEditing ? 'updated' : 'added'} successfully"
                      : "Failed to ${isEditing ? 'update' : 'add'} skill '$skillName'"),
                  backgroundColor: ok ? context.sw.give : Colors.redAccent,
                ),
              );
              if (ok) _loadSkills();
            },
            child: Text(isEditing ? 'Save Changes' : 'Add Skill'),
            style: ElevatedButton.styleFrom(
              backgroundColor: dialogContext.sw.give,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Curated (admin-managed) skills section - persisted to the `skills` collection.
  List<Widget> _buildCuratedSkillsSection() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Text(
              'Curated Skills',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.sw.give,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 19),
              label: const Text("Add Skill"),
              onPressed: () => _showAddSkillDialog(),
              style: TextButton.styleFrom(
                foregroundColor: context.sw.give,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _adminSkills.isEmpty
            ? const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No curated skills yet - tap "Add Skill" to create the first one.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _adminSkills.map((skill) {
                  final name = (skill['name'] as String?) ?? '';
                  final aliases = List<String>.from(skill['aliases'] ?? []);
                  return InputChip(
                    label: Text(aliases.isEmpty ? name : '$name (+${aliases.length})'),
                    tooltip: aliases.isEmpty ? null : 'Aliases: ${aliases.join(', ')}',
                    backgroundColor: context.sw.give.withValues(alpha: 0.08),
                    side: BorderSide(color: context.sw.give.withValues(alpha: 0.3)),
                    deleteIcon: Icon(Icons.clear, size: 18, color: context.sw.get),
                    onDeleted: () => _confirmDeleteSkill((skill['id'] as String?) ?? '', name),
                    onPressed: () => _showSkillDialog(existing: skill),
                  );
                }).toList(),
              ),
      ),
    ];
  }
}