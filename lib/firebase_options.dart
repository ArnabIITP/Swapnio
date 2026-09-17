// Swapnio - Firebase configuration.
//
// NOTE: the Firebase project is still the legacy `hotelbooking-f6a24` project.
// When the dedicated Swapnio Firebase project is created, run
//   flutterfire configure
// and let it overwrite this file (or update the values below by hand).
//
// Only Android is configured so far because that is the only platform whose
// config existed in the repository. Add `ios` / `web` entries (or re-run
// `flutterfire configure`) before shipping to those platforms.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase web options are not configured yet. Run '
        '`flutterfire configure` to add them.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'Firebase iOS/macOS options are not configured yet. Run '
          '`flutterfire configure` to add them.',
        );
      default:
        throw UnsupportedError(
          'Firebase options are not configured for $defaultTargetPlatform. '
          'Run `flutterfire configure` to add them.',
        );
    }
  }

  // Android client (package com.swapnio.app) of project hotelbooking-f6a24.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCU-1ZAV-CwS0c4zE_0Lr4MsfpBZcFui_M',
    appId: '1:924792323555:android:06237d60f2997dbf1f34d6',
    messagingSenderId: '924792323555',
    projectId: 'hotelbooking-f6a24',
    storageBucket: 'hotelbooking-f6a24.firebasestorage.app',
  );
}