import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallsPage extends StatelessWidget {
  const CallsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const Center(child: Text('Sign in to view calls.'));

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('call_sessions')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load calls. Please run the latest Supabase migration.\n\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final calls = (snapshot.data ?? [])
            .where((c) => c['caller_id'] == userId || c['callee_id'] == userId)
            .toList();

        if (calls.isEmpty) return const Center(child: Text('No calls yet'));

        return ListView.separated(
          padding: const EdgeInsets.only(top: 8, bottom: 100),
          itemCount: calls.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) {
            final call = calls[i];
            final outgoing = call['caller_id'] == userId;
            final video = call['kind']?.toString() == 'video';
            final status = call['status']?.toString() ?? 'ended';
            return ListTile(
              leading: CircleAvatar(
                child: Icon(video ? Icons.videocam_outlined : Icons.call_outlined),
              ),
              title: Text(
                outgoing ? 'Outgoing call' : 'Incoming call',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(status == 'missed' ? 'Missed call' : status),
              trailing: Icon(outgoing ? Icons.call_made : Icons.call_received),
            );
          },
        );
      },
    );
  }
}
