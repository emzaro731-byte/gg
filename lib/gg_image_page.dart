import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class GgImagePage extends StatefulWidget {
  const GgImagePage({super.key});

  @override
  State<GgImagePage> createState() => _GgImagePageState();
}

class _GgImagePageState extends State<GgImagePage> {
  final promptController = TextEditingController();
  final modelController = TextEditingController(text: 'seedream/5.0-pro');
  final imageUrlController = TextEditingController();
  final titleController = TextEditingController(text: 'GG AI Creation');
  final styleController = TextEditingController();
  final advancedController = TextEditingController();
  final AudioPlayer audioPlayer = AudioPlayer();

  String type = 'image';
  String provider = 'auto';
  String aspectRatio = '1:1';
  bool instrumental = false;
  bool generating = false;
  bool downloading = false;
  bool audioPlaying = false;
  String? outputUrl;
  String? taskId;
  String? error;
  VideoPlayerController? videoController;

  SupabaseClient get supabase => Supabase.instance.client;

  static const _presets = <String, List<Map<String, String>>>{
    'Image': [
      {'name': 'Seedream 5.0 Pro', 'id': 'seedream/5.0-pro'},
      {'name': 'Seedream 4.5', 'id': 'seedream/4.5'},
      {'name': 'Google Imagen 4', 'id': 'google/imagen4'},
      {'name': 'Google Imagen 4 Ultra', 'id': 'google/imagen4-ultra'},
      {'name': 'Flux 2 Pro', 'id': 'flux-2/pro'},
      {'name': 'Grok Imagine', 'id': 'grok-imagine'},
      {'name': 'GPT Image 2', 'id': 'gpt-image-2'},
      {'name': 'Ideogram V3', 'id': 'ideogram-v3'},
      {'name': 'Qwen Image', 'id': 'qwen-image'},
    ],
    'Video': [
      {'name': 'Kling 3.0', 'id': 'kling-3.0'},
      {'name': 'Kling 2.6', 'id': 'kling-2.6/text-to-video'},
      {'name': 'Kling 3.0 Turbo', 'id': 'kling-3.0/turbo-text-to-video'},
      {'name': 'Seedance 2.0', 'id': 'bytedance/seedance-2.0'},
      {'name': 'Seedance 2.0 Fast', 'id': 'bytedance/seedance-2.0-fast'},
      {'name': 'Seedance 1.5 Pro', 'id': 'bytedance/seedance-1.5-pro'},
      {'name': 'Hailuo 2.3 Pro', 'id': 'hailuo/2.3-pro'},
      {'name': 'Wan 2.7', 'id': 'wan/2.7-text-to-video'},
      {'name': 'Wan 2.6', 'id': 'wan/2.6-text-to-video'},
      {'name': 'Grok Imagine Video', 'id': 'grok-imagine-video'},
      {'name': 'Veo 3.1 Fast', 'id': 'veo3/veo-3.1-fast'},
      {'name': 'Veo 3.1 Quality', 'id': 'veo3/veo-3.1-quality'},
      {'name': 'Runway', 'id': 'runway'},
      {'name': 'PixVerse V6', 'id': 'pixverse/v6'},
    ],
    'Music': [
      {'name': 'Suno V5.5', 'id': 'V5_5'},
      {'name': 'Suno V5', 'id': 'V5'},
      {'name': 'Suno V4.5+', 'id': 'V4_5PLUS'},
      {'name': 'Suno V4.5', 'id': 'V4_5'},
      {'name': 'Suno V4.5 All', 'id': 'V4_5ALL'},
      {'name': 'Suno V4', 'id': 'V4'},
      {'name': 'Suno V3.5', 'id': 'V3_5'},
    ],
  };

  @override
  void dispose() {
    promptController.dispose();
    modelController.dispose();
    imageUrlController.dispose();
    titleController.dispose();
    styleController.dispose();
    advancedController.dispose();
    audioPlayer.dispose();
    videoController?.dispose();
    super.dispose();
  }

  void _setType(String value) {
    setState(() {
      type = value;
      modelController.text = _presets[value == 'image' ? 'Image' : value == 'video' ? 'Video' : 'Music']!.first['id']!;
      outputUrl = null;
      taskId = null;
      error = null;
      if (value == 'image') aspectRatio = '1:1';
      if (value == 'video') aspectRatio = '16:9';
    });
  }

  void _selectPreset(String id) => setState(() => modelController.text = id);

