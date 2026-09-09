from pathlib import Path


def replace_between(path, start, end, replacement):
    p = Path(path)
    s = p.read_text()
    a = s.find(start)
    if a < 0:
        raise SystemExit(f'{path}: start marker not found: {start}')
    b = s.find(end, a)
    if b < 0:
        raise SystemExit(f'{path}: end marker not found: {end}')
    p.write_text(s[:a] + replacement + s[b:])


# Premium WhatsApp-style message bubbles for the online chat implementation.
message = r'''  Widget _messageBubble(Map<String, dynamic> message) {
    final mine = message['sender_id'] == userId;
    final scheme = Theme.of(context).colorScheme;
    final created = DateTime.tryParse(message['created_at']?.toString() ?? '')?.toLocal();
    final type = message['message_type']?.toString() ?? 'text';
    final body = message['body']?.toString() ?? '';
    final edited = message['edited_at'] != null;
    final time = created == null ? '' : DateFormat('HH:mm').format(created);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => showMessageActions(message),
        onDoubleTap: () => _react(message['id'].toString(), '❤️'),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .84),
          margin: EdgeInsets.only(left: mine ? 54 : 6, right: mine ? 6 : 54, bottom: 6),
          padding: const EdgeInsets.fromLTRB(13, 9, 10, 6),
          decoration: BoxDecoration(
            gradient: mine
                ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primary, scheme.primary.withValues(alpha: .82)])
                : null,
            color: mine ? null : scheme.surfaceContainerHighest.withValues(alpha: .92),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(mine ? 20 : 5),
              bottomRight: Radius.circular(mine ? 5 : 20),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (type != 'text') mediaPreview(message) else Text(body, style: TextStyle(fontSize: 15.5, height: 1.28, color: mine ? scheme.onPrimary : scheme.onSurface)),
            if (type == 'text' && edited) Padding(padding: const EdgeInsets.only(top: 2), child: Text('edited', style: TextStyle(fontSize: 9, color: mine ? scheme.onPrimary.withValues(alpha: .7) : scheme.onSurfaceVariant))),
            if (time.isNotEmpty) Align(alignment: Alignment.bottomRight, child: Padding(padding: const EdgeInsets.only(top: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(time, style: TextStyle(fontSize: 9, color: mine ? scheme.onPrimary.withValues(alpha: .7) : scheme.onSurfaceVariant)), if (mine) ...[const SizedBox(width: 3), Icon(Icons.done_all_rounded, size: 14, color: scheme.onPrimary.withValues(alpha: .78))]]))),
          ]),
        ),
      ),
    );
  }

'''
replace_between('lib/chat_page.dart', '  Widget _messageBubble(Map<String, dynamic> message) {', '  @override\n  void dispose()', message)

