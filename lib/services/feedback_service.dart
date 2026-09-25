import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// In-app feedback: a lightweight, always-available "how's the app going"
/// channel, separate from [SafetyService]'s report/block flow (which is
/// about *another user's* behaviour) and from [ComplaintService] (a specific
/// issue someone wants resolved). Feedback is just a star rating plus a
/// note, always attributed to the signed-in user so admins know who sent it.
///
/// Data model
///   feedback/{autoId} -> { userId, userName, userEmail, message, rating,
///                          createdAt, status: 'new' | 'reviewed' }
class FeedbackService {
  FeedbackService._();

  static final FeedbackService instance = FeedbackService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> submitFeedback({
    required String message,
    int rating = 0,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _firestore.collection('feedback').add({
        'userId': user.uid,
        'userName': user.displayName ?? 'Swapnio user',
        'userEmail': user.email ?? '',
        'message': message,
        'rating': rating,
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('FeedbackService.submitFeedback failed: $e');
      return false;
    }
  }

  /// Live, real-time feed for the admin dashboard - newest first.
  Stream<QuerySnapshot> feedbackStream() {
    return _firestore
        .collection('feedback')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  Future<bool> markReviewed(String feedbackId) async {
    try {
      await _firestore.collection('feedback').doc(feedbackId).update({
        'status': 'reviewed',
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('FeedbackService.markReviewed failed: $e');
      return false;
    }
  }
}
