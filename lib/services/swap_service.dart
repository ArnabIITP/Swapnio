import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../features/analytics/analytics_provider.dart';

/// Swap sessions turn a chat into a real skill exchange:
///
///   pending -> accepted -> completed        (or: declined / cancelled / no_show)
///
/// Proposing, answering, cancelling and rescheduling run on the server
/// (functions/schedule.js) so both people's calendars are checked; only a
/// no-show report is still a direct write.
///
/// Data model (collection `swaps`)
///   participants:   [uidA, uidB]
///   participantNames: { uid: name }
///   skillOffered:   what the organiser will teach
///   skillWanted:    what the organiser wants to learn
///   scheduledFor:   Timestamp of the agreed session
///   status:         'pending' | 'accepted' | 'declined' | 'completed' | 'no_show'
///   createdBy:      uid
///   createdAt / completedAt
///   noShowReportedBy: uid of whoever flagged the no-show (accountability)
///
/// Only a *completed* session unlocks a rating - enforced both here and in
/// `firestore.rules` (ratings must reference a completed swap). A no-show
/// deliberately does NOT transition through `completed` - it must never
/// award points or unlock a rating for a session that didn't happen.
/// A user's session attendance record, used to decide whether they may book
/// further sessions (enforced by proposeSession in functions/schedule.js).
class ReliabilityStatus {
  final int attended;
  final int noShows;

  const ReliabilityStatus({required this.attended, required this.noShows});

  int get total => attended + noShows;

  /// Percentage of resolved sessions the user actually turned up for.
  int get showUpRate => total == 0 ? 100 : ((attended / total) * 100).round();

  /// New accounts get the benefit of the doubt until they have a real record.
  bool get canBookSessions => total < 3 || attended * 2 >= total;
}

class SwapSessionService {
  SwapSessionService._();

  static final SwapSessionService instance = SwapSessionService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String statusPending = 'pending';
  static const String statusAccepted = 'accepted';
  static const String statusDeclined = 'declined';
  static const String statusCompleted = 'completed';
  static const String statusNoShow = 'no_show';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Whether the current user is still allowed to book sessions, mirroring
  /// the check in proposeSession (functions/schedule.js). The server is the real
  /// gate - this exists so the UI can explain *why* rather than surfacing a
  /// raw permission-denied error.
  Future<ReliabilityStatus> myReliability() async {
    final uid = _uid;
    if (uid == null) return const ReliabilityStatus(attended: 0, noShows: 0);
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final data = doc.data() ?? {};
      return ReliabilityStatus(
        attended: (data['sessionsAttended'] as num?)?.toInt() ?? 0,
        noShows: (data['noShowCount'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('SwapSessionService.myReliability failed: $e');
      // Fail open - the security rule still enforces the real restriction.
      return const ReliabilityStatus(attended: 0, noShows: 0);
    }
  }

  /// Live list of the current user's sessions, newest first.
  Stream<QuerySnapshot> mySessionsStream() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _firestore
        .collection('swaps')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  static const String statusCancelled = 'cancelled';

  /// Planned session lengths, in minutes (server-enforced).
  static const List<int> plannedLengths = [30, 45, 60, 90];

  /// Accepted sessions can't be cancelled without a reason this close to
  /// the start; a running one can be cancelled only in its first 30 minutes.
  static const int lateCancelHours = 2;
  static const int runningCancelMinutes = 30;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  int get _tz => DateTime.now().timeZoneOffset.inMinutes * -1;

  Future<SessionResult> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _functions.httpsCallable(name).call({
        ...data,
        'tzOffset': _tz,
      });
      final map = Map<String, dynamic>.from((r.data as Map?) ?? const {});
      if (map['needsConfirm'] == true) {
        return SessionResult.warn(
          List<String>.from(map['warnings'] ?? const []),
        );
      }
      return SessionResult.ok(map);
    } on FirebaseFunctionsException catch (e) {
      final msg = e.message ?? 'Something went wrong. Please try again.';
      final m = RegExp(r'^([A-Z_]+): (.*)$', dotAll: true).firstMatch(msg);
      return m == null
          ? SessionResult.error(msg)
          : SessionResult.error(m.group(2)!, code: m.group(1));
    } catch (e) {
      debugPrint('SwapSessionService.$name failed: $e');
      return SessionResult.error(
        'Could not reach Swapnio. Check your connection.',
      );
    }
  }

