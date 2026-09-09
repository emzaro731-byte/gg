import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'chat_page.dart';
import 'gg_ai_page.dart';
import 'new_chat_page.dart';

class PremiumChatsPage extends StatefulWidget {
  const PremiumChatsPage({super.key, this.onlineUsers = const <String>{}});
  final Set<String> onlineUsers;

  @override
  State<PremiumChatsPage> createState() => _PremiumChatsPageState();
}

class _PremiumChatsPageState extends State<PremiumChatsPage> {
  final searchController = TextEditingController();
  String filter = 'All';
  bool showArchived = false;
  bool searchingUsers = false;
  List<Map<String, dynamic>> usernameResults = [];
  Timer? _searchDebounce;

  SupabaseClient get supabase => Supabase.instance.client;
  String get userId => supabase.auth.currentUser!.id;

  Stream<List<Map<String, dynamic>>> get _settingsStream => supabase
      .from('conversation_user_settings')
      .stream(primaryKey: ['conversation_id', 'user_id'])
      .eq('user_id', userId);

  @override
  void dispose() {
    _searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    final q = value.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    if (q.length < 2) {
      setState(() => usernameResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _searchUsers(q));
  }

  Future<void> _searchUsers(String query) async {
    if (!mounted) return;
    setState(() => searchingUsers = true);
    try {
      final rows = await supabase.rpc('search_users_by_username', params: {
        'search_username': query,
        'result_limit': 20,
      });
      if (!mounted) return;
      setState(() => usernameResults = List<Map<String, dynamic>>.from(rows as List));
    } on PostgrestException catch (_) {
      try {
        final rows = await supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url, bio, last_seen')
            .neq('id', userId)
            .ilike('username', '%$query%')
            .limit(20);
        if (mounted) setState(() => usernameResults = List<Map<String, dynamic>>.from(rows));
      } catch (_) {
        if (mounted) setState(() => usernameResults = []);
      }
    } catch (_) {
      if (mounted) setState(() => usernameResults = []);
    } finally {
      if (mounted) setState(() => searchingUsers = false);
    }
  }

  Future<void> _state(String id, {bool? pin, bool? archive, DateTime? muteUntil, bool clearMute = false}) async {
    try {
      await supabase.rpc('set_conversation_list_state', params: {
        'target_conversation_id': id,
        'pin_state': pin,
        'archive_state': archive,
        'mute_until_value': muteUntil?.toUtc().toIso8601String(),
        'clear_mute': clearMute,
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update chat: $e')));
    }
  }

  Future<void> _openUser(Map<String, dynamic> user) async {
    final id = user['id']?.toString();
    if (id == null || id.isEmpty) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NewChatPage(initialUserId: id)));
    if (mounted) {
      searchController.clear();
      setState(() => usernameResults = []);
    }
  }

  Future<void> _menu(Map<String, dynamic> chat, Map<String, dynamic>? setting) async {
    final id = chat['id'].toString();
    final pinned = setting?['pinned_at'] != null;
    final archived = setting?['archived_at'] != null;
    final muted = setting?['muted_until'] != null && DateTime.tryParse(setting!['muted_until'].toString())?.isAfter(DateTime.now().toUtc()) == true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined), title: Text(pinned ? 'Unpin chat' : 'Pin chat'), onTap: () { Navigator.pop(context); _state(id, pin: !pinned); }),
          ListTile(leading: Icon(archived ? Icons.unarchive_rounded : Icons.archive_outlined), title: Text(archived ? 'Unarchive chat' : 'Archive chat'), onTap: () { Navigator.pop(context); _state(id, archive: !archived); }),
          ListTile(leading: Icon(muted ? Icons.notifications_off_rounded : Icons.notifications_none_rounded), title: Text(muted ? 'Unmute chat' : 'Mute for 1 hour'), onTap: () { Navigator.pop(context); muted ? _state(id, clearMute: true) : _state(id, muteUntil: DateTime.now().add(const Duration(hours: 1))); }),
          ListTile(leading: const Icon(Icons.mark_chat_read_outlined), title: const Text('Mark as read'), onTap: () { Navigator.pop(context); _markRead(id); }),
        ]),
      ),
    );
  }

  Future<void> _markRead(String id) async {
    try {
      final latest = await supabase.from('messages').select('id').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
      if (latest == null) return;
      await supabase.rpc('mark_conversation_read', params: {'target_conversation_id': id, 'target_message_id': latest['id']});
    } catch (_) {}
  }

  void _openAi() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const GgAiPage()));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase.from('conversations').stream(primaryKey: ['id']).order('updated_at', ascending: false),
      builder: (context, conversationSnapshot) {
        if (conversationSnapshot.hasError) return Center(child: Text('Unable to load chats: ${conversationSnapshot.error}'));
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _settingsStream,
          builder: (context, settingsSnapshot) {
            final settings = <String, Map<String, dynamic>>{};
            for (final row in settingsSnapshot.data ?? const <Map<String, dynamic>>[]) settings[row['conversation_id'].toString()] = row;
            final query = searchController.text.trim().toLowerCase();
            final raw = conversationSnapshot.data ?? const <Map<String, dynamic>>[];
            final visible = raw.where((chat) {
              final setting = settings[chat['id'].toString()];
              final archived = setting?['archived_at'] != null;
              if (showArchived != archived) return false;
              if (filter == 'Pinned' && setting?['pinned_at'] == null) return false;
              if (query.isNotEmpty && !(chat['title']?.toString().toLowerCase().contains(query) ?? false) && !(chat['last_message']?.toString().toLowerCase().contains(query) ?? false)) return false;
              return true;
            }).toList();
            visible.sort((a, b) {
              final ap = settings[a['id'].toString()]?['pinned_at'] != null;
              final bp = settings[b['id'].toString()]?['pinned_at'] != null;
              if (ap != bp) return ap ? -1 : 1;
              return (b['updated_at']?.toString() ?? '').compareTo(a['updated_at']?.toString() ?? '');
            });

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextField(
                  controller: searchController,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                    hintText: 'Search friends by @username',
                    suffixIcon: query.isEmpty ? null : IconButton(onPressed: () { searchController.clear(); _onSearchChanged(''); }, icon: const Icon(Icons.close_rounded)),
                  ),
                ),
              ),
              if (query.length >= 2 && (searchingUsers || usernameResults.isNotEmpty)) _usernameSearchPanel(query),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: _openAi,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .18)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                          child: Icon(Icons.auto_awesome_rounded, color: Theme.of(context).colorScheme.onPrimary),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('GG AI', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Ask anything • Powered by Groq', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.primary),
                      ]),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                  _FilterChip(label: 'All', selected: filter == 'All', onTap: () => setState(() => filter = 'All')),
                  const SizedBox(width: 8),
                  _FilterChip(label: 'Pinned', selected: filter == 'Pinned', onTap: () => setState(() => filter = 'Pinned')),
                  const SizedBox(width: 8),
                  _FilterChip(label: showArchived ? 'Archived' : 'Archive', selected: showArchived, onTap: () => setState(() => showArchived = !showArchived)),
                ],),
              ),
              const SizedBox(height: 8),
              Expanded(child: visible.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(showArchived ? Icons.archive_outlined : Icons.chat_bubble_outline_rounded, size: 48), const SizedBox(height: 12), Text(showArchived ? 'No archived chats' : 'No chats found', style: const TextStyle(fontWeight: FontWeight.w700))]))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final chat = visible[index];
                        final id = chat['id'].toString();
                        final title = (chat['title'] ?? 'Conversation').toString();
                        final initial = title.isEmpty ? '?' : title.substring(0, 1).toUpperCase();
                        final participant = chat['other_user_id']?.toString();
                        final online = participant != null && widget.onlineUsers.contains(participant);
                        final setting = settings[id];
                        final pinned = setting?['pinned_at'] != null;
                        final muted = setting?['muted_until'] != null && DateTime.tryParse(setting!['muted_until'].toString())?.isAfter(DateTime.now().toUtc()) == true;
                        return Dismissible(
                          key: ValueKey(id),
                          background: _swipeBackground(Icons.archive_rounded, 'Archive', Alignment.centerLeft),
                          secondaryBackground: _swipeBackground(Icons.push_pin_rounded, 'Pin', Alignment.centerRight),
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.startToEnd) { await _state(id, archive: true); return false; }
                            await _state(id, pin: !pinned); return false;
                          },
                          child: _GlassChatTile(
                            title: title,
                            initial: initial,
                            lastMessage: (chat['last_message'] ?? 'Tap to open').toString(),
                            online: online,
                            pinned: pinned,
                            muted: muted,
                            onMenu: () => _menu(chat, setting),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversationId: id, title: title)));
                              if (mounted) setState(() {});
                            },
                          ),
                        );
                      },
                    )),
            ]);
          },
        );
      },
    );
  }

  Widget _usernameSearchPanel(String query) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .35)),
      ),
      child: searchingUsers
          ? const Padding(padding: EdgeInsets.all(18), child: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('Finding usernames…')]))
          : usernameResults.isEmpty
              ? const Padding(padding: EdgeInsets.all(18), child: Text('No user found with that username.'))
              : Column(children: [
                  const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 4), child: Align(alignment: Alignment.centerLeft, child: Text('People', style: TextStyle(fontWeight: FontWeight.w800)))),
                  ...usernameResults.take(8).map((user) {
                    final name = (user['display_name'] ?? user['username'] ?? 'GG User').toString();
                    final username = (user['username'] ?? '').toString();
                    final avatar = (user['avatar_url'] ?? '').toString();
                    return ListTile(
                      leading: avatar.isNotEmpty ? CircleAvatar(backgroundImage: NetworkImage(avatar)) : CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(username.isEmpty ? 'GG Messenger user' : '@$username'),
                      trailing: const Icon(Icons.chat_rounded),
                      onTap: () => _openUser(user),
                    );
                  }),
                ]),
    );
  }

  Widget _swipeBackground(IconData icon, String label, Alignment alignment) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(22)),
        alignment: alignment,
        child: Row(mainAxisAlignment: alignment == Alignment.centerLeft ? MainAxisAlignment.start : MainAxisAlignment.end, children: [Icon(icon), const SizedBox(width: 8), Text(label, style: const TextStyle(fontWeight: FontWeight.w700))]),
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
}

class _GlassChatTile extends StatelessWidget {
  const _GlassChatTile({required this.title, required this.initial, required this.lastMessage, required this.online, required this.pinned, required this.muted, required this.onMenu, required this.onTap});
  final String title, initial, lastMessage;
  final bool online, pinned, muted;
  final VoidCallback onMenu, onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 18, offset: const Offset(0, 5))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: Stack(children: [
          CircleAvatar(radius: 27, child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
          if (online) Positioned(right: 0, bottom: 0, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, border: Border.all(color: scheme.surface, width: 2)))),
        ]),
        title: Row(children: [Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))), if (pinned) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.push_pin_rounded, size: 16)), if (muted) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.notifications_off_rounded, size: 16))]),
        subtitle: Padding(padding: const EdgeInsets.only(top: 3), child: Text(lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis)),
        trailing: IconButton(onPressed: onMenu, icon: const Icon(Icons.more_horiz_rounded)),
        onTap: onTap,
      ),
    );
  }
}
