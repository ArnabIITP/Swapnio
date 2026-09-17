import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verification_model.dart';

class VerificationProvider extends ChangeNotifier {
  Verification? _verification;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Verification? get verification => _verification;

  VerificationProvider() {
    _fetchVerification();
  }

  Future<void> _fetchVerification() async {
    final user = _auth.currentUser;
    if (user != null) {
      _verification = Verification(
        emailVerified: user.emailVerified,
        phoneVerified: user.phoneNumber != null,
      );
    } else {
      _verification = Verification(emailVerified: false, phoneVerified: false);
    }
    notifyListeners();
  }

  /// Returns true if the verification email was actually sent.
  Future<bool> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return false;
    try {
      await user.sendEmailVerification();
      return true;
    } catch (_) {
      return false;
    }
  }

  // For phone verification, use Firebase Auth's phone verification flow in the UI
  Future<void> reload() async {
    await _auth.currentUser?.reload();
    await _fetchVerification();
  }
}
