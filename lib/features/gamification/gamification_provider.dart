import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'gamification_model.dart';

/// Read-only view of a user's gamification stats. Points/badges are only
/// ever written server-side by the `badgeOnCompletedSwap` Cloud Function
/// (see functions/index.js) - writing them client-side previously allowed
/// double-awarding points by re-completing the same swap, and could only
/// ever update the current user's own doc anyway (security rules), never
/// their swap partner's.
class GamificationProvider extends ChangeNotifier {
  Gamification? _gamification;
  final String userId;

  GamificationProvider({required this.userId}) {
    _fetchGamification();
  }

  Gamification? get gamification => _gamification;

  Future<void> _fetchGamification() async {
    final doc = await FirebaseFirestore.instance.collection('gamification').doc(userId).get();
    if (doc.exists) {
      final data = doc.data()!;
      _gamification = Gamification(
        points: data['points'] ?? 0,
        level: data['level'] ?? 1,
        badges: List<String>.from(data['badges'] ?? []),
      );
    } else {
      _gamification = Gamification(points: 0, level: 1, badges: []);
    }
    notifyListeners();
  }
}
