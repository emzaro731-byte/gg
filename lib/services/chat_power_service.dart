import 'package:supabase_flutter/supabase_flutter.dart';

/// Client helpers for chat power features. UI layers can call these helpers
/// without duplicating Supabase RPC names or preference handling.
class ChatPowerService {
  ChatPowerService(this.client);

  final SupabaseClient client;

  Future<void> setDisappearingMessages(String conversationId, int seconds) async {
    await client.rpc('set_disappearing_messages', params: {
      'target_conversation_id': conversationId,
      'seconds': seconds,
    });
  }

  Future<void> pinMessage(String messageId) async {
    await client.rpc('pin_message', params: {'target_message_id': messageId});
  }

  Future<void> unpinMessage(String messageId) async {
    await client.rpc('unpin_message', params: {'target_message_id': messageId});
  }

  Future<bool> isPinned(String messageId) async {
    final row = await client
        .from('message_pins')
        .select('message_id')
        .eq('message_id', messageId)
        .maybeSingle();
    return row != null;
  }

  Future<List<Map<String, dynamic>>> pinnedMessages(String conversationId) async {
    final rows = await client
        .from('message_pins')
        .select('message_id,pinned_by,pinned_at,messages!inner(conversation_id,body,message_type,created_at,sender_id)')
        .eq('messages.conversation_id', conversationId)
        .order('pinned_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<int> disappearingSeconds(String conversationId) async {
    final user = client.auth.currentUser;
    if (user == null) return 0;
    final row = await client
        .from('conversation_preferences')
        .select('disappearing_seconds')
        .eq('conversation_id', conversationId)
        .eq('user_id', user.id)
        .maybeSingle();
    return (row?['disappearing_seconds'] as num?)?.toInt() ?? 0;
  }
}
