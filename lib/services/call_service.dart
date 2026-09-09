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

  RealtimeChannel _privateChannel(String topic) => supabase.channel(topic, opts: const RealtimeChannelConfig(private: true));

  Future<void> listenForInvites({required BuildContext context, required String conversationId}) async {
    await _inviteChannel?.unsubscribe();
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _inviteChannel = _privateChannel('call-invite:$conversationId');
    _inviteChannel!.onBroadcast(event: 'invite', callback: (payload) {
      if (!context.mounted) return;
      final data = Map<String, dynamic>.from(payload);
      if (data['caller_id']?.toString() == user.id) return;
      final sessionId = data['call_id']?.toString();
      final callerId = data['caller_id']?.toString();
      if (sessionId == null || callerId == null) return;
      _showIncoming(context, conversationId, sessionId, callerId, data['video'] == true);
    }).subscribe();
  }

  Future<void> startOutgoing({required BuildContext context, required String conversationId, required String calleeId, required bool video, required String title}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final row = await supabase.from('call_sessions').insert({'conversation_id': conversationId, 'caller_id': user.id, 'callee_id': calleeId, 'kind': video ? 'video' : 'voice', 'status': 'ringing'}).select('id').single();
    final callId = row['id'].toString();
    final invite = _privateChannel('call-invite:$conversationId');
    invite.subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await invite.sendBroadcastMessage(event: 'invite', payload: {'call_id': callId, 'caller_id': user.id, 'callee_id': calleeId, 'video': video});
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!context.mounted) {
      await invite.unsubscribe();
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: callId, localUserId: user.id, remoteUserId: calleeId, video: video, isCaller: true, title: title)));
    await invite.unsubscribe();
  }

  void _showIncoming(BuildContext context, String conversationId, String callId, String callerId, bool video) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(.72),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
              decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(30)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircleAvatar(radius: 42, backgroundColor: Color(0xFF263247), child: Icon(Icons.person, size: 48, color: Colors.white70)),
                const SizedBox(height: 18),
                Text(video ? 'Incoming video call' : 'Incoming voice call', style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(video ? 'Someone is calling you on GG Messenger' : 'Someone is calling you', style: const TextStyle(color: Colors.white60), textAlign: TextAlign.center),
                const SizedBox(height: 26),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _CallAction(icon: Icons.call_end, label: 'Decline', color: Colors.red, onTap: () async {
                    try { await supabase.from('call_sessions').update({'status': 'declined'}).eq('id', callId); } catch (_) {}
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  }),
                  _CallAction(icon: video ? Icons.videocam : Icons.call, label: 'Accept', color: Colors.green, onTap: () {
                    Navigator.pop(dialogContext);
                    final user = supabase.auth.currentUser;
                    if (user == null || !context.mounted) return;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: callId, localUserId: user.id, remoteUserId: callerId, video: video, isCaller: false, title: video ? 'Video call' : 'Voice call')));
                  }),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> setupPeer({required String callId, required String localUserId, required bool video, required bool isCaller, required VoidCallback onConnected, required ValueChanged<MediaStream> onRemoteStream, required ValueChanged<RTCPeerConnectionState> onState}) async {
    final config = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}, {'urls': 'stun1.l.google.com:19302'}], 'sdpSemantics': 'unified-plan'};
    peerConnection = await createPeerConnection(config);
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': video ? {'facingMode': 'user', 'width': 720, 'height': 1280} : false});
    for (final track in localStream!.getTracks()) await peerConnection!.addTrack(track, localStream!);
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
      unawaited(_signal(callId, localUserId, {'type': 'ice', 'candidate': candidate.candidate, 'sdp_mid': candidate.sdpMid, 'sdp_mline_index': candidate.sdpMLineIndex}));
    };
    _signalChannel = _privateChannel('call:$callId');
    _signalChannel!.onBroadcast(event: 'signal', callback: (payload) {
      final data = Map<String, dynamic>.from(payload);
      if (data['from']?.toString() == localUserId) return;
      final type = data['type']?.toString();
      if (type == 'answer') applyAnswer(callId, data['sdp']?.toString());
      else if (type == 'offer' && !isCaller) acceptOffer(callId, localUserId, data['sdp']?.toString());
      else if (type == 'ice') addIceCandidate(data);
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed && isCaller) await createOffer(callId, localUserId);
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
    try { await supabase.from('call_sessions').update({'status': 'accepted'}).eq('id', callId); } catch (_) {}
  }

  Future<void> applyAnswer(String callId, String? sdp) async {
    if (sdp == null || peerConnection == null) return;
    await peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    try { await supabase.from('call_sessions').update({'status': 'accepted'}).eq('id', callId); } catch (_) {}
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

  Future<void> setSpeakerEnabled(bool enabled) async => Helper.setSpeakerphoneOn(enabled);

  Future<void> switchCamera() async {
    final tracks = localStream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> endCall(String callId) async {
    try { await supabase.from('call_sessions').update({'status': 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId); } catch (_) {}
    await dispose();
  }

  Future<void> dispose() async {
    final stream = localStream; localStream = null;
    final remote = remoteStream; remoteStream = null;
    final peer = peerConnection; peerConnection = null;
    final signal = _signalChannel; _signalChannel = null;
    await stream?.dispose();
    await remote?.dispose();
    await peer?.close();
    await signal?.unsubscribe();
  }

  Future<void> stopInvites() async { await _inviteChannel?.unsubscribe(); _inviteChannel = null; }
}

class _CallAction extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _CallAction({required this.icon, required this.label, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => Column(children: [
    FloatingActionButton(heroTag: '${label}_incoming', backgroundColor: color, onPressed: onTap, child: Icon(icon, color: Colors.white)),
    const SizedBox(height: 8), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  ]);
}

class CallPage extends StatefulWidget {
  final String callId; final String localUserId; final String remoteUserId; final bool video; final bool isCaller; final String title;
  const CallPage({required this.callId, required this.localUserId, required this.remoteUserId, required this.video, required this.isCaller, required this.title, super.key});
  @override State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final service = CallService.instance;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool muted = false, camera = true, speaker = false, switchingCamera = false;
  String state = 'Calling…';
  Timer? _ringTimer;

  @override void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      await service.setupPeer(
        callId: widget.callId, localUserId: widget.localUserId, video: widget.video, isCaller: widget.isCaller,
        onConnected: () { _ringTimer?.cancel(); if (mounted) setState(() => state = 'Connected'); },
        onRemoteStream: (stream) { remoteRenderer.srcObject = stream; _ringTimer?.cancel(); if (mounted) setState(() => state = 'Connected'); },
        onState: (value) { if (!mounted) return; final text = value.toString().split('.').last; setState(() => state = text.contains('Disconnected') ? 'Reconnecting…' : text); },
      );
      if (mounted) { localRenderer.srcObject = service.localStream; setState(() {}); }
      _ringTimer = Timer(const Duration(seconds: 45), () { if (mounted && state != 'Connected') _end(); });
    } catch (_) { if (mounted) setState(() => state = 'Unable to connect'); }
  }

  Future<void> _toggleSpeaker() async {
    speaker = !speaker;
    try { await service.setSpeakerEnabled(speaker); } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (switchingCamera) return;
    switchingCamera = true;
    try { await service.switchCamera(); } catch (_) {}
    switchingCamera = false;
    if (mounted) setState(() {});
  }

  Future<void> _end() async { _ringTimer?.cancel(); await service.endCall(widget.callId); if (mounted) Navigator.pop(context); }

  @override void dispose() {
    _ringTimer?.cancel();
    localRenderer.dispose(); remoteRenderer.dispose();
    unawaited(service.dispose());
    super.dispose();
  }

  Widget _control({required IconData icon, required String label, required VoidCallback onPressed, bool active = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(
      decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.white : Colors.white.withOpacity(.14)),
      child: IconButton(onPressed: onPressed, icon: Icon(icon, color: active ? Colors.black : Colors.white), iconSize: 25, padding: const EdgeInsets.all(14)),
    ),
    const SizedBox(height: 5), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
  ]);

  @override Widget build(BuildContext context) {
    final hasRemoteVideo = widget.video && remoteRenderer.srcObject != null;
    final hasLocalVideo = widget.video && localRenderer.srcObject != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (hasRemoteVideo) Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
        else Positioned.fill(child: Container(color: const Color(0xFF070A12), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const CircleAvatar(radius: 64, backgroundColor: Color(0xFF1D2638), child: Icon(Icons.person, color: Colors.white70, size: 72)),
          const SizedBox(height: 22),
          Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8), Text(state, style: const TextStyle(color: Colors.white60, fontSize: 15)),
        ])),
        SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 0), child: Row(children: [
          Container(decoration: BoxDecoration(color: Colors.black.withOpacity(.35), shape: BoxShape.circle), child: IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)), Text(state, style: const TextStyle(color: Colors.white70, fontSize: 12))])),
        ]))),
        if (hasLocalVideo) Positioned(top: MediaQuery.of(context).padding.top + 62, right: 16, width: 108, height: 154, child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white24), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 14)]),
          clipBehavior: Clip.antiAlias,
          child: RTCVideoView(localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
        )),
        Align(alignment: Alignment.bottomCenter, child: SafeArea(child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 13),
          decoration: BoxDecoration(color: Colors.black.withOpacity(.62), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _control(icon: muted ? Icons.mic_off : Icons.mic, label: muted ? 'Unmute' : 'Mute', active: muted, onPressed: () async { muted = !muted; await service.setMicrophoneMuted(muted); if (mounted) setState(() {}); }),
              _control(icon: speaker ? Icons.volume_up : Icons.volume_down, label: speaker ? 'Speaker' : 'Earpiece', active: speaker, onPressed: _toggleSpeaker),
              if (widget.video) _control(icon: camera ? Icons.videocam : Icons.videocam_off, label: camera ? 'Camera' : 'Camera off', active: !camera, onPressed: () async { camera = !camera; await service.setCameraEnabled(camera); if (mounted) setState(() {}); }),
              if (widget.video) _control(icon: Icons.cameraswitch, label: 'Flip', onPressed: _switchCamera),
            ]),
            const SizedBox(height: 18),
            FloatingActionButton.large(heroTag: 'end_call_main', backgroundColor: Colors.red, onPressed: _end, child: const Icon(Icons.call_end, color: Colors.white, size: 30)),
          ]),
        ))),
      ]),
    );
  }
}
