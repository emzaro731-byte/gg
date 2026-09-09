import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final displayName = TextEditingController();
  final username = TextEditingController();
  final bio = TextEditingController();
  bool loading = true;
  bool saving = false;
  bool uploadingPhoto = false;
  String? error;
  String? avatarUrl;

  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await supabase
          .from('profiles')
          .select('display_name, username, bio, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      if (row != null) {
        displayName.text = row['display_name']?.toString() ?? '';
        username.text = row['username']?.toString() ?? '';
        bio.text = row['bio']?.toString() ?? '';
        avatarUrl = row['avatar_url']?.toString();
      }
    } on PostgrestException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load your profile.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _changePhoto() async {
    if (uploadingPhoto) return;
    setState(() {
      uploadingPhoto = true;
      error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.single.bytes == null) return;

      final file = result.files.single;
      final bytes = file.bytes!;
      if (bytes.length > 8 * 1024 * 1024) {
        throw Exception('Profile photo must be 8 MB or smaller.');
      }

      final extension = (file.extension ?? 'jpg').toLowerCase();
      final safeExtension = switch (extension) {
        'png' => 'png',
        'webp' => 'webp',
        'gif' => 'gif',
        'heic' => 'heic',
        _ => 'jpg',
      };
      final path = '$userId/avatar.$safeExtension';
      final contentType = switch (safeExtension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' => 'image/heic',
        _ => 'image/jpeg',
      };

      await supabase.storage.from('avatars').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          cacheControl: '3600',
          upsert: true,
        ),
      );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);
      final cacheBustedUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';

      await supabase.from('profiles').update({
        'avatar_url': cacheBustedUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', userId);

      if (mounted) {
        setState(() => avatarUrl = cacheBustedUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } on StorageException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    final name = displayName.text.trim();
    final handle = username.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    final about = bio.text.trim();
    if (name.length < 2) {
      setState(() => error = 'Display name must be at least 2 characters.');
      return;
    }
    if (handle.isNotEmpty && (handle.length < 3 || handle.length > 30)) {
      setState(() => error = 'Username must be 3–30 characters.');
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'display_name': name,
        'username': handle.isEmpty ? null : handle,
        'bio': about.isEmpty ? null : about,
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
        Navigator.pop(context);
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message.contains('duplicate') ? 'That username is already taken.' : e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not save your profile.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    displayName.dispose();
    username.dispose();
    bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Edit profile'),
          actions: [
            IconButton(onPressed: saving ? null : _save, icon: const Icon(Icons.check_rounded)),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty
                              ? NetworkImage(avatarUrl!)
                              : null,
                          child: avatarUrl == null || avatarUrl!.isEmpty
                              ? Text(
                                  (displayName.text.isEmpty ? 'G' : displayName.text[0]).toUpperCase(),
                                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
                                )
                              : null,
                        ),
                        Material(
                          color: Theme.of(context).colorScheme.primary,
                          shape: const CircleBorder(),
                          elevation: 4,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: uploadingPhoto ? null : _changePhoto,
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: uploadingPhoto
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Icon(Icons.camera_alt_rounded, color: Theme.of(context).colorScheme.onPrimary, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: uploadingPhoto ? null : _changePhoto,
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: Text(uploadingPhoto ? 'Uploading…' : 'Change profile photo'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: displayName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: username,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Username', prefixText: '@', prefixIcon: Icon(Icons.alternate_email)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: bio,
                    maxLength: 160,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Bio', hintText: 'Tell people a little about you…', prefixIcon: Icon(Icons.info_outline)),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                    label: Text(saving ? 'Saving…' : 'Save profile'),
                  ),
                ],
              ),
      );
}
