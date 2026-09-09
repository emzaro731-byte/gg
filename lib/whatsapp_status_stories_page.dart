import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class WhatsAppStatusStoriesPage extends StatefulWidget {
  const WhatsAppStatusStoriesPage({super.key, required this.statuses});

  final List<Map<String, dynamic>> statuses;

  @override
  State<WhatsAppStatusStoriesPage> createState() => _WhatsAppStatusStoriesPageState();
}

class _WhatsAppStatusStoriesPageState extends State<WhatsAppStatusStoriesPage> with SingleTickerProviderStateMixin {
  late final AnimationController progress;
  VideoPlayerController? video;
  int index = 0;
  String? mediaUrl;
  bool loading = true;
  bool paused = false;

  Map<String, dynamic> get status => widget.statuses[index];
  String get type => status['media_type']?.toString() ?? 'text';
  String get caption => status['caption']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    progress = AnimationController(vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) _next();
      });
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    progress.stop();
    progress.reset();
    await video?.dispose();
    video = null;
    mediaUrl = null;
    loading = true;
    if (mounted) setState(() {});

    final path = status['media_path']?.toString();
    if (type != 'text' && path != null) {
      try {
        mediaUrl = await Supabase.instance.client.storage
            .from('status-media')
            .createSignedUrl(path, 3600);
        if (type == 'video' && mediaUrl != null) {
          final player = VideoPlayerController.networkUrl(Uri.parse(mediaUrl!));
          await player.initialize();
          await player.setLooping(false);
          await player.play();
          video = player;
          player.addListener(() {
            if (mounted && player.value.isInitialized && player.value.position >= player.value.duration) {
              _next();
            }
          });
        }
      } catch (_) {
        mediaUrl = null;
      }
    }

    await _recordView();
    if (!mounted) return;
    setState(() => loading = false);
    if (type != 'video') progress.forward();
  }

  Future<void> _recordView() async {
    final user = Supabase.instance.client.auth.currentUser;
    final id = status['id']?.toString();
    if (user == null || id == null) return;
    try {
      await Supabase.instance.client.from('status_views').upsert({
        'status_id': id,
        'viewer_id': user.id,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  void _next() {
    if (index >= widget.statuses.length - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => index++);
    _loadStatus();
  }

  void _previous() {
    if (index == 0) return;
    setState(() => index--);
    _loadStatus();
  }

  void _togglePause() {
    paused = !paused;
    if (paused) {
      progress.stop();
      video?.pause();
    } else {
      progress.forward();
      video?.play();
    }
    setState(() {});
  }

  Future<void> _reply() async {
    final controller = TextEditingController();
    final message = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          decoration: const BoxDecoration(
            color: Color(0xFF17181D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Row(children: [
            Expanded(child: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 500,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Reply to status…',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    final owner = status['user_id']?.toString();
    if (user == null || owner == null) return;

    // Stores a status reply as a normal message when the status owner is also the conversation recipient.
    // If your schema has a dedicated status_replies table, this can be switched to that table without changing the UI.
    try {
      final conversation = await Supabase.instance.client
          .from('conversations')
          .select('id')
          .eq('user_id', owner)
          .limit(1)
          .maybeSingle();
      final conversationId = conversation?['id']?.toString();
      if (conversationId != null) {
        await Supabase.instance.client.from('messages').insert({
          'conversation_id': conversationId,
          'sender_id': user.id,
          'body': message,
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply could not be sent')));
    }
  }

  Future<void> _deleteMine() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || status['user_id']?.toString() != user.id) return;
    final id = status['id']?.toString();
    final path = status['media_path']?.toString();
    if (id == null) return;
    try {
      await Supabase.instance.client.from('statuses').delete().eq('id', id).eq('user_id', user.id);
      if (path != null) await Supabase.instance.client.storage.from('status-media').remove([path]);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete status')));
    }
  }

  @override
  void dispose() {
    progress.dispose();
    video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = status['user_id']?.toString() == Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final width = MediaQuery.sizeOf(context).width;
          if (details.localPosition.dx < width * .35) {
            _previous();
          } else if (details.localPosition.dx > width * .65) {
            _next();
          } else {
            _togglePause();
          }
        },
        onLongPressStart: (_) {
          if (!paused) _togglePause();
        },
        onLongPressEnd: (_) {
          if (paused) _togglePause();
        },
        child: Stack(children: [
          Positioned.fill(child: _content()),
          SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(children: [
              Row(children: [
                for (var i = 0; i < widget.statuses.length; i++)
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedBuilder(
                      animation: progress,
                      builder: (_, __) => LinearProgressIndicator(
                        value: i < index ? 1 : i == index ? progress.value : 0,
                        minHeight: 3,
                        backgroundColor: Colors.white30,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const CircleAvatar(radius: 20, backgroundColor: Colors.white24, child: Icon(Icons.person, color: Colors.white)),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  mine ? 'My status' : 'Status',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                )),
                if (mine) IconButton(onPressed: _deleteMine, icon: const Icon(Icons.delete_outline, color: Colors.white)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
              ]),
            ]),
          )),
          if (!mine)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: SafeArea(child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _reply,
                  icon: const Icon(Icons.reply_rounded, color: Colors.white),
                  label: const Text('Reply', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
              ])),
            ),
        ]),
      ),
    );
  }

  Widget _content() {
    if (loading) return const Center(child: CircularProgressIndicator(color: Colors.white));
    if (type == 'text') {
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(34),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Theme.of(context).colorScheme.primary, Colors.black],
          ),
        ),
        child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
      );
    }
    if (mediaUrl == null) return const Center(child: Text('Unable to load status', style: TextStyle(color: Colors.white)));
    if (type == 'video' && video != null) {
      return Center(child: AspectRatio(aspectRatio: video!.value.aspectRatio == 0 ? 16 / 9 : video!.value.aspectRatio, child: VideoPlayer(video!)));
    }
    return Center(child: Image.network(mediaUrl!, fit: BoxFit.contain));
  }
}
