import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'whatsapp_status_stories_page.dart';

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
    try {
      await supabase.from('statuses').insert({
        'user_id': supabase.auth.currentUser!.id,
        'media_type': 'text',
        'caption': text,
        'expires_at': DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String(),
      });
    } catch (_) {
      if (mounted) _snack('Could not post status');
    }
  }

  Future<void> _mediaStatus() async {
    if (uploading) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.media, withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final extension = file.extension?.toLowerCase() ?? 'jpg';
    final isVideo = ['mp4', 'mov', 'm4v', 'webm'].contains(extension);
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';
    setState(() => uploading = true);
    try {
      await supabase.storage.from('status-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: _contentType(extension, isVideo), upsert: false),
      );
      await supabase.from('statuses').insert({
        'user_id': userId,
        'media_path': path,
        'media_type': isVideo ? 'video' : 'image',
        'expires_at': DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String(),
      });
    } catch (_) {
      if (mounted) _snack('Could not upload status');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  String _contentType(String ext, bool video) {
    const types = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'mp4': 'video/mp4',
      'mov': 'video/quicktime', 'm4v': 'video/x-m4v', 'webm': 'video/webm',
    };
    return types[ext] ?? (video ? 'video/*' : 'image/*');
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _openStories(List<Map<String, dynamic>> statuses, {int start = 0}) {
    if (statuses.isEmpty) return;
    final ordered = [...statuses];
    if (start > 0 && start < ordered.length) {
      final first = ordered.removeAt(start);
      ordered.insert(0, first);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => WhatsAppStatusStoriesPage(statuses: ordered)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final now = DateTime.now();
          final statuses = (snapshot.data ?? []).where((s) {
            final expiry = DateTime.tryParse(s['expires_at']?.toString() ?? '');
            return expiry == null || expiry.isAfter(now);
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
                  child: _Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      leading: _Avatar(label: 'You', active: mine.isNotEmpty, large: true),
                      title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(mine.isEmpty ? 'Tap + to share an update' : '${mine.length} active update${mine.length == 1 ? '' : 's'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton.filledTonal(onPressed: uploading ? null : _textStatus, icon: const Icon(Icons.edit_rounded)),
                        const SizedBox(width: 4),
                        IconButton.filled(onPressed: uploading ? null : _mediaStatus, icon: const Icon(Icons.add_a_photo_rounded)),
                      ]),
                      onTap: mine.isEmpty ? null : () => _openStories(mine),
                    ),
                  ),
                ),
              ),
              if (uploading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('Recent updates', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              )),
              if (others.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No recent updates yet.')))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                  sliver: SliverList.builder(
                    itemCount: others.length,
                    itemBuilder: (_, i) {
                      final status = others[i];
                      final id = status['user_id']?.toString() ?? 'User';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                            leading: _Avatar(label: id, active: true),
                            title: Text('User ${id.length > 6 ? id.substring(0, 6) : id}', style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(status['media_type'] == 'text' ? (status['caption']?.toString() ?? 'Text update') : '${status['media_type']} update', maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _openStories(others, start: i),
                          ),
                        ),
                      );
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

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .12)),
    ),
    child: child,
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.active, this.large = false});
  final String label;
  final bool active;
  final bool large;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: active ? Theme.of(context).colorScheme.primary : Colors.grey, width: 2.5)),
    child: CircleAvatar(
      radius: large ? 29 : 25,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(label.isEmpty ? '?' : label.substring(0, 1).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onPrimaryContainer)),
    ),
  );
}
