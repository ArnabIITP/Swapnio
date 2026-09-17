import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../theme.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _isLoading = false;
  Map<String, dynamic> _privacySettings = {
    'profileVisibility': 'public',
    'showEmail': false,
    'shareSkills': true,
    'shareAvailability': true,
    'allowDataCollection': true,
    'hideLocation': false,
  };

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No logged in user");

      // Stored as a `privacy` map on the user's own document (not a
      // sub-collection) so that other users - who can read `users/{uid}` but
      // not a private sub-collection - can actually see and honor these
      // preferences when viewing this user's profile.
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);

      final doc = await docRef.get();
      final privacy = doc.data()?['privacy'] as Map<String, dynamic>?;

      if (privacy != null) {
        setState(() {
          _privacySettings = {
            'profileVisibility': privacy['profileVisibility'] ?? 'public',
            'showEmail': privacy['showEmail'] ?? false,
            'shareSkills': privacy['shareSkills'] ?? true,
            'shareAvailability': privacy['shareAvailability'] ?? true,
            'allowDataCollection': privacy['allowDataCollection'] ?? true,
            'hideLocation': privacy['hideLocation'] ?? false,
          };
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading privacy settings: $e'))
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePrivacySettings() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No logged in user");

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'privacy': _privacySettings}, SetOptions(merge: true));
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Privacy settings saved'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving privacy settings: $e'))
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Privacy Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: AppTheme.primaryColor,
        elevation: 1.5,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppTheme.primaryColor),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                _buildInfoCard(),
                const SizedBox(height: 28),
                _buildProfileVisibilitySelector(),
                const SizedBox(height: 18),
                _buildSettingSwitch(
                  title: 'Show Email',
                  subtitle: 'Allow other users to see your email address',
                  value: _privacySettings['showEmail'],
                  onChanged: (value) {
                    setState(() {
                      _privacySettings['showEmail'] = value;
                    });
                  },
                ),
                _buildDivider(),
                _buildSettingSwitch(
                  title: 'Share Skills',
                  subtitle: 'Make your skills visible to other users',
                  value: _privacySettings['shareSkills'],
                  onChanged: (value) {
                    setState(() {
                      _privacySettings['shareSkills'] = value;
                    });
                  },
                ),
                _buildDivider(),
                _buildSettingSwitch(
                  title: 'Share Availability',
                  subtitle: 'Allow others to see when you are available',
                  value: _privacySettings['shareAvailability'],
                  onChanged: (value) {
                    setState(() {
                      _privacySettings['shareAvailability'] = value;
                    });
                  },
                ),
                _buildDivider(),
                _buildSettingSwitch(
                  title: 'Hide Location',
                  subtitle: 'Don\'t show your approximate location to others',
                  value: _privacySettings['hideLocation'],
                  onChanged: (value) {
                    setState(() {
                      _privacySettings['hideLocation'] = value;
                    });
                  },
                ),
                _buildDivider(),
                _buildSettingSwitch(
                  title: 'Allow Data Collection',
                  subtitle: 'Help us improve by sharing anonymous usage data',
                  value: _privacySettings['allowDataCollection'],
                  onChanged: (value) {
                    setState(() {
                      _privacySettings['allowDataCollection'] = value;
                    });
                  },
                ),
                const SizedBox(height: 28),
                _buildAppearanceSection(),
                const SizedBox(height: 28),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    elevation: 0,
                  ),
                  onPressed: _savePrivacySettings,
                  child: const Text('Save Changes'),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Looking to delete your account? That\'s in Profile > Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ),
              ],
            ),
    );
  }
  
  Widget _buildInfoCard() {
    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.privacy_tip, color: AppTheme.primaryColor, size: 28),
                const SizedBox(width: 10),
                const Text(
                  'Privacy Preferences',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.darkTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Control what information you share with other users and how your data is used in Swapnio.',
              style: TextStyle(fontSize: 15, color: Color(0xFF555555)),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProfileVisibilitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile Visibility',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose who can view your profile',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppTheme.primaryColor, width: 1.1),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _privacySettings['profileVisibility'],
              isExpanded: true,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              items: [
                DropdownMenuItem(
                  value: 'public',
                  child: const Text('Public - Anyone can view'),
                ),
                DropdownMenuItem(
                  value: 'matches',
                  child: const Text('Matches Only - Only users you\'ve matched with'),
                ),
                DropdownMenuItem(
                  value: 'private',
                  child: const Text('Private - Only you'),
                ),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _privacySettings['profileVisibility'] = value;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSettingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppTheme.primaryColor,
            inactiveTrackColor: Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
  
  Widget _buildAppearanceSection() {
    final appState = Provider.of<AppState>(context);
    return Card(
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.brightness_6, color: AppTheme.primaryColor, size: 28),
                SizedBox(width: 10),
                Text(
                  'Appearance',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D2D2D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Choose between the light and dark Sahara themes.',
              style: TextStyle(fontSize: 15, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                _buildThemeChip('Light', appState.themeMode),
                _buildThemeChip('Dark', appState.themeMode),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeChip(String label, ThemeMode current) {
    final themeMode = label == 'Dark' ? ThemeMode.dark : ThemeMode.light;
    final selected = current == themeMode;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppTheme.primaryColor,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.darkTextColor,
        fontWeight: FontWeight.bold,
      ),
      onSelected: (_) {
        Provider.of<AppState>(context, listen: false).setThemeMode(themeMode);
      },
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        color: Colors.grey.shade300,
        height: 1,
      ),
    );
  }
}
