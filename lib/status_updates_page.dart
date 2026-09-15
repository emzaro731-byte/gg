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