  /// Proposes a session. [type] is 'swap' (both teach), 'teach' (only you
  /// teach) or 'learn' (only you learn). A clash with a pending session
  /// comes back as warnings - call again with [force] to go ahead; a clash
  /// with an accepted session is an error.
  Future<SessionResult> proposeSession({
    required String otherUserId,
    required String type,
    required String skillOffered,
    required String skillWanted,
    required DateTime scheduledFor,
    required int plannedMinutes,
    String agenda = '',
    bool force = false,
  }) async {
    final r = await _call('proposeSession', {
      'otherUserId': otherUserId,
      'sessionType': type,
      'skillOffered': skillOffered,
      'skillWanted': skillWanted,
      'scheduledFor': scheduledFor.millisecondsSinceEpoch,
      'plannedMinutes': plannedMinutes,
      'agenda': agenda,
      'force': force,
    });
    if (r.isOk) {
      AnalyticsProvider.log('session_proposed', _uid ?? '', {
        'otherUserId': otherUserId,
        'sessionType': type,
      });
    }
    return r;
  }

  /// Accepts or declines a proposal (only the invited person can).
  Future<SessionResult> respond(String swapId, {required bool accept}) =>
      _call('respondSession', {'swapId': swapId, 'accept': accept});

  /// Cancels a session. A reason is optional, except within
  /// [lateCancelHours] of the start.
  Future<SessionResult> cancel(String swapId, {String reason = ''}) =>
      _call('cancelSession', {'swapId': swapId, 'reason': reason});

  /// Asks to move a session (moves it straight away if it's still your own
  /// unanswered proposal). The current time stays booked until the other
  /// person accepts.
  Future<SessionResult> requestReschedule(
    String swapId, {
    required DateTime newTime,
    int? plannedMinutes,
    bool force = false,
  }) => _call('requestReschedule', {
    'swapId': swapId,
    'scheduledFor': newTime.millisecondsSinceEpoch,
    if (plannedMinutes != null) 'plannedMinutes': plannedMinutes,
    'force': force,
  });

  Future<SessionResult> respondReschedule(
    String swapId, {
    required bool accept,
  }) => _call('respondReschedule', {'swapId': swapId, 'accept': accept});

