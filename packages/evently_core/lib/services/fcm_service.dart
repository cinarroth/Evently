import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../repositories/auth_repository.dart';

/// Push notification glue. Keeps the user's FCM token fresh on the profile
/// document and subscribes devices to the broadcast topics.
class FcmService {
  FcmService(this._authRepo);

  final AuthRepository _authRepo;

  static const _topics = <String>[
    'registrations',
    'announcements',
    'reminders'
  ];

  /// Call after sign-in. Requests permission, subscribes topics and uploads
  /// the token. Safe to call repeatedly (token refresh included).
  Future<void> initialise() async {
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      for (final topic in _topics) {
        await messaging.subscribeToTopic(topic);
      }
      final token = await messaging.getToken();
      if (token != null) {
        await _authRepo.saveFcmToken(token);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _authRepo.saveFcmToken(token);
      });
    } catch (e) {
      // Notification setup must never block sign-in (e.g. simulator without
      // push support).
      debugPrint('FCM setup skipped: $e');
    }
  }

  /// Pre-background-handler registration for release builds. The top-level
  /// handler must live in each app's main.dart.
  static Future<void> ensureBackgroundHandler() async {
    if (Platform.isIOS || Platform.isAndroid) {
      FirebaseMessaging.onBackgroundMessage(_noopBackground);
    }
  }
}

Future<void> _noopBackground(RemoteMessage message) async {
  // Apps override with their own @pragma('vm:entry-point') handler.
  debugPrint('Background FCM message: ${message.messageId}');
}