# Modern online composer and header. Keep all existing business logic and handlers.
build = r'''  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface.withValues(alpha: .92),
        titleSpacing: 4,
        title: Row(children: [
          Stack(children: [
            CircleAvatar(radius: 20, backgroundColor: scheme.primaryContainer, child: Text(_initial(widget.title), style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer))),
            Positioned(right: 0, bottom: 0, child: Container(width: 11, height: 11, decoration: BoxDecoration(color: online ? Colors.green : scheme.outline, shape: BoxShape.circle, border: Border.all(color: scheme.surface, width: 2)))),
          ]),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: Text(typing ? 'typing…' : online ? 'online' : 'offline', key: ValueKey('$typing-$online'), style: TextStyle(fontSize: 11, color: typing ? scheme.primary : scheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
          ])),
        ]),
        actions: [
          IconButton(tooltip: 'Voice call', onPressed: () => _startCall(false), icon: const Icon(Icons.call_rounded)),
          IconButton(tooltip: 'Video call', onPressed: () => _startCall(true), icon: const Icon(Icons.videocam_rounded)),
          PopupMenuButton<String>(onSelected: (v) { if (v == 'search') ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat search is coming soon.'))); }, itemBuilder: (_) => const [PopupMenuItem(value: 'search', child: ListTile(leading: Icon(Icons.search_rounded), title: Text('Search in chat'))), PopupMenuItem(value: 'media', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('Media, links & files')))]),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [scheme.surface, scheme.surfaceContainerLowest])),
        child: SafeArea(
          top: false,
          child: Column(children: [
            const SizedBox(height: kToolbarHeight + 8),
            Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messageStream,
              builder: (context, snapshot) {
                final items = snapshot.data ?? const <Map<String, dynamic>>[];
                if (snapshot.hasError) return const Center(child: Text('Unable to load messages right now.'));
                if (items.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 34, child: Text(_initial(widget.title), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))), const SizedBox(height: 12), Text('Start chatting with ${widget.title}', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 5), const Text('Messages are private to this conversation.', style: TextStyle(fontSize: 12))]));
                return ListView.builder(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.fromLTRB(10, 8, 10, 14), itemCount: items.length, itemBuilder: (_, i) => _messageBubble(items[i]));
              },
            )),
            if (replyingTo != null) Container(margin: const EdgeInsets.fromLTRB(10, 4, 10, 0), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .55), borderRadius: BorderRadius.circular(16)), child: Row(children: [Icon(Icons.reply_rounded, size: 18, color: scheme.primary), const SizedBox(width: 8), Expanded(child: Text(replyingTo?['body']?.toString() ?? 'Replying', maxLines: 1, overflow: TextOverflow.ellipsis)), IconButton(onPressed: () => setState(() => replyingTo = null), icon: const Icon(Icons.close_rounded), visualDensity: VisualDensity.compact)])),
            SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(9, 7, 9, 9), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle), child: IconButton(tooltip: 'Attach', onPressed: uploading ? null : pickAttachment, icon: const Icon(Icons.add_rounded))),
              const SizedBox(width: 7),
              Expanded(child: Container(padding: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(25), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45))), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: controller, focusNode: focus, minLines: 1, maxLines: 5, textCapitalization: TextCapitalization.sentences, onChanged: (value) => typingService.setTyping(value.trim().isNotEmpty), decoration: InputDecoration(hintText: editingId == null ? 'Message' : 'Edit message', border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11), suffixIcon: IconButton(tooltip: 'Emoji', onPressed: () => setState(() => showEmoji = !showEmoji), icon: const Icon(Icons.emoji_emotions_outlined)))))])),
              const SizedBox(width: 7),
              Container(decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle), child: IconButton(tooltip: controller.text.trim().isEmpty ? 'Voice message' : 'Send', onPressed: uploading ? null : (controller.text.trim().isEmpty ? toggleRecording : sendMessage), icon: Icon(recording ? Icons.stop_rounded : controller.text.trim().isEmpty ? Icons.mic_rounded : Icons.send_rounded, color: scheme.onPrimary))),
            ])),),
            if (showEmoji) Container(height: 52, alignment: Alignment.center, child: const Text('😀  😂  ❤️  👍  🔥  🎉  😍  😢  😮  🙏', style: TextStyle(fontSize: 23))),
          ]),
        ),
      ),
    );
  }
}

'''
replace_between('lib/chat_page.dart', '  @override\n  Widget build(BuildContext context) {', 'class VoiceMessageBubble', build)

# Offline cached chat gets the same visual language without pretending realtime is available.
offline_build = r'''  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(titleSpacing: 4, title: Row(children: [CircleAvatar(child: Text(widget.title.isEmpty ? '?' : widget.title[0].toUpperCase())), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis), const Text('Offline • messages will sync automatically', style: TextStyle(fontSize: 10))]))]), actions: [IconButton(onPressed: () => _startCall(false), icon: const Icon(Icons.call_rounded)), IconButton(onPressed: () => _startCall(true), icon: const Icon(Icons.videocam_rounded))]),
      body: Column(children: [
        Container(width: double.infinity, margin: const EdgeInsets.fromLTRB(10, 8, 10, 0), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9), decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(15)), child: Row(children: [Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onTertiaryContainer), const SizedBox(width: 8), Expanded(child: Text('Offline mode • your messages are safe on this device.', style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer, fontWeight: FontWeight.w600)))])),
        Expanded(child: messages.isEmpty ? const Center(child: Text('No cached messages yet.')) : ListView.builder(padding: const EdgeInsets.fromLTRB(10, 12, 10, 12), itemCount: messages.length, itemBuilder: (_, index) { final m = messages[index]; final mine = m['sender_id'] == userId; final queued = m['_offline'] == true; return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .84), margin: EdgeInsets.only(left: mine ? 54 : 5, right: mine ? 5 : 54, bottom: 6), padding: const EdgeInsets.fromLTRB(13, 9, 10, 7), decoration: BoxDecoration(color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest, borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(mine ? 20 : 5), bottomRight: Radius.circular(mine ? 5 : 20))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['body']?.toString() ?? '', style: const TextStyle(fontSize: 15.5, height: 1.28)), Row(mainAxisSize: MainAxisSize.min, children: [if (queued) const Text('Queued', style: TextStyle(fontSize: 9)), if (queued) const SizedBox(width: 4), const Icon(Icons.schedule_rounded, size: 13)])]))); }),
        ),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(9, 7, 9, 9), child: Row(children: [Container(decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle), child: const Icon(Icons.add_rounded)), const SizedBox(width: 7), Expanded(child: Container(decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(25)), child: TextField(controller: controller, minLines: 1, maxLines: 5, onChanged: _draftChanged, decoration: const InputDecoration(hintText: 'Message', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 11)))), const SizedBox(width: 7), IconButton.filled(onPressed: sending ? null : _send, icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded))]))),
      ]),
    );
  }
}
'''
replace_between('lib/offline_first_chat_page.dart', '  @override\n  Widget build(BuildContext context) {', '\n}\n', offline_build)

print('Chat UI upgrade applied.')
