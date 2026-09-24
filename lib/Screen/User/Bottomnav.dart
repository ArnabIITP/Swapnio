import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

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
    _scheduleConnectivityPoll();
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    super.dispose();
  }

  /// Adaptive poll: when offline, check every 2 s so recovery feels instant;
  /// when online, every 5 s to save battery.
  void _scheduleConnectivityPoll() {
    _connectivityTimer?.cancel();
    final interval = _offline
        ? const Duration(seconds: 2)
        : const Duration(seconds: 5);
    _connectivityTimer = Timer.periodic(interval, (_) => _checkConnectivity());
  }

  /// Firestore persistence keeps the app usable offline, but it silently
  /// queues writes - without a visible cue people assume a message or swipe
  /// went through when it hasn't yet.
  Future<void> _checkConnectivity() async {
    bool offline;
    try {
      final result = await InternetAddress.lookup('firestore.googleapis.com')
          .timeout(const Duration(seconds: 2));
      offline = result.isEmpty || result.first.rawAddress.isEmpty;
    } catch (_) {
      offline = true;
    }
    if (mounted && offline != _offline) {
      setState(() => _offline = offline);
      // Transition happened — switch to the appropriate poll cadence.
      _scheduleConnectivityPoll();
    }
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

  static const List<_Tab> _tabs = [
    _Tab('Home', Icons.home_outlined, Icons.home_rounded),
    _Tab('Discover', Icons.explore_outlined, Icons.explore),
    _Tab('Chats', Icons.forum_outlined, Icons.forum_rounded),
    _Tab('Profile', Icons.person_outline, Icons.person_rounded),
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
                    color: context.sw.ink,
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
            child: KeyedSubtree(
              key: _bodyKey,
              child: IndexedStack(
                index: _selectedIndex,
                children: _screens,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            height: 64,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.sw.ink,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _navItem(i, badge: i == 2 ? unread : null),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTabTap(int index) {
    HapticFeedback.selectionClick();
    if (index == _selectedIndex) {
      _scrollCurrentTabToTop();
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Widget _navItem(int index, {int? badge}) {
    final c = context.sw;
    final selected = _selectedIndex == index;
    final tab = _tabs[index];
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTabTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 14),
          decoration: BoxDecoration(
            color: selected ? c.win : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? tab.activeIcon : tab.icon,
                    size: 23,
                    color: selected
                        ? c.onWin
                        : Colors.white.withValues(alpha: 0.55),
                  ),
                  if (badge != null && badge > 0)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: BoxDecoration(
                          color: c.give,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.ink, width: 1.5),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.only(left: 7),
                        child: Text(
                          tab.label,
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: c.onWin,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Tab(this.label, this.icon, this.activeIcon);
}
