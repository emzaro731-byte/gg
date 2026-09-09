import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final search = TextEditingController();
  bool loading = false;
  List<Map<String, dynamic>> users = [];

  SupabaseClient get supabase => Supabase.instance.client;
  String get me => supabase.auth.currentUser!.id;

  Future<void> findUsers(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      setState(() => users = []);
      return;
    }
    try {
      final rows = await supabase.from('profiles').select('id, username, display_name, avatar_url').neq('id', me).or('username.ilike.%$q%,display_name.ilike.%$q%').limit(20);
      if (mounted) setState(() => users = List<Map<String, dynamic>>.from(rows));
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> startChat(Map<String, dynamic> profile) async {
    setState(() => loading = true);
    try {
      final existing = await supabase.from('conversation_members').select('conversation_id').eq('user_id', me);
      final ids = List<Map<String, dynamic>>.from(existing).map((e) => e['conversation_id'].toString()).toList();
      if (ids.isNotEmpty) {
        final shared = await supabase.from('conversation_members').select('conversation_id').eq('user_id', profile['id']).inFilter('conversation_id', ids);
        if (shared.isNotEmpty) {
          final id = shared.first['conversation_id'].toString();
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: id, title: profile['display_name'] ?? 'Chat')));
          return;
        }
      }

      final conversation = await supabase.from('conversations').insert({
        'title': profile['display_name'] ?? 'Chat',
        'is_group': false,
        'created_by': me,
      }).select('id').single();
      final id = conversation['id'].toString();
      await supabase.from('conversation_members').insert([
        {'conversation_id': id, 'user_id': me, 'role': 'member'},
        {'conversation_id': id, 'user_id': profile['id'], 'role': 'member'},
      ]);
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: id, title: profile['display_name'] ?? 'Chat')));
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('New chat')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: search,
                autofocus: true,
                onChanged: findUsers,
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search people', border: OutlineInputBorder(borderRadius: BorderRadius.circular(18))),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final name = user['display_name']?.toString() ?? 'GG User';
                        return ListTile(
                          leading: CircleAvatar(child: Text(name.substring(0, 1).toUpperCase())),
                          title: Text(name),
                          subtitle: Text(user['username']?.toString().isNotEmpty == true ? '@${user['username']}' : 'GG Messenger user'),
                          onTap: () => startChat(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
}
