import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../../theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;
  bool _isLoading = false;
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

  Future<void> _deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
      if (_auth.currentUser?.uid == uid) {
        await _auth.currentUser!.delete();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User deleted successfully")),
      );
      _fetchAllUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete user: $e")),
      );
    }
  }

  void _confirmDelete(String uid, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text("Are you sure you want to delete $name's account?"),
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
      backgroundColor: AppTheme.backgroundLight,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppTheme.primaryColor,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Admin Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFE29A63),
                      AppTheme.primaryColor,
                      AppTheme.tertiaryColor,
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  _fetchAllUsers();
                  _fetchAdminStats();
                },
              ),
            ],
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
            ),
          ),
        ],
        body: Column(
          children: [
            if (!_isLoading) _buildStatsSection(),
            Padding(
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
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: colorScheme.primary,
                unselectedLabelColor: Colors.grey,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: colorScheme.primary,
                tabs: const [
                  Tab(text: 'Users'),
                  Tab(text: 'Skills'),
                  Tab(text: 'Reports'),
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
      floatingActionButton: FloatingActionButton(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        onPressed: () {
          _showAddSkillDialog();
        },
        child: const Icon(Icons.add),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard Overview',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard(
                icon: Icons.people,
                value: _stats['userCount']?.toString() ?? '0',
                label: 'Total Users',
                color: Colors.blue,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.swap_horiz,
                value: _stats['swapsCount']?.toString() ?? '0',
                label: 'Total Swaps',
                color: AppTheme.tertiaryColor,
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
                color: AppTheme.tertiaryColor,
              ),
              const SizedBox(width: 12),
              _buildStatCard(
                icon: Icons.auto_awesome,
                value: _stats['totalSkillsOffered']?.toString() ?? '0',
                label: 'Skills Offered',
                color: Colors.purple,
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
          color: Colors.white,
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
                color: Colors.grey.shade600,
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
        final rating = (data['rating'] ?? 0.0) as double;
        final isAdmin = (data['isAdmin'] ?? false) as bool;
        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.13),
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 32, color: AppTheme.primaryColor)
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
                                color: Colors.purple.withValues(alpha: 0.13),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(
                                  color: Colors.purple,
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
                        style: TextStyle(color: Colors.grey.shade600),
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
                              const Icon(Icons.star, color: AppTheme.primaryColor, size: 17),
                              const SizedBox(width: 4),
                              Text('${rating.toStringAsFixed(1)} Rating'),
                            ],
                          ),
                          Row(
                            children: [
                              _buildUserActionButton(
                                icon: Icons.block,
                                color: AppTheme.tertiaryColor,
                                onTap: () => _confirmBanUser(uid, null),
                              ),
                              const SizedBox(width: 8),
                              _buildUserActionButton(
                                icon: Icons.delete,
                                color: Colors.red,
                                onTap: () => _confirmDelete(uid, name),
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
          child: const Row(
            children: [
              Text(
                'Most Popular Skills',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
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
              return Card(
                margin: const EdgeInsets.only(bottom: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
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
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppTheme.primaryColor),
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
                          backgroundColor: Colors.grey.shade200,
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
                size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'All clear',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No open reports right now.',
              style: TextStyle(color: Colors.grey.shade600),
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
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _loadReports,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
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

    return Card(
      margin: const EdgeInsets.only(bottom: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
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
                    color: AppTheme.tertiaryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.flag_outlined,
                      color: AppTheme.tertiaryColor),
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
                            color: Colors.grey.shade600, fontSize: 12),
                      ),
                      Text(
                        'Reporter: $reporterId',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12),
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
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                    backgroundColor: AppTheme.tertiaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
              backgroundColor: AppTheme.tertiaryColor,
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
                  backgroundColor: ok ? AppTheme.primaryColor : Colors.redAccent,
                ),
              );
              if (ok) _loadSkills();
            },
            child: Text(isEditing ? 'Save Changes' : 'Add Skill'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            const Text(
              'Curated Skills',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 19),
              label: const Text("Add Skill"),
              onPressed: () => _showAddSkillDialog(),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
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
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                    side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.3)),
                    deleteIcon: const Icon(Icons.clear, size: 18, color: AppTheme.tertiaryColor),
                    onDeleted: () => _confirmDeleteSkill((skill['id'] as String?) ?? '', name),
                    onPressed: () => _showSkillDialog(existing: skill),
                  );
                }).toList(),
              ),
      ),
    ];
  }
}