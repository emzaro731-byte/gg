import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'whatsapp_status_stories_page.dart';

class StatusUpdatesPage extends StatefulWidget {
  const StatusUpdatesPage({super.key});
  @override State<StatusUpdatesPage> createState() => _StatusUpdatesPageState();
}

class _StatusUpdatesPageState extends State<StatusUpdatesPage> {
  final supabase = Supabase.instance.client;
  final picker = ImagePicker();
  bool posting = false;
  String privacy = 'everyone';

  Future<void> _uploadBytes(List<int> bytes, String extension, bool isVideo) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.$extension';
    await _runPost(() async {
      await supabase.storage.from('status-media').uploadBinary(path, Uint8List.fromList(bytes), fileOptions: FileOptions(contentType: _contentType(extension, isVideo), upsert: false));
      await supabase.from('statuses').insert({'user_id': userId, 'media_path': path, 'media_type': isVideo ? 'video' : 'image', 'visibility': privacy, 'expires_at': DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String()});
    });
  }

  String _contentType(String extension, bool video) {
    const map = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/x-m4v', 'webm': 'video/webm'};
    return map[extension.toLowerCase()] ?? (video ? 'video/*' : 'image/*');
  }

  Future<void> _runPost(Future<void> Function() action) async {
    if (posting) return;
    setState(() => posting = true);
    try { await action(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status posted'))); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post status. Check your connection and try again.'))); }
    finally { if (mounted) setState(() => posting = false); }
  }

  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Updates')), body: const Center(child: Text('Status updates')));
}
