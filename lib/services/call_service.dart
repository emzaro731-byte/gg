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
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteDescriptionSet = false;
  bool _offerSent = false;

  RealtimeChannel _privateChannel(String topic) =>
      supabase.channel(topic, opts: const RealtimeChannelConfig(private: true));

  Future<void> listenForInvites({required BuildContext context, required String conversationId}) async {
    await _inviteChannel?.unsubscribe();
    final user = supabase.auth.currentUser;
    if (user == null) return;
    _inviteChannel = _privateChannel('call-invite:$conversationId');
    _inviteChannel!.onBroadcast(event: 'invite', callback: (payload) {
      if (!context.mounted) return;
      final data = Map<String, dynamic>.from(payload);
      if (data['caller_id']?.toString() == user.id) return;
      if (data['callee_id']?.toString() != user.id) return;
      final callId = data['call_id']?.toString();
      final callerId = data['caller_id']?.toString();
      if (callId == null || callerId == null) return;
      _showIncoming(context, callId, callerId, data['video'] == true);
    }).subscribe();
  }

  Future<void> startOutgoing({required BuildContext context, required String conversationId, required String calleeId, required bool video, required String title}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final row = await supabase.from('call_sessions').insert({
      'conversation_id': conversationId,
      'caller_id': user.id,
      'callee_id': calleeId,
      'kind': video ? 'video' : 'voice',
      'status': 'ringing'
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
    if (!context.mounted) {
      await invite.unsubscribe();
      return;
    }
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

  void _showIncoming(BuildContext context, String callId, String callerId, bool video) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      pageBuilder: (dialogContext, _, __) => AlertDialog(
        title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
        content: const Text('Someone is calling you on GG Messenger'),
        actions: [
          TextButton(onPressed: () async {
            try { await supabase.from('call_sessions').update({'status': 'declined'}).eq('id', callId); } catch (_) {}
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          }, child: const Text('Decline')),
          FilledButton(onPressed: () {
            Navigator.pop(dialogContext);
            final user = supabase.auth.currentUser;
            if (user == null || !context.mounted) return;
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
      ),
    );
  }

  Future<void> setupPeer({required String callId, required String localUserId, required bool video, required bool isCaller, required VoidCallback onConnected, required ValueChanged<MediaStream> onRemoteStream, required ValueChanged<RTCPeerConnectionState> onState}) async {
    _pendingIce.clear();
    _remoteDescriptionSet = false;
    _offerSent = false;
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

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
    _signalChannel!.onBroadcast(event: 'signal', callback: (payload) async {
      final data = Map<String, dynamic>.from(payload);
      if (data['from']?.toString() == localUserId) return;
      final type = data['type']?.toString();
      try {
        if (type == 'ready' && isCaller && !_offerSent) {
          _offerSent = true;
          await createOffer(callId, localUserId);
        } else if (type == 'answer' && isCaller) {
          await applyAnswer(callId, data['sdp']?.toString());
        } else if (type == 'offer' && !isCaller) {
          await acceptOffer(callId, localUserId, data['sdp']?.toString());
        } else if (type == 'ice') {
          await addIceCandidate(data);
        }
      } catch (e) {
        onState(RTCPeerConnectionState.RTCPeerConnectionStateFailed);
      }
    }).subscribe((status, _) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        // The callee announces readiness. This removes the race where the caller
        // sent the offer before the callee had subscribed to the call channel.
        if (!isCaller) {
          await _signal(callId, localUserId, {'type': 'ready'});
        }
      }
    });
  }

  Future<void> createOffer(String callId, String localUserId) async {
    final pc = peerConnection;
    if (pc == null) return;
    final offer = await pc.createOffer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1});
    await pc.setLocalDescription(offer);
    await _signal(callId, localUserId, {'type': 'offer', 'sdp': offer.sdp, 'sdp_type': offer.type});
  }

  Future<void> acceptOffer(String callId, String localUserId, String? sdp) async {
    final pc = peerConnection;
    if (pc == null || sdp == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    _remoteDescriptionSet = true;
    await _flushPendingIce();
    final answer = await pc.createAnswer({'offerToReceiveAudio': 1, 'offerToReceiveVideo': 1});
    await pc.setLocalDescription(answer);
    await _signal(callId, localUserId, {'type': 'answer', 'sdp': answer.sdp, 'sdp_type': answer.type});
    try { await supabase.from('call_sessions').update({'status': 'accepted'}).eq('id', callId); } catch (_) {}
  }

  Future<void> applyAnswer(String callId, String? sdp) async {
    final pc = peerConnection;
    if (pc == null || sdp == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _remoteDescriptionSet = true;
    await _flushPendingIce();
    try { await supabase.from('call_sessions').update({'status': 'accepted'}).eq('id', callId); } catch (_) {}
  }

  Future<void> addIceCandidate(Map<String, dynamic> data) async {
    final candidate = data['candidate']?.toString();
    if (candidate == null || peerConnection == null) return;
    final ice = RTCIceCandidate(candidate, data['sdp_mid']?.toString(), int.tryParse(data['sdp_mline_index']?.toString() ?? ''));
    if (!_remoteDescriptionSet) {
      _pendingIce.add(ice);
      return;
    }
    await peerConnection!.addCandidate(ice);
  }

  Future<void> _flushPendingIce() async {
    final pc = peerConnection;
    if (pc == null) return;
    for (final ice in List<RTCIceCandidate>.from(_pendingIce)) {
      try { await pc.addCandidate(ice); } catch (_) {}
    }
    _pendingIce.clear();
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
    _pendingIce.clear(); _remoteDescriptionSet = false; _offerSent = false;
    await stream?.dispose(); await remote?.dispose(); await peer?.close(); await signal?.unsubscribe();
  }
}

class CallPage extends StatefulWidget {
  final String callId, localUserId, remoteUserId, title;
  final bool video, isCaller;
  const CallPage({required this.callId, required this.localUserId, required this.remoteUserId, required this.video, required this.isCaller, required this.title, super.key});
  @override State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final service = CallService.instance;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool muted = false, camera = true, speaker = false, switchingCamera = false;
  String state = 'Calling…';
  Timer? ringTimer;

  @override void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      await service.setupPeer(
        callId: widget.callId,
        localUserId: widget.localUserId,
        video: widget.video,
        isCaller: widget.isCaller,
        onConnected: () { ringTimer?.cancel(); if (mounted) setState(() => state = 'Connected'); },
        onRemoteStream: (stream) { remoteRenderer.srcObject = stream; if (mounted) setState(() => state = 'Connected'); },
        onState: (value) { if (!mounted) return; setState(() => state = _friendlyState(value)); },
      );
      if (mounted) { localRenderer.srcObject = service.localStream; setState(() {}); }
      ringTimer = Timer(const Duration(seconds: 60), () { if (mounted && state != 'Connected') _end(); });
    } catch (e) {
      if (mounted) setState(() => state = 'Connection failed — check microphone/camera and internet');
    }
  }

  String _friendlyState(RTCPeerConnectionState value) {
    switch (value) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected: return 'Connected';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting: return 'Connecting…';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected: return 'Reconnecting…';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed: return 'Connection failed';
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed: return 'Call ended';
      default: return widget.isCaller ? 'Calling…' : 'Connecting…';
    }
  }

  Future<void> _toggleSpeaker() async { speaker = !speaker; try { await service.setSpeakerEnabled(speaker); } catch (_) {} if (mounted) setState(() {}); }
  Future<void> _switchCamera() async { if (switchingCamera) return; switchingCamera = true; try { await service.switchCamera(); } catch (_) {} switchingCamera = false; if (mounted) setState(() {}); }
  Future<void> _end() async { ringTimer?.cancel(); await service.endCall(widget.callId); if (mounted) Navigator.pop(context); }

  @override void dispose() { ringTimer?.cancel(); localRenderer.dispose(); remoteRenderer.dispose(); unawaited(service.dispose()); super.dispose(); }

  Widget _control(IconData icon, String label, VoidCallback action, {bool active = false}) => Column(mainAxisSize: MainAxisSize.min, children: [
    Container(decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.white : Colors.white.withValues(alpha: .14)), child: IconButton(onPressed: action, icon: Icon(icon, color: active ? Colors.black : Colors.white), iconSize: 25, padding: const EdgeInsets.all(14))),
    Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
  ]);

  @override Widget build(BuildContext context) {
    final remote = widget.video && remoteRenderer.srcObject != null;
    final local = widget.video && localRenderer.srcObject != null;
    return Scaffold(backgroundColor: Colors.black, body: Stack(children: [
      remote ? Positioned.fill(child: RTCVideoView(remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)) : Positioned.fill(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircleAvatar(radius: 64, backgroundColor: Color(0xFF1D2638), child: Icon(Icons.person, color: Colors.white70, size: 72)),
        const SizedBox(height: 22), Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8), Text(state, style: const TextStyle(color: Colors.white60)),
      ]))),
      if (local) Positioned(top: 60, right: 16, width: 108, height: 154, child: ClipRRect(borderRadius: BorderRadius.circular(18), child: RTCVideoView(localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))),
      SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [IconButton(onPressed: () => Navigator.maybePop(context), icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white)), Expanded(child: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)))])),
        const Spacer(),
        Container(margin: const EdgeInsets.all(14), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black.withValues(alpha: .62), borderRadius: BorderRadius.circular(30)), child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _control(muted ? Icons.mic_off : Icons.mic, muted ? 'Unmute' : 'Mute', () async { muted = !muted; await service.setMicrophoneMuted(muted); if (mounted) setState(() {}); }, active: muted),
            _control(speaker ? Icons.volume_up : Icons.volume_down, speaker ? 'Speaker' : 'Earpiece', _toggleSpeaker, active: speaker),
            if (widget.video) _control(camera ? Icons.videocam : Icons.videocam_off, camera ? 'Camera' : 'Camera off', () async { camera = !camera; await service.setCameraEnabled(camera); if (mounted) setState(() {}); }, active: !camera),
            if (widget.video) _control(Icons.cameraswitch, 'Flip', _switchCamera),
          ]),
          const SizedBox(height: 18),
          FloatingActionButton.large(heroTag: 'end_call_main', backgroundColor: Colors.red, onPressed: _end, child: const Icon(Icons.call_end, color: Colors.white)),
        ])),
      ])),
    ]));
  }
}
