import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/call_service.dart';
import 'services/recording_file.dart';
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
  bool showEmoji = false;
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
      showEmoji = false;
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
        final bytes = await readRecordingBytes(path);
        final storagePath = '$userId/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_voice.$recordingFileExtension';
        await supabase.storage.from('chat-media').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: recordingMimeType, upsert: false),
        );
        await supabase.from('messages').insert({
          'conversation_id': widget.conversationId,
          'sender_id': userId,
          'body': 'Voice message',
          'message_type': 'audio',
          'media_url': storagePath,
          'file_name': 'voice.$recordingFileExtension',
          'file_size': bytes.length,
          'mime_type': recordingMimeType,
          'duration_ms': duration,
        });
        await deleteRecordingFile(path);
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
    final path = await recordingPath('gg_voice_${DateTime.now().millisecondsSinceEpoch}.$recordingFileExtension');
    final encoder = kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc;
    await recorder.start(RecordConfig(encoder: encoder, bitRate: 24000, sampleRate: 16000, numChannels: 1), path: path);
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
        child: Wrap(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Message actions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () { Navigator.pop(context); setState(() => replyingTo = message); focus.requestFocus(); }),
          ListTile(leading: const Text('❤️', style: TextStyle(fontSize: 22)), title: const Text('React ❤️'), onTap: () { Navigator.pop(context); _react(message['id'].toString(), '❤️'); }),
          if (mine) ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () { Navigator.pop(context); setState(() { editingId = message['id'].toString(); controller.text = message['body']?.toString() ?? ''; }); focus.requestFocus(); }),
          if (mine) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete'), onTap: () { Navigator.pop(context); deleteMessage(message['id'].toString()); }),
        ]),
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
            : ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(snapshot.data!, width: 250, height: 190, fit: BoxFit.cover)),
      );
    }
    if (type == 'audio') {
      return VoiceMessageBubble(path: path, durationMs: message['duration_ms'] as int?, signedUrl: signedUrl);
    }
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Theme.of(context).colorScheme.surface.withValues(alpha: .35)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(type == 'video' ? Icons.video_file_rounded : Icons.insert_drive_file_rounded),
        const SizedBox(width: 9),
        Flexible(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  String _initial(String title) => title.trim().isEmpty ? '?' : title.trim().substring(0, 1).toUpperCase();

  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    return DateFormat('d MMMM yyyy').format(date);
  }

  Widget _dayPill(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _messageBubble(Map<String, dynamic> message) {
    final mine = message['sender_id'] == userId;
    final scheme = Theme.of(context).colorScheme;
    final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
    final type = message['message_type']?.toString() ?? 'text';
    final body = message['body']?.toString() ?? '';
    final edited = message['edited_at'] != null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => showMessageActions(message),
        onDoubleTap: () => _react(message['id'].toString(), '❤️'),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
          margin: EdgeInsets.only(left: mine ? 52 : 4, right: mine ? 4 : 52, bottom: 7),
          padding: const EdgeInsets.fromLTRB(14, 10, 11, 7),
          decoration: BoxDecoration(
            gradient: mine
                ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.primaryContainer.withValues(alpha: .82)])
                : null,
            color: mine ? null : scheme.surfaceContainerHighest.withValues(alpha: .86),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(19),
              topRight: const Radius.circular(19),
              bottomLeft: Radius.circular(mine ? 19 : 5),
              bottomRight: Radius.circular(mine ? 5 : 19),
            ),
            border: Border.all(color: scheme.outline.withValues(alpha: .09)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (message['reply_to'] != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
                decoration: BoxDecoration(color: scheme.primary.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)),
                child: const Row(children: [Icon(Icons.reply_rounded, size: 14), SizedBox(width: 5), Text('Reply', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))]),
              ),
            if (type == 'text') Text(body, style: const TextStyle(fontSize: 16, height: 1.28)) else mediaPreview(message),
            const SizedBox(height: 3),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(created == null ? '' : DateFormat('HH:mm').format(created), style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              if (edited) ...[const SizedBox(width: 5), Text('edited', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic))],
              if (mine) ...[const SizedBox(width: 4), Icon(Icons.done_all_rounded, size: 14, color: scheme.primary)],
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: .96),
          border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: .08))),
        ),
        child: Column(children: [
          if (editingId != null || replyingTo != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .45), borderRadius: BorderRadius.circular(15)),
              child: Row(children: [
                Icon(editingId != null ? Icons.edit_rounded : Icons.reply_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(editingId != null ? 'Editing message' : 'Replying to ${replyingTo?['body'] ?? 'message'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() { editingId = null; replyingTo = null; controller.clear(); }), icon: const Icon(Icons.close_rounded, size: 19)),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              tooltip: 'Attach',
              onPressed: uploading ? null : pickAttachment,
              icon: uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_circle_outline_rounded),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: scheme.outline.withValues(alpha: .10)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  IconButton(
                    tooltip: 'Emoji',
                    onPressed: () {
                      setState(() => showEmoji = !showEmoji);
                      if (showEmoji) focus.unfocus();
                    },
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      onTap: () { if (showEmoji) setState(() => showEmoji = false); },
                      onChanged: (value) => typingService.setTyping(value.trim().isNotEmpty),
                      onSubmitted: (_) => sendMessage(),
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(hintText: editingId != null ? 'Edit message' : 'Message', border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                    ),
                  ),
                  IconButton(onPressed: toggleRecording, tooltip: recording ? 'Stop recording' : 'Voice message', icon: Icon(recording ? Icons.stop_circle_rounded : Icons.mic_none_rounded), color: recording ? scheme.error : null),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: editingId != null ? 'Save' : 'Send',
              onPressed: sending ? null : sendMessage,
              icon: Icon(editingId != null ? Icons.check_rounded : Icons.send_rounded),
            ),
          ]),
          if (showEmoji)
            SizedBox(
              height: 210,
              child: GridView.count(
                crossAxisCount: 8,
                padding: const EdgeInsets.all(8),
                children: ['😀','😂','😍','🥰','😎','🤔','😭','😡','👍','👎','❤️','🔥','🎉','🙏','👏','💯','🤣','😘','😊','🥳','😴','🤩','😇','🙌','💙','💔','✨','🚀','😂','😅','🤝','🎯'].map((emoji) => InkWell(onTap: () { controller.text += emoji; controller.selection = TextSelection.collapsed(offset: controller.text.length); }, borderRadius: BorderRadius.circular(12), child: Center(child: Text(emoji, style: const TextStyle(fontSize: 25))))) .toList(),
              ),
            ),
        ]),
      ),
    );
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {},
          child: Row(children: [
            Hero(tag: 'chat-avatar-${widget.conversationId}', child: CircleAvatar(radius: 20, child: Text(_initial(widget.title), style: const TextStyle(fontWeight: FontWeight.w800)))),
            const SizedBox(width: 10),
            Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: Text(typing ? 'typing…' : online ? 'online' : 'offline', key: ValueKey('$typing-$online'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: typing || online ? scheme.primary : scheme.onSurfaceVariant))),
            ])),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'Voice call', onPressed: () => _startCall(false), icon: const Icon(Icons.call_outlined)),
          IconButton(tooltip: 'Video call', onPressed: () => _startCall(true), icon: const Icon(Icons.videocam_outlined)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'search') ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message search is coming next.')));
              if (value == 'clear') ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use message actions to delete individual messages.')));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'search', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.search_rounded), title: Text('Search messages'))),
              PopupMenuItem(value: 'clear', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.cleaning_services_outlined), title: Text('Chat options'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: messageStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Unable to load messages: ${snapshot.error}', textAlign: TextAlign.center)));
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primaryContainer.withValues(alpha: .55)), child: Icon(Icons.waving_hand_rounded, size: 42, color: scheme.primary)),
                  const SizedBox(height: 14),
                  Text('Start a conversation', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('Send a message to ${widget.title}.', style: TextStyle(color: scheme.onSurfaceVariant)),
                ]));
              }
              return ListView.builder(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final message = items[index];
                  final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
                  final previous = index > 0 ? DateTime.tryParse(items[index - 1]['created_at']?.toString() ?? '')?.toLocal() : null;
                  final newDay = created != null && (previous == null || created.year != previous.year || created.month != previous.month || created.day != previous.day);
                  return Column(children: [if (newDay) _dayPill(_dayLabel(created)), _messageBubble(message)]);
                },
              );
            },
          ),
        ),
        _composer(),
      ]),
    );
  }
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
      IconButton(onPressed: toggle, icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_fill), iconSize: 38),
      SizedBox(width: 92, child: LinearProgressIndicator(value: playing ? null : 0)),
      const SizedBox(width: 8),
      Text('${seconds}s', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    ]);
  }
}
