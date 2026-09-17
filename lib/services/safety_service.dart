import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Trust & safety helpers: blocking abusive users and reporting them.
///
/// Data model
///   blocks/{autoId}  -> { userId, blockedUserId, blockedUserName, createdAt }
///   reports/{autoId} -> { reporterId, reportedUserId, reason, details,
///                         status: 'open' | 'dismissed' | 'actioned', createdAt }
///
/// Both directions are honoured when filtering the swipe deck and the home
/// feed: a user is hidden if *I* blocked them or if *they* blocked me.
class SafetyService {
  SafetyService._();

  static final SafetyService instance = SafetyService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// The reasons offered in the report dialog.
  static const List<String> reportReasons = [
    'Inappropriate behaviour',
    'Spam or advertising',
    'Fake profile',
    'Harassment',
    'Other',
  ];

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('SafetyService used while signed out');
    }
    return user.uid;
  }

  /// Returns every user id that should be hidden from the current user:
  /// ids they blocked plus ids that blocked them.
  Future<Set<String>> hiddenUserIds() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return <String>{};

    final hidden = <String>{};
    try {
      final blockedByMe = await _firestore
          .collection('blocks')
          .where('userId', isEqualTo: user.uid)
          .get();
      for (final doc in blockedByMe.docs) {
        final id = doc.data()['blockedUserId'] as String?;
        if (id != null && id.isNotEmpty) hidden.add(id);
      }

      final blockedMe = await _firestore
          .collection('blocks')
          .where('blockedUserId', isEqualTo: user.uid)
          .get();
      for (final doc in blockedMe.docs) {
        final id = doc.data()['userId'] as String?;
        if (id != null && id.isNotEmpty) hidden.add(id);
      }
    } catch (e) {
      debugPrint('SafetyService.hiddenUserIds failed: $e');
    }
    return hidden;
  }

  Future<bool> isBlocked(String otherUserId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final snapshot = await _firestore
          .collection('blocks')
          .where('userId', isEqualTo: user.uid)
          .where('blockedUserId', isEqualTo: otherUserId)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('SafetyService.isBlocked failed: $e');
      return false;
    }
  }

  /// Live stream of the ids the current user has blocked.
  Stream<Set<String>> blockedUsersStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(<String>{});
    return _firestore
        .collection('blocks')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => doc.data()['blockedUserId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  /// Blocks [otherUserId] and clears any pending like requests between the two
  /// users so a stale match cannot survive the block.
  Future<bool> blockUser(String otherUserId, {String? displayName}) async {
    try {
      await _firestore.collection('blocks').add({
        'userId': _uid,
        'blockedUserId': otherUserId,
        'blockedUserName': displayName ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _removePendingRequestsBetween(otherUserId);
      return true;
    } catch (e) {
      debugPrint('SafetyService.blockUser failed: $e');
      return false;
    }
  }

  Future<bool> unblockUser(String blockDocId) async {
    try {
      await _firestore.collection('blocks').doc(blockDocId).delete();
      return true;
    } catch (e) {
      debugPrint('SafetyService.unblockUser failed: $e');
      return false;
    }
  }

  /// Removes the block for [otherUserId] if one exists.
  Future<bool> unblockByUserId(String otherUserId) async {
    try {
      final snapshot = await _firestore
          .collection('blocks')
          .where('userId', isEqualTo: _uid)
          .where('blockedUserId', isEqualTo: otherUserId)
          .get();
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
      }
      return true;
    } catch (e) {
      debugPrint('SafetyService.unblockByUserId failed: $e');
      return false;
    }
  }

  Future<bool> reportUser({
    required String reportedUserId,
    required String reason,
    String details = '',
  }) async {
    try {
      await _firestore.collection('reports').add({
        'reporterId': _uid,
        'reportedUserId': reportedUserId,
        'reason': reason,
        'details': details,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('SafetyService.reportUser failed: $e');
      return false;
    }
  }

  Future<void> _removePendingRequestsBetween(String otherUserId) async {
    try {
      final sent = await _firestore
          .collection('swipeRequests')
          .where('fromUserId', isEqualTo: _uid)
          .where('toUserId', isEqualTo: otherUserId)
          .get();
      final received = await _firestore
          .collection('swipeRequests')
          .where('fromUserId', isEqualTo: otherUserId)
          .where('toUserId', isEqualTo: _uid)
          .get();
      for (final doc in [...sent.docs, ...received.docs]) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('SafetyService._removePendingRequestsBetween failed: $e');
    }
  }
}