import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  CallService._();
  static final instance = CallService._();

  RealtimeChannel? _channel;
  StreamSubscription? _auth;

  Future<void> start({required BuildContext context, required String conversationId, required bool video}) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    await stop();
    final topic = 'call:$conversationId';
    _channel = client.channel(topic);
    _channel!.onBroadcast(event: 'call', callback: (payload) {
      if (!context.mounted) return;
      final data = Map<String, dynamic>.from(payload);
      if (data['user_id'] == user.id) return;
      _showIncoming(context, conversationId, data);
    });
    _channel!.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _channel!.sendBroadcastMessage(event: 'call', payload: {
          'action': 'invite',
          'user_id': user.id,
          'video': video,
          'at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    });
    if (context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(video: video, title: video ? 'Video call' : 'Voice call')));
    }
  }

  void _showIncoming(BuildContext context, String conversationId, Map<String, dynamic> data) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(data['video'] == true ? 'Incoming video call' : 'Incoming voice call'),
      content: const Text('GG Messenger call invitation received.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Decline')),
        FilledButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(video: data['video'] == true, title: data['video'] == true ? 'Video call' : 'Voice call'))); }, child: const Text('Accept')),
      ],
    ));
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await channel.unsubscribe();
  }
}

class CallPage extends StatelessWidget {
  final bool video;
  final String title;
  const CallPage({required this.video, required this.title, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
    body: Stack(children: [
      Center(child: Icon(video ? Icons.videocam_rounded : Icons.call_rounded, color: Colors.white54, size: 96)),
      Align(alignment: Alignment.bottomCenter, child: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _button(Icons.mic_off_rounded),
        _button(video ? Icons.videocam_off_rounded : Icons.volume_up_rounded),
        FloatingActionButton(backgroundColor: Colors.red, onPressed: () => Navigator.pop(context), child: const Icon(Icons.call_end_rounded)),
      ])))),
    ]),
  );

  Widget _button(IconData icon) => CircleAvatar(radius: 28, backgroundColor: Colors.white12, child: Icon(icon, color: Colors.white));
}
