import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'whatsapp_status_stories_page.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});
  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final supabase = Supabase.instance.client;
  final imagePicker = ImagePicker();
  bool posting = false;
  String _privacy = 'everyone';
  Map<String, Map<String, dynamic>> profiles = {};

  Stream<List<Map<String, dynamic>>> get _stream => supabase.from('statuses').stream(primaryKey: ['id']).order('created_at', ascending: false);

  @override
  void initState() { super.initState(); _loadProfiles(); }

  Future<void> _loadProfiles() async {
    try {
      final rows = await supabase.from('profiles').select('id, username, display_name, avatar_url');
      final next = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) next[row['id'].toString()] = Map<String, dynamic>.from(row);
      if (mounted) setState(() => profiles = next);
    } catch (_) {}
  }

  Map<String, dynamic>? _profile(String? id) => id == null ? null : profiles[id];
  String _name(String? id) {
    final p = _profile(id);
    final name = p?['display_name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final username = p?['username']?.toString().trim();
    if (username != null && username.isNotEmpty) return '@$username';
    return id == supabase.auth.currentUser?.id ? 'You' : 'GG User';
  }

  Future<void> _choosePrivacy() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Status privacy', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('Choose who can see new statuses')),
        RadioListTile(value: 'everyone', groupValue: _privacy, onChanged: (v) => Navigator.pop(context, v), title: const Text('Everyone'), subtitle: const Text('All authenticated GG users')),
        RadioListTile(value: 'nobody', groupValue: _privacy, onChanged: (v) => Navigator.pop(context, v), title: const Text('Only me'), subtitle: const Text('Keep new statuses private')),
        const SizedBox(height: 12),
      ])),
    );
    if (selected != null && mounted) setState(() => _privacy = selected);
  }

  Future<void> _postText() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Text status'),
      content: TextField(controller: controller, autofocus: true, maxLines: 5, maxLength: 500, decoration: const InputDecoration(hintText: 'Share an update...')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Post'))],
    ));
    controller.dispose();
    if (result == null || result.isEmpty) return;
    await _runPost(() => supabase.from('statuses').insert({'user_id': supabase.auth.currentUser!.id, 'media_type': 'text', 'caption': result, 'visibility': _privacy, 'expires_at': DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String()}));
  }

  Future<void> _postFromCamera() async {
    if (posting) return;
    final choice = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take photo'), onTap: () => Navigator.pop(context, 'photo')),
      ListTile(leading: const Icon(Icons.videocam_rounded), title: const Text('Record video'), onTap: () => Navigator.pop(context, 'video')),
      ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, 'gallery')),
    ])));
    if (choice == 'photo') {
      final file = await imagePicker.pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 1920);
      if (file != null) await _uploadXFile(file, false);
    } else if (choice == 'video') {
      final file = await imagePicker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 1));
      if (file != null) await _uploadXFile(file, true);
    } else if (choice == 'gallery') {
      await _postMediaFromGallery();
    }
  }

  Future<void> _postMediaFromGallery() async {
    if (posting) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: false, withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    final extension = (file!.extension ?? 'jpg').toLowerCase();
    await _uploadBytes(file.bytes!, extension, ['mp4', 'mov', 'm4v', 'webm'].contains(extension));
  }

  Future<void> _uploadXFile(XFile file, bool isVideo) async {
    final bytes = await file.readAsBytes();
    final name = file.name;
    final extension = name.contains('.') ? name.split('.').last.toLowerCase() : (isVideo ? 'mp4' : 'jpg');
    await _uploadBytes(bytes, extension, isVideo);
  }

  Future<void> _uploadBytes(List<int> bytes, String extension, bool isVideo) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.$extension';
    await _runPost(() async {
      await supabase.storage.from('status-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: _contentType(extension, isVideo), upsert: false));
      await supabase.from('statuses').insert({'user_id': userId, 'media_path': path, 'media_type': isVideo ? 'video' : 'image', 'visibility': _privacy, 'expires_at': DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String()});
    });
  }

  String _contentType(String ext, bool video) {
    const map = {'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','gif':'image/gif','webp':'image/webp','mp4':'video/mp4','mov':'video/quicktime','m4v':'video/x-m4v','webm':'video/webm'};
    return map[ext] ?? (video ? 'video/*' : 'image/*');
  }

  Future<void> _runPost(Future<void> Function() action) async {
    if (posting) return;
    setState(() => posting = true);
    try { await action(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status posted for 24 hours'))); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post status. Check your connection.'))); }
    finally { if (mounted) setState(() => posting = false); }
  }

  Future<void> _openStories(List<Map<String, dynamic>> statuses, {int start = 0}) async {
    if (statuses.isEmpty) return;
    final ordered = [...statuses];
    if (start > 0 && start < ordered.length) { final first = ordered.removeAt(start); ordered.insert(0, first); }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => WhatsAppStatusStoriesPage(statuses: ordered, profiles: profiles)));
    _loadProfiles();
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser?.id;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Unable to load updates right now.'));
        final now = DateTime.now();
        final all = (snapshot.data ?? []).where((s) { final expiry = DateTime.tryParse(s['expires_at']?.toString() ?? ''); return expiry == null || expiry.isAfter(now); }).toList();
        final mine = all.where((s) => s['user_id'] == me).toList();
        final recent = all.where((s) => s['user_id'] != me).toList();
        return CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Card(child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: _Avatar(name: _name(me), url: _profile(me)?['avatar_url']?.toString(), active: mine.isNotEmpty, radius: 29),
            title: Text(_name(me), style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(mine.isEmpty ? 'Share a photo, video or text' : '${mine.length} active update${mine.length == 1 ? '' : 's'}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: _choosePrivacy, tooltip: 'Status privacy', icon: Icon(_privacy == 'everyone' ? Icons.public_rounded : Icons.lock_rounded)), IconButton(onPressed: posting ? null : _postText, icon: const Icon(Icons.edit_rounded)), IconButton(onPressed: posting ? null : _postFromCamera, icon: const Icon(Icons.camera_alt_rounded))]),
            onTap: mine.isEmpty ? null : () => _openStories(mine),
          )))),
          if (posting) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 10), child: Text('Recent updates', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
          if (recent.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No recent updates yet.')))
          else SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), sliver: SliverList.builder(itemCount: recent.length, itemBuilder: (_, i) {
            final status = recent[i]; final id = status['user_id']?.toString(); final type = status['media_type']?.toString() ?? 'text';
            return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
              leading: _Avatar(name: _name(id), url: _profile(id)?['avatar_url']?.toString(), active: true, radius: 25),
              title: Text(_name(id), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(type == 'text' ? (status['caption']?.toString() ?? '') : '${type[0].toUpperCase()}${type.substring(1)} update', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _openStories(recent, start: i),
            ));
          })),
        ]);
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.active, required this.radius, this.url});
  final String name; final bool active; final double radius; final String? url;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = url != null && url!.startsWith('http') ? NetworkImage(url!) : null;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: active ? scheme.primary : scheme.outlineVariant, width: 2.5)), child: CircleAvatar(radius: radius, backgroundColor: scheme.primaryContainer, backgroundImage: image, child: image == null ? Text(initial, style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer)) : null));
  }
}
