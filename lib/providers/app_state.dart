import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../features/analytics/analytics_provider.dart';

class AppState extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>['email'],
  );
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  UserModel? _currentUser;
  bool _loading = false;
  String _error = '';
  int _unreadNotifications = 0;
  ThemeMode _themeMode = ThemeMode.light;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _notificationSubscription;

  UserModel? get currentUser => _currentUser;
  bool get loading => _loading;
  String get error => _error;
  int get unreadNotifications => _unreadNotifications;
  ThemeMode get themeMode => _themeMode;

  /// True when the profile still lacks any offered skill, so the UI can send
  /// the user through [ProfileSetupPage] once after signing in.
  bool get needsSetup =>
      _currentUser != null && _currentUser!.skillsOffered.isEmpty;

  /// True when this account has never recorded accepting the Terms &
  /// Privacy Policy and confirming it is 18+ - gates entry to the app ahead
  /// of [needsSetup], so nobody reaches onboarding without having agreed.
  /// Deliberately keyed off the persisted flag rather than "is this a brand
  /// new account": an account that signed up before this gate existed, or
  /// that backed out of the consent screen last time, must still be asked
  /// on its next sign-in rather than slipping through as "not new".
  bool get needsLegalConsent =>
      _currentUser != null &&
      !(_currentUser!.acceptedTerms && _currentUser!.ageConfirmed);

  AppState() {
    initializeUser();
  }

  // Listen to auth state changes and update user accordingly
  void initializeUser() {
    _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        await _fetchUserData(user.uid);
        _listenToNotificationCount(user.uid);
        await _fetchAppearanceSettings(user.uid);
        // Register this device for push notifications (best effort).
        NotificationService.instance.init(user.uid);
      } else {
        _loading = false;
        _currentUser = null;
        _unreadNotifications = 0;
        _notificationSubscription?.cancel();
        _notificationSubscription = null;
        notifyListeners();
      }
    }, onError: (Object error) {
      _loading = false;
      _error = 'Authentication state could not be loaded: $error';
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  /// Live unread badge: the count updates in real time as notifications are
  /// created or marked read (previously a one-shot `get()` that went stale).
  void _listenToNotificationCount(String userId) {
    _notificationSubscription?.cancel();
    _notificationSubscription = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      _unreadNotifications = snapshot.docs.length;
      notifyListeners();
    }, onError: (e) {
      debugPrint('Error listening to notifications: $e');
    });
  }

  // Fetch user data from Firestore
  Future<void> _fetchUserData(String userId) async {
    _loading = true;
    notifyListeners();

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (doc.exists) {
        _currentUser = UserModel.fromMap(doc.data()!, userId);
      } else {
        // Create a basic user record if it doesn't exist
        final User? authUser = _auth.currentUser;
        if (authUser != null) {
          _currentUser = UserModel(
            id: authUser.uid,
            email: authUser.email ?? '',
            name: authUser.displayName ?? 'User',
            photoUrl: authUser.photoURL ?? '',
          );
          
          await _firestore.collection('users').doc(userId).set(_currentUser!.toMap());
        }
      }
    } catch (e) {
      _error = 'Failed to load user data: $e';
      debugPrint(_error);
      // Keep the authenticated user in the app so a new account can still
      // complete onboarding after a transient Firestore read failure.
      final authUser = _auth.currentUser;
      if (authUser != null) {
        _currentUser = UserModel(
          id: authUser.uid,
          email: authUser.email ?? '',
          name: authUser.displayName ?? 'User',
          photoUrl: authUser.photoURL ?? '',
        );
      }
    }

    _loading = false;
    notifyListeners();
  }

  // Mark notifications as read
  Future<void> markNotificationsAsRead() async {
    if (_currentUser == null) return;
    
    try {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: _currentUser!.id)
          .where('read', isEqualTo: false)
          .get();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'read': true});
      }
      
      await batch.commit();
      _unreadNotifications = 0;
      notifyListeners();
    } catch (e) {
      print('Error marking notifications as read: $e');
    }
  }

  // Load saved theme preference
  Future<void> _fetchAppearanceSettings(String userId) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('appearance')
          .get();
      final saved = doc.data()?['themeMode'] as String?;
      if (saved == 'dark' && _themeMode != ThemeMode.dark) {
        _themeMode = ThemeMode.dark;
        notifyListeners();
      } else if (saved == 'light' && _themeMode != ThemeMode.light) {
        _themeMode = ThemeMode.light;
        notifyListeners();
      }
    } catch (e) {
      print('Error loading appearance settings: $e');
    }
  }

  // Change and persist the theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('appearance')
          .set({'themeMode': mode.name}, SetOptions(merge: true));
    } catch (e) {
      print('Error saving appearance settings: $e');
    }
  }

  // Sign in user
  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error = '';
    notifyListeners();

    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Signs in with Google and exchanges the Google token for a Firebase
  /// credential so the normal auth-state flow can load the user's profile.
  ///
  /// [preAcceptedLegal] is true when the caller already collected the terms
  /// + age checkboxes *before* starting the Google flow (the Signup page's
  /// "Continue with Google" button, gated on those boxes) - in that case the
  /// consent is written in the same call so the account never has a window
  /// where it exists but hasn't recorded consent. Callers that didn't
  /// pre-collect consent (the homepage's "Continue with Google") leave this
  /// false; [AppState.needsLegalConsent] then gates entry until the person
  /// explicitly agrees post sign-in.
  Future<bool> signInWithGoogle({bool preAcceptedLegal = false}) async {
    _loading = true;
    _error = '';
    notifyListeners();

    try {
      debugPrint('Starting Google account selection');
      final GoogleSignInAccount? googleUser = await _googleSignIn
          .signIn()
          .timeout(const Duration(seconds: 45));
      if (googleUser == null) {
        _error = 'Google sign-in was cancelled.';
        return false;
      }

      debugPrint('Google account selected: ${googleUser.email}');
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication.timeout(const Duration(seconds: 15));
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      if (googleAuth.idToken == null && googleAuth.accessToken == null) {
        throw StateError('Google did not return an authentication token.');
      }

      final userCredential = await _auth
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 30));
      debugPrint('Firebase Google sign-in completed');

      if (preAcceptedLegal) {
        final uid = userCredential.user!.uid;
        await _firestore.collection('users').doc(uid).set({
          'acceptedTerms': true,
          'ageConfirmed': true,
          'termsAcceptedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return true;
    } on FirebaseAuthException catch (e) {
      _error = e.message ?? 'Google sign-in failed.';
      return false;
    } catch (e) {
      _error = 'Google sign-in failed: $e';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Records the Terms/Privacy Policy + 18+ consent for the signed-in
  /// account - called from the post-sign-in [LegalConsentPage] gate. Once
  /// this succeeds, [needsLegalConsent] flips false and the root router in
  /// main.dart moves the user on to setup or the main app.
  Future<bool> acceptLegalTerms() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _currentUser == null) return false;
    try {
      await _firestore.collection('users').doc(uid).set({
        'acceptedTerms': true,
        'ageConfirmed': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _currentUser = _currentUser!.copyWith(acceptedTerms: true, ageConfirmed: true);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Could not save your consent: $e';
      notifyListeners();
      return false;
    }
  }

  // Sign up new user
  Future<bool> signUp(
    String email,
    String password,
    String name, {
    required bool acceptedTerms,
    required bool ageConfirmed,
  }) async {
    if (!acceptedTerms || !ageConfirmed) {
      _error = 'Please accept the Terms & Privacy Policy and confirm you are 18 or older.';
      notifyListeners();
      return false;
    }

    _loading = true;
    _error = '';
    notifyListeners();

    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);

      // Update display name
      await credential.user?.updateDisplayName(name);

      // Create user in Firestore
      final newUser = UserModel(
        id: credential.user!.uid,
        email: email,
        name: name,
        acceptedTerms: acceptedTerms,
        ageConfirmed: ageConfirmed,
      );

      await _firestore.collection('users').doc(credential.user!.uid).set({
        ...newUser.toMap(),
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      });

      AnalyticsProvider.log('sign_up', credential.user!.uid, {'method': 'email'});
      _loading = false;
      return true;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Update user profile
  Future<bool> updateUserProfile(UserModel updatedUser) async {
    if (_currentUser == null) {
      _error = 'Your account is still loading. Please try again.';
      notifyListeners();
      return false;
    }
    
    _loading = true;
    notifyListeners();

    try {
      await _firestore
          .collection('users')
          .doc(updatedUser.id)
          .set(updatedUser.toMap(), SetOptions(merge: true));
      _currentUser = updatedUser;
      AnalyticsProvider.log('profile_updated', updatedUser.id, {});
    } catch (e) {
      _error = 'Failed to update profile: $e';
      debugPrint(_error);
      _loading = false;
      notifyListeners();
      return false;
    }

    _loading = false;
    notifyListeners();
    return true;
  }

  // Upload profile image
  Future<String?> uploadProfileImage(File image) async {
    if (_currentUser == null) return null;
    
    _loading = true;
    notifyListeners();

    try {
      final ref = _storage.ref().child('profile_images/${_currentUser!.id}');
      final uploadTask = ref.putFile(image);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      // Update user photo URL
      if (_currentUser != null) {
        final updatedUser = _currentUser!.copyWith(photoUrl: downloadUrl);
        await updateUserProfile(updatedUser);
        
        // Also update in Firebase Auth
        await _auth.currentUser?.updatePhotoURL(downloadUrl);
      }

      _loading = false;
      notifyListeners();
      return downloadUrl;
    } catch (e) {
      _error = 'Failed to upload image: $e';
      _loading = false;
      notifyListeners();
      return null;
    }
  }

  Future<String?> uploadResume(File file) async {
    if (_currentUser == null) {
      _error = 'Your account is still loading. Please try again.';
      notifyListeners();
      return null;
    }
    _loading = true;
    _error = '';
    notifyListeners();
    try {
      final ref = _storage.ref().child('resumes/${_currentUser!.id}');
      final snapshot = await ref.putFile(
        file,
        SettableMetadata(contentType: 'application/pdf'),
      );
      final url = await snapshot.ref.getDownloadURL();
      final updatedUser = _currentUser!.copyWith(resumeUrl: url);
      if (!await updateUserProfile(updatedUser)) return null;
      return url;
    } catch (e) {
      _error = 'Failed to upload resume: $e';
      debugPrint(_error);
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Add a new swap request
  Future<bool> sendSwapRequest(Map<String, dynamic> requestData) async {
    if (_currentUser == null) return false;
    
    try {
      await _firestore.collection('swipeRequests').add(requestData);

      AnalyticsProvider.log('swap_request_sent', _currentUser!.id, {
        'toUserId': requestData['toUserId'],
      });
      // Add notification for recipient
      await _firestore.collection('notifications').add({
        'userId': requestData['toUserId'],
        'type': 'swap_request',
        'message': '${_currentUser!.name} wants to swap skills with you',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'senderName': _currentUser!.name,
        'senderPhoto': _currentUser!.photoUrl,
      });
      
      return true;
    } catch (e) {
      _error = 'Failed to send request: $e';
      print(_error);
      return false;
    }
  }

  // Rate a user after skill exchange
  Future<bool> rateUser(String userId, double rating, String review) async {
    if (_currentUser == null) return false;
    
    try {
      // Add the rating document
      await _firestore.collection('ratings').add({
        'fromUserId': _currentUser!.id,
        'toUserId': userId,
        'rating': rating,
        'review': review,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // Update the user's average rating using a transaction: the divisor is
      // the stored ratings count (NOT completedSwaps, which counts swaps, not
      // ratings - both participants rate the same swap separately).
      await _firestore.runTransaction((tx) async {
        final userRef = _firestore.collection('users').doc(userId);
        final userDoc = await tx.get(userRef);
        if (!userDoc.exists) return;

        final userData = userDoc.data()!;
        final currentRating = (userData['rating'] as num?)?.toDouble() ?? 0.0;
        final ratingsCount = (userData['ratingsCount'] as num?)?.toInt() ?? 0;
        final completedSwaps = (userData['completedSwaps'] as num?)?.toInt() ?? 0;

        final newRating =
            ((currentRating * ratingsCount) + rating) / (ratingsCount + 1);

        tx.update(userRef, {
          'rating': newRating,
          'ratingsCount': ratingsCount + 1,
          'completedSwaps': completedSwaps + 1,
        });
      });
      
      AnalyticsProvider.log('user_rated', _currentUser!.id, {
        'ratedUserId': userId,
        'rating': rating,
      });
      return true;
    } catch (e) {
      _error = 'Failed to rate user: $e';
      print(_error);
      return false;
    }
  }
}
