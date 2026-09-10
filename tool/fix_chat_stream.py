from pathlib import Path

p = Path('lib/chat_page.dart')
s = p.read_text()

field = "  List<Map<String, dynamic>> _lastMessages = const <Map<String, dynamic>>[];\n"
anchor = "  Stopwatch? recordClock;\n"
if field not in s:
    if anchor not in s:
        raise SystemExit('Chat state anchor not found')
    s = s.replace(anchor, anchor + field, 1)

old = """              builder: (context, snapshot) {
                final items = snapshot.data ?? const <Map<String, dynamic>>[];
                if (snapshot.hasError) return const Center(child: Text('Unable to load messages right now.'));
                if (items.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 34, child: Text(_initial(widget.title), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))), const SizedBox(height: 12), Text('Start chatting with ${widget.title}', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 5), const Text('Messages are private to this conversation.', style: TextStyle(fontSize: 12))]));
                return ListView.builder(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.fromLTRB(10, 8, 10, 14), itemCount: items.length, itemBuilder: (_, i) => _messageBubble(items[i]));
              },"""
new = """              builder: (context, snapshot) {
                // Supabase realtime streams can briefly emit an empty/error state while
                // reconnecting. Never replace an already loaded conversation with the
                // empty-chat screen during that transient state.
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  _lastMessages = List<Map<String, dynamic>>.unmodifiable(snapshot.data!);
                }
                final items = snapshot.hasData && snapshot.data!.isNotEmpty
                    ? snapshot.data!
                    : _lastMessages;
                if (snapshot.hasError && items.isEmpty) {
                  return const Center(child: Text('Unable to load messages right now.'));
                }
                if (items.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 34, child: Text(_initial(widget.title), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))), const SizedBox(height: 12), Text('Start chatting with ${widget.title}', style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 5), const Text('Messages are private to this conversation.', style: TextStyle(fontSize: 12))]));
                return ListView.builder(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.fromLTRB(10, 8, 10, 14), itemCount: items.length, itemBuilder: (_, i) => _messageBubble(items[i]));
              },"""
if old not in s:
    raise SystemExit('Expected StreamBuilder block not found')
s = s.replace(old, new, 1)
p.write_text(s)
print('Fixed transient empty chat stream state.')
