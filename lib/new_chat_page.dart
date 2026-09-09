import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'power_chat_page.dart';
import 'group_chat_page.dart';
import 'group_manage_page.dart';

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key, this.initialUserId});

  final String? initialUserId;

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final search = TextEditingController();
  bool loading = false;
  List<Map<String, dynamic>> users = [];

  SupabaseClient get supabase => Supabase.instance.client;
  String get me => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    final id = widget.initialUserId;
    if (id != null && id.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openInitialUser(id));
    }
  }

  Future<void> openInitialUser(String id) async {
    setState(() => loading = true);
    try {
      final row = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .eq('id', id)
          .maybeSingle();
      if (row != null && mounted) {
        await startChat(Map<String, dynamic>.from(row));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> findUsers(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      setState(() => users = []);
      return;
    }
    try {
      final rows = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url')
          .neq('id', me)
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(20);
      if (mounted) {
        setState(() => users = List<Map<String, dynamic>>.from(rows));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> startChat(Map<String, dynamic> profile) async {
    setState(() => loading = true);
    try {
      final result = await supabase.rpc(
        'create_direct_conversation',
        params: {'target_user_id': profile['id']},
      );
      final id = result.toString();
      final name = profile['display_name']?.toString() ?? 'Chat';
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PowerChatPage(conversationId: id, title: name),
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> openGroups() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GroupListPage()),
    );
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New chat'),
        actions: [
          IconButton(
            tooltip: 'My groups',
            onPressed: openGroups,
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GroupChatPage()),
            ),
            icon: const Icon(Icons.groups_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: search,
              autofocus: true,
              onChanged: findUsers,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search people',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
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
                      final name =
                          user['display_name']?.toString() ?? 'GG User';
                      final initial = name.isEmpty
                          ? '?'
                          : name.substring(0, 1).toUpperCase();
                      final username = user['username']?.toString() ?? '';
                      return ListTile(
                        leading: CircleAvatar(child: Text(initial)),
                        title: Text(name),
                        subtitle: Text(
                          username.isNotEmpty
                              ? '@$username'
                              : 'GG Messenger user',
                        ),
                        onTap: () => startChat(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class GroupListPage extends StatefulWidget {
  const GroupListPage({super.key});

  @override
  State<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends State<GroupListPage> {
  final supabase = Supabase.instance.client;

  Stream<List<Map<String, dynamic>>> groups() => supabase
      .from('conversations')
      .stream(primaryKey: ['id'])
      .eq('is_group', true)
      .order('updated_at', ascending: false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My groups')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: groups(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load groups: ${snapshot.error}'),
            );
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const Center(
              child: Text('No groups yet. Create one from New chat.'),
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final row = rows[i];
              final id = row['id'].toString();
              final title = row['title']?.toString() ?? 'Group';
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    title.isEmpty ? '?' : title[0].toUpperCase(),
                  ),
                ),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Open group management'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupManagePage(
                      conversationId: id,
                      title: title,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
