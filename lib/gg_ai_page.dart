import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'gg_image_page.dart';

class GgAiPage extends StatefulWidget {
  const GgAiPage({super.key});
  @override
  State<GgAiPage> createState() => _GgAiPageState();
}

class _VoiceStyle {
  const _VoiceStyle(this.name, this.pitch, this.rate);
  final String name;
  final double pitch;
  final double rate;
}

class _GgAiPageState extends State<GgAiPage> {
  final controller = TextEditingController();
  final scrollController = ScrollController();
  final tts = FlutterTts();
  final speech = stt.SpeechToText();
  final messages = <Map<String, dynamic>>[];
  final conversationId = DateTime.now().microsecondsSinceEpoch.toString();
  static const modes = ['Chat', 'Code', 'Debug', 'Explain'];
  static const voiceStyles = [
    _VoiceStyle('Warm', 1.00, .46), _VoiceStyle('Calm', .92, .40), _VoiceStyle('Bright', 1.18, .52),
    _VoiceStyle('Deep', .78, .42), _VoiceStyle('Friendly', 1.06, .48), _VoiceStyle('Professional', .94, .50),
    _VoiceStyle('Energetic', 1.24, .62), _VoiceStyle('Soft', 1.12, .34), _VoiceStyle('News', .98, .58),
    _VoiceStyle('Storyteller', .88, .40), _VoiceStyle('Tutor', 1.02, .45), _VoiceStyle('Assistant', 1.00, .50),
    _VoiceStyle('Gentle', 1.10, .32), _VoiceStyle('Confident', .86, .55), _VoiceStyle('Fast', 1.04, .72),
    _VoiceStyle('Slow', .96, .28), _VoiceStyle('Robot', .72, .58), _VoiceStyle('Cinematic', .82, .38),
    _VoiceStyle('Youthful', 1.26, .54), _VoiceStyle('Classic', .90, .44),
  ];
  String mode = 'Chat';
  int selectedVoice = 0;
  bool sending = false;
  bool listening = false;
  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void dispose() { controller.dispose(); scrollController.dispose(); tts.stop(); speech.stop(); super.dispose(); }

  Future<void> _toggleVoiceInput() async {
    if (listening) { await speech.stop(); if (mounted) setState(() => listening = false); return; }
    final available = await speech.initialize(onStatus: (s) { if (mounted && s == 'done') setState(() => listening = false); }, onError: (_) { if (mounted) setState(() => listening = false); });
    if (!available) return;
    if (mounted) setState(() => listening = true);
    await speech.listen(onResult: (SpeechRecognitionResult r) { if (mounted) { setState(() => controller.text = r.recognizedWords); controller.selection = TextSelection.collapsed(offset: controller.text.length); } }, listenOptions: const stt.SpeechListenOptions(partialResults: true, listenMode: stt.ListenMode.dictation));
  }

  Future<void> _speak(String text) async { final v = voiceStyles[selectedVoice]; await tts.setLanguage('en-US'); await tts.setPitch(v.pitch); await tts.setSpeechRate(v.rate); await tts.setVolume(1); await tts.speak(text); }

  Future<void> _send() async {
    final text = controller.text.trim(); if (text.isEmpty || sending) return;
    controller.clear(); setState(() { messages.add({'role': 'user', 'content': text}); sending = true; }); _scrollToBottom();
    try {
      final response = await supabase.functions.invoke('gg-ai-chat', body: {'messages': messages.map((m) => {'role': m['role'], 'content': m['content']}).toList(), 'mode': mode, 'model': 'openai/gpt-oss-120b'});
      final data = response.data; final reply = data is Map && data['reply'] != null ? data['reply'].toString() : 'GG AI could not generate a response.';
      if (mounted) setState(() => messages.add({'role': 'assistant', 'content': reply}));
    } on FunctionException catch (e) { if (mounted) setState(() => messages.add({'role': 'assistant', 'content': 'GG AI is unavailable right now. ${e.details ?? e.reasonPhrase ?? ''}'})); }
    catch (_) { if (mounted) setState(() => messages.add({'role': 'assistant', 'content': 'GG AI connection failed. Please try again.'})); }
    finally { if (mounted) { setState(() => sending = false); _scrollToBottom(); } }
  }

