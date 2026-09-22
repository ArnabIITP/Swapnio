import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:swapnio/Screen/User/setup.dart';
import 'package:swapnio/Screen/User/notification_settings.dart';
import 'package:swapnio/Screen/User/privacy_settings.dart';
import 'package:swapnio/providers/user_data_provider.dart';
import 'package:swapnio/providers/app_state.dart';
import '../Admin/Admin.dart';
import '../../features/gamification/gamification_model.dart';
import '../../features/gamification/gamification_provider.dart';
import '../../services/skill_catalog_service.dart';
import '../../services/swap_service.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme.dart';
import '../../ui/swapnio_badges.dart';
import '../../ui/swapnio_kit.dart';
import '../../ui/swapnio_widgets.dart';
import '../../ui/skill_suggestion_chips.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSettingsSheetOpen = false;

  /// The header gear icon toggles the settings panel open/closed - tapping
  /// again while it's open dismisses it instead of stacking another sheet.
  void _toggleSettingsSheet(Map<String, dynamic> userData) {
    if (_isSettingsSheetOpen) {
      Navigator.of(context).pop();
      return;
    }
    _isSettingsSheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.of(sheetContext).size.height * 0.85,
        child: Container(
          decoration: BoxDecoration(
            color: sheetContext.sw.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetContext.sw.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('Settings',
                        style: AppTheme.display(fontSize: 26, color: sheetContext.sw.text)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: _SettingsTabView(userData: userData)),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _isSettingsSheetOpen = false);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = Provider.of<UserDataProvider>(context, listen: false);
      userProvider.refreshUserData();
      Timer.periodic(const Duration(minutes: 1), (timer) {
        if (mounted) {
          setState(() {});
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getMembershipDuration(dynamic memberSince) {
    if (memberSince == null) return '0 days';
    DateTime date;
    if (memberSince is DateTime) {
      date = memberSince;
    } else if (memberSince is Timestamp) {
      date = memberSince.toDate();
    } else {
      return '0 days';
    }
    final now = DateTime.now();
    final difference = now.difference(date);
    final days = difference.inDays;
    if (days < 1) {
      return '0 days';
    } else if (days < 30) {
      return '$days day${days != 1 ? 's' : ''}';
    } else if (days < 365) {
      final months = (days / 30).floor();
      return '$months month${months > 1 ? 's' : ''}';
    } else {
      final years = (days / 365).floor();
      final remainingMonths = ((days % 365) / 30).floor();
      if (remainingMonths > 0) {
        return '$years year${years > 1 ? 's' : ''}, $remainingMonths month${remainingMonths > 1 ? 's' : ''}';
      }
      return '$years year${years > 1 ? 's' : ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<UserDataProvider>(
      builder: (context, userDataProvider, _) {
        final isLoading = userDataProvider.isLoading;
        final userData = userDataProvider.userData;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: user == null
              ? const Center(child: Text("No user logged in"))
              : isLoading
                  ? const SafeArea(child: ProfileSkeleton())
                  : userData == null
                      ? const Center(child: Text("Failed to load profile"))
                      : SafeArea(
                          bottom: false,
                          child: NestedScrollView(
                          // The profile header (gradient banner + stat cards)
                          // collapses out of the way on scroll-down and snaps
                          // back on scroll-up, instead of permanently taking
                          // up screen space above every tab. The status-bar
                          // inset is handled by the SafeArea above, NOT inside
                          // the header itself - doing it in both places made
                          // the fixed-height sliver box too small for its own
                          // content and it visually spilled into the tab bar.
                          headerSliverBuilder: (context, innerBoxIsScrolled) => [
                            SliverAppBar(
                              pinned: false,
                              floating: true,
                              snap: true,
                              automaticallyImplyLeading: false,
                              backgroundColor: context.sw.bg,
                              elevation: 0,
                              toolbarHeight: 0,
                              collapsedHeight: 0,
                              expandedHeight: 372,
                              flexibleSpace: FlexibleSpaceBar(
                                background: ClipRect(
                                  child: _buildProfileHeader(context, user, userData, colorScheme),
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
                                  labelStyle: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w800, fontSize: 13.5),
                                  unselectedLabelStyle: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w700, fontSize: 13.5),
                                  splashBorderRadius: BorderRadius.circular(12),
                                  tabs: const [
                                    Tab(height: 40, text: 'About'),
                                    Tab(height: 40, text: 'Skills'),
                                    Tab(height: 40, text: 'Activity'),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: TabBarView(
                                  controller: _tabController,
                                  children: [
                                    _AboutTabView(userData: userData),
                                    _SkillsTabView(userData: userData),
                                    _AchievementsTabView(userId: user.uid),
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

  Widget _buildProfileHeader(BuildContext context, User user,
      Map<String, dynamic> userData, ColorScheme colorScheme) {
    final c = context.sw;
    final name = (userData['name'] ?? '').toString().trim();
    final offered = List<String>.from(userData['skillsOffered'] ?? []);
    final wanted = List<String>.from(userData['skillsWanted'] ?? []);
    final rating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
    final swaps = (userData['completedSwaps'] as num?)?.toInt() ?? 0;

    return Container(
      color: c.bg,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Spacer(),
              Tooltip(
                message: 'Settings',
                child: Pressable(
                  onTap: () => _toggleSettingsSheet(userData),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                    child: Icon(Icons.settings_outlined,
                        size: 20, color: c.text, semanticLabel: 'Settings'),
                  ),
                ),
              ),
            ],
          ),
          Hero(
            tag: 'profile_avatar',
            child: SwapAvatar(
              name: name.isEmpty ? 'A' : name,
              photoUrl: userData['photoUrl'] as String?,
              size: 84,
              radius: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name.isEmpty ? 'Anonymous User' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.display(fontSize: 26, color: c.text),
          ),
          const SizedBox(height: 2),
          Text(
            swaps == 0
                ? 'Member for ${_getMembershipDuration(userData['memberSince'])}'
                : '$swaps swap${swaps == 1 ? '' : 's'} · member for ${_getMembershipDuration(userData['memberSince'])}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
          ),
          if (offered.isNotEmpty || wanted.isNotEmpty) ...[
            const SizedBox(height: 14),
            SwapSplit(
              giveLabel: 'TEACHES',
              giveSkill: offered.isEmpty ? 'Nothing yet' : offered.first,
              getLabel: 'LEARNING',
              getSkill: wanted.isEmpty ? 'Nothing yet' : wanted.first,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'rating',
                  value: rating > 0 ? rating.toStringAsFixed(1) : '-',
                  countValue: rating > 0 ? rating : null,
                  decimals: 1,
                  color: c.give,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                    label: 'swaps', value: '$swaps', countValue: swaps, color: c.get),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  label: 'profile',
                  value: '${(_profileStrength(userData) * 100).round()}%',
                  countValue: (_profileStrength(userData) * 100).round(),
                  suffix: '%',
                  color: c.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Endowed progress: the meter counts what is already there, so finishing
  /// feels like completing something rather than starting from zero.
  double _profileStrength(Map<String, dynamic> userData) {
    final checks = [
      (userData['photoUrl'] ?? '').toString().isNotEmpty,
      (userData['bio'] ?? '').toString().trim().isNotEmpty,
      List<String>.from(userData['skillsOffered'] ?? []).isNotEmpty,
      List<String>.from(userData['skillsWanted'] ?? []).isNotEmpty,
      List<String>.from(userData['availability'] ?? []).isNotEmpty,
    ];
    return checks.where((v) => v).length / checks.length;
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
    num? countValue,
    int decimals = 0,
    String suffix = '',
  }) {
    final c = context.sw;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: countValue == null
                ? Text(value, style: AppTheme.display(fontSize: 22, color: color))
                : CountUpText(
                    value: countValue,
                    decimals: decimals,
                    suffix: suffix,
                    style: AppTheme.display(fontSize: 22, color: color),
                  ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _AboutTabView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const _AboutTabView({required this.userData});

  @override
  State<_AboutTabView> createState() => _AboutTabViewState();
}

class _AboutTabViewState extends State<_AboutTabView> {
  final TextEditingController _bioController = TextEditingController();
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _bioController.text = widget.userData['bio']?.toString() ?? '';
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _saveBio() async {
    final userProvider = Provider.of<UserDataProvider>(context, listen: false);
    
    try {
      await userProvider.updateField('bio', _bioController.text);
      setState(() => _isEditing = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update bio: $e')),
      );
    }
  }
  
  void _showAvailabilityDialog() {
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    List<String> convertToStringList(dynamic data) {
      if (data == null) return [];
      
      if (data is String) {
        return [data];
      } else if (data is List) {
        return data.map((item) => item.toString()).toList();
      } else {
        return [];
      }
    }
    
    final List<String> currentAvailability = convertToStringList(widget.userData['availability']);
    
    final Map<String, bool> selections = {
      for (var day in days) day: currentAvailability.contains(day)
    };
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Availability'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: days.map((day) {
                    return CheckboxListTile(
                      title: Text(day),
                      value: selections[day],
                      onChanged: (bool? value) {
                        setDialogState(() {
                          selections[day] = value ?? false;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    final List<String> updatedAvailability = days
                        .where((day) => selections[day] == true)
                        .toList();
                    
                    try {
                      final userProvider = Provider.of<UserDataProvider>(context, listen: false);
                      await userProvider.updateField('availability', updatedAvailability);
                      Navigator.of(context).pop();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update availability: $e')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing && widget.userData['bio'] != _bioController.text) {
      _bioController.text = widget.userData['bio']?.toString() ?? '';
    }
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'About Me',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(_isEditing ? Icons.save : Icons.edit),
                  onPressed: () {
                    if (_isEditing) {
                      _saveBio();
                    } else {
                      setState(() => _isEditing = true);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            _isEditing
                ? TextField(
                    controller: _bioController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Write something about yourself...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  )
                : Text(
                    widget.userData['bio']?.toString() ?? 'No bio available',
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Availability',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showAvailabilityDialog(),
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildAvailabilitySchedule(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAvailabilitySchedule() {
    List<String> convertToStringList(dynamic data) {
      if (data == null) return [];
      
      if (data is String) {
        return [data];
      } else if (data is List) {
        return data.map((item) => item.toString()).toList();
      } else {
        return [];
      }
    }
    
    final List<String> availabilityList = convertToStringList(widget.userData['availability']);
    
    final now = DateTime.now();
    final currentDay = _getDayName(now.weekday);
    
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: availabilityList.contains(currentDay) 
                  ? context.sw.get.withValues(alpha: 0.1) 
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  availabilityList.contains(currentDay)
                      ? Icons.circle
                      : Icons.circle_outlined,
                  color: availabilityList.contains(currentDay)
                      ? context.sw.get
                      : Colors.grey,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  availabilityList.contains(currentDay)
                      ? 'Available Today'
                      : 'Not Available Today',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: availabilityList.contains(currentDay)
                        ? context.sw.get
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: Colors.grey.withValues(alpha: 0.2)),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: days.map((day) {
                final isAvailable = availabilityList.contains(day);
                final isToday = day == currentDay;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        isAvailable ? Icons.check_circle : Icons.cancel,
                        color: isAvailable ? context.sw.get : Colors.grey,
                        size: isToday ? 22 : 18,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        day + (isToday ? ' (Today)' : ''),
                        style: TextStyle(
                          fontSize: isToday ? 17 : 16,
                          fontWeight: isToday || isAvailable ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? context.sw.text : (isAvailable ? context.sw.text : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return '';
    }
  }
}

class _SkillsTabView extends StatefulWidget {
  final Map<String, dynamic> userData;

  const _SkillsTabView({required this.userData});

  @override
  State<_SkillsTabView> createState() => _SkillsTabViewState();
}

class _SkillsTabViewState extends State<_SkillsTabView> {
  final TextEditingController _newSkillController = TextEditingController();
  bool _addingOfferedSkill = true;

  @override
  void initState() {
    super.initState();
    SkillCatalogService.instance.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _newSkillController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newSkillController.dispose();
    super.dispose();
  }

  Future<void> _addSkill(String rawSkill, bool isOffered,
      {bool announce = true}) async {
    final skill = SkillCatalogService.instance.canonicalize(rawSkill);
    if (skill.isEmpty) return;

    final userProvider = Provider.of<UserDataProvider>(context, listen: false);
    
    try {
      List<String> convertToStringList(dynamic data) {
        if (data == null) return [];
        
        if (data is String) {
          return [data];
        } else if (data is List) {
          return data.map((item) => item.toString()).toList();
        } else {
          return [];
        }
      }
      
      List<String> currentSkills = isOffered 
        ? convertToStringList(widget.userData['skillsOffered'])
        : convertToStringList(widget.userData['skillsWanted']);
      
      if (!currentSkills.any((s) => s.toLowerCase() == skill.toLowerCase())) {
        currentSkills.add(skill);

        if (isOffered) {
          await userProvider.updateField('skillsOffered', currentSkills);
        } else {
          await userProvider.updateField('skillsWanted', currentSkills);
        }
        if (announce) _announceSkillReach(skill, isOffered);
      }
      
      _newSkillController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add skill: $e')),
      );
    }
  }
  
  /// Effort -> reward: tie adding a skill to its immediate consequence.
  /// Teaching X reaches everyone who wants X; wanting X reaches everyone who
  /// teaches it. A single-field array-contains count needs no extra index.
  Future<void> _announceSkillReach(String skill, bool isOffered) async {
    try {
      final result = await FirebaseFirestore.instance
          .collection('users')
          .where(isOffered ? 'skillsWanted' : 'skillsOffered',
              arrayContains: skill)
          .count()
          .get();
      final count = result.count ?? 0;
      if (!mounted || count == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOffered
              ? '$count ${count == 1 ? 'person wants' : 'people want'} to learn $skill'
              : '$count ${count == 1 ? 'person teaches' : 'people teach'} $skill - check Discover'),
          backgroundColor: context.sw.give,
        ),
      );
    } catch (_) {
      // Purely encouraging - never block adding a skill on this.
    }
  }

  Future<void> _removeSkill(String skill, bool isOffered) async {
    final userProvider = Provider.of<UserDataProvider>(context, listen: false);
    
    try {
      List<String> convertToStringList(dynamic data) {
        if (data == null) return [];
        
        if (data is String) {
          return [data];
        } else if (data is List) {
          return data.map((item) => item.toString()).toList();
        } else {
          return [];
        }
      }
      
      List<String> currentSkills = isOffered 
        ? convertToStringList(widget.userData['skillsOffered'])
        : convertToStringList(widget.userData['skillsWanted']);
      
      currentSkills.remove(skill);

      if (isOffered) {
        await userProvider.updateField('skillsOffered', currentSkills);
      } else {
        await userProvider.updateField('skillsWanted', currentSkills);
      }
      if (!mounted) return;
      // Removing is one tap with no confirm dialog, so give a way back.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Removed "$skill"'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'UNDO',
              onPressed: () => _addSkill(skill, isOffered, announce: false),
            ),
          ),
        );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove skill: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Skills I Offer',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildSkillPills(
              widget.userData['skillsOffered'] ?? [],
              Theme.of(context).colorScheme.primary,
              true,
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newSkillController,
                    decoration: InputDecoration(
                      hintText: 'Add a new skill...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    _addSkill(_newSkillController.text.trim(), _addingOfferedSkill);
                    _newSkillController.clear();
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(_addingOfferedSkill ? 'Add to Offered' : 'Add to Wanted'),
                ),
              ],
            ),
            SkillSuggestionChips(
              query: _newSkillController.text,
              onSelected: (s) {
                _addSkill(s, _addingOfferedSkill);
                _newSkillController.clear();
              },
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _addingOfferedSkill = !_addingOfferedSkill;
                  });
                },
                icon: Icon(_addingOfferedSkill 
                  ? Icons.swap_vertical_circle 
                  : Icons.swap_vertical_circle_outlined),
                label: Text('Switch to ${_addingOfferedSkill ? 'Wanted' : 'Offered'} Skills'),
              ),
            ),
            
            const SizedBox(height: 24),
            const Text(
              'Skills I\'m Looking For',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildSkillPills(
              widget.userData['skillsWanted'] ?? [],
              Theme.of(context).colorScheme.secondary,
              false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillPills(dynamic skills, Color color, bool isOffered) {
    List<String> convertToStringList(dynamic data) {
      if (data == null) return [];
      
      if (data is String) {
        return [data];
      } else if (data is List) {
        return data.map((item) => item.toString()).toList();
      } else {
        return [];
      }
    }
    
    final List<String> skillsList = convertToStringList(skills);
    
    if (skillsList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('No skills listed yet'),
      );
    }
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: skillsList.map((skill) => Chip(
        label: Text(skill),
        backgroundColor: color.withValues(alpha: 0.2),
        labelStyle: TextStyle(color: color.withValues(alpha: 0.8)),
        deleteIcon: const Icon(Icons.cancel, size: 18),
        onDeleted: () => _removeSkill(skill, isOffered),
      )).toList(),
    );
  }
}

class _SettingsTabView extends StatelessWidget {
  final Map<String, dynamic> userData;

  const _SettingsTabView({required this.userData});

  @override
  Widget build(BuildContext context) {
    final isAdmin = Provider.of<AppState>(context).currentUser?.isAdmin ?? false;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSettingsButton(
              context,
              icon: Icons.edit,
              title: 'Edit Profile',
              subtitle: 'Update your profile information',
              onTap: () => _closeThenPush(context, const ProfileSetupPage()),
            ),
            _buildSettingsButton(
              context,
              icon: Icons.notifications,
              title: 'Notification Settings',
              subtitle: 'Manage your notification preferences',
              onTap: () => _closeThenPush(context, const NotificationSettingsPage()),
            ),
            _buildSettingsButton(
              context,
              icon: Icons.lock,
              title: 'Privacy Settings',
              subtitle: 'Control your privacy preferences',
              onTap: () => _closeThenPush(context, const PrivacySettingsPage()),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'Community & Growth'.toUpperCase(),
                style: AppTheme.label(color: context.sw.textMuted),
              ),
            ),
            const SizedBox(height: 8),
            _buildSettingsButton(
              context,
              icon: Icons.insights,
              title: 'Progress Dashboard',
              subtitle: 'Track sessions, quizzes and peer ratings',
              onTap: () => _closeThenNamed(context, '/progress'),
            ),
            _buildSettingsButton(
              context,
              icon: Icons.forum,
              title: 'Community Forum',
              subtitle: 'Discuss and share with the community',
              onTap: () => _closeThenNamed(context, '/forum'),
            ),
            _buildSettingsButton(
              context,
              icon: Icons.verified_user,
              title: 'Profile Verification',
              subtitle: 'Verify your email and phone',
              onTap: () => _closeThenNamed(context, '/verification'),
            ),
            if (isAdmin) ...[
              _buildSettingsButton(
                context,
                icon: Icons.analytics,
                title: 'Analytics Dashboard',
                subtitle: 'Browse app activity events (admin only)',
                onTap: () => _closeThenNamed(context, '/analytics'),
              ),
              ],
            if (isAdmin)
              _buildSettingsButton(
                context,
                icon: Icons.admin_panel_settings,
                title: 'Admin Panel',
                subtitle: 'Manage users and system settings',
                onTap: () => _closeThenPush(context, const AdminPage()),
              ),
            _buildSettingsButton(
              context,
              icon: Icons.delete_forever,
              title: 'Delete Account',
              subtitle: 'Permanently remove your profile and data',
              danger: true,
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                _deleteAccount(context);
              },
            ),
            _buildSettingsButton(
              context,
              icon: Icons.logout,
              title: 'Sign Out',
              subtitle: 'Log out of your account',
              danger: true,
              onTap: () async {
                // Close the sheet first - signing out swaps the whole widget
                // tree underneath it, leaving an orphaned sheet on screen.
                Navigator.of(context, rootNavigator: true).pop();
                await FirebaseAuth.instance.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
  
  /// Settings actions always dismiss the sheet before they navigate, so it
  /// can't linger over the destination.
  void _closeThenPush(BuildContext context, Widget page) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => page));
  }

  void _closeThenNamed(BuildContext context, String route) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    navigator.pushNamed(route);
  }

  /// Permanently deletes the account: removes the Firestore profile and signs
  /// out. Deleting the Firebase Auth record itself needs a recent login - if
  /// it fails we tell the user to re-authenticate and retry.
  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently removes your profile, skills and settings. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Best-effort cleanup of data the security rules let the owner remove.
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      } catch (e) {
        debugPrint('Profile doc deletion failed: $e');
      }

      // Deleting the auth record requires a recent login.
      try {
        await user.delete();
      } catch (_) {
        await FirebaseAuth.instance.signOut();
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Your profile data was removed. To finish deleting your login, '
              'sign in again and repeat Delete Account.',
            ),
          ),
        );
        return;
      }

      await FirebaseAuth.instance.signOut();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete account: $e')),
      );
    }
  }

  Widget _buildSettingsButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final c = context.sw;
    final accent = danger ? const Color(0xFFD64545) : c.get;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        scale: 0.985,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: danger ? accent : c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Combined "Achievements" (points/level/badges/leaderboard) and "Activity"
/// (recent swap sessions, reviews received) tab - this used to be two taps
/// away under Settings; putting it on the profile directly makes it visible
/// without hunting for it.
class _AchievementsTabView extends StatefulWidget {
  final String userId;

  const _AchievementsTabView({required this.userId});

  @override
  State<_AchievementsTabView> createState() => _AchievementsTabViewState();
}

class _AchievementsTabViewState extends State<_AchievementsTabView> {
  String get userId => widget.userId;

  // Built once rather than inside build(): .snapshots() returns a new Stream
  // each call, which makes StreamBuilder re-subscribe (and flash a spinner)
  // on every rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _leaderboardStream;
  late final Future<QuerySnapshot> _recentReviewsFuture;
  late final Future<ReliabilityStatus> _reliabilityFuture;

  @override
  void initState() {
    super.initState();
    _leaderboardStream = FirebaseFirestore.instance
        .collection('gamification')
        .orderBy('points', descending: true)
        .limit(5)
        .snapshots();
    _recentReviewsFuture = FirebaseFirestore.instance
        .collection('ratings')
        .where('toUserId', isEqualTo: widget.userId)
        .orderBy('timestamp', descending: true)
        .limit(5)
        .get();
    _reliabilityFuture = SwapSessionService.instance.myReliability();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => GamificationProvider(userId: userId),
      child: Consumer<GamificationProvider>(
        builder: (context, provider, _) {
          final gamification = provider.gamification;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildReliabilityBanner(context),
                if (gamification == null)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  _buildGamificationSection(context, gamification),
                const SizedBox(height: 28),
                Text(
                  'Recent Sessions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _buildRecentSessions(context),
                const SizedBox(height: 28),
                Text(
                  'Recent Reviews',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _buildRecentReviews(context),
                const SizedBox(height: 28),
                Text(
                  'Leaderboard',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _buildLeaderboard(context),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Warns the user about their own attendance record before they discover
  /// it by being blocked from booking. Only appears once there's a real
  /// record and something worth flagging.
  Widget _buildReliabilityBanner(BuildContext context) {
    return FutureBuilder<ReliabilityStatus>(
      future: _reliabilityFuture,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null || status.total < 3 || status.showUpRate >= 80) {
          return const SizedBox.shrink();
        }
        final blocked = !status.canBookSessions;
        final color = blocked ? Colors.redAccent : Colors.orange.shade800;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(blocked ? Icons.block : Icons.warning_amber_rounded,
                  color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      blocked
                          ? 'Session booking paused'
                          : 'Your attendance is slipping',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      blocked
                          ? 'You showed up to ${status.attended} of ${status.total} sessions. '
                              'Attend the ones you\'ve agreed to and booking unlocks automatically.'
                          : '${status.showUpRate}% show-up rate. Missing more sessions will pause your booking.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGamificationSection(BuildContext context, Gamification gamification) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _statCard(context,
                  icon: Icons.stars, label: 'Points', value: '${gamification.points}'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(context,
                  icon: Icons.military_tech, label: 'Level', value: '${gamification.level}'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const KitSection('Badges'),
        BadgeCollection(earnedIds: gamification.badges),
      ],
    );
  }

  Widget _statCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final c = context.sw;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.give.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: c.give, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: AppTheme.display(fontSize: 22, color: c.text)),
                ),
                Text(label,
                    style: GoogleFonts.manrope(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSessions(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: SwapSessionService.instance.mySessionsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = (snapshot.data?.docs ?? []).take(5).toList();
        if (docs.isEmpty) {
          return Text(
            'No swap sessions yet.',
            style: TextStyle(color: context.sw.textMuted),
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final names = Map<String, dynamic>.from(data['participantNames'] ?? {});
            final otherId = List<String>.from(data['participants'] ?? [])
                .firstWhere((p) => p != userId, orElse: () => '');
            final otherName = (names[otherId] as String?) ?? 'Swap partner';
            final status = (data['status'] as String?) ?? 'pending';
            final skillOffered = data['skillOffered'] ?? '';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconForSessionStatus(status), color: context.sw.give),
              title: Text('$otherName - $skillOffered'),
              subtitle: Text(_labelForSessionStatus(status)),
              dense: true,
            );
          }).toList(),
        );
      },
    );
  }

  IconData _iconForSessionStatus(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle;
      case 'accepted':
        return Icons.event_available;
      case 'declined':
        return Icons.cancel;
      case 'no_show':
        return Icons.event_busy;
      default:
        return Icons.hourglass_empty;
    }
  }

  String _labelForSessionStatus(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'accepted':
        return 'Accepted - upcoming';
      case 'declined':
        return 'Declined';
      case 'no_show':
        return 'No-show';
      default:
        return 'Pending';
    }
  }

  Widget _buildRecentReviews(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: _recentReviewsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Text(
            'No reviews yet.',
            style: TextStyle(color: context.sw.textMuted),
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final rating = (data['rating'] as num?)?.toDouble() ?? 0.0;
            final review = (data['review'] as String?) ?? '';
            final timestamp = data['timestamp'] as Timestamp?;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.star, color: context.sw.give),
              title: Text('${rating.toStringAsFixed(1)} stars'),
              subtitle: Text(review.isEmpty
                  ? (timestamp != null ? DateFormat.yMMMd().format(timestamp.toDate()) : '')
                  : review),
              dense: true,
            );
          }).toList(),
        );
      },
    );
  }

  /// Top 5 users by gamification points.
  Widget _buildLeaderboard(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _leaderboardStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Text(
            'No points earned yet - be the first!',
            style: TextStyle(color: context.sw.textMuted),
          );
        }
        final uids = docs.map((d) => d.id).toList();
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: uids)
              .get(),
          builder: (context, usersSnap) {
            final names = <String, String>{};
            for (final doc in usersSnap.data?.docs ?? []) {
              names[doc.id] = (doc.data()['name'] as String?) ?? 'Swapnio user';
            }
            return Column(
              children: [
                for (var i = 0; i < docs.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: i < 3
                          ? context.sw.give.withValues(alpha: 0.15)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: i < 3
                              ? context.sw.give
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(
                      docs[i].id == userId ? 'You' : (names[docs[i].id] ?? 'Swapnio user'),
                      style: TextStyle(
                        fontWeight: docs[i].id == userId ? FontWeight.bold : null,
                      ),
                    ),
                    trailing: Text(
                      '${docs[i].data()['points'] ?? 0} pts',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
