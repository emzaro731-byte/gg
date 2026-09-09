import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'whatsapp_status_stories_page.dart';

class WhatsAppStatusPage extends StatefulWidget {
  const WhatsAppStatusPage({super.key});
  @override
  State<WhatsAppStatusPage> createState() => _WhatsAppStatusPageState();
}

class _WhatsAppStatusPageState extends State<WhatsAppStatusPage> {
  final supabase = Supabase.instance.client;
  final picker = ImagePicker();
  bool posting = false;
  String privacy = 'everyone';

  Stream<List<Map<String, dynamic>>> get _statuses => supabase
      .from('statuses')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  Future<String> _privacy() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Who can see your status?', style: TextStyle(fontWeight: FontWeight.w900))),
          RadioListTile<String>(value: 'everyone', groupValue: privacy, onChanged: (v) => Navigator.pop(c, v), title: const Text('Everyone'), subtitle: const Text('All authenticated GG users')),
          RadioListTile<String>(value: 'nobody', groupValue: privacy, onChanged: (v) => Navigator.pop(c, v), title: const Text('Only me'), subtitle: const Text('Useful for drafts or private posts')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (value != null) setState(() => privacy = value);
    return value ?? privacy;
  }

  Future<void> _postText() async {
    final controller = TextEditingController();
    Color background = const Color(0xFF172554);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Text status'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              height: 170,
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(22)),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(20),
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                maxLength: 500,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(hintText: 'Type a status...', hintStyle: TextStyle(color: Colors.white60), border: InputBorder.none),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final color in [
                const Color(0xFF172554), const Color(0xFF14532D), const Color(0xFF581C87), const Color(0xFF7C2D12), const Color(0xFF0F172A),
              ]) GestureDetector(onTap: () => setDialogState(() => background = color), child: CircleAvatar(backgroundColor: color, radius: 16)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Post')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    await _privacy();
    await _runPost(() async {
      await supabase.from('statuses').insert({'user_id': supabase.auth.currentUser!.id, 'media_type': 'text', 'caption': result, 'visibility': privacy});
    });
  }

  Future<void> _pickGallery() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.media, allowMultiple: false, withData: true);
    final file = result?.files.single;
    if (file?.bytes == null) return;
    await _handleMedia(file!.bytes!, file.extension ?? 'jpg');
  }

  Future<void> _pickCamera({required bool video}) async {
    try {
      final XFile? file = video
          ? await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 60))
          : await picker.pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 2160, maxHeight: 2160);
      if (file == null) return;
      await _handleMedia(await file.readAsBytes(), file.name.split('.').last);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Camera could not be opened. Check camera permission.')));
    }
  }

  Future<void> _handleMedia(Uint8List bytes, String extension) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final isVideo = ['mp4', 'mov', 'm4v', 'webm', '3gp'].contains(ext);
    final type = isVideo ? 'video' : 'image';
    if (isVideo) {
      final caption = await _captionDialog();
      if (caption == null) return;
      await _privacy();
      await _uploadStatus(bytes, ext, type, caption: caption);
      return;
    }
    final edited = await Navigator.push<EditedStatus>(context, MaterialPageRoute(builder: (_) => StatusMediaEditor(bytes: bytes)));
    if (edited == null) return;
    await _privacy();
    await _uploadStatus(edited.bytes, 'png', 'image', caption: edited.caption);
  }

  Future<String?> _captionDialog() async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Video caption'),
        content: TextField(controller: c, maxLines: 3, maxLength: 300, autofocus: true, decoration: const InputDecoration(hintText: 'Add a caption…')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Post'))],
      ),
    );
    c.dispose();
    return result;
  }

  Future<void> _uploadStatus(Uint8List bytes, String extension, String type, {String caption = ''}) async {
    final userId = supabase.auth.currentUser!.id;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.$extension';
    await _runPost(() async {
      await supabase.storage.from('status-media').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: _contentType(extension, type == 'video'), upsert: false));
      await supabase.from('statuses').insert({'user_id': userId, 'media_path': path, 'media_type': type, 'caption': caption.isEmpty ? null : caption, 'visibility': privacy});
    });
  }

  String _contentType(String extension, bool video) {
    const map = {'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp', 'mp4': 'video/mp4', 'mov': 'video/quicktime', 'm4v': 'video/x-m4v', 'webm': 'video/webm', '3gp': 'video/3gpp'};
    return map[extension] ?? (video ? 'video/*' : 'image/*');
  }

  Future<void> _runPost(Future<void> Function() action) async {
    if (posting) return;
    setState(() => posting = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status posted')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post status. Check your connection and try again.')));
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  Future<String?> _url(String path) async {
    try { return await supabase.storage.from('status-media').createSignedUrl(path, 3600); } catch (_) { return null; }
  }

  void _openStories(List<Map<String, dynamic>> statuses, int index) {
    if (statuses.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => WhatsAppStatusStoriesPage(statuses: statuses.skip(index).toList()..addAll(statuses.take(index)))));
  }

  @override
  Widget build(BuildContext context) {
    final me = supabase.auth.currentUser?.id;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _statuses,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Unable to load updates right now.'));
        final now = DateTime.now();
        final all = (snapshot.data ?? []).where((s) {
          final expiry = DateTime.tryParse(s['expires_at']?.toString() ?? '');
          final visible = s['visibility']?.toString() != 'nobody' || s['user_id'] == me;
          return visible && (expiry == null || expiry.isAfter(now));
        }).toList();
        final mine = all.where((s) => s['user_id'] == me).toList();
        final recent = all.where((s) => s['user_id'] != me).toList();
        return CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
          SliverToBoxAdapter(child: _header(context, mine, all)),
          if (posting) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 10), child: Text('Recent updates', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)))),
          if (recent.isEmpty) const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No recent updates yet.')))
          else SliverPadding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 120), sliver: SliverList.builder(
            itemCount: recent.length,
            itemBuilder: (_, index) => _StatusCard(status: recent[index], signedUrl: _url, onTap: () => _openStories(recent, index)),
          )),
        ]);
      },
    );
  }

  Widget _header(BuildContext context, List<Map<String, dynamic>> mine, List<Map<String, dynamic>> all) {
    return Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      GestureDetector(onTap: mine.isEmpty ? null : () => _openStories(mine, 0), child: _Avatar(label: 'You', active: mine.isNotEmpty, radius: 31)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('My status', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        Text(mine.isEmpty ? 'Share a photo, video or text' : '${mine.length} active update${mine.length == 1 ? '' : 's'}'),
      ])),
      PopupMenuButton<String>(
        tooltip: 'Create status',
        onSelected: (value) { if (value == 'text') _postText(); if (value == 'gallery') _pickGallery(); if (value == 'camera') _pickCamera(video: false); if (value == 'video') _pickCamera(video: true); },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.text_fields), title: Text('Text status'))),
          PopupMenuItem(value: 'camera', child: ListTile(leading: Icon(Icons.camera_alt_outlined), title: Text('Take photo'))),
          PopupMenuItem(value: 'video', child: ListTile(leading: Icon(Icons.videocam_outlined), title: Text('Record video'))),
          PopupMenuItem(value: 'gallery', child: ListTile(leading: Icon(Icons.photo_library_outlined), title: Text('Gallery'))),
        ],
        child: const Icon(Icons.add_circle_outline_rounded, size: 30),
      ),
      IconButton(tooltip: 'Status privacy', onPressed: _privacy, icon: const Icon(Icons.visibility_outlined)),
    ]))));
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.label, required this.active, required this.radius});
  final String label; final bool active; final double radius;
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: active ? scheme.primary : scheme.outlineVariant, width: 2.5)), child: CircleAvatar(radius: radius, backgroundColor: scheme.primaryContainer, child: Text(label.substring(0, 1).toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer))));
  }
}

