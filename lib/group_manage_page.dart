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
  bool loading = true;
  bool busy = false;
  String? myRole;
  List<Map<String, dynamic>> members = [];

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final rows = await supabase.from('conversation_members').select('user_id, role, profiles(id, username, display_name, avatar_url)').eq('conversation_id', widget.conversationId);
      final list = List<Map<String, dynamic>>.from(rows);
      myRole = list.cast<Map<String, dynamic>>().firstWhere((m) => m['user_id'] == supabase.auth.currentUser!.id, orElse: () => {})['role']?.toString();
      members = list;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load members: $e')));
    } finally { if (mounted) setState(() => loading = false); }
  }

  bool get isAdmin => myRole == 'admin';

  Future<void> callRpc(String fn, Map<String, dynamic> params) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await supabase.rpc(fn, params: params);
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> rename() async {
    final controller = TextEditingController(text: widget.title);
    final value = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Rename group'), content: TextField(controller: controller, maxLength: 80, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save'))]));
    controller.dispose();
    if (value != null && value.isNotEmpty) await callRpc('update_group_title', {'group_id': widget.conversationId, 'new_title': value});
  }

  Future<void> leave() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Leave group?'), content: const Text('You will no longer receive messages from this group.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave'))]));
    if (ok == true) { await callRpc('leave_group', {'group_id': widget.conversationId}); if (mounted) Navigator.pop(context, true); }
  }

  @override
  void initState() { super.initState(); load(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Group info'), actions: [if (isAdmin) IconButton(onPressed: busy ? null : rename, icon: const Icon(Icons.edit_outlined))]),
    body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        CircleAvatar(radius: 42, child: Text(widget.title.isEmpty ? '?' : widget.title[0].toUpperCase(), style: const TextStyle(fontSize: 30))),
        const SizedBox(height: 12),
        Center(child: Text(widget.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
        const SizedBox(height: 6),
        Center(child: Text('${members.length} members')),
        const SizedBox(height: 24),
        if (isAdmin) ListTile(leading: const Icon(Icons.person_add_alt_1), title: const Text('Add members'), subtitle: const Text('Invite people to this group'), onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use New Group/Search to select users; member invitations can be added next.')))),
        const Divider(),
        ...members.map((member) {
          final profile = member['profiles'] is Map ? Map<String, dynamic>.from(member['profiles']) : <String, dynamic>{};
          final name = profile['display_name']?.toString().trim().isNotEmpty == true ? profile['display_name'].toString() : 'GG User';
          final username = profile['username']?.toString() ?? '';
          final role = member['role']?.toString() ?? 'member';
          final id = member['user_id'].toString();
          final mine = id == supabase.auth.currentUser!.id;
          return ListTile(
            leading: CircleAvatar(child: Text(name[0].toUpperCase())),
            title: Text(name),
            subtitle: Text(username.isEmpty ? role : '@$username • $role'),
            trailing: isAdmin && !mine ? PopupMenuButton<String>(onSelected: (action) async {
              if (action == 'remove') await callRpc('remove_group_member', {'group_id': widget.conversationId, 'member_id': id});
              if (action == 'toggle') await callRpc('set_group_admin', {'group_id': widget.conversationId, 'member_id': id, 'make_admin': role != 'admin'});
            }, itemBuilder: (_) => [PopupMenuItem(value: 'toggle', child: Text(role == 'admin' ? 'Demote admin' : 'Make admin')), const PopupMenuItem(value: 'remove', child: Text('Remove member'))]) : null,
          );
        }),
        const SizedBox(height: 18),
        OutlinedButton.icon(onPressed: busy ? null : leave, icon: const Icon(Icons.logout), label: const Text('Leave group')),
      ]),
    ),
  );
}
