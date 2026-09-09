import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String title;

  const ChatPage({required this.conversationId, required this.title, super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  bool sending = false;

  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  Stream<List<Map<String, dynamic>>> get messages => supabase
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', widget.conversationId)
      .order('created_at');

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    controller.clear();
    try {
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': userId,
        'body': text,
        'message_type': 'text',
      });
      await supabase.from('conversations').update({
        'last_message': text,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.conversationId);
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> deleteMessage(String id) async {
    try {
      await supabase.from('messages').delete().eq('id', id);
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Unable to load messages: ${snapshot.error}'));
                final items = snapshot.data ?? [];
                if (items.isEmpty) return const Center(child: Text('No messages yet. Say hello!'));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final message = items[index];
                    final mine = message['sender_id'] == userId;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: mine ? () => deleteMessage(message['id'].toString()) : null,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(message['body']?.toString() ?? ''),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline)),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => sendMessage(),
                      minLines: 1,
                      maxLines: 5,
                      decoration: InputDecoration(hintText: 'Message', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(onPressed: sending ? null : sendMessage, icon: const Icon(Icons.send_rounded)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
