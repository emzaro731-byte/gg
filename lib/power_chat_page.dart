import 'package:flutter/material.dart';
import 'chat_page.dart';
import 'services/chat_power_service.dart';

class PowerChatPage extends StatefulWidget {
  const PowerChatPage({required this.conversationId, required this.title, super.key});
  final String conversationId;
  final String title;

  @override
  State<PowerChatPage> createState() => _PowerChatPageState();
}

class _PowerChatPageState extends State<PowerChatPage> {
  late final ChatPowerService power;
  String wallpaper = 'default';
  String disappearing = 'off';

  @override
  void initState() {
    super.initState();
    power = ChatPowerService(widget.conversationId);
    _load();
  }

  Future<void> _load() async {
    wallpaper = await power.wallpaper();
    disappearing = await power.disappearing();
    if (mounted) setState(() {});
  }

  Future<void> _wallpaper() async {
    const choices = {'default': 'Default', 'midnight': 'Midnight', 'blue': 'Ocean blue', 'plain': 'Plain'};
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Chat wallpaper'),
        content: Column(mainAxisSize: MainAxisSize.min, children: choices.entries.map((e) => RadioListTile<String>(value: e.key, groupValue: wallpaper, title: Text(e.value), onChanged: (v) => Navigator.pop(context, v))).toList()),
      ),
    );
    if (value == null) return;
    await power.setWallpaper(value);
    if (mounted) setState(() => wallpaper = value);
  }

  Future<void> _disappearing() async {
    const choices = {'off': 'Off', '24h': '24 hours', '7d': '7 days'};
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disappearing messages'),
        content: Column(mainAxisSize: MainAxisSize.min, children: choices.entries.map((e) => RadioListTile<String>(value: e.key, groupValue: disappearing, title: Text(e.value), onChanged: (v) => Navigator.pop(context, v))).toList()),
      ),
    );
    if (value == null) return;
    final seconds = value == '24h' ? 86400 : value == '7d' ? 604800 : 0;
    try {
      await power.setDisappearing(value);
      await ChatPowerServiceRpc.setSeconds(widget.conversationId, seconds);
      if (mounted) setState(() => disappearing = value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update disappearing messages.')));
    }
  }

  Future<void> _pinned() async {
    try {
      final rows = await ChatPowerServiceRpc.pinned(widget.conversationId);
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(
          child: rows.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No pinned messages yet.')))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final m = rows[i];
                    return ListTile(leading: const Icon(Icons.push_pin_rounded), title: Text(m['body']?.toString() ?? 'Message'), subtitle: Text(m['pinned_at']?.toString() ?? ''));
                  },
                ),
        ),
      );
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pinned messages are unavailable right now.')));
    }
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 10), child: Text('Chat options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ListTile(leading: const Icon(Icons.push_pin_outlined), title: const Text('Pinned messages'), onTap: () { Navigator.pop(context); _pinned(); }),
          ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Disappearing messages'), subtitle: Text(disappearing == 'off' ? 'Off' : disappearing == '24h' ? '24 hours' : '7 days'), onTap: () { Navigator.pop(context); _disappearing(); }),
          ListTile(leading: const Icon(Icons.wallpaper_outlined), title: const Text('Chat wallpaper'), subtitle: Text(wallpaper), onTap: () { Navigator.pop(context); _wallpaper(); }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ChatPage(conversationId: widget.conversationId, title: widget.title),
        Positioned(
          top: 4,
          right: 145,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
            shape: const CircleBorder(),
            child: IconButton(tooltip: 'Chat options', onPressed: _menu, icon: const Icon(Icons.more_vert_rounded)),
          ),
        ),
      ],
    );
  }
}

class ChatPowerServiceRpc {
  static final _client = ChatPowerServiceClient.client;
  static Future<void> setSeconds(String conversationId, int seconds) async {
    await _client.rpc('set_disappearing_messages', params: {'p_conversation_id': conversationId, 'p_seconds': seconds});
  }

  static Future<List<Map<String, dynamic>>> pinned(String conversationId) async {
    final rows = await _client.from('message_pins').select('message_id,pinned_at,messages(body)').eq('conversation_id', conversationId).order('pinned_at', ascending: false);
    return (rows as List).map((r) {
      final message = r['messages'];
      return {'body': message is Map ? message['body'] : 'Message', 'pinned_at': r['pinned_at']};
    }).toList();
  }
}

class ChatPowerServiceClient {
  static dynamic get client => throw UnimplementedError('Use Supabase.instance.client');
}
