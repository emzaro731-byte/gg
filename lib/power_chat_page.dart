import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';

class PowerChatPage extends StatefulWidget {
  const PowerChatPage({required this.conversationId, required this.title, super.key});
  final String conversationId;
  final String title;

  @override
  State<PowerChatPage> createState() => _PowerChatPageState();
}

class _PowerChatPageState extends State<PowerChatPage> {
  String wallpaper = 'default';
  String disappearing = 'off';
  bool chatPinned = false;
  bool chatMuted = false;

  SupabaseClient get supabase => Supabase.instance.client;
  String get _wallpaperKey => 'chat_wallpaper_${widget.conversationId}';

  static const wallpapers = <String, String>{
    'default': 'Default',
    'midnight': 'Midnight',
    'ocean': 'Ocean blue',
    'purple': 'Royal purple',
    'forest': 'Forest',
    'sunset': 'Sunset',
    'rose': 'Rose',
    'lavender': 'Lavender',
    'sky': 'Sky',
    'mint': 'Mint',
    'peach': 'Peach',
    'sand': 'Warm sand',
    'coffee': 'Coffee',
    'aurora': 'Aurora',
    'night': 'Starry night',
    'emerald': 'Emerald',
    'coral': 'Coral',
    'ice': 'Ice',
    'slate': 'Slate',
    'plain': 'Plain',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    wallpaper = prefs.getString(_wallpaperKey) ?? 'default';
    if (!wallpapers.containsKey(wallpaper)) wallpaper = 'default';
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final row = await supabase.from('conversation_user_settings').select('pinned_at,muted_until').eq('conversation_id', widget.conversationId).eq('user_id', uid).maybeSingle();
        chatPinned = row?['pinned_at'] != null;
        final mutedUntil = row?['muted_until']?.toString();
        chatMuted = mutedUntil != null && DateTime.tryParse(mutedUntil)?.isAfter(DateTime.now().toUtc()) == true;
      }
      final pref = await supabase.from('conversation_preferences').select('disappearing_seconds').eq('conversation_id', widget.conversationId).eq('user_id', supabase.auth.currentUser!.id).maybeSingle();
      final seconds = (pref?['disappearing_seconds'] as num?)?.toInt() ?? 0;
      disappearing = seconds >= 604800 ? '7d' : seconds >= 86400 ? '24h' : 'off';
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _wallpaper() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(children: [Icon(Icons.wallpaper_outlined), SizedBox(width: 10), Text('Chat wallpaper', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))]),
              ),
              const Divider(height: 1),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.7),
                  itemCount: wallpapers.length,
                  itemBuilder: (_, index) {
                    final entry = wallpapers.entries.elementAt(index);
                    final selected = entry.key == wallpaper;
                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.pop(context, entry.key),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: Stack(fit: StackFit.expand, children: [
                            DecoratedBox(decoration: _wallpaperDecorationFor(entry.key, context)),
                            Center(child: Text(entry.value, style: TextStyle(fontWeight: FontWeight.w800, color: _previewTextColor(entry.key, context), shadows: const [Shadow(blurRadius: 4)]))),
                            if (selected) const Positioned(right: 8, top: 8, child: CircleAvatar(radius: 13, child: Icon(Icons.check, size: 17))),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperKey, value);
    if (mounted) {
      setState(() => wallpaper = value);
      _toast('Wallpaper changed to ${wallpapers[value]}');
    }
  }

  Color _previewTextColor(String key, BuildContext context) => const {'midnight': Colors.white, 'night': Colors.white, 'slate': Colors.white, 'aurora': Colors.white}[key] ?? Theme.of(context).colorScheme.onSurface;

  BoxDecoration _wallpaperDecorationFor(String key, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const gradients = <String, List<Color>>{
      'ocean': [Color(0xFFE7F5FF), Color(0xFF82B8E8)],
      'purple': [Color(0xFFF1E9FF), Color(0xFFB79AE8)],
      'forest': [Color(0xFFEAF7EF), Color(0xFF6FA57F)],
      'sunset': [Color(0xFFFFE4D0), Color(0xFFFF8A65)],
      'rose': [Color(0xFFFFE4EC), Color(0xFFE88FA8)],
      'lavender': [Color(0xFFF3EDFF), Color(0xFF9E83D4)],
      'sky': [Color(0xFFE0F4FF), Color(0xFF65BCE8)],
      'mint': [Color(0xFFE4FFF5), Color(0xFF62C9A4)],
      'peach': [Color(0xFFFFF0E3), Color(0xFFFFB47A)],
      'sand': [Color(0xFFFFF5DC), Color(0xFFD9B77A)],
      'coffee': [Color(0xFFF0E0D2), Color(0xFF8B6250)],
      'aurora': [Color(0xFF102A43), Color(0xFF267D73), Color(0xFF5B3C88)],
      'night': [Color(0xFF07111F), Color(0xFF162C4D), Color(0xFF291C45)],
      'emerald': [Color(0xFFE1F7EC), Color(0xFF208B67)],
      'coral': [Color(0xFFFFE6E1), Color(0xFFE86F61)],
      'ice': [Color(0xFFF0FBFF), Color(0xFF8AC8DA)],
      'slate': [Color(0xFF263241), Color(0xFF526477)],
    };
    if (key == 'plain') return BoxDecoration(color: scheme.surface);
    if (key == 'default') return BoxDecoration(color: scheme.scaffoldBackgroundColor);
    if (key == 'midnight') return const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF101A36), Color(0xFF050816)]));
    final colors = gradients[key] ?? const [Color(0xFFE7F5FF), Color(0xFF82B8E8)];
    return BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors));
  }

  BoxDecoration _wallpaperDecoration(BuildContext context) => _wallpaperDecorationFor(wallpaper, context);

  Future<void> _disappearing() async {
    const choices = {'off': 'Off', '24h': '24 hours', '7d': '7 days'};
    final value = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Disappearing messages'), content: Column(mainAxisSize: MainAxisSize.min, children: choices.entries.map((e) => RadioListTile<String>(value: e.key, groupValue: disappearing, title: Text(e.value), onChanged: (v) => Navigator.pop(context, v))).toList())));
    if (value == null) return;
    final seconds = value == '24h' ? 86400 : value == '7d' ? 604800 : 0;
    try {
      await supabase.rpc('set_disappearing_messages', params: {'p_conversation_id': widget.conversationId, 'p_seconds': seconds});
      if (mounted) setState(() => disappearing = value);
      _toast('Disappearing messages updated');
    } catch (_) { _toast('Could not update disappearing messages.'); }
  }

  Future<void> _pinned() async {
    try {
      final rows = await supabase.from('message_pins').select('message_id,pinned_at,messages(body,conversation_id)').order('pinned_at', ascending: false);
      final filtered = (rows as List).where((r) { final m = r['messages']; return m is Map && m['conversation_id']?.toString() == widget.conversationId; }).toList();
      if (!mounted) return;
      showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: filtered.isEmpty ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No pinned messages yet.'))) : ListView.builder(shrinkWrap: true, itemCount: filtered.length, itemBuilder: (_, i) { final m = filtered[i]; final message = m['messages']; return ListTile(leading: const Icon(Icons.push_pin_rounded), title: Text(message is Map ? message['body']?.toString() ?? 'Message' : 'Message'), subtitle: Text(m['pinned_at']?.toString() ?? '')); })));
    } catch (_) { _toast('Pinned messages are unavailable right now.'); }
  }

  Future<void> _togglePinChat() async {
    try { await supabase.rpc('set_conversation_list_state', params: {'target_conversation_id': widget.conversationId, 'pin_state': !chatPinned}); if (mounted) { setState(() => chatPinned = !chatPinned); _toast(chatPinned ? 'Chat pinned' : 'Chat unpinned'); } } catch (_) { _toast('Could not change chat pin.'); }
  }

  Future<void> _toggleMute() async {
    try { await supabase.rpc('set_conversation_list_state', params: {'target_conversation_id': widget.conversationId, 'mute_until_value': chatMuted ? null : DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(), 'clear_mute': chatMuted}); if (mounted) { setState(() => chatMuted = !chatMuted); _toast(chatMuted ? 'Notifications muted for 1 hour' : 'Notifications unmuted'); } } catch (_) { _toast('Could not change notification settings.'); }
  }

  Future<void> _searchMessages() async {
    final query = await showDialog<String>(context: context, builder: (_) { final controller = TextEditingController(); return AlertDialog(title: const Text('Search messages'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Search this chat'), onSubmitted: (value) => Navigator.pop(context, value.trim())), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Search'))]); });
    if (query == null || query.isEmpty) return;
    try { final rows = await supabase.from('messages').select('id,body,created_at,sender_id').eq('conversation_id', widget.conversationId).ilike('body', '%$query%').order('created_at', ascending: false).limit(50); if (!mounted) return; showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: rows.isEmpty ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No messages found.'))) : ListView.builder(shrinkWrap: true, itemCount: rows.length, itemBuilder: (_, i) => ListTile(leading: const Icon(Icons.message_outlined), title: Text(rows[i]['body']?.toString() ?? ''), subtitle: Text(rows[i]['created_at']?.toString() ?? ''))))); } catch (_) { _toast('Search is unavailable right now.'); }
  }

  Future<void> _mediaAndFiles() async {
    try { final rows = await supabase.from('messages').select('body,message_type,media_url,file_name,file_size,created_at').eq('conversation_id', widget.conversationId).neq('media_url', null).order('created_at', ascending: false).limit(100); if (!mounted) return; showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: rows.isEmpty ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No media or files in this chat.'))) : ListView.builder(shrinkWrap: true, itemCount: rows.length, itemBuilder: (_, i) => ListTile(leading: Icon(_iconForType(rows[i]['message_type']?.toString())), title: Text(rows[i]['file_name']?.toString() ?? rows[i]['body']?.toString() ?? 'Media'), subtitle: Text(rows[i]['created_at']?.toString() ?? ''))))); } catch (_) { _toast('Media and files are unavailable right now.'); }
  }

  IconData _iconForType(String? type) { switch (type) { case 'image': return Icons.image_outlined; case 'video': return Icons.videocam_outlined; case 'audio': return Icons.audiotrack_outlined; default: return Icons.insert_drive_file_outlined; } }

  void _menu() {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Wrap(children: [const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 10), child: Text('Chat options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), ListTile(leading: const Icon(Icons.search_rounded), title: const Text('Search messages'), onTap: () { Navigator.pop(context); _searchMessages(); }), ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Media, links & files'), onTap: () { Navigator.pop(context); _mediaAndFiles(); }), ListTile(leading: const Icon(Icons.push_pin_outlined), title: Text(chatPinned ? 'Unpin chat' : 'Pin chat'), onTap: () { Navigator.pop(context); _togglePinChat(); }), ListTile(leading: const Icon(Icons.push_pin_rounded), title: const Text('Pinned messages'), onTap: () { Navigator.pop(context); _pinned(); }), ListTile(leading: const Icon(Icons.notifications_off_outlined), title: Text(chatMuted ? 'Unmute notifications' : 'Mute notifications'), subtitle: Text(chatMuted ? 'Muted for 1 hour' : 'Mute for 1 hour'), onTap: () { Navigator.pop(context); _toggleMute(); }), ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Disappearing messages'), subtitle: Text(disappearing == 'off' ? 'Off' : disappearing == '24h' ? '24 hours' : '7 days'), onTap: () { Navigator.pop(context); _disappearing(); }), ListTile(leading: const Icon(Icons.wallpaper_outlined), title: const Text('Chat wallpaper'), subtitle: Text(wallpapers[wallpaper] ?? 'Default'), onTap: () { Navigator.pop(context); _wallpaper(); })])));
  }

  void _toast(String message) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }

  @override
  Widget build(BuildContext context) {
    final transparentTheme = Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.transparent);
    return Stack(fit: StackFit.expand, children: [DecoratedBox(decoration: _wallpaperDecoration(context)), Theme(data: transparentTheme, child: ChatPage(conversationId: widget.conversationId, title: widget.title)), Positioned(top: 4, right: 145, child: Material(color: Theme.of(context).colorScheme.surface.withValues(alpha: .88), shape: const CircleBorder(), child: IconButton(tooltip: 'Chat options', onPressed: _menu, icon: const Icon(Icons.more_vert_rounded))))]);
  }
}