  Future<void> _attach() async {
    final result = await FilePicker.platform.pickFiles(withData: true); final file = result?.files.single; if (file == null || file.bytes == null) return;
    final path = '${supabase.auth.currentUser!.id}/ai/${DateTime.now().millisecondsSinceEpoch}_${file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}';
    try { await supabase.storage.from('chat-media').uploadBinary(path, file.bytes!, fileOptions: FileOptions(upsert: false)); if (mounted) setState(() => messages.add({'role': 'user', 'content': '📎 ${file.name}', 'attachment': path})); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Attachment upload failed: $e'))); }
  }

  Future<void> _feedback(int index, int value) async { try { await supabase.from('ai_feedback').upsert({'conversation_id': conversationId, 'message_index': index, 'user_id': supabase.auth.currentUser!.id, 'value': value, 'updated_at': DateTime.now().toUtc().toIso8601String()}); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value == 1 ? 'Liked' : 'Disliked'))); } catch (_) {} }
  Future<void> _copy(String text) async { await Clipboard.setData(ClipboardData(text: text)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'))); }
  Future<void> _share(String text) async { await Share.share(text); }

  void _scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (scrollController.hasClients) scrollController.animateTo(scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }); }
  IconData _modeIcon(String value) { switch (value) { case 'Code': return Icons.code_rounded; case 'Debug': return Icons.bug_report_rounded; case 'Explain': return Icons.school_rounded; default: return Icons.auto_awesome_rounded; } }

  Future<void> _voicePicker() async { await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => ListView.builder(itemCount: voiceStyles.length, itemBuilder: (_, i) => ListTile(leading: CircleAvatar(child: Text('${i + 1}')), title: Text(voiceStyles[i].name), trailing: selectedVoice == i ? const Icon(Icons.check_circle_rounded) : null, onTap: () { setState(() => selectedVoice = i); Navigator.pop(context); }))); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Row(children: [CircleAvatar(radius: 20, child: Icon(_modeIcon(mode))), const SizedBox(width: 10), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GG AI', style: TextStyle(fontWeight: FontWeight.w900)), Text('GPT-OSS 120B • Groq', style: TextStyle(fontSize: 11))])]), actions: [IconButton(tooltip: 'Voice style', onPressed: _voicePicker, icon: const Icon(Icons.record_voice_over_rounded)), IconButton(tooltip: 'Generate image', onPressed: sending ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GgImagePage())), icon: const Icon(Icons.image_rounded)), IconButton(tooltip: 'New AI chat', onPressed: sending ? null : () => setState(() => messages.clear()), icon: const Icon(Icons.add_comment_rounded))]),
      body: Column(children: [
        SizedBox(height: 58, child: ListView.separated(padding: const EdgeInsets.all(8), scrollDirection: Axis.horizontal, itemCount: modes.length, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, i) { final item = modes[i]; return ChoiceChip(selected: mode == item, avatar: Icon(_modeIcon(item), size: 18), label: Text(item), onSelected: sending ? null : (_) => setState(() => mode = item)); })),
        Expanded(child: messages.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle), child: Icon(_modeIcon(mode), size: 42, color: scheme.onPrimaryContainer)), const SizedBox(height: 18), const Text('GG AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text('Voice assistant • 20 voice styles • copy • share • like/dislike • image generation • attachments', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge)]))) : ListView.builder(controller: scrollController, padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), itemCount: messages.length, itemBuilder: (_, index) { final m = messages[index]; final user = m['role'] == 'user'; final text = m['content']?.toString() ?? ''; return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: const BoxConstraints(maxWidth: 380), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.fromLTRB(14, 12, 10, 8), decoration: BoxDecoration(color: user ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(text, style: TextStyle(color: user ? scheme.onPrimary : scheme.onSurface, height: 1.4)), if (m['attachment'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('📎 Attachment uploaded', style: TextStyle(color: user ? scheme.onPrimary : scheme.primary, fontWeight: FontWeight.w700))), if (!user) Row(children: [IconButton(tooltip: 'Listen', onPressed: () => _speak(text), icon: const Icon(Icons.volume_up_rounded, size: 19)), IconButton(tooltip: 'Copy', onPressed: () => _copy(text), icon: const Icon(Icons.copy_rounded, size: 18)), IconButton(tooltip: 'Share', onPressed: () => _share(text), icon: const Icon(Icons.share_rounded, size: 18)), IconButton(tooltip: 'Like', onPressed: () => _feedback(index, 1), icon: const Icon(Icons.thumb_up_alt_outlined, size: 18)), IconButton(tooltip: 'Dislike', onPressed: () => _feedback(index, -1), icon: const Icon(Icons.thumb_down_alt_outlined, size: 18))])]))); })) ),
        if (sending) const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 6), child: Align(alignment: Alignment.centerLeft, child: Text('GG AI is thinking…'))),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 12), child: Row(children: [IconButton(tooltip: 'Upload image/video/file', onPressed: sending ? null : _attach, icon: const Icon(Icons.attach_file_rounded)), Expanded(child: TextField(controller: controller, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), minLines: 1, maxLines: 6, decoration: InputDecoration(hintText: listening ? 'Listening…' : 'Message GG AI…', prefixIcon: Icon(_modeIcon(mode)), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)))), IconButton(tooltip: 'Voice assistant', onPressed: _toggleVoiceInput, icon: Icon(listening ? Icons.stop_circle_rounded : Icons.mic_rounded)), const SizedBox(width: 3), IconButton.filled(onPressed: sending ? null : _send, icon: const Icon(Icons.arrow_upward_rounded))]))),
      ]),
    );
  }
}
