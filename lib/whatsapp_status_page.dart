import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WhatsAppStatusPage extends StatefulWidget {
  const WhatsAppStatusPage({super.key});

  @override
  State<WhatsAppStatusPage> createState() => _WhatsAppStatusPageState();
}

class _WhatsAppStatusPageState extends State<WhatsAppStatusPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final ImagePicker picker = ImagePicker();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<Map<String, dynamic>> _statuses = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  bool _loading = true;
  String? _error;

  String? get userId => supabase.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadStatuses();
    _subscription = supabase.from('statuses').stream(primaryKey: ['id']).order('created_at', ascending: false).listen((rows) {
      if (!mounted) return;
      final now = DateTime.now().toUtc();
      setState(() {
        _statuses = rows.where((row) {
          final expires = DateTime.tryParse(row['expires_at']?.toString() ?? '');
          return expires == null || expires.isAfter(now);
        }).toList();
      });
      _loadProfiles();
    }, onError: (Object error) {
      if (mounted) setState(() => _error = error.toString());
    });
  }

  Future<void> _loadStatuses() async {
    try {
      final rows = await supabase.from('statuses').select('id,user_id,media_path,media_type,caption,created_at,expires_at').gt('expires_at', DateTime.now().toUtc().toIso8601String()).order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _statuses = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
      await _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadProfiles() async {
    final ids = _statuses.map((s) => s['user_id']?.toString()).whereType<String>().where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;
    try {
      final rows = await supabase.from('profiles').select('id,username,display_name,avatar_url,last_seen').inFilter('id', ids.toList());
      if (!mounted) return;
      setState(() {
        _profiles = {for (final row in List<Map<String, dynamic>>.from(rows)) row['id'].toString(): row};
      });
    } catch (_) {}
  }

  Future<void> _createTextStatus() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New status'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5, maxLength: 500, decoration: const InputDecoration(hintText: 'What’s on your mind?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || userId == null) return;
    try {
      await supabase.from('statuses').insert({'user_id': userId, 'media_type': 'text', 'caption': text});
      await _loadStatuses();
    } catch (e) {
      _showError('Could not post status: $e');
    }
  }

  Future<void> _pickMedia({required bool video}) async {
    if (userId == null) return;
    try {
      final XFile? file = video ? await picker.pickVideo(source: ImageSource.gallery) : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final extension = video ? 'mp4' : 'jpg';
      final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
      await supabase.storage.from('status-media').uploadBinary(path, bytes, fileOptions: FileOptions(upsert: false, contentType: video ? 'video/mp4' : 'image/jpeg'));
      final caption = await _captionDialog();
      await supabase.from('statuses').insert({'user_id': userId, 'media_path': path, 'media_type': video ? 'video' : 'image', 'caption': caption});
      await _loadStatuses();
    } catch (e) {
      _showError('Could not create status: $e');
    }
  }

  Future<String?> _captionDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a caption'),
        content: TextField(controller: controller, maxLength: 300, decoration: const InputDecoration(hintText: 'Optional caption')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: const Text('Skip')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    return value?.isEmpty == true ? null : value;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showCreateMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.text_fields_rounded), title: const Text('Text status'), onTap: () { Navigator.pop(context); _createTextStatus(); }),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Photo status'), onTap: () { Navigator.pop(context); _pickMedia(video: false); }),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Video status'), onTap: () { Navigator.pop(context); _pickMedia(video: true); }),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mine = _statuses.where((s) => s['user_id']?.toString() == userId).toList();
    final others = _statuses.where((s) => s['user_id']?.toString() != userId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Updates'), actions: [IconButton(onPressed: _loadStatuses, tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded))]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStatuses,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
                children: [
                  _myStatusTile(mine),
                  const SizedBox(height: 18),
                  if (others.isNotEmpty) ...[_sectionTitle('Recent updates'), const SizedBox(height: 4), ...others.map(_statusTile)] else _emptyUpdates(),
                  if (_error != null) ...[const SizedBox(height: 12), Text('Some updates could not be loaded.', style: TextStyle(color: Colors.red))],
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _showCreateMenu, icon: const Icon(Icons.add_rounded), label: const Text('New status', style: TextStyle(fontWeight: FontWeight.w800))),
    );
  }

  Widget _myStatusTile(List<Map<String, dynamic>> mine) {
    final profile = userId == null ? null : _profiles[userId!];
    final name = (profile?['display_name'] ?? supabase.auth.currentUser?.email ?? 'My status').toString();
    final avatar = (profile?['avatar_url'] ?? '').toString();
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Stack(clipBehavior: Clip.none, children: [_avatar(name, avatar, radius: 30, border: mine.isNotEmpty), Positioned(right: -2, bottom: -1, child: CircleAvatar(radius: 10, backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(Icons.add, size: 14)))]),
      title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(mine.isEmpty ? 'Tap to add a status update' : '${mine.length} update${mine.length == 1 ? '' : 's'} • visible for 24 hours'),
      onTap: _showCreateMenu,
    );
  }

  Widget _statusTile(Map<String, dynamic> status) {
    final uid = status['user_id']?.toString() ?? '';
    final profile = _profiles[uid];
    final name = (profile?['display_name'] ?? profile?['username'] ?? 'GG User').toString();
    final avatar = (profile?['avatar_url'] ?? '').toString();
    final created = DateTime.tryParse(status['created_at']?.toString() ?? '')?.toLocal();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        leading: _avatar(name, avatar, radius: 27, border: true),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(_statusSummary(status, created), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openStatus(status, name),
      ),
    );
  }

  Widget _avatar(String name, String url, {double radius = 28, bool border = false}) {
    final child = url.isNotEmpty ? CircleAvatar(radius: radius, backgroundImage: NetworkImage(url)) : CircleAvatar(radius: radius, child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)));
    return border ? Container(padding: const EdgeInsets.all(2.5), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2.5)), child: child) : child;
  }

  String _statusSummary(Map<String, dynamic> status, DateTime? created) {
    final type = status['media_type']?.toString() ?? 'text';
    final caption = status['caption']?.toString() ?? '';
    final icon = type == 'image' ? '📷 ' : type == 'video' ? '🎥 ' : '';
    final time = created == null ? '' : ' • ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    return '$icon${caption.isEmpty ? 'Status update' : caption}$time';
  }

  Future<void> _openStatus(Map<String, dynamic> status, String name) async {
    String? signedUrl;
    final path = status['media_path']?.toString();
    if (path != null && path.isNotEmpty) {
      try {
        signedUrl = await supabase.storage.from('status-media').createSignedUrl(path, 3600);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewerPage(status: status, name: name, mediaUrl: signedUrl)));
  }

  Widget _sectionTitle(String title) => Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 6), child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)));

  Widget _emptyUpdates() => Padding(padding: const EdgeInsets.fromLTRB(28, 60, 28, 30), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.update_rounded, size: 58, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 14), const Text('No recent updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 7), const Text('When your friends post photos, videos, or text, they’ll appear here.', textAlign: TextAlign.center)]));
}

