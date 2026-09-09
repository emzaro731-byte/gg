import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class WhatsAppStatusStoriesPage extends StatefulWidget {
  const WhatsAppStatusStoriesPage({super.key, required this.statuses, this.profiles = const {}});
  final List<Map<String, dynamic>> statuses;
  final Map<String, Map<String, dynamic>> profiles;
  @override
  State<WhatsAppStatusStoriesPage> createState() => _WhatsAppStatusStoriesPageState();
}

class _WhatsAppStatusStoriesPageState extends State<WhatsAppStatusStoriesPage> with SingleTickerProviderStateMixin {
  late final AnimationController progress;
  VideoPlayerController? video;
  Timer? videoTimer;
  int index = 0;
  String? mediaUrl;
  bool loading = true;
  bool paused = false;
  String? myReaction;
  int viewCount = 0;
  List<Map<String, dynamic>> viewers = [];

  Map<String, dynamic> get status => widget.statuses[index];
  String get type => status['media_type']?.toString() ?? 'text';
  String get caption => status['caption']?.toString() ?? '';
  String? get ownerId => status['user_id']?.toString();
  bool get mine => ownerId == Supabase.instance.client.auth.currentUser?.id;

  String _ownerName() {
    final p = ownerId == null ? null : widget.profiles[ownerId];
    final name = p?['display_name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final username = p?['username']?.toString().trim();
    if (username != null && username.isNotEmpty) return '@$username';
    return mine ? 'My status' : 'GG User';
  }

  String? _avatarUrl(String? id) => widget.profiles[id]?['avatar_url']?.toString();

  @override
  void initState() {
    super.initState();
    progress = AnimationController(vsync: this, duration: const Duration(seconds: 5))..addStatusListener((s) { if (s == AnimationStatus.completed && mounted) _next(); });
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    progress.stop(); progress.reset(); videoTimer?.cancel(); await video?.dispose();
    video = null; mediaUrl = null; loading = true; myReaction = null; viewCount = 0; viewers = [];
    if (mounted) setState(() {});
    final path = status['media_path']?.toString();
    if (type != 'text' && path != null) {
      try {
        mediaUrl = await Supabase.instance.client.storage.from('status-media').createSignedUrl(path, 3600);
        if (type == 'video' && mediaUrl != null) {
          final player = VideoPlayerController.networkUrl(Uri.parse(mediaUrl!));
          await player.initialize(); await player.setLooping(false); await player.play(); video = player;
          player.addListener(() { if (mounted && player.value.isInitialized && player.value.position >= player.value.duration) _next(); });
        }
      } catch (_) { mediaUrl = null; }
    }
    await Future.wait([_recordView(), _loadReactionAndViews()]);
    if (!mounted) return;
    setState(() => loading = false);
    if (type != 'video') progress.forward();
  }

  Future<void> _recordView() async {
    final user = Supabase.instance.client.auth.currentUser; final id = status['id']?.toString();
    if (user == null || id == null) return;
    try { await Supabase.instance.client.from('status_views').upsert({'status_id': id, 'viewer_id': user.id, 'viewed_at': DateTime.now().toUtc().toIso8601String()}); } catch (_) {}
  }

  Future<void> _loadReactionAndViews() async {
    final id = status['id']?.toString(); final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return;
    try {
      final reaction = await Supabase.instance.client.from('status_reactions').select('reaction').eq('status_id', id).eq('user_id', user.id).maybeSingle();
      myReaction = reaction?['reaction']?.toString();
      final rows = await Supabase.instance.client.from('status_views').select('viewer_id, viewed_at').eq('status_id', id).order('viewed_at', ascending: false);
      viewCount = rows.length;
      if (mine) viewers = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
  }

  void _next() { if (index >= widget.statuses.length - 1) { Navigator.pop(context); return; } setState(() => index++); _loadStatus(); }
  void _previous() { if (index == 0) return; setState(() => index--); _loadStatus(); }
  void _togglePause() { paused = !paused; if (paused) { progress.stop(); video?.pause(); } else { progress.forward(); video?.play(); } setState(() {}); }

  Future<void> _react(String reaction) async {
    final id = status['id']?.toString(); final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null || mine) return;
    try {
      if (myReaction == reaction) { await Supabase.instance.client.from('status_reactions').delete().eq('status_id', id).eq('user_id', user.id); if (mounted) setState(() => myReaction = null); }
      else { await Supabase.instance.client.from('status_reactions').upsert({'status_id': id, 'user_id': user.id, 'reaction': reaction}); if (mounted) setState(() => myReaction = reaction); }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reaction could not be saved'))); }
  }

  Future<void> _showReactions() async {
    const reactions = ['❤️','😂','😮','😢','👏','🔥'];
    await showModalBottomSheet(context: context, builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(18), child: Wrap(alignment: WrapAlignment.spaceEvenly, children: [for (final r in reactions) IconButton(tooltip: r, onPressed: () { Navigator.pop(context); _react(r); }, icon: Text(r, style: const TextStyle(fontSize: 30)))]))));
  }

