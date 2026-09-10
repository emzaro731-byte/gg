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
      modelController.text = _presets[value]!.first['id']!;
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
        taskId = returnedTask;
        await _pollTask(returnedTask);
      } else {
        outputUrl = url;
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
        final nestedUrl = nested is Map ? (nested['resultUrls'] is List && nested['resultUrls'].isNotEmpty ? nested['resultUrls'].first.toString() : null) : null;
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
      setState(() => audioPlaying = false);
      return;
    }
    await audioPlayer.play(UrlSource(url));
    setState(() => audioPlaying = true);
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
      final safeTitle = titleController.text.trim().isEmpty ? 'gg-${type}' : titleController.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
      final fileName = '$safeTitle-${DateTime.now().millisecondsSinceEpoch}.${_extension()}';
      final saved = await FileSaver.instance.downloadLink(
        link: LinkDetails(link: downloadUrl),
        name: fileName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to your phone: $fileName')));
        if (saved.isEmpty) {
          setState(() => error = 'The download was handed to Android, but the saved path was not returned. Check Downloads.');
        }
      }
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] != null ? details['error'].toString() : details?.toString() ?? e.reasonPhrase ?? 'Download failed.';
      if (mounted) setState(() => error = message);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presets = _presets[type == 'image' ? 'Image' : type == 'video' ? 'Video' : 'Music']!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GG Create', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: generating ? null : () => setState(() { promptController.clear(); outputUrl = null; error = null; }), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]), borderRadius: BorderRadius.circular(28)),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome_rounded, size: 36),
              SizedBox(height: 8),
              Text('Create anything', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text('Images, videos and music through your Supabase AI APIs.'),
            ]),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(segments: const [
            ButtonSegment(value: 'image', label: Text('Image'), icon: Icon(Icons.image_rounded)),
            ButtonSegment(value: 'video', label: Text('Video'), icon: Icon(Icons.movie_creation_rounded)),
            ButtonSegment(value: 'music', label: Text('Music'), icon: Icon(Icons.music_note_rounded)),
          ], selected: {type}, onSelectionChanged: generating ? null : (s) => _setType(s.first)),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: provider,
            decoration: const InputDecoration(labelText: 'AI provider'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto — use APIs configured in Supabase')),
              DropdownMenuItem(value: 'kie', child: Text('KIE — all supported KIE models')),
              DropdownMenuItem(value: 'existing-api', child: Text('Existing GG AI API')),
            ],
            onChanged: generating ? null : (v) => setState(() => provider = v ?? 'auto'),
          ),
          const SizedBox(height: 8),
          const Text('GG checks the secure Supabase Edge Function configuration. API keys never go into the APK.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: presets.any((p) => p['id'] == modelController.text) ? modelController.text : null,
            decoration: const InputDecoration(labelText: 'KIE model presets'),
            hint: const Text('Choose a model or enter any current KIE model ID below'),
            items: presets.map((p) => DropdownMenuItem(value: p['id'], child: Text(p['name']!))).toList(),
            onChanged: generating ? null : (v) { if (v != null) _selectPreset(v); },
          ),
          const SizedBox(height: 10),
          TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model ID', hintText: 'Any current KIE model ID')),
          const SizedBox(height: 12),
          TextField(
            controller: promptController,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(labelText: type == 'music' ? 'Song prompt / lyrics' : 'Prompt', hintText: type == 'video' ? 'A cinematic futuristic Lagos night drive…' : type == 'music' ? 'High-energy Nigerian Afrobeats, infectious drums, rich vocals…' : 'A futuristic Nigerian city at night…', alignLabelWithHint: true),
          ),
          if (type == 'music') ...[
            const SizedBox(height: 12),
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Song title')),
            const SizedBox(height: 12),
            TextField(controller: styleController, maxLines: 3, decoration: const InputDecoration(labelText: 'Style / genre', hintText: 'Afrobeats, Afro-fusion, cinematic…')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Instrumental'), value: instrumental, onChanged: generating ? null : (v) => setState(() => instrumental = v)),
          ],
          if (type == 'video') ...[
            const SizedBox(height: 12),
            TextField(controller: imageUrlController, decoration: const InputDecoration(labelText: 'Reference image URL (optional)')),
          ],
          if (type != 'music') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: aspectRatio, decoration: const InputDecoration(labelText: 'Aspect ratio'), items: const [DropdownMenuItem(value: '1:1', child: Text('1:1')), DropdownMenuItem(value: '16:9', child: Text('16:9')), DropdownMenuItem(value: '9:16', child: Text('9:16'))], onChanged: generating ? null : (v) => setState(() => aspectRatio = v ?? aspectRatio)),
          ],
          const SizedBox(height: 12),
          ExpansionTile(title: const Text('Advanced KIE input'), subtitle: const Text('Optional JSON for model-specific parameters'), children: [Padding(padding: const EdgeInsets.fromLTRB(0, 0, 0, 12), child: TextField(controller: advancedController, minLines: 3, maxLines: 10, decoration: const InputDecoration(hintText: '{"duration": 5, "quality": "1080p"}')))]),
          const SizedBox(height: 12),
          SizedBox(height: 54, child: FilledButton.icon(onPressed: generating ? null : _generate, icon: generating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(type == 'image' ? Icons.image_rounded : type == 'video' ? Icons.movie_rounded : Icons.music_note_rounded), label: Text(generating ? 'Generating…' : 'Generate ${type[0].toUpperCase()}${type.substring(1)}'))),
          if (generating) ...[const SizedBox(height: 12), const Center(child: Text('AI is processing your creation. Please keep GG open.'))],
          if (taskId != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText('Task: $taskId', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
          if (error != null) ...[const SizedBox(height: 14), Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)), child: Text(error!, style: TextStyle(color: scheme.onErrorContainer)))],
          if (outputUrl != null) ...[
            const SizedBox(height: 18),
            if (type == 'image') ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.network(outputUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(20), child: Text('Generated image URL could not be displayed.')))),
            if (type == 'video' && videoController?.value.isInitialized == true) ClipRRect(borderRadius: BorderRadius.circular(24), child: AspectRatio(aspectRatio: videoController!.value.aspectRatio, child: Stack(alignment: Alignment.center, children: [VideoPlayer(videoController!), IconButton.filled(onPressed: () => setState(() { videoController!.value.isPlaying ? videoController!.pause() : videoController!.play(); }), icon: Icon(videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow, size: 34))]))),
            if (type == 'music') SizedBox(height: 70, child: FilledButton.icon(onPressed: _playAudio, icon: Icon(audioPlaying ? Icons.pause : Icons.play_arrow), label: Text(audioPlaying ? 'Pause music' : 'Play music'))),
            const SizedBox(height: 12),
            SizedBox(height: 52, child: OutlinedButton.icon(onPressed: downloading ? null : _downloadOutput, icon: downloading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), label: Text(downloading ? 'Downloading…' : 'Download to phone'))),
            const SizedBox(height: 10),
            SelectableText(outputUrl!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
