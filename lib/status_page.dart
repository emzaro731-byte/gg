import 'dart:io';

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

  Stream<List<Map<String, dynamic>>> get _statusStream => supabase.from('statuses').stream(primaryKey: ['id']).order('created_at', ascending: false);

  Future<void> _createTextStatus() async {
    final controller = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New status'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5, maxLength: 500, decoration: const InputDecoration(hintText: 'What is happening?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    if (caption == null || caption.isEmpty) return;
    await supabase.from('statuses').insert({'user_id': supabase.auth.currentUser!.id, 'media_type': 'text', 'caption': caption});
  }

  Future<void> _pickMedia() async {
    if (uploading) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.media, withData: false);
    final file = result?.files.single;
    if (file?.path == null) return;
    final path = file!.path!;
    final extension = file.extension?.toLowerCase() ?? '';
    final isVideo = ['mp4', 'mov', 'm4v', 'webm'].contains(extension);
    final mediaType = isVideo ? 'video' : 'image';
    final contentType = isVideo ? 'video/$extension' : 'image/$extension';
    final userId = supabase.auth.currentUser!.id;
    final storagePath = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    setState(() => uploading = true);
    try {
      await supabase.storage.from('status-media').upload(storagePath, File(path), fileOptions: FileOptions(contentType: contentType, upsert: false));
      await supabase.from('statuses').insert({'user_id': userId, 'media_path': storagePath, 'media_type': mediaType});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status upload failed: $e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<String?> _signedUrl(String path) async {
    try {
      return await supabase.storage.from('status-media').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  String _timeLeft(String expiresAt) {
    final remaining = DateTime.parse(expiresAt).toLocal().difference(DateTime.now());
    if (remaining.isNegative) return 'Expired';
    if (remaining.inHours >= 1) return '${remaining.inHours}h left';
    return '${remaining.inMinutes.clamp(1, 59)}m left';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _statusStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Unable to load statuses: ${snapshot.error}'));
            final statuses = (snapshot.data ?? []).where((s) {
              final expires = DateTime.tryParse(s['expires_at']?.toString() ?? '');
              return expires != null && expires.isAfter(DateTime.now());
            }).toList();
            final mine = statuses.where((s) => s['user_id'] == supabase.auth.currentUser?.id).toList();
            final others = statuses.where((s) => s['user_id'] != supabase.auth.currentUser?.id).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Card(child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: const Text('My status'),
                  subtitle: Text(mine.isEmpty ? 'Tap to add a status' : '${mine.length} active status${mine.length == 1 ? '' : 'es'}'),
                  trailing: IconButton(onPressed: uploading ? null : _createTextStatus, icon: const Icon(Icons.edit_outlined)),
                  onTap: uploading ? null : _pickMedia,
                )),
                if (uploading) const LinearProgressIndicator(),
                if (others.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 20, bottom: 8), child: Text('Recent updates', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                  ...others.map((status) => _StatusTile(status: status, signedUrl: _signedUrl, timeLeft: _timeLeft)),
                ] else
                  const Padding(padding: EdgeInsets.only(top: 50), child: Center(child: Text('No recent updates yet.'))),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: uploading ? null : _pickMedia, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('Add status')),
      );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.status, required this.signedUrl, required this.timeLeft});
  final Map<String, dynamic> status;
  final Future<String?> Function(String) signedUrl;
  final String Function(String) timeLeft;

  @override
  Widget build(BuildContext context) {
    final type = status['media_type']?.toString() ?? 'text';
    final caption = status['caption']?.toString();
    final userId = status['user_id']?.toString() ?? 'User';
    return Card(child: ListTile(
      leading: CircleAvatar(child: Text(userId.substring(0, 1).toUpperCase())),
      title: Text('User ${userId.substring(0, 6)}'),
      subtitle: Text(type == 'text' ? (caption ?? 'Text status') : '${type[0].toUpperCase()}${type.substring(1)} status'),
      trailing: Text(timeLeft(status['expires_at'].toString())),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewerPage(status: status, signedUrl: signedUrl))),
    ));
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
  VideoPlayerController? _video;
  String? _url;
  bool loading = true;

  String get type => widget.status['media_type']?.toString() ?? 'text';
  String get caption => widget.status['caption']?.toString() ?? '';
  String? get path => widget.status['media_path']?.toString();

  @override
  void initState() {
    super.initState();
    _recordView();
    _loadMedia();
  }

  Future<void> _recordView() async {
    final id = widget.status['id']?.toString();
    final user = Supabase.instance.client.auth.currentUser;
    if (id == null || user == null) return;
    try {
      await Supabase.instance.client.from('status_views').upsert({'status_id': id, 'viewer_id': user.id, 'viewed_at': DateTime.now().toUtc().toIso8601String()});
    } catch (_) {}
  }

  Future<void> _loadMedia() async {
    if (type == 'text' || path == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final url = await widget.signedUrl(path!);
    if (url == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    _url = url;
    if (type == 'video') {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await controller.initialize();
        await controller.setLooping(true);
        await controller.play();
        _video = controller;
      } catch (_) {
        await controller.dispose();
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Status')),
        body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : type == 'text'
                  ? Padding(padding: const EdgeInsets.all(32), child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)))
                  : _url == null
                      ? const Text('Unable to open this status', style: TextStyle(color: Colors.white))
                      : type == 'video'
                          ? _video == null
                              ? const Text('This video could not be played.', style: TextStyle(color: Colors.white))
                              : AspectRatio(
                                  aspectRatio: _video!.value.aspectRatio == 0 ? 16 / 9 : _video!.value.aspectRatio,
                                  child: Stack(alignment: Alignment.bottomCenter, children: [
                                    VideoPlayer(_video!),
                                    VideoProgressIndicator(_video!, allowScrubbing: true, padding: const EdgeInsets.all(12)),
                                    Positioned(bottom: 24, child: IconButton.filled(
                                      onPressed: () async {
                                        if (_video!.value.isPlaying) {
                                          await _video!.pause();
                                        } else {
                                          await _video!.play();
                                        }
                                        if (mounted) setState(() {});
                                      },
                                      icon: Icon(_video!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                                    )),
                                  ]),
                                )
                          : InteractiveViewer(child: Image.network(_url!, fit: BoxFit.contain)),
        ),
      );
}
