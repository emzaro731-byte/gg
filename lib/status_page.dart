import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final supabase = Supabase.instance.client;
  bool uploading = false;

  Stream<List<Map<String, dynamic>>> get _stream => supabase
      .from('statuses')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  Future<void> _textStatus() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create status'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(hintText: 'Share an update...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    await supabase.from('statuses').insert({
      'user_id': supabase.auth.currentUser!.id,
      'media_type': 'text',
      'caption': text,
    });
  }

  Future<void> _mediaStatus() async {
    if (uploading) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.media, withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final extension = file.extension?.toLowerCase() ?? '';
    final isVideo = ['mp4', 'mov', 'm4v', 'webm'].contains(extension);
    final type = isVideo ? 'video' : 'image';
    final contentType = _contentType(extension, isVideo);
    final userId = supabase.auth.currentUser!.id;
    final storagePath = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    setState(() => uploading = true);
    try {
      await supabase.storage.from('status-media').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: contentType, upsert: false),
      );
      await supabase.from('statuses').insert({
        'user_id': userId,
        'media_path': storagePath,
        'media_type': type,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  String _contentType(String extension, bool isVideo) {
    const types = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/x-m4v', 'webm': 'video/webm',
    };
    return types[extension] ?? (isVideo ? 'video/*' : 'image/*');
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
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Unable to load updates.'));
          final now = DateTime.now();
          final statuses = (snapshot.data ?? []).where((s) {
            final expiry = DateTime.tryParse(s['expires_at']?.toString() ?? '');
            return expiry != null && expiry.isAfter(now);
          }).toList();
          final me = supabase.auth.currentUser?.id;
          final mine = statuses.where((s) => s['user_id'] == me).toList();
          final others = statuses.where((s) => s['user_id'] != me).toList();

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: _GlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _StoryAvatar(label: 'You', active: mine.isNotEmpty, large: true),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('My status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(mine.isEmpty ? 'Tap + to share an update' : '${mine.length} active update${mine.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
                            ]),
                          ),
                          IconButton.filledTonal(onPressed: uploading ? null : _textStatus, icon: const Icon(Icons.edit_rounded)),
                          const SizedBox(width: 5),
                          IconButton.filled(onPressed: uploading ? null : _mediaStatus, icon: const Icon(Icons.add_a_photo_rounded)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (uploading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 18, 20, 8), child: Text('Recent updates', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20))),),
              if (others.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No recent updates yet.')))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                  sliver: SliverList.builder(
                    itemCount: others.length,
                    itemBuilder: (_, index) {
                      final status = others[index];
                      return _StatusTile(status: status, signedUrl: _url);
                    },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: uploading ? null : _mediaStatus,
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text('Add status'),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: scheme.outline.withValues(alpha: .12)),
        boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: .08), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: child,
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({required this.label, required this.active, this.large = false});
  final String label;
  final bool active;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: active ? scheme.primary : scheme.outlineVariant, width: 2.5)),
      child: CircleAvatar(
        radius: large ? 29 : 25,
        backgroundColor: scheme.primaryContainer,
        child: Text(label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer)),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status, required this.signedUrl});
  final Map<String, dynamic> status;
  final Future<String?> Function(String) signedUrl;

  @override
  Widget build(BuildContext context) {
    final type = status['media_type']?.toString() ?? 'text';
    final userId = status['user_id']?.toString() ?? 'User';
    final caption = status['caption']?.toString();
    final expiry = DateTime.tryParse(status['expires_at']?.toString() ?? '');
    final left = expiry == null ? '' : _remaining(expiry);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _GlassCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: _StoryAvatar(label: userId, active: true),
          title: Text('User ${userId.length > 6 ? userId.substring(0, 6) : userId}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(type == 'text' ? (caption ?? 'Text update') : '${type[0].toUpperCase()}${type.substring(1)} update', maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(left, style: Theme.of(context).textTheme.labelSmall),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewerPage(status: status, signedUrl: signedUrl))),
        ),
      ),
    );
  }

  String _remaining(DateTime expiry) {
    final d = expiry.toLocal().difference(DateTime.now());
    if (d.isNegative) return 'Expired';
    if (d.inHours > 0) return '${d.inHours}h';
    return '${d.inMinutes.clamp(1, 59)}m';
  }
}

class StatusViewerPage extends StatefulWidget {
  const StatusViewerPage({super.key, required this.status, required this.signedUrl});
  final Map<String, dynamic> status;
  final Future<String?> Function(String) signedUrl;

  @override
  State<StatusViewerPage> createState() => _StatusViewerPageState();
}

class _StatusViewerPageState extends State<StatusViewerPage> {
  VideoPlayerController? video;
  String? url;
  bool loading = true;

  String get type => widget.status['media_type']?.toString() ?? 'text';
  String get caption => widget.status['caption']?.toString() ?? '';
  String? get path => widget.status['media_path']?.toString();

  @override
  void initState() {
    super.initState();
    _view();
    _load();
  }

  Future<void> _view() async {
    final id = widget.status['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return;
    try {
      await Supabase.instance.client.from('status_views').upsert({'status_id': id, 'viewer_id': user.id, 'viewed_at': DateTime.now().toUtc().toIso8601String()});
    } catch (_) {}
  }

  Future<void> _load() async {
    if (type == 'text' || path == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final signed = await widget.signedUrl(path!);
    if (signed == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    url = signed;
    if (type == 'video') {
      final c = VideoPlayerController.networkUrl(Uri.parse(signed));
      try {
        await c.initialize();
        await c.setLooping(true);
        await c.play();
        video = c;
      } catch (_) {
        await c.dispose();
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
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Status')),
        body: Center(
          child: loading
              ? const CircularProgressIndicator(color: Colors.white)
              : type == 'text'
                  ? Padding(padding: const EdgeInsets.all(32), child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)))
                  : url == null
                      ? const Text('Unable to open this status', style: TextStyle(color: Colors.white))
                      : type == 'video' && video != null
                          ? AspectRatio(aspectRatio: video!.value.aspectRatio == 0 ? 16 / 9 : video!.value.aspectRatio, child: Stack(alignment: Alignment.bottomCenter, children: [
                              VideoPlayer(video!),
                              VideoProgressIndicator(video!, allowScrubbing: true, padding: const EdgeInsets.all(12)),
                              Positioned(bottom: 24, child: IconButton.filled(onPressed: () async { if (video!.value.isPlaying) { await video!.pause(); } else { await video!.play(); } if (mounted) setState(() {}); }, icon: Icon(video!.value.isPlaying ? Icons.pause : Icons.play_arrow))),
                            ]))
                          : InteractiveViewer(child: Image.network(url!, fit: BoxFit.contain)),
        ),
      );
}