  Future<void> _showViewers() async {
    if (!mine) return;
    final ids = viewers.map((v) => v['viewer_id']?.toString()).whereType<String>().toList();
    final names = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      try {
        final rows = await Supabase.instance.client.from('profiles').select('id, display_name, username, avatar_url').inFilter('id', ids);
        for (final row in List<Map<String, dynamic>>.from(rows)) names[row['id'].toString()] = Map<String, dynamic>.from(row);
      } catch (_) {}
    }
    if (!mounted) return;
    showModalBottomSheet(context: context, showDragHandle: true, builder: (context) => SafeArea(child: SizedBox(height: 420, child: Column(children: [
      ListTile(title: Text('$viewCount view${viewCount == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w900))),
      Expanded(child: ListView.builder(itemCount: viewers.length, itemBuilder: (_, i) {
        final id = viewers[i]['viewer_id']?.toString(); final p = names[id]; final name = p?['display_name']?.toString() ?? p?['username']?.toString() ?? 'GG User'; final avatar = p?['avatar_url']?.toString();
        return ListTile(leading: CircleAvatar(backgroundImage: avatar != null && avatar.startsWith('http') ? NetworkImage(avatar) : null, child: avatar == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase()) : null), title: Text(name), subtitle: Text('Viewed ${viewers[i]['viewed_at'] ?? ''}'));
      })),
    ]))));
  }

