import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/call_service.dart';

class CallsPage extends StatefulWidget {
  const CallsPage({super.key});

  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  final supabase = Supabase.instance.client;
  final Map<String, Future<Map<String, dynamic>?>> _profiles = {};

  String get userId => supabase.auth.currentUser!.id;

  Future<Map<String, dynamic>?> _profile(String id) {
    return _profiles.putIfAbsent(id, () async {
      try {
        final row = await supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url')
            .eq('id', id)
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
      } catch (_) {
        return null;
      }
    });
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'missed':
        return 'Missed call';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'ringing':
        return 'Ringing';
      case 'completed':
        return 'Completed';
      default:
        return 'Call ended';
    }
  }

  IconData _statusIcon(String status, bool outgoing) {
    if (status == 'missed') return Icons.call_missed_rounded;
    if (status == 'declined') return Icons.call_end_rounded;
    return outgoing ? Icons.call_made_rounded : Icons.call_received_rounded;
  }

  String _time(String? raw) {
    final date = DateTime.tryParse(raw ?? '')?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    return DateFormat('dd MMM, HH:mm').format(date);
  }

  String _duration(Map<String, dynamic> call) {
    final started = DateTime.tryParse(call['started_at']?.toString() ?? '');
    final ended = DateTime.tryParse(call['ended_at']?.toString() ?? '');
    if (started == null || ended == null) return '';
    final seconds = ended.difference(started).inSeconds;
    if (seconds < 1) return '';
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return minutes > 0 ? '${minutes}m ${remaining}s' : '${remaining}s';
  }

  Future<void> _redial(Map<String, dynamic> call, Map<String, dynamic>? profile) async {
    final conversationId = call['conversation_id']?.toString();
    final otherId = call['caller_id'] == userId
        ? call['callee_id']?.toString()
        : call['caller_id']?.toString();
    if (conversationId == null || otherId == null || otherId.isEmpty) return;

    final video = call['kind']?.toString() == 'video';
    final name = profile?['display_name']?.toString() ?? 'GG User';
    try {
      await CallService.instance.startOutgoing(
        context: context,
        conversationId: conversationId,
        calleeId: otherId,
        video: video,
        title: name,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start call: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = supabase.auth.currentUser;
    if (current == null) return const Center(child: Text('Sign in to view calls.'));

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('call_sessions')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 52),
                  const SizedBox(height: 12),
                  const Text(
                    'Call history is temporarily unavailable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'You can still make calls from a chat.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        }

        final calls = (snapshot.data ?? [])
            .where((c) => c['caller_id'] == userId || c['callee_id'] == userId)
            .toList();

        if (calls.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_in_talk_outlined, size: 62, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                const Text('No calls yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                const Text('Your voice and video call history will appear here.'),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 110),
            itemCount: calls.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final call = calls[i];
              final outgoing = call['caller_id'] == userId;
              final otherId = outgoing
                  ? call['callee_id']?.toString()
                  : call['caller_id']?.toString();
              final video = call['kind']?.toString() == 'video';
              final status = call['status']?.toString() ?? 'ended';

              if (otherId == null || otherId.isEmpty) {
                return _callTile(call, null, outgoing, video, status);
              }

              return FutureBuilder<Map<String, dynamic>?>(
                future: _profile(otherId),
                builder: (_, profileSnapshot) => _callTile(
                  call,
                  profileSnapshot.data,
                  outgoing,
                  video,
                  status,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _callTile(
    Map<String, dynamic> call,
    Map<String, dynamic>? profile,
    bool outgoing,
    bool video,
    String status,
  ) {
    final name = profile?['display_name']?.toString() ??
        profile?['username']?.toString() ??
        'GG User';
    final avatar = profile?['avatar_url']?.toString();
    final time = _time(call['created_at']?.toString());
    final duration = _duration(call);
    final missed = status == 'missed';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 25,
              backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar == null || avatar.isEmpty
                  ? Text(name.isEmpty ? '?' : name[0].toUpperCase())
                  : null,
            ),
            Positioned(
              right: -3,
              bottom: -2,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: Theme.of(context).colorScheme.surface,
                child: Icon(
                  video ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 13,
                ),
              ),
            ),
          ],
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: missed ? Theme.of(context).colorScheme.error : null,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(_statusIcon(status, outgoing), size: 15,
                color: missed ? Theme.of(context).colorScheme.error : null),
            const SizedBox(width: 5),
            Flexible(child: Text('${_statusLabel(status)}${duration.isEmpty ? '' : ' • $duration'}')),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(time, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 5),
            IconButton(
              tooltip: video ? 'Video call again' : 'Call again',
              onPressed: () => _redial(call, profile),
              icon: Icon(video ? Icons.videocam_rounded : Icons.call_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