class _StatusCard extends StatefulWidget {
  const _StatusCard({required this.status, required this.signedUrl, required this.onTap});
  final Map<String, dynamic> status; final Future<String?> Function(String) signedUrl; final VoidCallback onTap;
  @override State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  Map<String, dynamic>? profile;
  @override void initState() { super.initState(); _loadProfile(); }
  Future<void> _loadProfile() async {
    try {
      final row = await Supabase.instance.client.from('profiles').select('display_name, username, avatar_url').eq('id', widget.status['user_id']).maybeSingle();
      if (mounted && row != null) setState(() => profile = Map<String, dynamic>.from(row));
    } catch (_) {}
  }
  @override Widget build(BuildContext context) {
    final type = widget.status['media_type']?.toString() ?? 'text';
    final name = profile?['display_name']?.toString() ?? 'GG User';
    final caption = widget.status['caption']?.toString() ?? '';
    final avatar = profile?['avatar_url']?.toString();
    return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      leading: CircleAvatar(radius: 28, backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null, child: avatar == null || avatar.isEmpty ? Text(name.substring(0, 1).toUpperCase()) : null),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Row(children: [Icon(type == 'text' ? Icons.text_fields : type == 'video' ? Icons.videocam_outlined : Icons.image_outlined, size: 16), const SizedBox(width: 5), Expanded(child: Text(type == 'text' ? caption : '${type[0].toUpperCase()}${type.substring(1)} update', maxLines: 1, overflow: TextOverflow.ellipsis))]),
      onTap: widget.onTap,
    ));
  }
}

