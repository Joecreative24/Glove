// messaging_service.dart
// Firebase Cloud Messaging (push notifications). Registers the device token
// under the user profile so the alert-fan-out Cloud Function can target it,
// and exposes the foreground message stream for in-app banners.
//
// Tokens are stored at  users/{uid}/fcmTokens/{token}  (a subcollection),
// which the `sendAlertPush` function reads to deliver pushes.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

import '../core/firebase_refs.dart';
import '../core/firestore_utils.dart';

class MessagingService {
  final FirebaseMessaging _fcm;
  MessagingService({FirebaseMessaging? messaging})
      : _fcm = messaging ?? FirebaseMessaging.instance;

  /// Asks the OS for notification permission (no-op on Android < 13).
  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Call right after login: stores this device's token and keeps it fresh.
  Future<void> registerToken(String uid) async {
    final token = await _fcm.getToken();
    if (token != null) await _saveToken(uid, token);

    // Persist rotated tokens too.
    _fcm.onTokenRefresh.listen((t) => _saveToken(uid, t));
  }

  Future<void> _saveToken(String uid, String token) =>
      FirebaseRefs.user(uid).collection('fcmTokens').doc(token).set({
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updatedAt': serverNow,
      });

  /// Call on logout so this device stops receiving the user's pushes.
  Future<void> unregisterToken(String uid) async {
    final token = await _fcm.getToken();
    if (token == null) return;
    await FirebaseRefs.user(uid).collection('fcmTokens').doc(token).delete();
  }

  /// Foreground messages — show an in-app banner / refresh the alert list.
  Stream<RemoteMessage> onForegroundMessage() => FirebaseMessaging.onMessage;
}
