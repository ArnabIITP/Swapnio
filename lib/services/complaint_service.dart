import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Complaints: a specific issue a user wants moderators to actually resolve
/// (a bug, a bad experience, something that fell through the cracks) - as
/// opposed to [FeedbackService] (general sentiment) or [SafetyService]'s
/// report flow (flagging another user's behaviour). Each complaint carries
/// the reporter's contact email so admins can follow up directly, and lives
/// in its own admin route so it's not buried among user-vs-user reports.
///
/// Data model
///   complaints/{autoId} -> { userId, userName, userEmail, subject,
///                            description, status: 'open' | 'in_progress' |
///                            'resolved', createdAt, resolvedAt, resolutionNote }
class ComplaintService {
  ComplaintService._();

  static final ComplaintService instance = ComplaintService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String statusOpen = 'open';
  static const String statusInProgress = 'in_progress';
  static const String statusResolved = 'resolved';

  Future<bool> submitComplaint({
    required String subject,
    required String description,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      await _firestore.collection('complaints').add({
        'userId': user.uid,
        'userName': user.displayName ?? 'Swapnio user',
        'userEmail': user.email ?? '',
        'subject': subject,
        'description': description,
        'status': statusOpen,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('ComplaintService.submitComplaint failed: $e');
      return false;
    }
  }

  /// Live feed for the admin Complaints page, newest first.
  Stream<QuerySnapshot> complaintsStream() {
    return _firestore
        .collection('complaints')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();
  }

  Future<bool> updateStatus(
    String complaintId,
    String status, {
    String resolutionNote = '',
  }) async {
    try {
      await _firestore.collection('complaints').doc(complaintId).update({
        'status': status,
        if (status == statusResolved) 'resolvedAt': FieldValue.serverTimestamp(),
        if (resolutionNote.isNotEmpty) 'resolutionNote': resolutionNote,
      });
      return true;
    } catch (e) {
      debugPrint('ComplaintService.updateStatus failed: $e');
      return false;
    }
  }
}
