import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import '../../ui/swapnio_kit.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _isLoading = false;
  Map<String, dynamic> _notificationSettings = {
    'newMatches': true,
    'messages': true,
    'skillRequests': true,
    'skillUpdates': false,
    'appUpdates': true,
  };

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No logged in user");

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications');
      
      final doc = await docRef.get();
      
      if (doc.exists) {
        setState(() {
          _notificationSettings = {
            'newMatches': doc.data()?['newMatches'] ?? true,
            'messages': doc.data()?['messages'] ?? true,
            'skillRequests': doc.data()?['skillRequests'] ?? true,
            'skillUpdates': doc.data()?['skillUpdates'] ?? false,
            'appUpdates': doc.data()?['appUpdates'] ?? true,
          };
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading settings: $e'))
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveNotificationSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("No logged in user");

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('notifications')
          .set(_notificationSettings, SetOptions(merge: true));
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings saved'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving settings: $e'))
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
      backgroundColor: context.sw.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwapHeader(title: 'Notifications', subtitle: 'Choose what Swapnio may ping you about'),
            Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 8),
                _buildInfoCard(),
                const SizedBox(height: 28),
                _buildSettingSwitch(
                  title: 'New Matches',
                  subtitle: 'Get notified when you match with someone',
                  value: _notificationSettings['newMatches'],
                  onChanged: (value) {
                    setState(() {
                      _notificationSettings['newMatches'] = value;
                    });
                  },
                ),
                _buildSettingSwitch(
                  title: 'Messages',
                  subtitle: 'Receive notifications for new messages',
                  value: _notificationSettings['messages'],
                  onChanged: (value) {
                    setState(() {
                      _notificationSettings['messages'] = value;
                    });
                  },
                ),
                _buildSettingSwitch(
                  title: 'Skill Requests',
                  subtitle: 'Get notified when someone requests your skills',
                  value: _notificationSettings['skillRequests'],
                  onChanged: (value) {
                    setState(() {
                      _notificationSettings['skillRequests'] = value;
                    });
                  },
                ),
                _buildSettingSwitch(
                  title: 'Skill Updates',
                  subtitle: 'Get notified about new skills in your area',
                  value: _notificationSettings['skillUpdates'],
                  onChanged: (value) {
                    setState(() {
                      _notificationSettings['skillUpdates'] = value;
                    });
                  },
                ),
                _buildSettingSwitch(
                  title: 'App Updates',
                  subtitle: 'Stay informed about new app features',
                  value: _notificationSettings['appUpdates'],
                  onChanged: (value) {
                    setState(() {
                      _notificationSettings['appUpdates'] = value;
                    });
                  },
                ),
                const SizedBox(height: 28),
                PillButton(label: 'Save Changes', onTap: _saveNotificationSettings),
              ],
            ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoCard() {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications, color: context.sw.give, size: 28),
                const SizedBox(width: 10),
                Text(
                  'Notification Preferences',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: context.sw.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Control which notifications you receive from Swapnio. You can toggle each type of notification on or off.',
              style: TextStyle(fontSize: 15, color: Color(0xFF555555)),
            ),
          ],
        ),
    );
  }
  
  Widget _buildSettingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final c = context.sw;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        radius: 18,
        onTap: () => onChanged(!value),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(fontSize: 12, color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              activeTrackColor: c.give,
              inactiveThumbColor: c.surface,
              inactiveTrackColor: c.surfaceLow,
              trackOutlineColor: WidgetStatePropertyAll(c.border),
            ),
          ],
        ),
      ),
    );
  }

}
