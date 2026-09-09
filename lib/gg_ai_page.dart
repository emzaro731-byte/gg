import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gg_image_page.dart';

class GgAiPage extends StatefulWidget {
  const GgAiPage({super.key});

  @override
  State<GgAiPage> createState() => _GgAiPageState();
}

class _GgAiPageState extends State<GgAiPage> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final messages = <Map<String, String>>[];
  static const modes = ['Chat', 'Code', 'Debug', 'Explain'];
  String mode = 'Chat';
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
          'mode': mode,
          'model': 'openai/gpt-oss-120b',
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
    } catch (_) {
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

  IconData _modeIcon(String value) {
    switch (value) {
      case 'Code': return Icons.code_rounded;
      case 'Debug': return Icons.bug_report_rounded;
      case 'Explain': return Icons.school_rounded;
      default: return Icons.auto_awesome_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(radius: 20, child: Icon(_modeIcon(mode))),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GG AI', style: TextStyle(fontWeight: FontWeight.w900)),
            Text('GPT-OSS 120B • Groq', style: TextStyle(fontSize: 11)),
          ]),
        ]),
        actions: [
          IconButton(
            tooltip: 'Generate image',
            onPressed: sending ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GgImagePage())),
            icon: const Icon(Icons.image_rounded),
          ),
          IconButton(
            tooltip: 'New AI chat',
            onPressed: sending ? null : () => setState(() => messages.clear()),
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 58,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            scrollDirection: Axis.horizontal,
            itemCount: modes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final item = modes[index];
              return ChoiceChip(
                selected: mode == item,
                avatar: Icon(_modeIcon(item), size: 18),
                label: Text(item),
                onSelected: sending ? null : (_) => setState(() => mode = item),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Create image with Magic Hour'),
              onPressed: sending ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GgImagePage())),
            ),
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                        child: Icon(_modeIcon(mode), size: 42, color: scheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 18),
                      Text('GG AI ${mode == 'Chat' ? '' : mode}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                        mode == 'Code'
                            ? 'Build Flutter, Dart, React, Python, APIs and more with GPT-OSS 120B.'
                            : mode == 'Debug'
                                ? 'Paste an error or code and let GG AI find the cause and fix it.'
                                : mode == 'Explain'
                                    ? 'Get clear, step-by-step explanations for code and technical topics.'
                                    : 'Ask questions, write messages, brainstorm ideas, or create images right inside GG.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
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
                        constraints: const BoxConstraints(maxWidth: 360),
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
                  maxLines: 7,
                  decoration: InputDecoration(
                    hintText: mode == 'Code' ? 'Describe code to build…' : mode == 'Debug' ? 'Paste an error or bug…' : 'Message GG AI…',
                    prefixIcon: Icon(_modeIcon(mode)),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: sending ? null : _send, icon: const Icon(Icons.arrow_upward_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}
