import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'premium_chats_page.dart';
import 'services/offline_cache_service.dart';

class OfflineFirstChatsPage extends StatefulWidget {
  const OfflineFirstChatsPage({super.key, this.onlineUsers = const <String>{}});

  final Set<String> onlineUsers;

  @override
  State<OfflineFirstChatsPage> createState() => _OfflineFirstChatsPageState();
}

class _OfflineFirstChatsPageState extends State<OfflineFirstChatsPage>
    with WidgetsBindingObserver {
  final connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _conversationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _settingsSubscription;

  List<Map<String, dynamic>> _cachedConversations = [];
  List<Map<String, dynamic>> _cachedSettings = [];
  bool _online = true;
  bool _loadingCache = true;

  SupabaseClient get supabase => Supabase.instance.client;
  String? get userId => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final id = userId;
    if (id == null) return;

    final cached = await OfflineCacheService.instance.loadConversations(id);
    final settings = await OfflineCacheService.instance.loadConversationSettings(id);
    if (!mounted) return;
    setState(() {
      _cachedConversations = cached;
      _cachedSettings = settings;
      _loadingCache = false;
    });

    await _refreshConnectivity();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(_setConnectivity);
  }

  Future<void> _refreshConnectivity() async {
    try {
      _setConnectivity(await connectivity.checkConnectivity());
    } catch (_) {
      _setConnectivity(const [ConnectivityResult.none]);
    }
  }

  void _setConnectivity(List<ConnectivityResult> result) {
    final online = !result.contains(ConnectivityResult.none) && result.isNotEmpty;
    if (!mounted) return;
    if (_online == online) {
      if (online) _startCaching();
      return;
    }
    setState(() => _online = online);
    if (online) {
      _startCaching();
    } else {
      _stopCaching();
    }
  }

  void _startCaching() {
    final id = userId;
    if (id == null || _conversationSubscription != null) return;

    _conversationSubscription = supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .listen((rows) async {
          await OfflineCacheService.instance.saveConversations(id, rows);
          if (mounted) setState(() => _cachedConversations = rows);
          await _cacheMessages(id, rows);
        }, onError: (_) {});

    _settingsSubscription = supabase
        .from('conversation_user_settings')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('user_id', id)
        .listen((rows) async {
          await OfflineCacheService.instance.saveConversationSettings(id, rows);
          if (mounted) setState(() => _cachedSettings = rows);
        }, onError: (_) {});
  }

  Future<void> _cacheMessages(
    String id,
    List<Map<String, dynamic>> conversations,
  ) async {
    // Keep a useful local history without trying to mirror an unlimited mailbox.
    for (final conversation in conversations.take(30)) {
      final conversationId = conversation['id']?.toString();
      if (conversationId == null || conversationId.isEmpty) continue;
      try {
        final rows = await supabase
            .from('messages')
            .select('id, conversation_id, sender_id, body, message_type, media_url, file_name, file_size, mime_type, duration_ms, reply_to, edited_at, created_at')
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: false)
            .limit(500);
        final messages = List<Map<String, dynamic>>.from(rows)
          ..sort((a, b) => (a['created_at']?.toString() ?? '')
              .compareTo(b['created_at']?.toString() ?? ''));
        await OfflineCacheService.instance.saveMessages(id, conversationId, messages);
      } catch (_) {
        // A single failed conversation must never break offline mode.
      }
    }
  }

  Future<void> _stopCaching() async {
    await _conversationSubscription?.cancel();
    await _settingsSubscription?.cancel();
    _conversationSubscription = null;
    _settingsSubscription = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshConnectivity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _stopCaching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online) {
      return Stack(
        children: [
          PremiumChatsPage(onlineUsers: widget.onlineUsers),
          _statusBanner(context, false),
        ],
      );
    }

    return Column(
      children: [
        _statusBanner(context, true),
        Expanded(child: _offlineList(context)),
      ],
    );
  }

  Widget _statusBanner(BuildContext context, bool offline) {
    return Material(
      color: offline
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Colors.transparent,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: offline
            ? const Padding(
                key: ValueKey('offline'),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline • showing your previous chats',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(key: ValueKey('online'), height: 0),
      ),
    );
  }

  Widget _offlineList(BuildContext context) {
    if (_loadingCache) return const Center(child: CircularProgressIndicator());

    final settings = <String, Map<String, dynamic>>{
      for (final row in _cachedSettings) row['conversation_id'].toString(): row,
    };

    final rows = [..._cachedConversations]..sort((a, b) {
      final ap = settings[a['id'].toString()]?['pinned_at'] != null;
      final bp = settings[b['id'].toString()]?['pinned_at'] != null;
      if (ap != bp) return ap ? -1 : 1;
      return (b['updated_at']?.toString() ?? '')
          .compareTo(a['updated_at']?.toString() ?? '');
    });

    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 52),
              SizedBox(height: 12),
              Text('You are offline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              SizedBox(height: 6),
              Text('Open chats while online first. GG will keep them on this device for offline use.', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final chat = rows[index];
        final id = chat['id'].toString();
        final title = (chat['title'] ?? 'Conversation').toString();
        final initial = title.isEmpty ? '?' : title.substring(0, 1).toUpperCase();
        final setting = settings[id];
        final pinned = setting?['pinned_at'] != null;
        final muted = setting?['muted_until'] != null;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            leading: CircleAvatar(radius: 27, child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900))),
            title: Row(children: [
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (pinned) const Icon(Icons.push_pin_rounded, size: 16),
              if (muted) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.notifications_off_rounded, size: 16)),
            ]),
            subtitle: Text((chat['last_message'] ?? 'Tap to open').toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _openOfflineChat(context, id, title),
          ),
        );
      },
    );
  }

  Future<void> _openOfflineChat(BuildContext context, String conversationId, String title) async {
    final id = userId;
    if (id == null) return;
    final messages = await OfflineCacheService.instance.loadMessages(id, conversationId);
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineMessagesPage(title: title, messages: messages)));
  }
}

class OfflineMessagesPage extends StatelessWidget {
  const OfflineMessagesPage({super.key, required this.title, required this.messages});

  final String title;
  final List<Map<String, dynamic>> messages;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          CircleAvatar(child: Text(title.isEmpty ? '?' : title[0].toUpperCase())),
          const SizedBox(width: 10),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: messages.isEmpty
          ? const Center(child: Text('No messages saved on this device yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final body = (message['body'] ?? '').toString();
                final mine = message['sender_id'] == Supabase.instance.client.auth.currentUser?.id;
                final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                    margin: const EdgeInsets.only(bottom: 7),
                    padding: const EdgeInsets.fromLTRB(14, 10, 11, 7),
                    decoration: BoxDecoration(
                      color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(body),
                      if (created != null)
                        Text('${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}', style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