  Map<String, dynamic> _input() {
    Map<String, dynamic> input = {};
    final raw = advancedController.text.trim();
    if (raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Advanced input must be a JSON object.');
      input = Map<String, dynamic>.from(decoded);
    }
    if (type == 'video') {
      input['aspectRatio'] = aspectRatio;
      if (imageUrlController.text.trim().isNotEmpty) input['imageUrl'] = imageUrlController.text.trim();
    }
    if (type == 'image') input['aspect_ratio'] = aspectRatio;
    if (type == 'music') {
      input['customMode'] = true;
      input['instrumental'] = instrumental;
      input['title'] = titleController.text.trim();
      input['style'] = styleController.text.trim();
      input['prompt'] = promptController.text.trim();
    }
    return input;
  }

  Future<void> _generate() async {
    final prompt = promptController.text.trim();
    final model = modelController.text.trim();
    if (generating || model.isEmpty || (prompt.isEmpty && type != 'music')) return;
    final session = supabase.auth.currentSession;
    if (session == null) {
      setState(() => error = 'Please sign in to GG before generating media.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      generating = true;
      error = null;
      outputUrl = null;
      taskId = null;
    });
    try {
      final response = await supabase.functions.invoke('gg-media-generate', body: {
        'provider': provider,
        'type': type,
        'model': model,
        'prompt': prompt,
        'input': _input(),
      });
      final data = response.data;
      if (data is! Map) throw Exception('Invalid response from GG media service.');
      final returnedError = data['error']?.toString();
      final url = data['output_url']?.toString();
      final returnedTask = data['task_id']?.toString();
      if (url == null || url.isEmpty) {
        if (returnedTask == null || returnedTask.isEmpty) throw Exception(returnedError ?? 'The provider returned no output.');
        if (mounted) setState(() => taskId = returnedTask);
        await _pollTask(returnedTask);
      } else {
        if (mounted) setState(() => outputUrl = url);
        await _prepareVideo(url);
      }
    } on FunctionException catch (e) {
      final details = e.details;
      String message = 'Media generation failed.';
      if (details is Map && details['error'] != null) message = details['error'].toString();
      else if (details != null) message = details.toString();
      else if (e.reasonPhrase?.isNotEmpty == true) message = e.reasonPhrase!;
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> _pollTask(String id) async {
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final response = await supabase.functions.invoke('gg-media-generate', body: {
        'action': 'status',
        'provider': 'kie',
        'type': type,
        'task_id': id,
      });
      final data = response.data;
      if (data is! Map) continue;
      final url = data['output_url']?.toString();
      final responseData = data['data'];
      final successFlag = data['successFlag'] ?? (responseData is Map ? responseData['successFlag'] : null);
      final status = data['status']?.toString() ?? (responseData is Map ? responseData['status']?.toString() : null);
      if (url != null && url.isNotEmpty) {
        setState(() => outputUrl = url);
        await _prepareVideo(url);
        return;
      }
      if (successFlag == 2 || status == 'failed' || status == 'error' || status == 'fail') {
        throw Exception(data['errorMessage']?.toString() ?? 'KIE generation failed.');
      }
      if (successFlag == 1) {
        final nested = responseData is Map ? responseData['response'] : null;
        final nestedUrl = nested is Map
            ? (nested['resultUrls'] is List && nested['resultUrls'].isNotEmpty ? nested['resultUrls'].first.toString() : null)
            : null;
        if (nestedUrl != null && nestedUrl.isNotEmpty) {
          setState(() => outputUrl = nestedUrl);
          await _prepareVideo(nestedUrl);
          return;
        }
      }
    }
    throw Exception('Generation is still processing. Task ID: $id');
  }

  Future<void> _prepareVideo(String url) async {
    if (type != 'video') return;
    final old = videoController;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    videoController = controller;
    await old?.dispose();
    await controller.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _playAudio() async {
    final url = outputUrl;
    if (url == null) return;
    if (audioPlaying) {
      await audioPlayer.pause();
      if (mounted) setState(() => audioPlaying = false);
      return;
    }
    await audioPlayer.play(UrlSource(url));
    if (mounted) setState(() => audioPlaying = true);
    audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => audioPlaying = false);
    });
  }

  String _extension() => type == 'image' ? 'png' : type == 'video' ? 'mp4' : 'mp3';

  Future<void> _downloadOutput() async {
    final url = outputUrl;
    if (url == null || url.isEmpty || downloading) return;
    setState(() {
      downloading = true;
      error = null;
    });
    try {
      final response = await supabase.functions.invoke('gg-media-generate', body: {
        'action': 'download',
        'provider': provider,
        'type': type,
        'source_url': url,
      });
      final data = response.data;
      if (data is! Map) throw Exception('Invalid download response.');
      final downloadUrl = data['download_url']?.toString();
      if (downloadUrl == null || downloadUrl.isEmpty) throw Exception(data['error']?.toString() ?? 'No download URL was returned.');
      final safeTitle = titleController.text.trim().isEmpty
          ? 'gg-$type'
          : titleController.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final fileName = '$safeTitle-${DateTime.now().millisecondsSinceEpoch}.${_extension()}';
      final saved = await FileSaver.instance.downloadLink(
        link: LinkDetails(link: downloadUrl),
        name: fileName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to your phone: $fileName')));
        if (saved.isEmpty) setState(() => error = 'Check your Downloads folder for the generated file.');
      }
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] != null
          ? details['error'].toString()
          : details?.toString() ?? e.reasonPhrase ?? 'Download failed.';
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  String get _typeLabel => type == 'image' ? 'Image' : type == 'video' ? 'Video' : 'Music';
  IconData get _typeIcon => type == 'image' ? Icons.auto_awesome_rounded : type == 'video' ? Icons.movie_creation_rounded : Icons.music_note_rounded;
  String get _typeDescription => type == 'image'
      ? 'Create polished artwork, portraits and visuals.'
      : type == 'video'
          ? 'Turn ideas and images into cinematic video.'
          : 'Generate songs, instrumentals and sound ideas.';

  Widget _sectionCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
    );
  }

  Widget _modeButton(String value, String label, IconData icon) {
    final selected = type == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: generating ? null : () => _setType(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Icon(icon, color: selected ? Theme.of(context).colorScheme.onPrimary : null),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Theme.of(context).colorScheme.onPrimary : null)),
          ]),
        ),
      ),
    );
  }

  Widget _buildOutput(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (outputUrl == null) return const SizedBox.shrink();
    return _sectionCard(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(_typeIcon)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your $_typeLabel is ready', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text('Preview and save it to your phone.', style: Theme.of(context).textTheme.bodySmall),
            ])),
          ]),
        ),
        if (type == 'image')
          ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(outputUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 220, child: Center(child: Text('Preview unavailable'))))),
        if (type == 'video' && videoController?.value.isInitialized == true)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: videoController!.value.aspectRatio,
              child: Stack(alignment: Alignment.center, children: [
                VideoPlayer(videoController!),
                DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(50)),
                  child: IconButton(
                    onPressed: () => setState(() => videoController!.value.isPlaying ? videoController!.pause() : videoController!.play()),
                    iconSize: 34,
                    color: Colors.white,
                    icon: Icon(videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                ),
              ]),
            ),
          ),
        if (type == 'music')
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              CircleAvatar(radius: 28, child: Icon(audioPlaying ? Icons.graphic_eq_rounded : Icons.music_note_rounded)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titleController.text.trim().isEmpty ? 'GG AI Music' : titleController.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(audioPlaying ? 'Playing now' : 'Ready to preview', style: Theme.of(context).textTheme.bodySmall),
              ])),
              IconButton.filled(onPressed: _playAudio, icon: Icon(audioPlaying ? Icons.pause : Icons.play_arrow)),
            ]),
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: downloading ? null : _downloadOutput,
            icon: downloading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
            label: Text(downloading ? 'Saving…' : 'Save $_typeLabel to phone'),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presets = _presets[_typeLabel]!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GG Create', style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: generating ? null : () => setState(() { promptController.clear(); outputUrl = null; taskId = null; error = null; }),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primaryContainer, scheme.secondaryContainer]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(children: [
              Container(width: 58, height: 58, decoration: BoxDecoration(color: scheme.surface.withValues(alpha: .65), borderRadius: BorderRadius.circular(18)), child: Icon(_typeIcon, size: 30)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI $_typeLabel Studio', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(_typeDescription),
              ])),
            ]),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            padding: const EdgeInsets.all(6),
            child: Row(children: [
              _modeButton('image', 'Image', Icons.image_rounded),
              _modeButton('video', 'Video', Icons.movie_creation_rounded),
              _modeButton('music', 'Music', Icons.music_note_rounded),
            ]),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Generation setup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Choose the engine and model for this creation.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: provider,
                decoration: const InputDecoration(labelText: 'AI engine', prefixIcon: Icon(Icons.hub_rounded)),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto — use Supabase AI configuration')),
                  DropdownMenuItem(value: 'kie', child: Text('KIE AI')),
                  DropdownMenuItem(value: 'existing-api', child: Text('Existing GG AI API')),
                ],
                onChanged: generating ? null : (v) => setState(() => provider = v ?? 'auto'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: presets.any((p) => p['id'] == modelController.text) ? modelController.text : null,
                decoration: InputDecoration(labelText: 'Model', prefixIcon: Icon(_typeIcon)),
                hint: const Text('Select a model'),
                items: presets.map((p) => DropdownMenuItem(value: p['id'], child: Text(p['name']!))).toList(),
                onChanged: generating ? null : (v) { if (v != null) _selectPreset(v); },
              ),
              const SizedBox(height: 10),
              TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model ID', prefixIcon: Icon(Icons.code_rounded), hintText: 'Enter any current KIE model ID')),
              const SizedBox(height: 8),
              Text('API credentials stay inside Supabase and are never shipped in the APK.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type == 'music' ? 'Describe your song' : 'Describe your creation', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(type == 'music' ? 'Give GG the lyrics, mood or musical direction.' : 'Be specific about subject, style, lighting and motion.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                minLines: 5,
                maxLines: 9,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: type == 'video' ? 'A cinematic futuristic Lagos night drive, neon reflections, smooth camera movement…' : type == 'music' ? 'High-energy Nigerian Afrobeats with infectious drums, rich vocals and a confident hook…' : 'A futuristic Nigerian city at night, cinematic lighting, premium realistic photography…',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
              if (type == 'music') ...[
                const SizedBox(height: 12),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Song title', prefixIcon: Icon(Icons.title_rounded))),
                const SizedBox(height: 12),
                TextField(controller: styleController, maxLines: 3, decoration: const InputDecoration(labelText: 'Style / genre', hintText: 'Afrobeats, Afro-fusion, R&B, cinematic…', prefixIcon: Icon(Icons.tune_rounded))),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Instrumental only', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Generate without vocals'), value: instrumental, onChanged: generating ? null : (v) => setState(() => instrumental = v)),
              ],
              if (type == 'video') ...[
                const SizedBox(height: 12),
                TextField(controller: imageUrlController, decoration: const InputDecoration(labelText: 'Reference image URL', hintText: 'Optional image-to-video source', prefixIcon: Icon(Icons.link_rounded))),
              ],
            ]),
          ),
          if (type != 'music') ...[
            const SizedBox(height: 14),
            _sectionCard(child: Row(children: [
              const Icon(Icons.crop_rounded),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Aspect ratio', style: TextStyle(fontWeight: FontWeight.w800)), Text('Choose the output frame.', style: TextStyle(fontSize: 12))])),
              DropdownButton<String>(value: aspectRatio, underline: const SizedBox.shrink(), items: const [DropdownMenuItem(value: '1:1', child: Text('1:1')), DropdownMenuItem(value: '16:9', child: Text('16:9')), DropdownMenuItem(value: '9:16', child: Text('9:16'))], onChanged: generating ? null : (v) => setState(() => aspectRatio = v ?? aspectRatio)),
            ])),
          ],
          const SizedBox(height: 14),
          _sectionCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Advanced controls', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Optional model-specific JSON parameters'),
              children: [Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: TextField(controller: advancedController, minLines: 4, maxLines: 10, decoration: const InputDecoration(hintText: '{"duration": 5, "quality": "1080p"}', alignLabelWithHint: true)))],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 58,
            child: FilledButton.icon(
              onPressed: generating ? null : _generate,
              icon: generating ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_typeIcon),
              label: Text(generating ? 'Creating $_typeLabel…' : 'Create $_typeLabel', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
          ),
          if (generating) ...[
            const SizedBox(height: 12),
            _sectionCard(child: Row(children: [const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GG is creating your $_typeLabel', style: const TextStyle(fontWeight: FontWeight.w800)), const Text('Keep the app open while the provider finishes.', style: TextStyle(fontSize: 12))]))])),
          ],
          if (taskId != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('Task ID: $taskId', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer), const SizedBox(width: 10), Expanded(child: Text(error!, style: TextStyle(color: scheme.onErrorContainer)))])),
          ],
          if (outputUrl != null) ...[const SizedBox(height: 16), _buildOutput(context)],
        ],
      ),
    );
  }
}
