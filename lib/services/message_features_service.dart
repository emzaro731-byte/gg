import 'package:supabase_flutter/supabase_flutter.dart';

class MessageFeaturesService {
  MessageFeaturesService(this.supabase);

  final SupabaseClient supabase;

  Future<void> markDelivered(String messageId) async {
    await supabase.rpc('mark_message_delivered', params: {
      'target_message_id': messageId,
    });
  }

  Future<void> markRead(String messageId) async {
    await supabase.rpc('mark_message_read', params: {
      'target_message_id': messageId,
    });
  }

  Future<void> pin(String messageId) async {
    await supabase.rpc('pin_message', params: {
      'target_message_id': messageId,
    });
  }

  Future<void> unpin(String messageId) async {
    await supabase.rpc('unpin_message', params: {
      'target_message_id': messageId,
    });
  }

  Future<void> deleteForEveryone(String messageId) async {
    await supabase.rpc('delete_message_for_everyone', params: {
      'target_message_id': messageId,
    });
  }

  Future<List<Map<String, dynamic>>> reactionCounts(String messageId) async {
    final rows = await supabase.rpc('get_message_reaction_counts', params: {
      'target_message_id': messageId,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<Map<String, dynamic>> receipt(String messageId) async {
    final rows = await supabase.rpc('get_message_receipt', params: {
      'target_message_id': messageId,
    });
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? {'delivered_count': 0, 'read_count': 0} : list.first;
  }
}
