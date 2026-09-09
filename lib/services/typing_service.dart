import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class TypingService {
  TypingService(this.supabase, this.conversationId);

  final SupabaseClient supabase;
  final String conversationId;
  RealtimeChannel? _channel;
  Timer? _stopTimer;

  void start(void Function(bool) onTyping) {
    _channel = supabase.channel('typing:$conversationId');
    _channel!
        .onBroadcast(event: 'typing', callback: (payload) {
          final data = Map<String, dynamic>.from(payload);
          if (data['user_id']?.toString() == supabase.auth.currentUser?.id) return;
          onTyping(data['typing'] == true);
        })
        .subscribe();
  }

  Future<void> setTyping(bool value) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.sendBroadcastMessage(
      event: 'typing',
      payload: {
        'user_id': supabase.auth.currentUser?.id,
        'typing': value,
      },
    );
    _stopTimer?.cancel();
    if (value) {
      _stopTimer = Timer(const Duration(seconds: 2), () => setTyping(false));
    }
  }

  Future<void> dispose() async {
    _stopTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.unsubscribe();
  }
}
