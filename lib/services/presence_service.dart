import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks signed-in users with Supabase Realtime Presence and a last-seen
/// heartbeat so the contact list recovers when a mobile connection changes.
class PresenceService {
  PresenceService(this.supabase);

  final SupabaseClient supabase;
  RealtimeChannel? _channel;
  Timer? _heartbeat;
  Timer? _retryTimer;
  final StreamController<Set<String>> _onlineUsers =
      StreamController<Set<String>>.broadcast();
  bool _started = false;
  bool _disposed = false;
  bool _connecting = false;

  Stream<Set<String>> get onlineUsers => _onlineUsers.stream;

  Future<void> start() async {
    if (_disposed || _connecting) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (_started && _channel != null) {
      await _track(user.id);
      return;
    }

    _connecting = true;
    _retryTimer?.cancel();

    final oldChannel = _channel;
    _channel = null;
    if (oldChannel != null) {
      try {
        await oldChannel.untrack();
        await oldChannel.unsubscribe();
      } catch (_) {}
    }

    final channel = supabase.channel(
      'global:presence',
      opts: const RealtimeChannelConfig(private: true),
    );
    _channel = channel;

    channel
        .onPresenceSync((_) => _publishState())
        .onPresenceJoin((_) => _publishState())
        .onPresenceLeave((_) => _publishState())
        .subscribe((status, error) async {
      if (_disposed || _channel != channel) return;

      if (status == RealtimeSubscribeStatus.subscribed) {
        _started = true;
        _connecting = false;
        await _track(user.id);
        _publishState();
        _startHeartbeat(user.id);
      } else if (error != null ||
          status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _started = false;
        _connecting = false;
        _onlineUsers.add(<String>{});
        _scheduleRetry();
      }
    });
  }

  Future<void> _track(String userId) async {
    final channel = _channel;
    if (channel == null || _disposed) return;
    try {
      await channel.track({
        'user_id': userId,
        'online_at': DateTime.now().toUtc().toIso8601String(),
      });
      // last_seen is also maintained for contact-list fallback and debugging.
      await supabase
          .from('profiles')
          .update({'last_seen': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (error) {
      debugPrint('GG presence track failed: $error');
    }
  }

  void _startHeartbeat(String userId) {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_disposed) return;
      if (_channel == null || !_started) {
        await start();
        return;
      }
      await _track(userId);
      _publishState();
    });
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer?.isActive == true) return;
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed) start();
    });
  }

  void _publishState() {
    final channel = _channel;
    if (channel == null || _disposed) return;

    try {
      final states = channel.presenceState();
      final ids = <String>{};
      for (final state in states) {
        for (final presence in state.presences) {
          final id = presence.payload['user_id']?.toString();
          if (id != null && id.isNotEmpty) ids.add(id);
        }
      }
      _onlineUsers.add(ids);
    } catch (error) {
      debugPrint('GG presence state failed: $error');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _started = false;
    _connecting = false;
    _heartbeat?.cancel();
    _retryTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.untrack();
        await channel.unsubscribe();
      } catch (_) {}
    }
    if (!_onlineUsers.isClosed) await _onlineUsers.close();
  }
}
