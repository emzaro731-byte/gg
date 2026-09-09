import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent device cache used when Supabase/network access is unavailable.
/// Cache is namespaced by authenticated user so accounts do not share data.
class OfflineCacheService {
  OfflineCacheService._();
  static final OfflineCacheService instance = OfflineCacheService._();

  static const _prefix = 'gg_offline_v1';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  String _key(String userId, String type, [String? id]) =>
      '$_prefix:$userId:$type${id == null ? '' : ':$id'}';

  List<Map<String, dynamic>> _decode(String? value) {
    if (value == null || value.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveConversations(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(_key(userId, 'conversations'), jsonEncode(rows));
  }

  Future<List<Map<String, dynamic>>> loadConversations(String userId) async {
    final prefs = await _prefs;
    return _decode(prefs.getString(_key(userId, 'conversations')));
  }

  Future<void> saveConversationSettings(
    String userId,
    List<Map<String, dynamic>> rows,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(_key(userId, 'settings'), jsonEncode(rows));
  }

  Future<List<Map<String, dynamic>>> loadConversationSettings(String userId) async {
    final prefs = await _prefs;
    return _decode(prefs.getString(_key(userId, 'settings')));
  }

  Future<void> saveMessages(
    String userId,
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(
      _key(userId, 'messages', conversationId),
      jsonEncode(rows),
    );
  }

  Future<List<Map<String, dynamic>>> loadMessages(
    String userId,
    String conversationId,
  ) async {
    final prefs = await _prefs;
    return _decode(prefs.getString(_key(userId, 'messages', conversationId)));
  }

  Future<void> addPendingMessage(
    String userId,
    String conversationId,
    Map<String, dynamic> message,
  ) async {
    final prefs = await _prefs;
    final key = _key(userId, 'pending', conversationId);
    final rows = _decode(prefs.getString(key));
    rows.add(message);
    await prefs.setString(key, jsonEncode(rows));
  }

  Future<List<Map<String, dynamic>>> loadPendingMessages(
    String userId,
    String conversationId,
  ) async {
    final prefs = await _prefs;
    return _decode(
      prefs.getString(_key(userId, 'pending', conversationId)),
    );
  }

  Future<void> clearPendingMessages(
    String userId,
    String conversationId,
  ) async {
    final prefs = await _prefs;
    await prefs.remove(_key(userId, 'pending', conversationId));
  }
}
