import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks the signed-in user's online state with Supabase Realtime Presence.
/// Presence is intentionally used for slow-changing state such as online/offline,
/// not high-frequency events such as typing.
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
      opts: RealtimeChannelConfig(
        presence: PresenceConfig(key: user.id),
      ),
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
        // Presence failure must never prevent the messenger UI from loading.
        _onlineUsers.add(<String>{});
      }
    });
  }

  void _publishState() {
    final channel = _channel;
    if (channel == null) return;

    final state = channel.presenceState();
    final ids = <String>{};
    for (final entries in state.values) {
      for (final entry in entries) {
        if (entry is Map && entry['user_id'] != null) {
          ids.add(entry['user_id'].toString());
        }
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