class EditedStatus {
  const EditedStatus(this.bytes, this.caption);
  final Uint8List bytes; final String caption;
}

class StatusMediaEditor extends StatefulWidget {
  const StatusMediaEditor({super.key, required this.bytes});
  final Uint8List bytes;
  @override State<StatusMediaEditor> createState() => _StatusMediaEditorState();
}

class _StatusMediaEditorState extends State<StatusMediaEditor> {
  final boundaryKey = GlobalKey();
  final caption = TextEditingController();
  final List<Offset> drawing = [];
  final List<_EditorText> texts = [];
  final List<String> stickers = [];
  Color drawColor = Colors.white;
  double drawWidth = 5;
  Uint8List? imageBytes;

  @override void initState() { super.initState(); imageBytes = widget.bytes; }

  Future<void> _crop(String mode) async {
    final decoded = img.decodeImage(imageBytes!);
    if (decoded == null) return;
    final w = decoded.width.toDouble(); final h = decoded.height.toDouble();
    double targetW = w, targetH = h;
    if (mode == 'square') { final s = min(w, h); targetW = s; targetH = s; }
    if (mode == '4:5') { targetW = min(w, h * .8); targetH = targetW / .8; if (targetH > h) { targetH = h; targetW = h * .8; } }
    if (mode == '16:9') { targetW = min(w, h * 16 / 9); targetH = targetW * 9 / 16; if (targetH > h) { targetH = h; targetW = h * 16 / 9; } }
    final x = ((w - targetW) / 2).round(); final y = ((h - targetH) / 2).round();
    final cropped = img.copyCrop(decoded, x: x, y: y, width: targetW.round(), height: targetH.round());
    setState(() => imageBytes = Uint8List.fromList(img.encodePng(cropped)));
  }