  Future<void> _reply() async {
    final controller = TextEditingController();
    final message = await showModalBottomSheet<String>(context: context, backgroundColor: Colors.transparent, isScrollControlled: true, builder: (context) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: SafeArea(child: Container(padding: const EdgeInsets.fromLTRB(16, 12, 16, 18), decoration: const BoxDecoration(color: Color(0xFF17181D), borderRadius: BorderRadius.vertical(top: Radius.circular(24))), child: Row(children: [Expanded(child: TextField(controller: controller, autofocus: true, maxLength: 500, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Reply to status…', hintStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none))), const SizedBox(width: 8), IconButton.filled(onPressed: () => Navigator.pop(context, controller.text.trim()), icon: const Icon(Icons.send_rounded))])))));
    controller.dispose();
    if (message == null || message.isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser; final owner = ownerId;
    if (user == null || owner == null) return;
    try {
      final memberships = await Supabase.instance.client.from('conversation_members').select('conversation_id').eq('user_id', user.id);
      String? conversationId;
      for (final m in List<Map<String, dynamic>>.from(memberships)) {
        final id = m['conversation_id'];
        final other = await Supabase.instance.client.from('conversation_members').select('user_id').eq('conversation_id', id).eq('user_id', owner).maybeSingle();
        if (other != null) { conversationId = id.toString(); break; }
      }
      if (conversationId == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open a chat with this person first, then reply to the status.')));
        return;
      }
      await Supabase.instance.client.from('messages').insert({'conversation_id': conversationId, 'sender_id': user.id, 'body': message, 'message_type': 'text'});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent')));
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply could not be sent'))); }
  }

  Future<void> _deleteMine() async {
    final user = Supabase.instance.client.auth.currentUser; final id = status['id']?.toString(); final path = status['media_path']?.toString();
    if (user == null || !mine || id == null) return;
    try { await Supabase.instance.client.from('statuses').delete().eq('id', id).eq('user_id', user.id); if (path != null) await Supabase.instance.client.storage.from('status-media').remove([path]); if (mounted) Navigator.pop(context); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete status'))); }
  }

  @override
  void dispose() { videoTimer?.cancel(); progress.dispose(); video?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: GestureDetector(
    onTapDown: (d) { final width = MediaQuery.sizeOf(context).width; if (d.localPosition.dx < width * .35) _previous(); else if (d.localPosition.dx > width * .65) _next(); else _togglePause(); },
    onLongPressStart: (_) { if (!paused) _togglePause(); }, onLongPressEnd: (_) { if (paused) _togglePause(); },
    child: Stack(children: [Positioned.fill(child: _content()), SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 0), child: Column(children: [
      Row(children: [for (var i = 0; i < widget.statuses.length; i++) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: AnimatedBuilder(animation: progress, builder: (_, __) => LinearProgressIndicator(value: i < index ? 1 : i == index ? progress.value : 0, minHeight: 3, backgroundColor: Colors.white30, borderRadius: BorderRadius.circular(4)))))]),
      const SizedBox(height: 12), Row(children: [CircleAvatar(radius: 20, backgroundImage: _avatarUrl(ownerId) != null && _avatarUrl(ownerId)!.startsWith('http') ? NetworkImage(_avatarUrl(ownerId)!) : null, backgroundColor: Colors.white24, child: _avatarUrl(ownerId) == null ? const Icon(Icons.person, color: Colors.white) : null), const SizedBox(width: 10), Expanded(child: Text(_ownerName(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))), if (mine) IconButton(onPressed: _showViewers, icon: const Icon(Icons.visibility_outlined, color: Colors.white)), if (mine) IconButton(onPressed: _deleteMine, icon: const Icon(Icons.delete_outline, color: Colors.white)), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))]),
    ]))),
    Positioned(left: 12, right: 12, bottom: 18, child: SafeArea(child: Row(children: [if (!mine) IconButton(onPressed: _showReactions, icon: Text(myReaction ?? '❤️', style: const TextStyle(fontSize: 28))), if (!mine) const SizedBox(width: 4), if (!mine) Expanded(child: OutlinedButton.icon(onPressed: _reply, icon: const Icon(Icons.reply_rounded, color: Colors.white), label: const Text('Reply', style: TextStyle(color: Colors.white)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), padding: const EdgeInsets.symmetric(vertical: 14)))), if (mine) Expanded(child: OutlinedButton.icon(onPressed: _showViewers, icon: const Icon(Icons.visibility_outlined, color: Colors.white), label: Text('$viewCount views', style: const TextStyle(color: Colors.white)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), padding: const EdgeInsets.symmetric(vertical: 14))))]))),
  ])));

  Widget _content() {
    if (loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (type == 'text') return Container(alignment: Alignment.center, padding: const EdgeInsets.all(34), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Theme.of(context).colorScheme.primary, Colors.black])), child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)));
    if (mediaUrl == null) return const Center(child: Text('Unable to load status', style: TextStyle(color: Colors.white)));
    if (type == 'video' && video != null) return Center(child: AspectRatio(aspectRatio: video!.value.aspectRatio == 0 ? 16 / 9 : video!.value.aspectRatio, child: VideoPlayer(video!)));
    return Center(child: Image.network(mediaUrl!, fit: BoxFit.contain));
  }
}
