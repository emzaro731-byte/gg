import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GgAiPage extends StatefulWidget {
  const GgAiPage({super.key});

  @override
  State<GgAiPage> createState() => _GgAiPageState();
}

class _GgAiPageState extends State<GgAiPage> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final messages = <Map<String, String>>[];
  bool sending = false;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;
    controller.clear();
    setState(() {
      messages.add({'role': 'user', 'content': text});
      sending = true;
    });
    _scrollToBottom();

    try {
      final response = await supabase.functions.invoke(
        'gg-ai-chat',
        body: {
          'messages': messages
              .map((message) => {'role': message['role'], 'content': message['content']})
              .toList(),
        },
      );
      final data = response.data;
      final reply = data is Map && data['reply'] != null
          ? data['reply'].toString()
          : 'GG AI could not generate a response.';
      if (!mounted) return;
      setState(() => messages.add({'role': 'assistant', 'content': reply}));
    } on FunctionException catch (e) {
      if (!mounted) return;
      final detail = e.details?.toString() ?? e.reasonPhrase ?? 'Unknown error';
      setState(() => messages.add({'role': 'assistant', 'content': 'GG AI is unavailable right now. $detail'}));
    } catch (e) {
      if (!mounted) return;
      setState(() => messages.add({'role': 'assistant', 'content': 'GG AI connection failed. Please try again.'}));
    } finally {
      if (mounted) {
        setState(() => sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(
          children: [
            CircleAvatar(radius: 20, child: Icon(Icons.auto_awesome_rounded)),
            SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('GG AI', style: TextStyle(fontWeight: FontWeight.w900)),
              Text('Powered by Groq', style: TextStyle(fontSize: 11)),
            ]),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New AI chat',
            onPressed: () => setState(() => messages.clear()),
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.auto_awesome_rounded, size: 42, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 18),
                        const Text('Meet GG AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text('Ask questions, write messages, brainstorm ideas, or get help right inside GG.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                      ]),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    itemCount: messages.length,
                    itemBuilder: (_, index) {
                      final message = messages[index];
                      final isUser = message['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 340),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isUser ? 20 : 5),
                              bottomRight: Radius.circular(isUser ? 5 : 20),
                            ),
                          ),
                          child: Text(message['content'] ?? '', style: TextStyle(color: isUser ? scheme.onPrimary : scheme.onSurface, height: 1.4)),
                        ),
                      );
                    },
                  ),
          ),
          if (sending)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(alignment: Alignment.centerLeft, child: Text('GG AI is thinking…')),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Message GG AI…',
                      prefixIcon: const Icon(Icons.auto_awesome_rounded),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sending ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
