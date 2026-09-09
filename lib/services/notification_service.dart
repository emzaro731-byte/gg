import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<AuthState>? _authSubscription;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty) return;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final token = await _messaging.getToken();
    if (token != null) await saveToken(token);

    await _tokenSubscription?.cancel();
    _tokenSubscription = _messaging.onTokenRefresh.listen(saveToken);

    await _authSubscription?.cancel();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((_) async {
      final refreshedToken = await _messaging.getToken();
      if (refreshedToken != null) await saveToken(refreshedToken);
    });
  }

  Future<void> saveToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    await _supabase.from('device_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,token');
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
    _tokenSubscription = null;
    _authSubscription = null;
  }
}
