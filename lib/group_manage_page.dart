import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GroupManagePage extends StatefulWidget {
  const GroupManagePage({super.key, required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  @override
  State<GroupManagePage> createState() => _GroupManagePageState();
}

class _GroupManagePageState extends State<GroupManagePage> {
  final supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool loading = true;
  bool busy = false;
  String? myRole;
  String groupTitle = '';
  String query = '';
  List<Map<String, dynamic>> members = [];

  @override
  void initState() {
    super.initState();
    groupTitle = widget.title;
    _searchController.addListener(() {
      if (mounted) setState(() => query = _searchController.text.trim().toLowerCase());
    });
    load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get isAdmin => myRole == 'admin';

  List<Map<String, dynamic>> get filteredMembers {
    if (query.isEmpty) return members;
    return members.where((member) {
      final profile = member['profiles'] is Map
          ? Map<String, dynamic>.from(member['profiles'])
          : <String, dynamic>{};
      final name = profile['display_name']?.toString().toLowerCase() ?? '';
      final username = profile['username']?.toString().toLowerCase() ?? '';
      return name.contains(query) || username.contains(query);
    }).toList();
  }

  String _name(Map<String, dynamic> profile) {
    final display = profile['display_name']?.toString().trim() ?? '';
    return display.isEmpty ? 'GG User' : display;
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  Widget _avatar(Map<String, dynamic> profile, {double size = 48}) {
    final name = _name(profile);
    final avatar = profile['avatar_url']?.toString().trim() ?? '';
    final image = avatar.isEmpty
        ? null
        : NetworkImage(avatar);
    return CircleAvatar(
      radius: size / 2,
      backgroundImage: image,
      child: image == null
          ? Text(_initials(name), style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .28))
          : null,
    );
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await supabase
          .from('conversation_members')
          .select('user_id, role, profiles(id, username, display_name, avatar_url)')
          .eq('conversation_id', widget.conversationId);
      final list = List<Map<String, dynamic>>.from(rows);
      final current = supabase.auth.currentUser?.id;
      myRole = current == null
          ? null
          : list
              .firstWhere((m) => m['user_id'] == current, orElse: () => <String, dynamic>{})['role']
              ?.toString();
      members = list;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load members: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> callRpc(String fn, Map<String, dynamic> params) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await supabase.rpc(fn, params: params);
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> rename() async {
    final controller = TextEditingController(text: groupTitle);
    final value = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Group name',
            prefixIcon: Icon(Icons.groups_rounded),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.isNotEmpty) {
      await callRpc('update_group_title', {'group_id': widget.conversationId, 'new_title': value});
      if (mounted) setState(() => groupTitle = value);
    }
  }

  Future<void> leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text('You will no longer receive messages from this group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) {
      await callRpc('leave_group', {'group_id': widget.conversationId});
      if (mounted) Navigator.pop(context, true);
    }
  }

  Widget _memberTile(Map<String, dynamic> member) {
    final profile = member['profiles'] is Map
        ? Map<String, dynamic>.from(member['profiles'])
        : <String, dynamic>{};
    final name = _name(profile);
    final username = profile['username']?.toString() ?? '';
    final role = member['role']?.toString() ?? 'member';
    final id = member['user_id'].toString();
    final mine = id == supabase.auth.currentUser?.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: .25)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: _avatar(profile),
        title: Row(
          children: [
            Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (mine) ...[
              const SizedBox(width: 7),
              const Text('You', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
        subtitle: Text(
          username.isEmpty ? (role == 'admin' ? 'Group admin' : 'Member') : '@$username',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (role == 'admin')
              const Chip(
                avatar: Icon(Icons.shield_rounded, size: 14),
                label: Text('Admin'),
                visualDensity: VisualDensity.compact,
              ),
            if (isAdmin && !mine)
              PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'remove') {
                    await callRpc('remove_group_member', {
                      'group_id': widget.conversationId,
                      'member_id': id,
                    });
                  }
                  if (action == 'toggle') {
                    await callRpc('set_group_admin', {
                      'group_id': widget.conversationId,
                      'member_id': id,
                      'make_admin': role != 'admin',
                    });
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(role == 'admin' ? 'Demote admin' : 'Make admin'),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove member'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group info', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Rename group',
              onPressed: busy ? null : rename,
              icon: const Icon(Icons.edit_rounded),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer.withValues(alpha: .85),
                          scheme.surfaceContainerHighest.withValues(alpha: .65),
                        ],
                      ),
                      border: Border.all(color: scheme.outline.withValues(alpha: .16)),
                    ),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 48,
                              backgroundColor: scheme.primary,
                              child: Text(
                                _initials(groupTitle),
                                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: scheme.onPrimary),
                              ),
                            ),
                            if (isAdmin)
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: const [BoxShadow(blurRadius: 8, spreadRadius: 1)],
                                ),
                                child: Icon(Icons.edit_rounded, size: 16, color: scheme.primary),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          groupTitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 5),
                        Text('${members.length} ${members.length == 1 ? 'member' : 'members'}', style: TextStyle(color: scheme.onSurfaceVariant)),
                        if (isAdmin) ...[
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: busy
                                ? null
                                : () => ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Member invitations can be added from New Group/Search.')),
                                    ),
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Add members'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('Members', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const Spacer(),
                      if (query.isNotEmpty) Text('${filteredMembers.length} found', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search members',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(onPressed: _searchController.clear, icon: const Icon(Icons.close_rounded)),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .45),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (filteredMembers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 38),
                      child: Column(
                        children: [
                          Icon(Icons.person_search_rounded, size: 46, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 10),
                          Text('No members found', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('Try a different name or username.', style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  else
                    ...filteredMembers.map(_memberTile),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: busy ? null : leave,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Leave group'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error.withValues(alpha: .45)),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
