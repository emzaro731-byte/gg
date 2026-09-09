import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/call_service.dart';
import 'services/typing_service.dart';

class ChatPage extends StatefulWidget {
  final String conversationId;
  final String title;
  const ChatPage({required this.conversationId, required this.title, super.key});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  final focus = FocusNode();
  final recorder = AudioRecorder();
  bool sending = false, online = false, typing = false, uploading = false, recording = false;
  Map<String, dynamic>? replyingTo;
  String? editingId;
  Stopwatch? recordClock;
  late final RealtimeChannel presenceChannel;
  late final Stream<List<Map<String, dynamic>>> messageStream;
  late final TypingService typingService;
  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    messageStream = supabase.from('messages').stream(primaryKey: ['id']).eq('conversation_id', widget.conversationId).order('created_at');
    presenceChannel = supabase.channel('chat-presence:${widget.conversationId}');
    presenceChannel.onPresenceSync((_) => _refreshPresence());
    presenceChannel.onPresenceJoin((_) => _refreshPresence());
    presenceChannel.onPresenceLeave((_) => _refreshPresence());
    presenceChannel.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await presenceChannel.track({'user_id': userId, 'online_at': DateTime.now().toUtc().toIso8601String()});
        _refreshPresence();
      }
    });
    typingService = TypingService(supabase, widget.conversationId)..start((value) {
      if (mounted) setState(() => typing = value);
    });
    unawaited(CallService.instance.listenForInvites(context: context, conversationId: widget.conversationId));
  }

  void _refreshPresence() {
    if (!mounted) return;
    final states = presenceChannel.presenceState();
    final found = states.any((state) => state.presences.any((presence) => presence.payload['user_id']?.toString() != userId));
    setState(() => online = found);
  }

  Future<String?> _otherMemberId() async {
    final rows = await supabase.from('conversation_members').select('user_id').eq('conversation_id', widget.conversationId).neq('user_id', userId).limit(1);
    if (rows.isEmpty) return null;
    return rows.first['user_id']?.toString();
  }

  Future<void> _startCall(bool video) async {
    try {
      final other = await _otherMemberId();
      if (other == null) throw Exception('This conversation does not have another member to call.');
      await CallService.instance.startOutgoing(context: context, conversationId: widget.conversationId, calleeId: other, video: video, title: widget.title);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start call: $e')));
    }
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    final oldEditing = editingId;
    final reply = replyingTo;
    controller.clear();
    setState(() { editingId = null; replyingTo = null; });
    try {
      await typingService.setTyping(false);
      if (oldEditing != null) {
        await supabase.from('messages').update({'body': text, 'edited_at': DateTime.now().toUtc().toIso8601String()}).eq('id', oldEditing).eq('sender_id', userId);
      } else {
        await supabase.from('messages').insert({'conversation_id': widget.conversationId, 'sender_id': userId, 'body': text, 'message_type': 'text', 'reply_to': reply?['id']});
      }
    } on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
    finally { if (mounted) setState(() => sending = false); }
  }

  Future<void> toggleRecording() async {
    if (recording) {
      final path = await recorder.stop();
      recordClock?.stop();
      if (mounted) setState(() => recording = false);
      if (path == null) return;
      final duration = recordClock?.elapsedMilliseconds ?? 0;
      if (duration < 500) { try { await File(path).delete(); } catch (_) {} return; }
      await _uploadVoiceNote(path, duration);
      return;
    }
    if (!await recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required for voice notes.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/gg_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000, numChannels: 1), path: path);
    recordClock = Stopwatch()..start();
    if (mounted) setState(() => recording = true);
  }

  Future<void> _uploadVoiceNote(String path, int duration) async {
    try {
      setState(() => uploading = true);
      final bytes = await File(path).readAsBytes();
      final storagePath = '$userId/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_voice.m4a';
      await supabase.storage.from('chat-media').uploadBinary(storagePath, bytes, fileOptions: const FileOptions(contentType: 'audio/mp4', upsert: false));
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': userId,
        'body': 'Voice message',
        'message_type': 'audio',
        'media_url': storagePath,
        'file_name': 'voice.m4a',
        'file_size': bytes.length,
        'mime_type': 'audio/mp4',
        'duration_ms': duration,
      });
      try { await File(path).delete(); } catch (_) {}
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Voice note failed: $e')));
    } finally { if (mounted) setState(() => uploading = false); }
  }

  Future<void> pickAttachment() async {
    if (uploading) return;
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This device did not provide file bytes.')));
      return;
    }
    setState(() => uploading = true);
    try {
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '$userId/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await supabase.storage.from('chat-media').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: false));
      await supabase.from('messages').insert({'conversation_id': widget.conversationId, 'sender_id': userId, 'body': file.name, 'message_type': _messageType(file.extension, file.mimeType), 'media_url': path, 'file_name': file.name, 'file_size': file.size, 'mime_type': file.mimeType});
    } on StorageException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attachment upload failed: ${e.message}'))); }
    on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Message save failed: ${e.message}'))); }
    finally { if (mounted) setState(() => uploading = false); }
  }

  String _messageType(String? ext, String? mime) {
    final m = (mime ?? '').toLowerCase();
    if (m.startsWith('image/')) return 'image';
    if (m.startsWith('video/')) return 'video';
    if (m.startsWith('audio/')) return 'audio';
    final e = (ext ?? '').toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(e)) return 'image';
    if (['mp4', 'mov', 'webm', 'mkv'].contains(e)) return 'video';
    if (['mp3', 'm4a', 'wav', 'aac', 'ogg'].contains(e)) return 'audio';
    return 'file';
  }

  Future<String?> signedUrl(String path) async { try { return await supabase.storage.from('chat-media').createSignedUrl(path, 3600); } catch (_) { return null; } }

  Future<void> deleteMessage(String id) async { try { await supabase.from('messages').delete().eq('id', id).eq('sender_id', userId); } on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); } }

  Future<void> react(String id, String emoji) async {
    try {
      final existing = await supabase.from('message_reactions').select('message_id').eq('message_id', id).eq('user_id', userId).eq('reaction', emoji).maybeSingle();
      if (existing == null) await supabase.from('message_reactions').insert({'message_id': id, 'user_id': userId, 'reaction': emoji}); else await supabase.from('message_reactions').delete().eq('message_id', id).eq('user_id', userId).eq('reaction', emoji);
    } on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Run the messaging migration first: ${e.message}'))); }
  }

  void showMessageActions(Map<String, dynamic> message) {
    final mine = message['sender_id'] == userId;
    showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Text('❤️', style: TextStyle(fontSize: 22)), title: const Text('React ❤️'), onTap: () { Navigator.pop(context); react(message['id'].toString(), '❤️'); }),
      ListTile(leading: const Text('😂', style: TextStyle(fontSize: 22)), title: const Text('React 😂'), onTap: () { Navigator.pop(context); react(message['id'].toString(), '😂'); }),
      ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () { Navigator.pop(context); setState(() => replyingTo = message); focus.requestFocus(); }),
      if (mine) ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () { Navigator.pop(context); setState(() { editingId = message['id'].toString(); controller.text = message['body']?.toString() ?? ''; }); focus.requestFocus(); }),
      if (mine) ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error), title: const Text('Delete'), onTap: () { Navigator.pop(context); deleteMessage(message['id'].toString()); }),
    ])));
  }

  Widget mediaPreview(Map<String, dynamic> message) {
    final type = message['message_type']?.toString() ?? 'file';
    final path = message['media_url']?.toString();
    final name = message['file_name']?.toString() ?? message['body']?.toString() ?? 'Attachment';
    if (path == null || path.isEmpty) return Text(name);
    if (type == 'audio') return VoiceMessageBubble(path: path, durationMs: (message['duration_ms'] as num?)?.toInt(), signedUrl: signedUrl);
    if (type == 'image') return FutureBuilder<String?>(future: signedUrl(path), builder: (_, snapshot) { final url = snapshot.data; if (url == null) return Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.image_outlined), const SizedBox(width: 8), Flexible(child: Text(name))]); return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(url, width: 230, height: 180, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text(name))); });
    final icon = type == 'video' ? Icons.video_file_outlined : Icons.insert_drive_file_outlined;
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon), const SizedBox(width: 10), Flexible(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis))]);
  }

  @override
  void dispose() { unawaited(presenceChannel.unsubscribe()); unawaited(typingService.dispose()); unawaited(CallService.instance.stopInvites()); recorder.dispose(); controller.dispose(); focus.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      titleSpacing: 0,
      title: Row(children: [CircleAvatar(radius: 19, child: Text(widget.title.isEmpty ? '?' : widget.title.substring(0, 1).toUpperCase())), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), Text(typing ? 'typing…' : online ? 'online' : 'offline', style: TextStyle(fontSize: 12, color: typing || online ? Colors.green : null))])]),
      actions: [IconButton(onPressed: () => _startCall(false), icon: const Icon(Icons.call_outlined)), IconButton(onPressed: () => _startCall(true), icon: const Icon(Icons.videocam_outlined))],
    ),
    body: Column(children: [
      Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(stream: messageStream, builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Unable to load messages: ${snapshot.error}'));
        final items = snapshot.data ?? [];
        if (items.isEmpty) return const Center(child: Text('No messages yet. Say hello!'));
        return ListView.builder(padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), itemCount: items.length, itemBuilder: (context, index) {
          final message = items[index]; final mine = message['sender_id'] == userId; final body = message['body']?.toString() ?? ''; final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
          final replyId = message['reply_to']?.toString(); final replied = replyId == null ? null : items.cast<Map<String, dynamic>?>().firstWhere((m) => m?['id']?.toString() == replyId, orElse: () => null);
          return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(onLongPress: () => showMessageActions(message), child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
            decoration: BoxDecoration(color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 4), bottomRight: Radius.circular(mine ? 4 : 18))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (replied != null) Container(width: double.infinity, padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 7), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: .35), borderRadius: BorderRadius.circular(10)), child: Text(replied['body']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (message['message_type'] == 'text') Text(body, style: const TextStyle(fontSize: 16)) else mediaPreview(message),
              const SizedBox(height: 3), Row(mainAxisSize: MainAxisSize.min, children: [if (message['edited_at'] != null) const Text('edited  •  ', style: TextStyle(fontSize: 10)), Text(created == null ? '' : DateFormat('HH:mm').format(created), style: const TextStyle(fontSize: 10))]),
            ]),
          )));
        });
      })),
      if (replyingTo != null || editingId != null) Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(14, 8, 8, 8), color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Row(children: [Icon(editingId != null ? Icons.edit_rounded : Icons.reply_rounded, size: 18), const SizedBox(width: 8), Expanded(child: Text(editingId != null ? 'Editing message' : 'Replying to ${replyingTo?['body'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis)), IconButton(onPressed: () => setState(() { replyingTo = null; editingId = null; controller.clear(); }), icon: const Icon(Icons.close))])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Row(children: [
        IconButton(onPressed: pickAttachment, icon: uploading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file_rounded)),
        Expanded(child: TextField(controller: controller, focusNode: focus, onChanged: (value) => typingService.setTyping(value.trim().isNotEmpty), textInputAction: TextInputAction.send, onSubmitted: (_) => sendMessage(), minLines: 1, maxLines: 5, decoration: InputDecoration(hintText: editingId != null ? 'Edit message' : recording ? 'Recording voice note…' : 'Message', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)), contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)))),
        const SizedBox(width: 4),
        IconButton(onPressed: editingId != null ? sendMessage : toggleRecording, color: recording ? Theme.of(context).colorScheme.error : null, icon: Icon(editingId != null ? Icons.check_rounded : recording ? Icons.stop_circle_rounded : Icons.mic_rounded)),
        const SizedBox(width: 2),
        IconButton.filled(onPressed: sending ? null : sendMessage, icon: const Icon(Icons.send_rounded)),
      ])),
    ]),
  );
}

class VoiceMessageBubble extends StatefulWidget {
  final String path;
  final int? durationMs;
  final Future<String?> Function(String) signedUrl;
  const VoiceMessageBubble({required this.path, required this.durationMs, required this.signedUrl, super.key});
  @override State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final player = AudioPlayer();
  bool playing = false;

  Future<void> toggle() async {
    if (playing) {
      await player.pause();
      if (mounted) setState(() => playing = false);
      return;
    }
    final url = await widget.signedUrl(widget.path);
    if (url == null) return;
    await player.play(UrlSource(url));
    if (mounted) setState(() => playing = true);
    player.onPlayerComplete.listen((_) { if (mounted) setState(() => playing = false); });
  }

  @override
  void dispose() { player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final seconds = ((widget.durationMs ?? 0) / 1000).round();
    return Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: toggle, icon: Icon(playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded), iconSize: 38), const SizedBox(width: 4), SizedBox(width: 100, child: LinearProgressIndicator(value: playing ? null : 0)), const SizedBox(width: 8), Text('${seconds}s', style: const TextStyle(fontSize: 12))]);
  }
}
