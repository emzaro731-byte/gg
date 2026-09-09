import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class WhatsAppStatusPage extends StatefulWidget {
  const WhatsAppStatusPage({super.key});

  @override
  State<WhatsAppStatusPage> createState() => _WhatsAppStatusPageState();
}

class _WhatsAppStatusPageState extends State<WhatsAppStatusPage> {
  final supabase = Supabase.instance.client;
  bool posting = false;

  Stream<List<Map<String, dynamic>>> get _statuses => supabase
      .from('statuses')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  Future<void> _postText() async {
    final controller = TextEditingController();
    Color background = const Color(0xFF172554);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Text status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                height: 170,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(20),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 5,
                  maxLength: 500,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'Type a status...',
                    hintStyle: TextStyle(color: Colors.white60),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final color in [
                    const Color(0xFF172554),
                    const Color(0xFF14532D),
                    const Color(0xFF581C87),
                    const Color(0xFF7C2D12),
                    const Color(0xFF0F172A),
                  ])
                    GestureDetector(
                      onTap: () => setDialogState(() => background = color),
                      child: CircleAvatar(backgroundColor: color, radius: 16),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Post'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    await _runPost(() async {
      await supabase.from('statuses').insert({
        'user_id': supabase.auth.currentUser!.id,
        'media_type': 'text',
        'caption': result,
      });
    });
  }

  Future<void> _postMedia({bool camera = false}) async {
    if (posting) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    final bytes = file!.bytes!;
    final extension = (file.extension ?? 'jpg').toLowerCase();
    final isVideo = ['mp4', 'mov', 'm4v', 'webm'].contains(extension);
    final type = isVideo ? 'video' : 'image';
    final userId = supabase.auth.currentUser!.id;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.$extension';

    await _runPost(() async {
      await supabase.storage.from('status-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: _contentType(extension, isVideo),
          upsert: false,
        ),
      );
      await supabase.from('statuses').insert({
        'user_id': userId,
        'media_path': path,
        'media_type': type,
      });
    });
  }

  String _contentType(String extension, bool video) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'm4v': 'video/x-m4v',
      'webm': 'video/webm',
    };
    return map[extension] ?? (video ? 'video/*' : 'image/*');
  }

  Future<void> _runPost(Future<void> Function() action) async {
    if (posting) return;
    setState(() => posting = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status posted')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post status. Check your connection and try again.')));
      }
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  Future<String?> _url(String path) async {
    try {
      return await supabase.storage.from('status-media').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser?.id;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _statuses,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Unable to load updates right now.'));
        }
        final now = DateTime.now();
        final all = (snapshot.data ?? []).where((s) {
          final expiry = DateTime.tryParse(s['expires_at']?.toString() ?? '');
          return expiry == null || expiry.isAfter(now);
        }).toList();
        final mine = all.where((s) => s['user_id'] == me).toList();
        final recent = all.where((s) => s['user_id'] != me).toList();

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(context, mine)),
            if (posting)
              const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text('Recent updates', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ),
            ),
            if (recent.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No recent updates yet.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                sliver: SliverList.builder(
                  itemCount: recent.length,
                  itemBuilder: (_, index) => _StatusCard(
                    status: recent[index],
                    signedUrl: _url,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewer(status: recent[index], signedUrl: _url))),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, List<Map<String, dynamic>> mine) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Avatar(label: 'You', active: mine.isNotEmpty, radius: 31),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My status', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    Text(mine.isEmpty ? 'Share a photo, video or text' : '${mine.length} active update${mine.length == 1 ? '' : 's'}'),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Create status',
                onSelected: (value) {
                  if (value == 'text') _postText();
                  if (value == 'gallery') _postMedia();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.text_fields), title: Text('Text'))),
                  PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('Photo or video'))),
                ],
                child: const Icon(Icons.add_circle_outline_rounded, size: 30),
              ),
              IconButton(
                tooltip: 'Add photo or video',
                onPressed: posting ? null : () => _postMedia(camera: true),
                icon: const Icon(Icons.camera_alt_rounded, size: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.active, required this.radius});
  final String label;
  final bool active;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: active ? scheme.primary : scheme.outlineVariant, width: 2.5)),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: scheme.primaryContainer,
        child: Text(label.substring(0, 1).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer)),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.signedUrl, required this.onTap});
  final Map<String, dynamic> status;
  final Future<String?> Function(String) signedUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = status['media_type']?.toString() ?? 'text';
    final id = status['user_id']?.toString() ?? 'User';
    final caption = status['caption']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: _Avatar(label: id, active: true, radius: 25),
        title: Text('User ${id.length > 6 ? id.substring(0, 6) : id}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Row(children: [
          Icon(type == 'text' ? Icons.text_fields : type == 'video' ? Icons.videocam_outlined : Icons.image_outlined, size: 16),
          const SizedBox(width: 5),
          Expanded(child: Text(type == 'text' ? caption : '${type[0].toUpperCase()}${type.substring(1)} update', maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        onTap: onTap,
      ),
    );
  }
}

class StatusViewer extends StatefulWidget {
  const StatusViewer({super.key, required this.status, required this.signedUrl});
  final Map<String, dynamic> status;
  final Future<String?> Function(String) signedUrl;

  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> {
  VideoPlayerController? video;
  String? url;
  bool loading = true;

  String get type => widget.status['media_type']?.toString() ?? 'text';
  String get caption => widget.status['caption']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _recordView();
  }

  Future<void> _recordView() async {
    final id = widget.status['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return;
    try {
      await Supabase.instance.client.from('status_views').upsert({
        'status_id': id,
        'viewer_id': user.id,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    final path = widget.status['media_path']?.toString();
    if (type == 'text' || path == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final signed = await widget.signedUrl(path);
    if (signed == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    url = signed;
    if (type == 'video') {
      final controller = VideoPlayerController.networkUrl(Uri.parse(signed));
      try {
        await controller.initialize();
        await controller.setLooping(true);
        await controller.play();
        video = controller;
      } catch (_) {
        await controller.dispose();
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Status')),
      body: Center(
        child: loading
            ? const CircularProgressIndicator(color: Colors.white)
            : type == 'text'
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w800)),
                  )
                : url == null
                    ? const Text('Unable to open this status', style: TextStyle(color: Colors.white))
                    : type == 'video' && video != null
                        ? AspectRatio(
                            aspectRatio: video!.value.aspectRatio == 0 ? 16 / 9 : video!.value.aspectRatio,
                            child: VideoPlayer(video!),
                          )
                        : InteractiveViewer(child: Image.network(url!, fit: BoxFit.contain)),
      ),
    );
  }
}

class StatusPage extends StatelessWidget {
  const StatusPage({super.key});

  @override
  Widget build(BuildContext context) => const WhatsAppStatusPage();
}
