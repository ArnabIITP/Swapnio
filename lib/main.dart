/*
 * Swapnio - A Flutter-based skill swapping platform.
 * Copyright (C) 2026 Arnab Das and Manab Kumar Barman
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'Screen/Auth/Startpage.dart';
import 'Screen/splash_screen.dart';
import 'Screen/User/Bottomnav.dart';
import 'Screen/User/chat_page.dart';
import 'Screen/User/setup.dart';
import 'providers/app_state.dart';
import 'providers/user_data_provider.dart';
import 'features/feature_routes.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';
import 'theme.dart';

/// Global navigator so push-notification taps can deep-link into a chat.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _initializeFirebase();

    // Firestore offline persistence: the app keeps working (cached reads, queued
    // writes) on a flaky connection instead of showing empty screens.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    await _initializeCrashReporting();

    runApp(const MyApp());
  }, (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
  });
}

/// Routes Flutter framework errors and uncaught async errors (via the
/// runZonedGuarded above) to Crashlytics instead of only the debug console,
/// so crashes in the field are actually visible to the team.
Future<void> _initializeCrashReporting() async {
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
}

/// Initialises Firebase with the explicit platform options when they exist and
/// falls back to the platform-provided configuration for platforms that have
/// not been set up with `flutterfire configure` yet (e.g. desktop).
Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    try {
      await Firebase.initializeApp();
    } catch (inner) {
      print('Firebase initialization failed: $inner');
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => UserDataProvider()),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          NotificationService.navigatorKey = appNavigatorKey;
          return MaterialApp(
            title: 'Swapnio',
            debugShowCheckedModeBanner: false,
            navigatorKey: appNavigatorKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appState.themeMode,
            routes: featureRoutes,
            home: _splashDone
                ? _buildMainContent(appState)
                : SplashScreen(
                    onFinished: () {
                      if (mounted) setState(() => _splashDone = true);
                    },
                  ),
          );
        },
      ),
    );
  }

  Widget _buildMainContent(AppState appState) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final User? user = snapshot.data;

        if (user == null) {
          return const StarterPage();
        }

        if (appState.loading || appState.currentUser == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (appState.needsSetup) {
          return const ProfileSetupPage();
        }

        return const BottomNavPage();
      },
    );
  }
}

