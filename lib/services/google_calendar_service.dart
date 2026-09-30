import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Connects the member's Google Calendar to Swapnio's server (see
/// functions/calendar.js).
///
/// Google sign-in here asks for the calendar scopes and returns a one-time
/// server auth code; the server swaps it for lasting access, stored
/// encrypted, so it can create each accepted session's event (with a Meet
/// link and both people as guests), move it on reschedule and delete it on
/// cancel - even while this phone is off. Nothing calendar-related runs on
/// the device any more.
class GoogleCalendarService {
  GoogleCalendarService._();

  static final GoogleCalendarService instance = GoogleCalendarService._();

  /// The Firebase project's web OAuth client - the server exchanges the
  /// auth code against it.
  static const String _serverClientId =
      '924792323555-ludfh213atbvrhtclsmj6of0c8s5o3rl.apps.googleusercontent.com';
  static const String eventsScope =
      'https://www.googleapis.com/auth/calendar.events';
  static const String freeBusyScope =
      'https://www.googleapis.com/auth/calendar.freebusy';

  /// Codes the server puts at the start of a scheduling error when a
  /// connection is missing: yours, or the other person's.
  static const String requiredMarker = 'CALENDAR_REQUIRED';
  static const String partnerMarker = 'PARTNER_CALENDAR_REQUIRED';

  final _functions = FirebaseFunctions.instance;

  /// Everything Swapnio needs from Google, asked for in ONE consent screen:
  /// calendar events (with Meet links) and free/busy.
  GoogleSignIn _signIn() => GoogleSignIn(
    scopes: ['email', eventsScope, freeBusyScope],
    serverClientId: _serverClientId,
    // Android: always return a code the server can trade for a refresh
    // token, even if this account granted access before.
    forceCodeForRefreshToken: true,
  );

  /// The single Connect button. Returns null on success, or a message.
  Future<String?> connect() async {
    final google = _signIn();
    try {
      final account = await google.signIn();
      if (account == null) return 'Connection cancelled.';
      final code = account.serverAuthCode;
      if (code == null || code.isEmpty) {
        return "Google didn't return a sign-in code. Please try again.";
      }
      await _functions.httpsCallable('connectGoogleCalendar').call({
        'code': code,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Could not connect Google Calendar.';
    } catch (e) {
      debugPrint('GoogleCalendarService.connect failed: $e');
      return 'Could not connect Google Calendar. Please try again.';
    } finally {
      // The server holds the access now; no need to keep a device session.
      await google.signOut().catchError((_) => null);
    }
  }

  Future<String?> disconnect() async {
    try {
      await _functions.httpsCallable('disconnectGoogleCalendar').call();
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Could not disconnect.';
    } catch (_) {
      return 'Could not disconnect. Check your connection.';
    }
  }

  Future<({bool connected, String email, bool freeBusy, bool shareBusy})>
  status() async {
    try {
      final r = await _functions.httpsCallable('calendarStatus').call();
      final m = Map<String, dynamic>.from(r.data as Map);
      return (
        connected: m['connected'] == true,
        email: (m['email'] as String?) ?? '',
        freeBusy: m['freeBusy'] == true,
        shareBusy: m['shareBusy'] == true,
      );
    } catch (e) {
      debugPrint('GoogleCalendarService.status failed: $e');
      return (connected: false, email: '', freeBusy: false, shareBusy: false);
    }
  }

  Future<String?> setBusySharing(bool share) async {
    try {
      await _functions.httpsCallable('setBusySharing').call({'share': share});
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Could not change sharing.';
    } catch (_) {
      return 'Could not change sharing. Check your connection.';
    }
  }
}
