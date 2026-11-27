import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Push bildirimleri (Firebase Cloud Messaging).
///
/// google-services.json gerekmez: Firebase ayarları derlemede --dart-define ile
/// verilir. Ayar yoksa servis sessizce kapalı kalır ve uygulama normal çalışır.
///   --dart-define=FCM_API_KEY=...  --dart-define=FCM_APP_ID=...
///   --dart-define=FCM_SENDER_ID=... --dart-define=FCM_PROJECT_ID=...
abstract final class PushService {
  static const _apiKey = String.fromEnvironment('FCM_API_KEY');
  static const _appId = String.fromEnvironment('FCM_APP_ID');
  static const _senderId = String.fromEnvironment('FCM_SENDER_ID');
  static const _projectId = String.fromEnvironment('FCM_PROJECT_ID');

  static bool get configured =>
      _apiKey.isNotEmpty && _appId.isNotEmpty && _senderId.isNotEmpty && _projectId.isNotEmpty;

  static bool _ready = false;
  static final StreamController<Map<String, dynamic>> _taps = StreamController<Map<String, dynamic>>.broadcast();

  /// Bildirime dokunulunca gelen veri (ör. {'kind':'invite','room_id':...}).
  static Stream<Map<String, dynamic>> get taps => _taps.stream;

  static Future<void> init() async {
    if (!configured || _ready) return;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
        ),
      );
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _taps.add(Map<String, dynamic>.from(m.data)));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _taps.add(Map<String, dynamic>.from(initial.data));
      _ready = true;
    } catch (error) {
      debugPrint('OKEYX_PUSH_INIT_ERROR: $error');
    }
  }

  /// İzin ister ve cihaz token'ını döndürür; push kapalıysa null.
  static Future<String?> token() async {
    await init();
    if (!_ready) return null;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
      return await FirebaseMessaging.instance.getToken();
    } catch (error) {
      debugPrint('OKEYX_PUSH_TOKEN_ERROR: $error');
      return null;
    }
  }
}