class StatusViewerPage extends StatelessWidget {
  const StatusViewerPage({super.key, required this.status, required this.name, this.mediaUrl});
  final Map<String, dynamic> status;
  final String name;
  final String? mediaUrl;

  @override
  Widget build(BuildContext context) {
    final type = status['media_type']?.toString() ?? 'text';
    final caption = status['caption']?.toString() ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: type == 'image' && mediaUrl != null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Expanded(child: InteractiveViewer(child: Image.network(mediaUrl!, fit: BoxFit.contain))), if (caption.isNotEmpty) _caption(caption)])
              : type == 'video'
                  ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 80), const SizedBox(height: 12), const Text('Video status', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)), if (caption.isNotEmpty) _caption(caption)])
                  : Text(caption, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Widget _caption(String text) => Padding(padding: const EdgeInsets.only(top: 12), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 17)));
}

class EditedStatus {
  const EditedStatus(this.bytes, this.caption);
  final List<int> bytes;
  final String caption;
}

class StatusMediaEditor extends StatelessWidget {
  const StatusMediaEditor({super.key, required this.bytes});
  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit status')),
      body: Column(children: [
        Expanded(child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain)),
        const Padding(padding: EdgeInsets.all(16), child: Text('Add a caption from the New status menu to publish this media.')),
      ]),
    );
  }
}
