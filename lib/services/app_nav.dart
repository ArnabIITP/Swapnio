import 'package:flutter/foundation.dart';

/// Lets any screen (e.g. a tapped notification) switch the bottom-nav tab
/// and the Inbox's inner tab without holding references to them.
class AppNav {
  AppNav._();

  static const int home = 0;
  static const int discover = 1;
  static const int inbox = 2;
  static const int profile = 3;

  static const int inboxRequests = 0;
  static const int inboxChats = 1;
  static const int inboxSessions = 2;

  /// The bottom-nav tab to show (Bottomnav listens).
  static final ValueNotifier<int?> tab = ValueNotifier(null);

  /// The Inbox tab to show (the Inbox listens).
  static final ValueNotifier<int?> inboxTab = ValueNotifier(null);

  static void go(int bottomTab, {int? inboxTab}) {
    // Reset first so asking for the same tab twice still fires.
    tab.value = null;
    tab.value = bottomTab;
    if (inboxTab != null) {
      AppNav.inboxTab.value = null;
      AppNav.inboxTab.value = inboxTab;
    }
  }
}
