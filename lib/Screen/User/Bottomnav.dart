import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';

import 'package:swapnio/Screen/User/home_dashboard.dart';
import 'package:swapnio/Screen/User/setup.dart';
import 'package:swapnio/Screen/User/Swap.dart';
import 'package:swapnio/Screen/User/profile.dart';
import 'package:swapnio/providers/app_state.dart';
import 'Request.dart';
import '../../theme.dart';

class BottomNavPage extends StatefulWidget {
  const BottomNavPage({super.key});

  @override
  State<BottomNavPage> createState() => _BottomNavPageState();
}

class _BottomNavPageState extends State<BottomNavPage> {
  int _selectedIndex = 0;
  bool _setupPromptShown = false;

  late final List<Widget> _screens = [
    // Home is a dashboard ("what needs me?"), Discover owns all browsing -
    // they used to be two tabs doing the same browse job.
    HomeDashboard(onNavigateToTab: _goToTab),
    Swap(onNavigateToTab: _goToTab),
    RequestPage(onNavigateToTab: _goToTab),
    const ProfilePage(),
  ];

  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.explore_outlined,
    Icons.forum_outlined,
    Icons.person_outline,
  ];

  void _goToTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final unread = Provider.of<AppState>(context).unreadNotifications;
    final theme = Theme.of(context);
    final appState = Provider.of<AppState>(context);

    // Onboarding gate: send brand-new profiles (no skills offered yet) through
    // the setup flow exactly once, so the feed isn't full of empty cards.
    if (appState.currentUser != null &&
        appState.needsSetup &&
        !_setupPromptShown) {
      _setupPromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
        );
      });
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _screens[_selectedIndex],
      bottomNavigationBar: CurvedNavigationBar(
        index: _selectedIndex,
        height: 62,
        backgroundColor: theme.scaffoldBackgroundColor,
        color: theme.colorScheme.surface,
        buttonBackgroundColor: AppTheme.primaryColor,
        animationDuration: const Duration(milliseconds: 350),
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          _navIcon(_icons[0], 0),
          _navIcon(_icons[1], 1),
          _navIcon(_icons[2], 2, badge: unread),
          _navIcon(_icons[3], 3),
        ],
      ),
    );
  }

  Widget _navIcon(IconData icon, int index, {int? badge}) {
    final selected = _selectedIndex == index;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          icon,
          size: 26,
          color: selected ? Colors.white : AppTheme.warmMutedText,
        ),
        if (badge != null && badge > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}