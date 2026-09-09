import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String title;
  const ChatPage({required this.conversationId, required this.title, super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  final focus = FocusNode();
  bool sending = false, online = false;
  Map<String, dynamic>? replyingTo;
  String? editingId;
  late final RealtimeChannel presenceChannel;
  late final Stream<List<Map<String, dynamic>>> messageStream;
  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    messageStream = supabase.from('messages').stream(primaryKey: ['id']).eq('conversation_id', widget.conversationId).order('created_at');
    presenceChannel = supabase.channel('chat-presence:${widget.conversationId}');
    presenceChannel.onPresenceSync((_) => _refreshPresence());
    presenceChannel.onPresenceJoin((_) => _refreshPresence());
    presenceChannel.onPresenceLeave((_) => _refreshPresence());
    presenceChannel.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await presenceChannel.track({'user_id': userId, 'online_at': DateTime.now().toUtc().toIso8601String()});
        _refreshPresence();
      }
    });
  }

  void _refreshPresence() {
    if (!mounted) return;
    final states = presenceChannel.presenceState();
    final found = states.any((state) => state.presences.any((presence) => presence.payload['user_id']?.toString() != userId));
    setState(() => online = found);
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    final oldEditing = editingId;
    final reply = replyingTo;
    controller.clear();
    setState(() { editingId = null; replyingTo = null; });
    try {
      if (oldEditing != null) {
        await supabase.from('messages').update({'body': text, 'edited_at': DateTime.now().toUtc().toIso8601String()}).eq('id', oldEditing).eq('sender_id', userId);
      } else {
        await supabase.from('messages').insert({'conversation_id': widget.conversationId, 'sender_id': userId, 'body': text, 'message_type': 'text', 'reply_to': reply?['id']});
      }
    } on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
    finally { if (mounted) setState(() => sending = false); }
  }

  Future<void> deleteMessage(String id) async {
    try { await supabase.from('messages').delete().eq('id', id).eq('sender_id', userId); }
    on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
  }

  Future<void> react(String id, String emoji) async {
    try {
      final existing = await supabase.from('message_reactions').select('message_id').eq('message_id', id).eq('user_id', userId).eq('reaction', emoji).maybeSingle();
      if (existing == null) {
        await supabase.from('message_reactions').insert({'message_id': id, 'user_id': userId, 'reaction': emoji});
      } else {
        await supabase.from('message_reactions').delete().eq('message_id', id).eq('user_id', userId).eq('reaction', emoji);
      }
    } on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Run the messaging migration first: ${e.message}'))); }
  }

  void showMessageActions(Map<String, dynamic> message) {
    final mine = message['sender_id'] == userId;
    showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Text('❤️', style: TextStyle(fontSize: 22)), title: const Text('React ❤️'), onTap: () { Navigator.pop(context); react(message['id'].toString(), '❤️'); }),
      ListTile(leading: const Text('😂', style: TextStyle(fontSize: 22)), title: const Text('React 😂'), onTap: () { Navigator.pop(context); react(message['id'].toString(), '😂'); }),
      ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () { Navigator.pop(context); setState(() => replyingTo = message); focus.requestFocus(); }),
      if (mine) ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () { Navigator.pop(context); setState(() { editingId = message['id'].toString(); controller.text = message['body']?.toString() ?? ''; }); focus.requestFocus(); }),
      if (mine) ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: const Text('Delete'), onTap: () { Navigator.pop(context); deleteMessage(message['id'].toString()); }),
    ])));
  }

  @override
  void dispose() { unawaited(presenceChannel.unsubscribe()); controller.dispose(); focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: Row(children: [CircleAvatar(radius: 19, child: Text(widget.title.isEmpty ? '?' : widget.title.substring(0, 1).toUpperCase())), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), Text(online ? 'online' : 'offline', style: TextStyle(fontSize: 12, color: online ? Colors.green : null))])]),
      actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined)), IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined))],
    ),
    body: Column(children: [
      Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(stream: messageStream, builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load messages: ${snapshot.error}'));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('No messages yet. Say hello!'));
        return ListView.builder(padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), itemCount: items.length, itemBuilder: (context, index) {
          final message = items[index]; final mine = message['sender_id'] == userId; final body = message['body']?.toString() ?? ''; final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
          final replyId = message['reply_to']?.toString(); final replied = replyId == null ? null : items.cast<Map<String, dynamic>?>().firstWhere((m) => m?['id']?.toString() == replyId, orElse: () => null);
          return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(onLongPress: () => showMessageActions(message), child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .80), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
            decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 4), bottomRight: Radius.circular(mine ? 4 : 18))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (replied != null) Container(width: double.infinity, padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 7), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: .35), borderRadius: BorderRadius.circular(10)), child: Text(replied['body']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis)),
              Text(body, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 3), Row(mainAxisSize: MainAxisSize.min, children: [if (message['edited_at'] != null) const Text('edited  •  ', style: TextStyle(fontSize: 10)), Text(created == null ? '' : DateFormat('HH:mm').format(created), style: const TextStyle(fontSize: 10))]),
            ]),
          )));
        });
      })),
      if (replyingTo != null || editingId != null) Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(14, 8, 8, 8), color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Row(children: [Icon(editingId != null ? Icons.edit_rounded : Icons.reply_rounded, size: 18), const SizedBox(width: 8), Expanded(child: Text(editingId != null ? 'Editing message' : 'Replying to ${replyingTo?['body'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis)), IconButton(onPressed: () => setState(() { replyingTo = null; editingId = null; controller.clear(); }), icon: const Icon(Icons.close))])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(children: [IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline)), Expanded(child: TextField(controller: controller, focusNode: focus, textInputAction: TextInputAction.send, onSubmitted: (_) => sendMessage(), minLines: 1, maxLines: 5, decoration: InputDecoration(hintText: editingId != null ? 'Edit message' : 'Message', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)))), const SizedBox(width: 6), IconButton.filled(onPressed: sending ? null : sendMessage, icon: Icon(editingId != null ? Icons.check_rounded : Icons.send_rounded))]))),
    ]),
  );
}
