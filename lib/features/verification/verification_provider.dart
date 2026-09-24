import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'verification_model.dart';

class VerificationProvider extends ChangeNotifier {
  Verification? _verification;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Phone verification state
  bool _phoneVerificationInProgress = false;
  bool _codeSent = false;
  String? _verificationId;
  int? _resendToken;
  String? _verificationError;

  Verification? get verification => _verification;
  bool get phoneVerificationInProgress => _phoneVerificationInProgress;
  bool get codeSent => _codeSent;
  String? get verificationError => _verificationError;

  VerificationProvider() {
    _fetchVerification();
  }

  Future<void> _fetchVerification() async {
    final user = _auth.currentUser;
    if (user != null) {
      _verification = Verification(
        emailVerified: user.emailVerified,
        phoneVerified: user.phoneNumber != null && user.phoneNumber!.isNotEmpty,
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

  /// Starts the Firebase phone verification flow.
  /// Sends an SMS with an OTP code to [phoneNumber].
  Future<void> startPhoneVerification(String phoneNumber) async {
    _phoneVerificationInProgress = true;
    _codeSent = false;
    _verificationError = null;
    _verificationId = null;
    notifyListeners();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: _resendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification (e.g. on Android with auto-retrieval).
          await _linkPhoneCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          _phoneVerificationInProgress = false;
          _verificationError = e.message ?? 'Phone verification failed.';
          notifyListeners();
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _codeSent = true;
          _phoneVerificationInProgress = false;
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      _phoneVerificationInProgress = false;
      _verificationError = 'Could not start phone verification: $e';
      notifyListeners();
    }
  }

  /// Verifies the SMS code the user entered.
  Future<bool> verifyOTP(String smsCode) async {
    if (_verificationId == null) {
      _verificationError = 'No verification in progress. Send a code first.';
      notifyListeners();
      return false;
    }

    _phoneVerificationInProgress = true;
    _verificationError = null;
    notifyListeners();

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      return await _linkPhoneCredential(credential);
    } catch (e) {
      _phoneVerificationInProgress = false;
      _verificationError = 'Invalid code. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Links the phone credential to the current user account.
  Future<bool> _linkPhoneCredential(PhoneAuthCredential credential) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _verificationError = 'Not signed in.';
        _phoneVerificationInProgress = false;
        notifyListeners();
        return false;
      }

      // If the user already has a phone number linked, update it.
      // Otherwise, link the new credential.
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        await user.updatePhoneNumber(credential);
      } else {
        await user.linkWithCredential(credential);
      }

      // Refresh verification status.
      _codeSent = false;
      _phoneVerificationInProgress = false;
      _verificationId = null;
      _verificationError = null;
      await _fetchVerification();
      return true;
    } on FirebaseAuthException catch (e) {
      _phoneVerificationInProgress = false;
      if (e.code == 'credential-already-in-use') {
        _verificationError = 'This phone number is linked to another account.';
      } else {
        _verificationError = e.message ?? 'Phone verification failed.';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _phoneVerificationInProgress = false;
      _verificationError = 'Phone verification failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Resets phone verification state (e.g. user cancels).
  void resetPhoneVerification() {
    _phoneVerificationInProgress = false;
    _codeSent = false;
    _verificationId = null;
    _verificationError = null;
    notifyListeners();
  }

  Future<void> reload() async {
    await _auth.currentUser?.reload();
    await _fetchVerification();
  }
}
