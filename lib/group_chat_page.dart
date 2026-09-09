import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_page.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final title = TextEditingController();
  final search = TextEditingController();
  final supabase = Supabase.instance.client;
  final selected = <String>{};
  List<Map<String, dynamic>> users = [];
  bool loading = false;

  String get me => supabase.auth.currentUser!.id;

  Future<void> findUsers(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      if (mounted) setState(() => users = []);
      return;
    }
    try {
      final rows = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .neq('id', me)
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(30);
      if (mounted) setState(() => users = List<Map<String, dynamic>>.from(rows));
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> createGroup() async {
    final name = title.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a group name.')));
      return;
    }
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one member.')));
      return;
    }
    setState(() => loading = true);
    try {
      final result = await supabase.rpc('create_group_conversation', params: {
        'group_title': name,
        'member_ids': selected.toList(),
      });
      final id = result.toString();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ChatPage(conversationId: id, title: name)),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    title.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('New group'),
          actions: [
            IconButton(
              tooltip: 'Create group',
              onPressed: loading ? null : createGroup,
              icon: const Icon(Icons.check_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: title,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Group name',
                  prefixIcon: Icon(Icons.groups_rounded),
                ),
              ),
            ),
            if (selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${selected.length} member${selected.length == 1 ? '' : 's'} selected'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextField(
                controller: search,
                onChanged: findUsers,
                decoration: InputDecoration(
                  hintText: 'Search people to add',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(onPressed: () { search.clear(); setState(() => users = []); }, icon: const Icon(Icons.clear)),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final user = users[index];
                  final id = user['id'].toString();
                  final name = user['display_name']?.toString() ?? 'GG User';
                  final username = user['username']?.toString() ?? '';
                  final checked = selected.contains(id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (_) => setState(() => checked ? selected.remove(id) : selected.add(id)),
                    secondary: CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                    title: Text(name),
                    subtitle: Text(username.isEmpty ? 'GG Messenger user' : '@$username'),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : createGroup,
                    icon: loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.groups_rounded),
                    label: Text(loading ? 'Creating…' : 'Create group'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