  /// Busy blocks between [from] and [to]: mine (labelled) and, with
  /// [otherUserId], theirs (unlabelled).
  Future<BusyTimes> busyTimes({
    required DateTime from,
    required DateTime to,
    String? otherUserId,
    String? excludeSwapId,
  }) async {
    final r = await _call('busyTimes', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
      if (otherUserId != null) 'otherUserId': otherUserId,
      if (excludeSwapId != null) 'excludeSwapId': excludeSwapId,
    });
    if (!r.isOk) return const BusyTimes([], []);
    List<BusyBlock> parse(Object? v) => [
      for (final b in (v as List? ?? const []))
        BusyBlock.fromMap(Map<String, dynamic>.from(b as Map)),
    ];
    return BusyTimes(parse(r.data['mine']), parse(r.data['theirs']));
  }

  /// My own cancellations in the last 30 days (never shown to others).
  Future<({int total, int late})> myCancellationStats() async {
    final r = await _call('myCancellationStats', {});
    return (
      total: (r.data['total'] as num?)?.toInt() ?? 0,
      late: (r.data['late'] as num?)?.toInt() ?? 0,
    );
  }

  /// Flags a scheduled session as a no-show instead of completing it - the
  /// session simply never happened, so it must not award points or unlock a
  /// rating the way `completeSession` does.
  Future<bool> markNoShow(String swapId) async {
    final uid = _uid;
    try {
      await _firestore.collection('swaps').doc(swapId).update({
        'status': statusNoShow,
        'noShowReportedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('SwapSessionService.markNoShow failed: $e');
      return false;
    }
  }

  /// Minimum length before a session can be completed. The
  /// completeSwapSession Cloud Function is the real gate; this is for the UI.
  static const int minSessionMinutes = 30;

  /// Check-in opens this long before the scheduled start (server-enforced).
  static const int checkInEarlyMinutes = 15;

  /// Checks the current user in. The session's clock starts on the server
  /// once both participants have checked in. Returns an error message, or
  /// null on success.
  Future<String?> checkIn(String swapId) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('checkInSession').call({
        'swapId': swapId,
      });
      AnalyticsProvider.log('session_checkin', _uid ?? '', {'swapId': swapId});
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Could not check in. Please try again.';
    } catch (e) {
      debugPrint('SwapSessionService.checkIn failed: $e');
      return 'Could not check in. Please try again.';
    }
  }

  /// Confirms the session happened. Both participants must confirm before it
  /// counts - there is no automatic confirmation - the server enforces
  /// the check-ins and the minimum length and awards points and badges.
  Future<({bool ok, bool completed, String? error})> confirmCompletion(
    String swapId, {
    String sessionNotes = '',
    bool goalAchieved = true,
    Map<String, dynamic>? swapData,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('completeSwapSession')
          .call({
            'swapId': swapId,
            'notes': sessionNotes,
            'goalAchieved': goalAchieved,
          });
      final completed = (result.data as Map?)?['completed'] == true;
      final uid = _uid;
      if (uid != null) {
        AnalyticsProvider.log('session_completed', uid, {
          'swapId': swapId,
          'confirmedByBoth': completed,
        });
        // Progress Dashboard bookkeeping (self-written, not trusted by the
        // passport): record this user's side of the swap.
        if (swapData != null) {
          final offered = swapData['skillOffered'] as String?;
          final wanted = swapData['skillWanted'] as String?;
          if (offered != null && wanted != null) {
            final iAmOrganiser = uid == swapData['createdBy'];
            final taught = iAmOrganiser ? offered : wanted;
            final learned = iAmOrganiser ? wanted : offered;
            await _recordSessionProgress(uid, taught);
            if (learned != taught) await _recordSessionProgress(uid, learned);
          }
        }
      }
      return (ok: true, completed: completed, error: null);
    } on FirebaseFunctionsException catch (e) {
      return (ok: false, completed: false, error: e.message);
    } catch (e) {
      debugPrint('SwapSessionService.confirmCompletion failed: $e');
      return (ok: false, completed: false, error: null);
    }
  }

  /// Increments the session count for one skill on the current user's own
  /// `progress/{uid}` document, creating the entry if it doesn't exist yet.
  Future<void> _recordSessionProgress(String userId, String skillName) async {
    try {
      final ref = _firestore.collection('progress').doc(userId);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data() ?? <String, dynamic>{};
        final skills = (data['skills'] as List<dynamic>? ?? [])
            .map((s) => Map<String, dynamic>.from(s as Map))
            .toList();
        final existing = skills.firstWhere(
          (s) => s['skillName'] == skillName,
          orElse: () => <String, dynamic>{},
        );
        if (existing.isEmpty) {
          skills.add({
            'skillName': skillName,
            'sessionsCompleted': 1,
            'avgQuizScore': 0.0,
            'quizCount': 0,
            'streakDays': 1,
            'peerRating': 0.0,
            'peerRatingCount': 0,
          });
        } else {
          existing['sessionsCompleted'] =
              (existing['sessionsCompleted'] ?? 0) + 1;
          existing['streakDays'] = (existing['streakDays'] ?? 0) + 1;
        }
        tx.set(ref, {
          'totalSessions': (data['totalSessions'] ?? 0) + 1,
          'totalMessages': data['totalMessages'] ?? 0,
          'totalTasks': data['totalTasks'] ?? 0,
          'skills': skills,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('SwapSessionService._recordSessionProgress failed: $e');
    }
  }

  /// The id of a completed session between the current user and [otherUserId],
  /// or null when the two have not finished a swap yet.
  Future<String?> completedSessionWith(String otherUserId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final snapshot = await _firestore
          .collection('swaps')
          .where('participants', arrayContains: uid)
          .where('status', isEqualTo: statusCompleted)
          .limit(20)
          .get();
      for (final doc in snapshot.docs) {
        final participants = List<String>.from(
          doc.data()['participants'] ?? [],
        );
        if (participants.contains(otherUserId)) return doc.id;
      }
    } catch (e) {
      debugPrint('SwapSessionService.completedSessionWith failed: $e');
    }
    return null;
  }
}

/// The outcome of a scheduling call: done, needs the caller to confirm
/// warnings (a pending clash), or failed with a message to show.
class SessionResult {
  final Map<String, dynamic> data;
  final List<String> warnings;
  final String? error;

  /// Machine-readable reason, e.g. CALENDAR_REQUIRED.
  final String? code;

  const SessionResult._(this.data, this.warnings, this.error, [this.code]);

  factory SessionResult.ok(Map<String, dynamic> data) =>
      SessionResult._(data, const [], null);
  factory SessionResult.warn(List<String> warnings) =>
      SessionResult._(const {}, warnings, null);
  factory SessionResult.error(String message, {String? code}) =>
      SessionResult._(const {}, const [], message, code);

  bool get isOk => error == null && warnings.isEmpty;
  bool get needsConfirm => warnings.isNotEmpty;
}

/// A block of time that's taken. [label] is set only for my own sessions.
class BusyBlock {
  final DateTime start;
  final DateTime end;
  final String kind;
  final String? label;

  const BusyBlock(this.start, this.end, this.kind, this.label);

  bool get isFirm => kind == 'accepted' || kind == 'external';

  factory BusyBlock.fromMap(Map<String, dynamic> m) => BusyBlock(
    DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
    DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
    (m['kind'] as String?) ?? 'accepted',
    m['label'] as String?,
  );
}

class BusyTimes {
  final List<BusyBlock> mine;
  final List<BusyBlock> theirs;

  const BusyTimes(this.mine, this.theirs);
}
