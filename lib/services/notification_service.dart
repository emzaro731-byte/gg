import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) return;
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final token = await _messaging.getToken();
    if (token != null) await saveToken(token);
    _messaging.onTokenRefresh.listen(saveToken);
  }

  Future<void> saveToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': 'flutter',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,token');
  }
}
