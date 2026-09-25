import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Chat-room level actions that don't belong in [SwapSessionService] or
/// [SafetyService]: right now, just unmatching.
class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Ends a match: the room is flagged `unmatched` rather than deleted, so
  /// history isn't destroyed and moderators can still see what was said if a
  /// report follows. Both sides stop seeing it in their Chats tab and can no
  /// longer send new messages (enforced in the UI; the room doc itself stays
  /// readable to both participants under the existing security rules).
  /// Any pending like/request between the two is cleared too, so unmatching
  /// doesn't leave a stale request sitting in either inbox.
  Future<bool> unmatch(String chatRoomId, String otherUserId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      await _firestore.collection('chatRooms').doc(chatRoomId).update({
        'unmatched': true,
        'unmatchedBy': uid,
        'unmatchedAt': FieldValue.serverTimestamp(),
      });
      await _removePendingRequestsBetween(uid, otherUserId);
      return true;
    } catch (e) {
      debugPrint('ChatService.unmatch failed: $e');
      return false;
    }
  }

  Future<void> _removePendingRequestsBetween(String uid, String otherUserId) async {
    try {
      final sent = await _firestore
          .collection('swipeRequests')
          .where('fromUserId', isEqualTo: uid)
          .where('toUserId', isEqualTo: otherUserId)
          .get();
      final received = await _firestore
          .collection('swipeRequests')
          .where('fromUserId', isEqualTo: otherUserId)
          .where('toUserId', isEqualTo: uid)
          .get();
      for (final doc in [...sent.docs, ...received.docs]) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('ChatService._removePendingRequestsBetween failed: $e');
    }
  }
}
