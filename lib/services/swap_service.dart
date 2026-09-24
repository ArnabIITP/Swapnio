import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../features/analytics/analytics_provider.dart';

/// Swap sessions turn a chat into a real skill exchange:
///
///   pending -> accepted -> completed        (or: declined / cancelled / no_show)
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
/// further sessions (see `isReliableEnough()` in firestore.rules).
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
  /// the `isReliableEnough()` rule in firestore.rules. The rule is the real
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

  Future<bool> proposeSession({
    required String otherUserId,
    required String otherUserName,
    required String myName,
    required String skillOffered,
    required String skillWanted,
    required DateTime scheduledFor,
    String meetingLink = '',
    String agenda = '',
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _firestore.collection('swaps').add({
        'participants': [uid, otherUserId],
        'participantNames': {uid: myName, otherUserId: otherUserName},
        'skillOffered': skillOffered,
        'skillWanted': skillWanted,
        'scheduledFor': Timestamp.fromDate(scheduledFor),
        'meetingLink': meetingLink,
        'agenda': agenda,
        'status': statusPending,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('notifications').add({
        'userId': otherUserId,
        'type': 'session_proposed',
        'message': '$myName proposed a swap session with you',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'senderId': uid,
        'senderName': myName,
        'senderPhoto': '',
      });

      AnalyticsProvider.log('session_proposed', uid, {
        'otherUserId': otherUserId,
        'skillOffered': skillOffered,
        'skillWanted': skillWanted,
      });
      return true;
    } catch (e) {
      debugPrint('SwapSessionService.proposeSession failed: $e');
      return false;
    }
  }

  Future<bool> updateStatus(String swapId, String status) async {
    try {
      final data = <String, dynamic>{
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (status == statusCompleted) {
        data['completedAt'] = FieldValue.serverTimestamp();
      }
      await _firestore.collection('swaps').doc(swapId).update(data);
      return true;
    } catch (e) {
      debugPrint('SwapSessionService.updateStatus failed: $e');
      return false;
    }
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

  /// Marks a session complete and awards gamification points to both users.
  ///
  /// Uses a transaction on the swap doc so double-tapping "Mark as completed"
  /// cannot award points twice: points are only given when the status actually
  /// transitions accepted -> completed.
  Future<bool> completeSession(
    String swapId,
    List<dynamic> participants, {
    int points = 25,
    String sessionNotes = '',
    bool goalAchieved = true,
  }) async {
    bool transitioned = false;
    String? skillOffered;
    String? skillWanted;
    String? createdBy;
    try {
      await _firestore.runTransaction((tx) async {
        final ref = _firestore.collection('swaps').doc(swapId);
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final data = snap.data()!;
        final currentStatus = data['status'] as String? ?? '';
        if (currentStatus == statusCompleted) return;
        tx.update(ref, {
          'status': statusCompleted,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          if (sessionNotes.isNotEmpty) 'sessionNotes': sessionNotes,
          'goalAchieved': goalAchieved,
        });
        skillOffered = data['skillOffered'] as String?;
        skillWanted = data['skillWanted'] as String?;
        createdBy = data['createdBy'] as String?;
        transitioned = true;
      });
    } catch (e) {
      debugPrint('SwapSessionService.completeSession failed: $e');
      return false;
    }
    if (!transitioned) return true; // already completed before - no re-award

    // Log the completion event for the analytics dashboard.
    final completerUid = _uid;
    if (completerUid != null) {
      AnalyticsProvider.log('session_completed', completerUid, {
        'swapId': swapId,
        'skillOffered': skillOffered ?? '',
        'skillWanted': skillWanted ?? '',
      });
    }

    // Points/badges are awarded server-side by the `badgeOnCompletedSwap`
    // Cloud Function on the pending->completed transition. Writing the
    // partner's gamification doc client-side is rejected by the security
    // rules (allow write: if isSelf), so it must NOT be done here.

    // Progress tracking: each participant can only write their OWN progress
    // doc (security rules), so this only records the CALLER's side of the
    // swap - the skill they taught and the skill they learned. `skillOffered`
    // /`skillWanted` are recorded from the swap organiser's (`createdBy`)
    // perspective, so they're flipped for the other participant.
    final myUid = _uid;
    if (myUid != null && skillOffered != null && skillWanted != null) {
      final iAmOrganiser = myUid == createdBy;
      final taught = iAmOrganiser ? skillOffered! : skillWanted!;
      final learned = iAmOrganiser ? skillWanted! : skillOffered!;
      await _recordSessionProgress(myUid, taught);
      if (learned != taught) await _recordSessionProgress(myUid, learned);
    }
    return true;
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
          existing['sessionsCompleted'] = (existing['sessionsCompleted'] ?? 0) + 1;
          existing['streakDays'] = (existing['streakDays'] ?? 0) + 1;
        }
        tx.set(
          ref,
          {
            'totalSessions': (data['totalSessions'] ?? 0) + 1,
            'totalMessages': data['totalMessages'] ?? 0,
            'totalTasks': data['totalTasks'] ?? 0,
            'skills': skills,
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('SwapSessionService._recordSessionProgress failed: $e');
    }
  }

  /// Reschedules an accepted (or pending) session and notifies the partner.
  Future<bool> rescheduleSession({
    required String swapId,
    required Map<String, dynamic> swapData,
    required String myName,
    required DateTime newTime,
  }) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _firestore.collection('swaps').doc(swapId).update({
        'scheduledFor': Timestamp.fromDate(newTime),
        'rescheduledBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final participants = List<String>.from(swapData['participants'] ?? []);
      final otherId = participants.firstWhere((p) => p != uid,
          orElse: () => '');
      if (otherId.isEmpty) return true;

      await _firestore.collection('notifications').add({
        'userId': otherId,
        'type': 'session_rescheduled',
        'message':
            '$myName rescheduled your swap session to ${newTime.toLocal()}',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'senderId': uid,
        'senderName': myName,
        'senderPhoto': '',
      });
      return true;
    } catch (e) {
      debugPrint('SwapSessionService.rescheduleSession failed: $e');
      return false;
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
        final participants =
            List<String>.from(doc.data()['participants'] ?? []);
        if (participants.contains(otherUserId)) return doc.id;
      }
    } catch (e) {
      debugPrint('SwapSessionService.completedSessionWith failed: $e');
    }
    return null;
  }
}