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
  String? error;

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
          .select('display_name, username, bio')
          .eq('id', userId)
          .maybeSingle();
      if (row != null) {
        displayName.text = row['display_name']?.toString() ?? '';
        username.text = row['username']?.toString() ?? '';
        bio.text = row['bio']?.toString() ?? '';
      }
    } on PostgrestException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Could not load your profile.';
    } finally {
      if (mounted) setState(() => loading = false);
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
                    child: CircleAvatar(
                      radius: 46,
                      child: Text(
                        (displayName.text.isEmpty ? 'G' : displayName.text[0]).toUpperCase(),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
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
