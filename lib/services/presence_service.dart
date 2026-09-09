import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks the signed-in user's online state with Supabase Realtime Presence.
class PresenceService {
  PresenceService(this.supabase);

  final SupabaseClient supabase;
  RealtimeChannel? _channel;
  final StreamController<Set<String>> _onlineUsers =
      StreamController<Set<String>>.broadcast();
  bool _started = false;

  Stream<Set<String>> get onlineUsers => _onlineUsers.stream;

  Future<void> start() async {
    if (_started) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    _channel = supabase.channel(
      'global:presence',
      opts: const RealtimeChannelConfig(private: true),
    );

    _channel!
        .onPresenceSync((_) => _publishState())
        .onPresenceJoin((_) => _publishState())
        .onPresenceLeave((_) => _publishState())
        .subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel!.track({
          'user_id': user.id,
          'online_at': DateTime.now().toUtc().toIso8601String(),
        });
        _started = true;
        _publishState();
      } else if (error != null) {
        _onlineUsers.add(<String>{});
      }
    });
  }

  void _publishState() {
    final channel = _channel;
    if (channel == null) return;

    final states = channel.presenceState();
    final ids = <String>{};
    for (final state in states) {
      for (final presence in state.presences) {
        final id = presence.payload['user_id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    _onlineUsers.add(ids);
  }

  Future<void> dispose() async {
    _started = false;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await channel.untrack();
      await channel.unsubscribe();
    }
    await _onlineUsers.close();
  }
}
