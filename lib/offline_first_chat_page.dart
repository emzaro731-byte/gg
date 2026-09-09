import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_page.dart';
import 'services/offline_sync_service.dart';

/// Chooses the normal realtime ChatPage when Supabase is reachable and a
/// lightweight cached/queued chat when it is not. This keeps the existing
/// online chat features while making message history and drafts usable offline.
class OfflineFirstChatPage extends StatefulWidget {
  const OfflineFirstChatPage({
    required this.conversationId,
    required this.title,
    super.key,
  });

  final String conversationId;
  final String title;

  @override
  State<OfflineFirstChatPage> createState() => _OfflineFirstChatPageState();
}

class _OfflineFirstChatPageState extends State<OfflineFirstChatPage> {
  final sync = OfflineSyncService.instance;
  Timer? _probe;
  bool? _online;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _probe = Timer.periodic(const Duration(seconds: 8), (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    final ok = await _probeSupabase();
    if (!mounted) return;
    if (ok && _online != true) {
      await sync.syncConversation(widget.conversationId);
    }
    if (mounted) setState(() => _online = ok);
  }

  Future<bool> _probeSupabase() async {
    try {
      await supabase.auth.getSession();
      await supabase.from('messages').select('id').eq('conversation_id', widget.conversationId).limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online == true) {
      return ChatPage(
        conversationId: widget.conversationId,
        title: widget.title,
      );
    }
    return _CachedChat(
      conversationId: widget.conversationId,
      title: widget.title,
      onOnline: _checkConnection,
    );
  }
}

class _CachedChat extends StatefulWidget {
  const _CachedChat({
    required this.conversationId,
    required this.title,
    required this.onOnline,
  });

  final String conversationId;
  final String title;
  final Future<void> Function() onOnline;

  @override
  State<_CachedChat> createState() => _CachedChatState();
}

class _CachedChatState extends State<_CachedChat> {
  final controller = TextEditingController();
  final sync = OfflineSyncService.instance;
  List<Map<String, dynamic>> messages = [];
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = await sync.loadMessages(widget.conversationId);
    final draft = await sync.loadDraft(widget.conversationId);
    if (!mounted) return;
    setState(() {
      messages = cached;
      controller.text = draft;
    });
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => sending = true);

    final now = DateTime.now().toUtc().toIso8601String();
    final message = <String, dynamic>{
      'id': sync.newMessageId(),
      'conversation_id': widget.conversationId,
      'sender_id': user.id,
      'body': text,
      'message_type': 'text',
      'created_at': now,
      '_offline': true,
      '_queued_at': now,
    };

    await sync.queueMessage(
      conversationId: widget.conversationId,
      message: message,
    );
    await sync.syncConversation(widget.conversationId);
    await sync.saveDraft(widget.conversationId, '');
    final cached = await sync.loadMessages(widget.conversationId);

    if (!mounted) return;
    setState(() {
      messages = cached;
      controller.clear();
      sending = false;
    });
    unawaited(widget.onOnline());
  }

  Future<void> _draftChanged(String value) =>
      sync.saveDraft(widget.conversationId, value);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(child: Text(widget.title.isEmpty ? '?' : widget.title[0].toUpperCase())),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const Text('Offline • cached history', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Text(
              'You are offline. Messages are saved here and will send automatically when internet returns.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('No cached messages yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, index) {
                      final m = messages[index];
                      final mine = m['sender_id'] == Supabase.instance.client.auth.currentUser?.id;
                      final queued = m['_offline'] == true;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                          margin: const EdgeInsets.only(bottom: 7),
                          padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m['body']?.toString() ?? ''),
                              if (queued)
                                const Padding(
                                  padding: EdgeInsets.only(top: 3),
                                  child: Text('Queued • will send online', style: TextStyle(fontSize: 9)),
                                ),
                            ],
                          ),
                        ),
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
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: _draftChanged,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(22))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: sending ? null : _send,
                    icon: sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
