import 'dart:io';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// What a scanned code turned out to be.
enum ScanOutcome {
  profile,
  ownCode,
  privateProfile,
  resetCode,
  notSwapnio,
  notFound,
}

class ScanResult {
  final ScanOutcome outcome;
  final String? userId;
  final String? passportNumber;

  const ScanResult(this.outcome, {this.userId, this.passportNumber});
}

/// Profile QR codes and the referral program built on them.
///
/// A profile QR holds a Play Store link for Swapnio with the owner's
/// passport number (and QR version) as the install referrer, e.g.
/// `...details?id=com.swapnio.app&referrer=swp%3DSWP-LUVO-PVGM.0`.
///  - Scanned in Swapnio's own scanner it opens that profile.
///  - Scanned with any phone camera by someone without the app it opens the
///    Play Store, and after install Google hands the referrer back to the
///    app, which claims the referral (see [claimInstallReferrerOnce]).
/// Passport numbers are unique (reserved server-side), so every QR is too.
/// Resetting bumps `qrVersion`, which makes older screenshots stop opening
/// the profile.
class ReferralService {
  ReferralService._();

  static final ReferralService instance = ReferralService._();

  static const String _packageName = 'com.swapnio.app';
  static final RegExp _codePattern = RegExp(
    r'SWP-[A-Z0-9]{4}-[A-Z0-9]{4}(?:\.(\d+))?',
  );

  final _firestore = FirebaseFirestore.instance;

  String qrPayload(String passportNumber, int version) {
    final referrer = Uri.encodeComponent('swp=$passportNumber.$version');
    return 'https://play.google.com/store/apps/details?id=$_packageName&referrer=$referrer';
  }

  /// The passport number and version inside a scanned string, if any.
  ({String passport, int version})? parse(String raw) {
    final decoded = Uri.decodeFull(raw).toUpperCase();
    final match = _codePattern.firstMatch(decoded);
    if (match == null) return null;
    final passport = match.group(0)!.split('.').first;
    return (
      passport: passport,
      version: int.tryParse(match.group(1) ?? '') ?? 0,
    );
  }

  /// Works out whose profile a scanned code opens.
  Future<ScanResult> resolve(String raw) async {
    final code = parse(raw);
    if (code == null) return const ScanResult(ScanOutcome.notSwapnio);
    final me = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap = await _firestore
          .collection('users')
          .where('passportNumber', isEqualTo: code.passport)
          .limit(1)
          .get();
      if (snap.docs.isEmpty)
        return ScanResult(ScanOutcome.notFound, passportNumber: code.passport);
      final doc = snap.docs.first;
      if (doc.id == me) return ScanResult(ScanOutcome.ownCode, userId: doc.id);
      final current = (doc.data()['qrVersion'] as num?)?.toInt() ?? 0;
      if (current != code.version) {
        return ScanResult(ScanOutcome.resetCode, passportNumber: code.passport);
      }
      return ScanResult(
        ScanOutcome.profile,
        userId: doc.id,
        passportNumber: code.passport,
      );
    } on FirebaseException catch (e) {
      // The users rule hides private profiles, so the lookup is refused.
      if (e.code == 'permission-denied') {
        return ScanResult(
          ScanOutcome.privateProfile,
          passportNumber: code.passport,
        );
      }
      rethrow;
    }
  }

  /// Makes the current user's old QR codes stop opening their profile.
  Future<void> resetMyQr() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'qrVersion': FieldValue.increment(1),
    });
  }

  /// Records who invited the current user (server-side checks decide - see
  /// functions/referrals.js). Returns the inviter's name, or throws with a
  /// message the UI can show.
  Future<String> claim(String rawCode, {String source = 'install'}) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('claimReferral')
          .call({'code': rawCode, 'source': source});
      return (Map<String, dynamic>.from(result.data as Map))['referrerName']
              as String? ??
          '';
    } on FirebaseFunctionsException catch (e) {
      throw e.message ?? 'Could not record the invite.';
    }
  }

  /// On Android, reads the Play Store install referrer once per account and
  /// claims the referral if the app was installed from someone's QR. Safe to
  /// call on every launch.
  Future<void> claimInstallReferrerOnce() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final ref = _firestore.collection('users').doc(uid);
      final doc = await ref.get();
      final data = doc.data();
      if (data == null ||
          data['referredBy'] != null ||
          data['installReferrerChecked'] == true) {
        return;
      }
      final details = await AndroidPlayInstallReferrer.installReferrer;
      final raw = details.installReferrer ?? '';
      await ref.update({'installReferrerChecked': true});
      if (parse(raw) != null) await claim(raw);
    } catch (e) {
      debugPrint('ReferralService.claimInstallReferrerOnce: $e');
    }
  }

  /// Whether the signed-in account could still be credited to an inviter:
  /// on its first day and not referred yet. The server re-checks everything
  /// (including "no completed sessions"); this only avoids pointless calls.
  Future<bool> isFirstDayUnreferred() async {
    final user = FirebaseAuth.instance.currentUser;
    final created = user?.metadata.creationTime;
    if (user == null || created == null) return false;
    if (DateTime.now().difference(created) > const Duration(hours: 24))
      return false;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    return doc.data()?['referredBy'] == null;
  }

  /// People the current user invited, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> myReferrals() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return _firestore
        .collection('referrals')
        .where('referrerId', isEqualTo: uid)
        .snapshots();
  }
}
