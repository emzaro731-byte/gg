import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_page.dart';
import 'new_chat_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late final TextEditingController controller;
  late final TabController tabs;
  List<Map<String, dynamic>> people = [];
  List<Map<String, dynamic>> chats = [];
  List<Map<String, dynamic>> messages = [];
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialQuery);
    tabs = TabController(length: 3, vsync: this);
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => search());
    }
  }

  Future<void> search() async {
    final raw = controller.text.trim();
    final q = raw.startsWith('@') ? raw.substring(1).trim().toLowerCase() : raw.toLowerCase();
    if (q.length < 2) {
      setState(() {
        people = [];
        chats = [];
        messages = [];
        error = q.isEmpty ? null : 'Type at least 2 characters.';
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;

      final peopleRows = await supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url, bio, last_seen')
          .neq('id', me)
          .or('username.ilike.%$q%,display_name.ilike.%$q%')
          .limit(30);
      final chatRows = await supabase
          .from('conversations')
          .select('id, title, is_group, last_message, updated_at')
          .or('title.ilike.%$q%,last_message.ilike.%$q%')
          .order('updated_at', ascending: false)
          .limit(30);
      final messageRows = await supabase
          .from('messages')
          .select('id, conversation_id, sender_id, body, message_type, created_at')
          .ilike('body', '%$q%')
          .order('created_at', ascending: false)
          .limit(40);

      if (!mounted) return;
      setState(() {
        people = List<Map<String, dynamic>>.from(peopleRows);
        chats = List<Map<String, dynamic>>.from(chatRows);
        messages = List<Map<String, dynamic>>.from(messageRows);
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) setState(() => error = 'Search failed. Please try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: controller,
          autofocus: widget.initialQuery.isEmpty,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search friends by @username',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => search(),
        ),
        actions: [
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () {
                controller.clear();
                setState(() {
                  people = [];
                  chats = [];
                  messages = [];
                  error = null;
                });
              },
              icon: const Icon(Icons.clear),
            ),
          IconButton(
            tooltip: 'Search',
            onPressed: loading ? null : search,
            icon: const Icon(Icons.search),
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          tabs: [
            Tab(text: 'People (${people.length})'),
            Tab(text: 'Chats (${chats.length})'),
            Tab(text: 'Messages (${messages.length})'),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(error!, textAlign: TextAlign.center),
                  ),
                )
              : TabBarView(
                  controller: tabs,
                  children: [_people(), _chats(), _messages()],
                ),
    );
  }

  Widget _people() {
    if (people.isEmpty) return _empty('No friends found', Icons.person_search_rounded);
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: people.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (_, index) {
        final person = people[index];
        final name = (person['display_name'] ?? person['username'] ?? 'GG User').toString();
        final username = person['username']?.toString();
        return ListTile(
          leading: _avatar(person['avatar_url']?.toString(), name),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(username == null || username.isEmpty ? 'GG Messenger user' : '@$username'),
          trailing: const Icon(Icons.chat_bubble_outline),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NewChatPage(initialUserId: person['id'].toString()),
            ),
          ),
        );
      },
    );
  }

  Widget _chats() {
    if (chats.isEmpty) return _empty('No chats found', Icons.forum_outlined);
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: chats.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
      itemBuilder: (_, index) {
        final chat = chats[index];
        final title = (chat['title'] ?? 'Conversation').toString();
        return ListTile(
          leading: CircleAvatar(child: Text(title.isEmpty ? '?' : title[0].toUpperCase())),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            (chat['last_message'] ?? 'No messages yet').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatPage(
                conversationId: chat['id'].toString(),
                title: title,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _messages() {
    if (messages.isEmpty) return _empty('No messages found', Icons.manage_search_rounded);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, index) {
        final message = messages[index];
        final conversationId = message['conversation_id']?.toString() ?? '';
        final shortConversationId = conversationId.length > 8 ? conversationId.substring(0, 8) : conversationId;
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.message_outlined)),
            title: Text(
              (message['body'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('Conversation ${shortConversationId.isEmpty ? 'unknown' : '$shortConversationId…'}'),
            onTap: conversationId.isEmpty
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        conversationId: conversationId,
                        title: 'Conversation',
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _empty(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text),
        ],
      ),
    );
  }

  Widget _avatar(String? url, String name) {
    return url != null && url.isNotEmpty
        ? CircleAvatar(backgroundImage: NetworkImage(url))
        : CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase()));
  }
}
