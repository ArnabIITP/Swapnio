import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final GlobalKey _bodyKey = GlobalKey();
  bool _offline = false;
  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connectivityTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _checkConnectivity());
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  /// Firestore persistence keeps the app usable offline, but it silently
  /// queues writes - without a visible cue people assume a message or swipe
  /// went through when it hasn't yet.
  Future<void> _checkConnectivity() async {
    bool offline;
    try {
      final result = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 5));
      offline = result.isEmpty || result.first.rawAddress.isEmpty;
    } catch (_) {
      offline = true;
    }
    if (mounted && offline != _offline) setState(() => _offline = offline);
  }

  /// Re-tapping the active tab scrolls it back to the top. Each tab owns its
  /// own Scaffold (and so its own primary scroll controller), so instead of
  /// threading a callback into every screen, find the first vertical
  /// scrollable that's actually scrolled and animate it home.
  void _scrollCurrentTabToTop() {
    ScrollableState? target;
    void visit(Element element) {
      if (target != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        final scrollable = element.state as ScrollableState;
        if (scrollable.position.axis == Axis.vertical &&
            scrollable.position.pixels > 0) {
          target = scrollable;
          return;
        }
      }
      element.visitChildElements(visit);
    }

    _bodyKey.currentContext?.visitChildElements(visit);
    target?.position.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

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
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: _offline
                ? Material(
                    color: Colors.grey.shade800,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        child: Row(
                          children: const [
                            Icon(Icons.cloud_off, size: 16, color: Colors.white),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "You're offline - changes will sync when you reconnect",
                                style: TextStyle(color: Colors.white, fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Expanded(
            child: KeyedSubtree(key: _bodyKey, child: _screens[_selectedIndex]),
          ),
        ],
      ),
      bottomNavigationBar: CurvedNavigationBar(
        index: _selectedIndex,
        height: 62,
        backgroundColor: theme.scaffoldBackgroundColor,
        color: theme.colorScheme.surface,
        buttonBackgroundColor: AppTheme.primaryColor,
        animationDuration: const Duration(milliseconds: 350),
        onTap: (index) {
          if (index == _selectedIndex) {
            HapticFeedback.selectionClick();
            _scrollCurrentTabToTop();
            return;
          }
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
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