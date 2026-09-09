import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GgImagePage extends StatefulWidget {
  const GgImagePage({super.key});

  @override
  State<GgImagePage> createState() => _GgImagePageState();
}

class _GgImagePageState extends State<GgImagePage> {
  final promptController = TextEditingController();
  String model = 'flux-schnell';
  String aspectRatio = '1:1';
  bool generating = false;
  String? imageUrl;
  String? error;
  int? creditsCharged;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final prompt = promptController.text.trim();
    if (prompt.isEmpty || generating) return;

    setState(() {
      generating = true;
      error = null;
      imageUrl = null;
      creditsCharged = null;
    });

    try {
      final response = await supabase.functions.invoke(
        'gg-image-generate',
        body: {
          'prompt': prompt,
          'model': model,
          'aspect_ratio': aspectRatio,
          'resolution': '640px',
        },
      );
      final data = response.data;
      if (data is! Map) throw Exception('Invalid image service response.');
      final url = data['image_url']?.toString();
      if (url == null || url.isEmpty) throw Exception(data['error']?.toString() ?? 'No image was returned.');
      if (!mounted) return;
      setState(() {
        imageUrl = url;
        creditsCharged = int.tryParse(data['credits_charged']?.toString() ?? '');
      });
    } on FunctionException catch (e) {
      if (!mounted) return;
      setState(() => error = e.details?.toString() ?? e.reasonPhrase ?? 'Magic Hour request failed.');
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GG Image', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Clear',
            onPressed: generating ? null : () => setState(() { promptController.clear(); imageUrl = null; error = null; }),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.secondaryContainer]),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome_rounded, size: 34),
              SizedBox(height: 10),
              Text('Create with GG', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text('Describe an image and Magic Hour will generate it for you.'),
            ]),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: promptController,
            minLines: 4,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Image prompt',
              hintText: 'A futuristic Port Harcourt skyline at sunset, cinematic lighting…',
              alignLabelWithHint: true,
              prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 58), child: Icon(Icons.edit_rounded)),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: model,
              decoration: InputDecoration(labelText: 'Model', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
              items: const [
                DropdownMenuItem(value: 'flux-schnell', child: Text('FLUX Schnell')),
                DropdownMenuItem(value: 'flux-2-klein', child: Text('FLUX 2 Klein')),
                DropdownMenuItem(value: 'z-image-turbo', child: Text('Z-Image Turbo')),
              ],
              onChanged: generating ? null : (v) { if (v != null) setState(() => model = v); },
            )),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: aspectRatio,
              decoration: InputDecoration(labelText: 'Ratio', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none)),
              items: const [
                DropdownMenuItem(value: '1:1', child: Text('Square 1:1')),
                DropdownMenuItem(value: '16:9', child: Text('Landscape 16:9')),
                DropdownMenuItem(value: '9:16', child: Text('Portrait 9:16')),
              ],
              onChanged: generating ? null : (v) { if (v != null) setState(() => aspectRatio = v); },
            )),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: generating ? null : _generate,
              icon: generating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_rounded),
              label: Text(generating ? 'Creating image…' : 'Generate Image'),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)), child: Text(error!, style: TextStyle(color: scheme.onErrorContainer))),
          ],
          if (imageUrl != null) ...[
            const SizedBox(height: 18),
            ClipRRect(borderRadius: BorderRadius.circular(24), child: AspectRatio(aspectRatio: aspectRatio == '16:9' ? 16 / 9 : aspectRatio == '9:16' ? 9 / 16 : 1, child: Image.network(imageUrl!, fit: BoxFit.cover, loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator())))),
            const SizedBox(height: 8),
            Text(creditsCharged == null ? 'Generated by Magic Hour' : 'Magic Hour credits used: $creditsCharged', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
