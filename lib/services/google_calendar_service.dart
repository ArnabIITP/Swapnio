import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Real Google Calendar + Google Meet integration for swap sessions.
///
/// Accounts created with "Sign in with Google" already have a cached Google
/// session on-device, so calendar access can usually be granted silently -
/// no separate "connect" step. Accounts created with email/password have no
/// such session, so they go through an explicit one-time consent
/// ([connect]) the first time they try to schedule a session with a Meet
/// link.
///
/// Creating the event with `conferenceData` set is what makes Google
/// generate a real, unique Meet link for that event - the same thing the
/// Calendar UI does when you tick "Add Google Meet video conferencing".
class GoogleCalendarService {
  GoogleCalendarService._();

  static final GoogleCalendarService instance = GoogleCalendarService._();

  static const String _calendarScope =
      'https://www.googleapis.com/auth/calendar.events';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', _calendarScope],
  );

  bool _connected = false;
  bool get isConnected => _connected;

  /// True if this account authenticated with Google in the first place -
  /// for these users, calendar access can be granted without a separate
  /// "connect your calendar" prompt.
  bool get signedInWithGoogle {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    return user.providerData.any((p) => p.providerId == 'google.com');
  }

  /// Tries to silently pick up calendar access - works for Google-auth users
  /// whose device already has a cached Google session, and for anyone who
  /// has connected before this app launch. Never prompts the user.
  Future<bool> ensureConnected() async {
    if (_connected) return true;
    try {
      final account = await _googleSignIn.signInSilently();
      if (account == null) return false;
      final granted = await _googleSignIn.requestScopes([_calendarScope]);
      _connected = granted;
      return granted;
    } catch (e) {
      debugPrint('GoogleCalendarService.ensureConnected failed: $e');
      return false;
    }
  }

  /// Explicit, user-initiated connect flow (the "Connect Google Calendar"
  /// button) - for accounts that signed up with email/password and have no
  /// cached Google session to pick up silently.
  Future<bool> connect() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;
      final granted = await _googleSignIn.requestScopes([_calendarScope]);
      _connected = granted;
      return granted;
    } catch (e) {
      debugPrint('GoogleCalendarService.connect failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best effort - the in-memory flag below is what the UI relies on.
    }
    _connected = false;
  }

  /// Creates a calendar event for the swap session with a real, auto-
  /// generated Google Meet link attached, and returns that link - or null
  /// if calendar access isn't connected or the request fails, in which case
  /// the session is still proposed, just without a meeting link.
  Future<String?> createSwapEvent({
    required String title,
    required DateTime start,
    required String description,
  }) async {
    if (!_connected) return null;
    try {
      final account = _googleSignIn.currentUser;
      if (account == null) return null;
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) return null;

      final end = start.add(const Duration(hours: 1));
      final uri = Uri.parse(
        'https://www.googleapis.com/calendar/v3/calendars/primary/events'
        '?conferenceDataVersion=1',
      );
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'summary': title,
          'description': description,
          'start': {'dateTime': start.toUtc().toIso8601String()},
          'end': {'dateTime': end.toUtc().toIso8601String()},
          'conferenceData': {
            'createRequest': {
              'requestId': 'swapnio-${DateTime.now().millisecondsSinceEpoch}',
              'conferenceSolutionKey': {'type': 'hangoutsMeet'},
            },
          },
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['hangoutLink'] as String?;
      }
      debugPrint(
        'GoogleCalendarService.createSwapEvent: ${response.statusCode} ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('GoogleCalendarService.createSwapEvent failed: $e');
      return null;
    }
  }
}
