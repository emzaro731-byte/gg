import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  CallService._();
  static final instance = CallService._();

  final SupabaseClient supabase = Supabase.instance.client;
  RealtimeChannel? _inviteChannel;
  RealtimeChannel? _signalChannel;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  RealtimeChannel _privateChannel(String topic) => supabase.channel(
        topic,
        opts: const RealtimeChannelConfig(private: true),
      );

  Future<void> listenForInvites({required BuildContext context, required String conversationId}) async {
    await _inviteChannel?.unsubscribe();
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _inviteChannel = _privateChannel('call-invite:$conversationId');
    _inviteChannel!
        .onBroadcast(event: 'invite', callback: (payload) {
          if (!context.mounted) return;
          final data = Map<String, dynamic>.from(payload);
          if (data['caller_id']?.toString() == user.id) return;
          final sessionId = data['call_id']?.toString();
          final callerId = data['caller_id']?.toString();
          if (sessionId == null || callerId == null) return;
          _showIncoming(context, conversationId, sessionId, callerId, data['video'] == true);
        })
        .subscribe();
  }

  Future<void> startOutgoing({required BuildContext context, required String conversationId, required String calleeId, required bool video, required String title}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final row = await supabase.from('call_sessions').insert({
      'conversation_id': conversationId,
      'caller_id': user.id,
      'callee_id': calleeId,
      'call_type': video ? 'video' : 'audio',
      'status': 'ringing',
    }).select('id').single();
    final callId = row['id'].toString();
    final invite = _privateChannel('call-invite:$conversationId');
    invite.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await invite.sendBroadcastMessage(event: 'invite', payload: {
          'call_id': callId,
          'caller_id': user.id,
          'callee_id': calleeId,
          'video': video,
        });
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(
      callId: callId,
      localUserId: user.id,
      remoteUserId: calleeId,
      video: video,
      isCaller: true,
      title: title,
    )));
    await invite.unsubscribe();
  }

  void _showIncoming(BuildContext context, String conversationId, String callId, String callerId, bool video) {
    showDialog(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
      content: const Text('Someone is calling you on GG Messenger.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Decline')),
        FilledButton(onPressed: () {
          Navigator.pop(dialogContext);
          final user = supabase.auth.currentUser;
          if (user == null) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(
            callId: callId,
            localUserId: user.id,
            remoteUserId: callerId,
            video: video,
            isCaller: false,
            title: video ? 'Video call' : 'Voice call',
          )));
        }, child: const Text('Accept')),
      ],
    ));
  }

  Future<void> setupPeer({required String callId, required String localUserId, required bool video, required bool isCaller, required VoidCallback onConnected, required ValueChanged<MediaStream> onRemoteStream, required ValueChanged<RTCPeerConnectionState> onState}) async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };
    peerConnection = await createPeerConnection(config);
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user', 'width': 720, 'height': 1280} : false,
    });
    for (final track in localStream!.getTracks()) {
      await peerConnection!.addTrack(track, localStream!);
    }
    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams.first;
        onRemoteStream(event.streams.first);
      }
    };
    peerConnection!.onConnectionState = (state) {
      onState(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) onConnected();
    };
    peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(_signal(callId, localUserId, {
        'type': 'ice',
        'candidate': candidate.candidate,
        'sdp_mid': candidate.sdpMid,
        'sdp_mline_index': candidate.sdpMLineIndex,
      }));
    };
    _signalChannel = _privateChannel('call:$callId');
    _signalChannel!.onBroadcast(event: 'signal', callback: (payload) {
      final data = Map<String, dynamic>.from(payload);
      if (data['from']?.toString() == localUserId) return;
      final type = data['type']?.toString();
      if (type == 'answer') {
        applyAnswer(data['sdp']?.toString());
      } else if (type == 'offer' && !isCaller) {
        acceptOffer(callId, localUserId, data['sdp']?.toString());
      } else if (type == 'ice') {
        addIceCandidate(data);
      }
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed && isCaller) {
        await createOffer(callId, localUserId);
      }
    });
  }

  Future<void> createOffer(String callId, String localUserId) async {
    final offer = await peerConnection!.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1});
    await peerConnection!.setLocalDescription(offer);
    await _signal(callId, localUserId, {'type': 'offer', 'sdp': offer.sdp, 'sdp_type': offer.type});
  }

  Future<void> acceptOffer(String callId, String localUserId, String? sdp) async {
    if (sdp == null) return;
    await peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    final answer = await peerConnection!.createAnswer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1});
    await peerConnection!.setLocalDescription(answer);
    await _signal(callId, localUserId, {'type': 'answer', 'sdp': answer.sdp, 'sdp_type': answer.type});
    await supabase.from('call_sessions').update({'status': 'accepted', 'answered_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId);
  }

  Future<void> applyAnswer(String? sdp) async {
    if (sdp == null || peerConnection == null) return;
    await peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    await supabase.from('call_sessions').update({'status': 'accepted', 'answered_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _signalChannel?.topic.split(':').last ?? '');
  }

  Future<void> addIceCandidate(Map<String, dynamic> data) async {
    final candidate = data['candidate']?.toString();
    if (candidate == null) return;
    await peerConnection?.addCandidate(RTCIceCandidate(candidate, data['sdp_mid']?.toString(), int.tryParse(data['sdp_mline_index']?.toString() ?? '')));
  }

  Future<void> _signal(String callId, String from, Map<String, dynamic> payload) async {
    final channel = _signalChannel;
    if (channel == null) return;
    await channel.sendBroadcastMessage(event: 'signal', payload: {...payload, 'from': from});
  }

  Future<void> setMicrophoneMuted(bool muted) async {
    for (final track in localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) track.enabled = !muted;
  }

  Future<void> setCameraEnabled(bool enabled) async {
    for (final track in localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) track.enabled = enabled;
  }

  Future<void> endCall(String callId) async {
    await supabase.from('call_sessions').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId);
    await dispose();
  }

  Future<void> dispose() async {
    await localStream?.dispose();
    await remoteStream?.dispose();
    await peerConnection?.close();
    await _signalChannel?.unsubscribe();
    peerConnection = null;
    localStream = null;
    remoteStream = null;
    _signalChannel = null;
  }

  Future<void> stopInvites() async {
    await _inviteChannel?.unsubscribe();
    _inviteChannel = null;
  }
}

class CallPage extends StatefulWidget {
  final String callId;
  final String localUserId;
  final String remoteUserId;
  final bool video;
  final bool isCaller;
  final String title;
  const CallPage({required this.callId, required this.localUserId, required this.remoteUserId, required this.video, required this.isCaller, required this.title, super.key});
  @override State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final service = CallService.instance;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool muted = false;
  bool camera = true;
  String state = 'Connecting…';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await service.setupPeer(
      callId: widget.callId,
      localUserId: widget.localUserId,
      video: widget.video,
      isCaller: widget.isCaller,
      onConnected: () { if (mounted) setState(() => state = 'Connected'); },
      onRemoteStream: (stream) { remoteRenderer.srcObject = stream; if (mounted) setState(() => state = 'Connected'); },
      onState: (value) { if (mounted) setState(() => state = value.toString().split('.').last); },
    );
    if (mounted) {
      localRenderer.srcObject = service.localStream;
      setState(() {});
    }
  }

  Future<void> _end() async {
    await service.endCall(widget.callId);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    unawaited(service.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title), Text(state, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal))])),
    body: Stack(children: [
      if (widget.video && remoteRenderer.srcObject != null) Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)) else const Center(child: Icon(Icons.person, color: Colors.white24, size: 120)),
      if (widget.video && localRenderer.srcObject != null) Positioned(top: 18, right: 18, width: 110, height: 160, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: RTCVideoView(localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
      Align(alignment: Alignment.bottomCenter, child: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        FloatingActionButton(heroTag: 'mute', onPressed: () async { muted = !muted; await service.setMicrophoneMuted(muted); if (mounted) setState(() {}); }, child: Icon(muted ? Icons.mic_off : Icons.mic)),
        if (widget.video) FloatingActionButton(heroTag: 'camera', onPressed: () async { camera = !camera; await service.setCameraEnabled(camera); if (mounted) setState(() {}); }, child: Icon(camera ? Icons.videocam : Icons.videocam_off)),
        FloatingActionButton(heroTag: 'end', backgroundColor: Colors.red, onPressed: _end, child: const Icon(Icons.call_end)),
      ])))),
    ]),
  );
}
