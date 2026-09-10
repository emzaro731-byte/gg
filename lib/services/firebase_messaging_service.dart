import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('GG FCM background message: ${message.messageId}');
}

class FirebaseMessagingService {
  FirebaseMessagingService._();
  static final instance = FirebaseMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _initialized = false;

  Future<void> initialize() async {
    if (kIsWeb || _initialized) return;

    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }

    _messaging.onTokenRefresh.listen(_saveToken);
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('GG FCM foreground message: ${message.messageId}');
    });

    _initialized = true;
  }

  Future<void> registerCurrentUser() async {
    if (kIsWeb || !_initialized) return;
    final token = await _messaging.getToken();
    if (token != null) {
      await _saveToken(token);
    }
  }

  Future<void> _saveToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client.from('device_tokens').upsert(
      {
        'user_id': user.id,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'token',
    );
  }
}
