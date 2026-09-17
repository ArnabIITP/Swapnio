import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../Screen/User/chat_page.dart';

/// Push-notification plumbing for Swapnio.
///
/// * registers the device with FCM and stores the token on the user document
///   (`users/{uid}.fcmTokens`) so the Cloud Function in `functions/index.js`
///   can deliver pushes
/// * exposes [onForegroundMessage] so the UI can react to pushes received while
///   the app is open (the notification bell/badge already updates live from the
///   `notifications` collection, so no local-notification plugin is required)
/// * keeps the token list clean when FCM rotates the token
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Set from `main.dart`; used to deep-link when a push notification is
  /// tapped while the app is in background/terminated.
  static GlobalKey<NavigatorState>? navigatorKey;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Optional hook for foreground messages (e.g. show an in-app banner).
  void Function(RemoteMessage message)? onForegroundMessage;

  bool _initialised = false;

  /// Call once after the user signs in.
  Future<void> init(String userId) async {
    if (_initialised) return;
    _initialised = true;
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await _messaging.getToken();
      if (token != null) {
        await _storeToken(userId, token);
      }

      _messaging.onTokenRefresh.listen((newToken) => _storeToken(userId, newToken));

      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Push received in foreground: ${message.notification?.title}');
        onForegroundMessage?.call(message);
      });

      // Tap-through routing: background/terminated taps open the relevant
      // conversation instead of dumping the user on the home feed.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);
    } catch (e) {
      debugPrint('NotificationService.init failed: $e');
    }
  }

  void _handleMessageTap(RemoteMessage message) {
    final data = message.data;
    final context = navigatorKey?.currentContext;
    if (context == null) return;

    final senderId = data['senderId'] as String?;
    if (senderId == null || senderId.isEmpty) return;

    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == senderId) return;

    final chatRoomId = me.compareTo(senderId) < 0
        ? '$me' '_' '$senderId'
        : '$senderId' '_' '$me';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatRoomId: chatRoomId,
          otherUserName: (data['senderName'] as String?) ?? 'Chat',
          otherUserPhoto: '',
          otherUserId: senderId,
        ),
      ),
    );
  }

  Future<void> _storeToken(String userId, String token) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });
    } catch (e) {
      debugPrint('NotificationService._storeToken failed: $e');
    }
  }
}