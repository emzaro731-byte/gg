import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Offline-first cache and sync coordinator for messages.
///
/// The server remains the source of truth. Local data is used immediately when
/// there is no connection, and queued writes are pushed automatically when a
/// Supabase request succeeds again.
class OfflineSyncService {
  OfflineSyncService._();
  static final OfflineSyncService instance = OfflineSyncService._();

  static const _messagesPrefix = 'gg.offline.messages.';
  static const _pendingPrefix = 'gg.offline.pending.';
  static const _draftPrefix = 'gg.offline.draft.';

  Timer? _timer;
  bool _syncing = false;

  SupabaseClient get supabase => Supabase.instance.client;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  String _key(String prefix, String conversationId) => '$prefix$conversationId';

  Future<List<Map<String, dynamic>>> loadMessages(String conversationId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(_messagesPrefix, conversationId));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveMessages(
    String conversationId,
    List<Map<String, dynamic>> messages,
  ) async {
    final prefs = await _prefs;
    final sorted = List<Map<String, dynamic>>.from(messages)
      ..sort((a, b) =>
          (a['created_at']?.toString() ?? '').compareTo(b['created_at']?.toString() ?? ''));
    // Keep a practical local history instead of allowing preferences to grow
    // without bound.
    final trimmed = sorted.length > 1000
        ? sorted.sublist(sorted.length - 1000)
        : sorted;
    await prefs.setString(_key(_messagesPrefix, conversationId), jsonEncode(trimmed));
  }

  Future<void> mergeMessages(
    String conversationId,
    Iterable<Map<String, dynamic>> incoming,
  ) async {
    final existing = await loadMessages(conversationId);
    final byId = <String, Map<String, dynamic>>{
      for (final message in existing)
        if (message['id'] != null) message['id'].toString(): message,
    };
    for (final message in incoming) {
      final id = message['id']?.toString();
      if (id != null && id.isNotEmpty) byId[id] = Map<String, dynamic>.from(message);
    }
    await saveMessages(conversationId, byId.values.toList());
  }

  Future<void> queueMessage({
    required String conversationId,
    required Map<String, dynamic> message,
  }) async {
    final prefs = await _prefs;
    final pending = await loadPending(conversationId);
    pending.removeWhere((item) => item['id']?.toString() == message['id']?.toString());
    pending.add(Map<String, dynamic>.from(message));
    await prefs.setString(_key(_pendingPrefix, conversationId), jsonEncode(pending));
    await mergeMessages(conversationId, [message]);
  }

  Future<List<Map<String, dynamic>>> loadPending(String conversationId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(_pendingPrefix, conversationId));
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _removePending(String conversationId, String id) async {
    final prefs = await _prefs;
    final pending = await loadPending(conversationId);
    pending.removeWhere((item) => item['id']?.toString() == id);
    await prefs.setString(_key(_pendingPrefix, conversationId), jsonEncode(pending));
  }

  Future<void> syncConversation(String conversationId) async {
    if (_syncing) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _syncing = true;
    try {
      final pending = await loadPending(conversationId);
      for (final message in pending) {
        try {
          final id = message['id']?.toString();
          if (id == null) continue;
          final payload = Map<String, dynamic>.from(message)
            ..remove('_offline')
            ..remove('_queued_at');
          await supabase.from('messages').upsert(payload, onConflict: 'id');
          await _removePending(conversationId, id);
        } catch (_) {
          // Keep it queued. A later retry will send it.
        }
      }

      final rows = await supabase
          .from('messages')
          .select()
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true)
          .limit(1000);
      await mergeMessages(
        conversationId,
        List<Map<String, dynamic>>.from(rows),
      );
    } catch (_) {
      // Offline or temporarily unavailable: cached data remains usable.
    } finally {
      _syncing = false;
    }
  }

  /// Starts a lightweight foreground retry loop. Supabase remains fully online;
  /// this only provides a recovery trigger after the device regains access.
  void startAutoSync(Iterable<String> conversationIds) {
    _timer?.cancel();
    final ids = conversationIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      for (final id in ids) {
        await syncConversation(id);
      }
    });
  }

  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> saveDraft(String conversationId, String text) async {
    final prefs = await _prefs;
    if (text.isEmpty) {
      await prefs.remove(_key(_draftPrefix, conversationId));
    } else {
      await prefs.setString(_key(_draftPrefix, conversationId), text);
    }
  }

  Future<String> loadDraft(String conversationId) async {
    final prefs = await _prefs;
    return prefs.getString(_key(_draftPrefix, conversationId)) ?? '';
  }

  String newMessageId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  void dispose() => stopAutoSync();
}
