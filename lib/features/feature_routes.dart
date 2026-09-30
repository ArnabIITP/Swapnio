// Centralized routes for new features
import 'package:flutter/material.dart';
import 'verification/verification_screen.dart';
import 'progress/progress_dashboard.dart';
import 'forum/forum_screen.dart';
import 'analytics/analytics_dashboard.dart';

Map<String, WidgetBuilder> featureRoutes = {
  '/verification': (context) => VerificationScreen(),
  '/progress': (context) => ProgressDashboard(),
  '/forum': (context) => ForumScreen(),
  '/analytics': (context) => AnalyticsDashboard(),
};
