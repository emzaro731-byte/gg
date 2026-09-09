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
  const ChatPage({required this.conversationId, required this.title, super.key});
  final String conversationId;
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final controller = TextEditingController();
  final focus = FocusNode();
  final recorder = AudioRecorder();
  late final Stream<List<Map<String, dynamic>>> messageStream;
  late final TypingService typingService;
  late final RealtimeChannel presenceChannel;

  bool sending = false;
  bool uploading = false;
  bool recording = false;
  bool online = false;
  bool typing = false;
  String? editingId;
  Map<String, dynamic>? replyingTo;
  Stopwatch? recordClock;

  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    messageStream = supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at');

    presenceChannel = supabase.channel(
      'chat-presence:${widget.conversationId}',
      opts: const RealtimeChannelConfig(private: true),
    );
    presenceChannel
        .onPresenceSync((_) => _refreshPresence())
        .onPresenceJoin((_) => _refreshPresence())
        .onPresenceLeave((_) => _refreshPresence())
        .subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await presenceChannel.track({'user_id': userId, 'online_at': DateTime.now().toUtc().toIso8601String()});
        _refreshPresence();
      }
    });

    typingService = TypingService(supabase, widget.conversationId)
      ..start((value) {
        if (mounted) setState(() => typing = value);
      });
    unawaited(CallService.instance.listenForInvites(context: context, conversationId: widget.conversationId));
  }

  void _refreshPresence() {
    if (!mounted) return;
    final states = presenceChannel.presenceState();
    final found = states.any((state) => state.presences.any((p) => p.payload['user_id']?.toString() != userId));
    setState(() => online = found);
  }

  Future<String?> _otherMemberId() async {
    final rows = await supabase
        .from('conversation_members')
        .select('user_id')
        .eq('conversation_id', widget.conversationId)
        .neq('user_id', userId)
        .limit(1);
    return rows.isEmpty ? null : rows.first['user_id']?.toString();
  }

  Future<void> _startCall(bool video) async {
    try {
      final other = await _otherMemberId();
      if (other == null) throw Exception('No other participant found.');
      await CallService.instance.startOutgoing(
        context: context,
        conversationId: widget.conversationId,
        calleeId: other,
        video: video,
        title: widget.title,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
    }
  }

  Future<void> sendMessage() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    final edit = editingId;
    final reply = replyingTo;
    setState(() {
      sending = true;
      editingId = null;
      replyingTo = null;
      controller.clear();
    });
    try {
      await typingService.setTyping(false);
      if (edit != null) {
        await supabase.from('messages').update({
          'body': text,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', edit).eq('sender_id', userId);
      } else {
        await supabase.from('messages').insert({
          'conversation_id': widget.conversationId,
          'sender_id': userId,
          'body': text,
          'message_type': 'text',
          'reply_to': reply?['id'],
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> pickAttachment() async {
    if (uploading) return;
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() => uploading = true);
    try {
      final extension = (file.extension ?? '').toLowerCase();
      final mime = _mimeForExtension(extension);
      final path = '$userId/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
      await supabase.storage.from('chat-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mime, upsert: false),
      );
      await supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': userId,
        'body': file.name,
        'message_type': _messageType(extension, mime),
        'media_url': path,
        'file_name': file.name,
        'file_size': file.size,
        'mime_type': mime,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  String _mimeForExtension(String ext) {
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/x-m4v', 'webm': 'video/webm',
      'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'wav': 'audio/wav', 'aac': 'audio/aac', 'ogg': 'audio/ogg',
      'pdf': 'application/pdf', 'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  String _messageType(String ext, String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    if (ext == 'pdf' || ext == 'doc' || ext == 'docx') return 'file';
    return 'file';
  }

  Future<String?> signedUrl(String path) async {
    try {
      return await supabase.storage.from('chat-media').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> toggleRecording() async {
    if (recording) {
      final path = await recorder.stop();
      recordClock?.stop();
      if (mounted) setState(() => recording = false);
      if (path == null) return;
      final duration = recordClock?.elapsedMilliseconds ?? 0;
      if (duration < 500) return;
      try {
        setState(() => uploading = true);
        final bytes = await File(path).readAsBytes();
        final storagePath = '$userId/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_voice.m4a';
        await supabase.storage.from('chat-media').uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(contentType: 'audio/mp4', upsert: false),
        );
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
      } finally {
        if (mounted) setState(() => uploading = false);
      }
      return;
    }

    if (!await recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/gg_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000, numChannels: 1), path: path);
    recordClock = Stopwatch()..start();
    if (mounted) setState(() => recording = true);
  }

  Future<void> deleteMessage(String id) async {
    await supabase.from('messages').delete().eq('id', id).eq('sender_id', userId);
  }

  void showMessageActions(Map<String, dynamic> message) {
    final mine = message['sender_id'] == userId;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () { Navigator.pop(context); setState(() => replyingTo = message); focus.requestFocus(); }),
            ListTile(leading: const Text('❤️', style: TextStyle(fontSize: 22)), title: const Text('React ❤️'), onTap: () { Navigator.pop(context); _react(message['id'].toString(), '❤️'); }),
            if (mine) ListTile(leading: const Icon(Icons.edit), title: const Text('Edit'), onTap: () { Navigator.pop(context); setState(() { editingId = message['id'].toString(); controller.text = message['body']?.toString() ?? ''; }); focus.requestFocus(); }),
            if (mine) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete'), onTap: () { Navigator.pop(context); deleteMessage(message['id'].toString()); }),
          ],
        ),
      ),
    );
  }

  Future<void> _react(String id, String emoji) async {
    final existing = await supabase.from('message_reactions').select('message_id').eq('message_id', id).eq('user_id', userId).eq('reaction', emoji).maybeSingle();
    if (existing == null) {
      await supabase.from('message_reactions').insert({'message_id': id, 'user_id': userId, 'reaction': emoji});
    } else {
      await supabase.from('message_reactions').delete().eq('message_id', id).eq('user_id', userId).eq('reaction', emoji);
    }
  }

  Widget mediaPreview(Map<String, dynamic> message) {
    final type = message['message_type']?.toString() ?? 'file';
    final path = message['media_url']?.toString();
    final name = message['file_name']?.toString() ?? 'Attachment';
    if (path == null) return Text(name);
    if (type == 'image') {
      return FutureBuilder<String?>(
        future: signedUrl(path),
        builder: (_, snapshot) => snapshot.data == null
            ? Text(name)
            : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(snapshot.data!, width: 230, height: 180, fit: BoxFit.cover)),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(type == 'video' ? Icons.video_file : type == 'audio' ? Icons.audiotrack : Icons.insert_drive_file), const SizedBox(width: 8), Flexible(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis))]);
  }

  @override
  void dispose() {
    unawaited(presenceChannel.unsubscribe());
    unawaited(typingService.dispose());
    unawaited(CallService.instance.stopInvites());
    recorder.dispose();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            CircleAvatar(radius: 19, child: Text(widget.title.isEmpty ? '?' : widget.title.substring(0, 1).toUpperCase())),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(typing ? 'typing…' : online ? 'online' : 'offline', style: TextStyle(fontSize: 12, color: typing || online ? Colors.green : null)),
            ]),
          ]),
          actions: [
            IconButton(onPressed: () => _startCall(false), icon: const Icon(Icons.call_outlined)),
            IconButton(onPressed: () => _startCall(true), icon: const Icon(Icons.videocam_outlined)),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messageStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('Unable to load messages: ${snapshot.error}'));
                final items = snapshot.data ?? [];
                if (items.isEmpty) return const Center(child: Text('No messages yet. Say hello!'));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final message = items[index];
                    final mine = message['sender_id'] == userId;
                    final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => showMessageActions(message),
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(14, 10, 12, 7),
                          decoration: BoxDecoration(
                            color: mine ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (message['reply_to'] != null) const Text('↩ Reply', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            if (message['message_type'] == 'text') Text(message['body']?.toString() ?? '', style: const TextStyle(fontSize: 16)) else mediaPreview(message),
                            const SizedBox(height: 3),
                            Text(created == null ? '' : DateFormat('HH:mm').format(created), style: const TextStyle(fontSize: 10)),
                          ]),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (editingId != null || replyingTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(children: [
                Icon(editingId != null ? Icons.edit : Icons.reply, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(editingId != null ? 'Editing message' : 'Replying to ${replyingTo?['body'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => setState(() { editingId = null; replyingTo = null; controller.clear(); }), icon: const Icon(Icons.close)),
              ]),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                IconButton(onPressed: uploading ? null : pickAttachment, icon: uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file)),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    onChanged: (value) => typingService.setTyping(value.trim().isNotEmpty),
                    onSubmitted: (_) => sendMessage(),
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(hintText: editingId != null ? 'Edit message' : 'Message', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))),
                  ),
                ),
                IconButton(onPressed: toggleRecording, icon: Icon(recording ? Icons.stop_circle : Icons.mic), color: recording ? Colors.red : null),
                IconButton.filled(onPressed: sending ? null : sendMessage, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
        ]),
      );
}

class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({required this.path, required this.durationMs, required this.signedUrl, super.key});
  final String path;
  final int? durationMs;
  final Future<String?> Function(String) signedUrl;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
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
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = ((widget.durationMs ?? 0) / 1000).round();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(onPressed: toggle, icon: Icon(playing ? Icons.pause_circle : Icons.play_circle), iconSize: 38),
      Text('${seconds}s'),
    ]);
  }
}