  void _addText() {
    final c = TextEditingController();
    showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Add text'), content: TextField(controller: c, autofocus: true, maxLength: 120, decoration: const InputDecoration(hintText: 'Write something…')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add'))])).then((value) { c.dispose(); if (value != null && value.isNotEmpty) setState(() => texts.add(_EditorText(value, const Offset(.5, .5), Colors.white))); });
  }

  void _addSticker() async {
    final emoji = await showModalBottomSheet<String>(context: context, builder: (c) => SafeArea(child: Wrap(alignment: WrapAlignment.center, children: [for (final e in ['❤️','😂','🔥','😍','👏','😎','🎉','✨','👍','😮','🥳','💯']) Padding(padding: const EdgeInsets.all(8), child: InkWell(onTap: () => Navigator.pop(c, e), child: Text(e, style: const TextStyle(fontSize: 36))))])));
    if (emoji != null) setState(() => stickers.add(emoji));
  }

  Future<void> _export() async {
    final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return;
    if (mounted) Navigator.pop(context, EditedStatus(data.buffer.asUint8List(), caption.text.trim()));
  }

  @override void dispose() { caption.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Edit status'), actions: [IconButton(onPressed: _export, icon: const Icon(Icons.check_rounded))]), body: SafeArea(child: Column(children: [
      Expanded(child: Center(child: RepaintBoundary(key: boundaryKey, child: AspectRatio(aspectRatio: 9 / 16, child: LayoutBuilder(builder: (context, box) => GestureDetector(
        onPanStart: (d) { final p = Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight); setState(() => drawing.add(p)); },
        onPanUpdate: (d) { final p = Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight); setState(() => drawing.add(p)); },
        child: Stack(fit: StackFit.expand, children: [
          Image.memory(imageBytes!, fit: BoxFit.cover),
          CustomPaint(painter: _DrawingPainter(drawing, drawColor, drawWidth)),
          for (final t in texts) Positioned(left: t.position.dx * box.maxWidth - 60, top: t.position.dy * box.maxHeight - 20, child: GestureDetector(onPanUpdate: (d) => setState(() => t.position = Offset((t.position.dx + d.delta.dx / box.maxWidth).clamp(.05, .95), (t.position.dy + d.delta.dy / box.maxHeight).clamp(.05, .95))), child: Text(t.text, style: TextStyle(color: t.color, fontSize: 30, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 6, color: Colors.black)])))),
          for (var i = 0; i < stickers.length; i++) Positioned(left: 20.0 + i * 46, top: 50, child: Text(stickers[i], style: const TextStyle(fontSize: 38))),
        ]),
      ))))),
      Container(color: Colors.black, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Column(children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [IconButton(tooltip: 'Crop square', onPressed: () => _crop('square'), icon: const Icon(Icons.crop_square, color: Colors.white)), IconButton(tooltip: 'Crop 4:5', onPressed: () => _crop('4:5'), icon: const Icon(Icons.crop_portrait, color: Colors.white)), IconButton(tooltip: 'Crop 16:9', onPressed: () => _crop('16:9'), icon: const Icon(Icons.crop_landscape, color: Colors.white)), IconButton(tooltip: 'Text', onPressed: _addText, icon: const Icon(Icons.text_fields, color: Colors.white)), IconButton(tooltip: 'Sticker', onPressed: _addSticker, icon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white)), PopupMenuButton<Color>(onSelected: (c) => setState(() => drawColor = c), icon: const Icon(Icons.palette_outlined, color: Colors.white), itemBuilder: (_) => const [PopupMenuItem(value: Colors.white, child: Text('White')), PopupMenuItem(value: Colors.red, child: Text('Red')), PopupMenuItem(value: Colors.yellow, child: Text('Yellow')), PopupMenuItem(value: Colors.cyan, child: Text('Cyan'))]), IconButton(tooltip: 'Clear drawing', onPressed: () => setState(() => drawing.clear()), icon: const Icon(Icons.undo_rounded, color: Colors.white))])),
        TextField(controller: caption, maxLength: 300, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Add a caption…', hintStyle: TextStyle(color: Colors.white54), prefixIcon: Icon(Icons.subtitles_outlined, color: Colors.white54), filled: true, fillColor: Colors.white10, border: OutlineInputBorder(borderSide: BorderSide.none))),
      ]),
    ])));
  }
}

class _EditorText {
  _EditorText(this.text, this.position, this.color);
  final String text; Offset position; final Color color;
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter(this.points, this.color, this.width);
  final List<Offset> points; final Color color; final double width;
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    if (points.length < 2) return;
    for (var i = 1; i < points.length; i++) canvas.drawLine(Offset(points[i - 1].dx * size.width, points[i - 1].dy * size.height), Offset(points[i].dx * size.width, points[i].dy * size.height), p);
  }
  @override bool shouldRepaint(covariant _DrawingPainter old) => true;
}

class StatusPage extends StatelessWidget {
  const StatusPage({super.key});
  @override Widget build(BuildContext context) => const WhatsAppStatusPage();
}
