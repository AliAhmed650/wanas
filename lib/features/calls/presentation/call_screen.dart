import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/widgets/user_avatar.dart';
import '../agora_config.dart';
import '../data/call_repository.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({
    super.key,
    required this.callId,
    required this.otherName,
    required this.video,
    required this.isCaller,
  });

  final String callId;
  final String otherName;
  final bool video;
  final bool isCaller;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final CallRepository _repo = ref.read(callRepositoryProvider);

  RtcEngine? _engine;
  VideoViewController? _localController;
  VideoViewController? _remoteController;
  StreamSubscription<Call?>? _sub;
  Timer? _ringTimeout;
  Timer? _ticker;

  int? _remoteUid;
  int _seconds = 0;
  bool _muted = false;
  bool _cameraOff = false;
  late bool _speaker = widget.video;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _sub = _repo.watchCall(widget.callId).listen(_onCallChanged);
    if (widget.isCaller) {
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (_remoteUid == null) _end(status: 'missed');
      });
    }
    _init();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ringTimeout?.cancel();
    _ticker?.cancel();
    final e = _engine;
    if (e != null) _releaseEngine(e);
    super.dispose();
  }

  void _onCallChanged(Call? c) {
    if (c == null) return;
    if (c.status == 'declined' || c.status == 'ended' || c.status == 'missed') {
      _close();
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _end({String status = 'ended'}) async {
    await _repo.setStatus(widget.callId, status);
    _close();
  }

  Future<void> _releaseEngine(RtcEngine e) async {
    try {
      await e.leaveChannel();
      await e.release();
    } catch (_) {}
  }

  Future<void> _init() async {
    final perms = [Permission.microphone, if (widget.video) Permission.camera];
    final result = await perms.request();
    if (result.values.any((s) => !s.isGranted)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('محتاج إذن الميكروفون والكاميرا')),
        );
      }
      await _end();
      return;
    }
    if (!mounted) return;

    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    if (!mounted) {
      await _releaseEngine(engine);
      return;
    }

    engine.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (connection, remoteUid, elapsed) {
        if (!mounted) return;
        _ringTimeout?.cancel();
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
        setState(() {
          _remoteController = VideoViewController.remote(
            rtcEngine: engine,
            canvas: VideoCanvas(uid: remoteUid),
            connection: RtcConnection(channelId: widget.callId),
          );
          _remoteUid = remoteUid;
        });
      },
      onUserOffline: (connection, remoteUid, reason) {
        if (mounted) _end();
      },
      onError: (err, msg) => debugPrint('Agora error: $err $msg'),
    ));

    if (widget.video) {
      await engine.enableVideo();
      await engine.startPreview();
    } else {
      await engine.enableAudio();
    }
    await engine.setEnableSpeakerphone(_speaker);

    if (!mounted) {
      await _releaseEngine(engine);
      return;
    }
    setState(() {
      _engine = engine;
      if (widget.video) {
        _localController = VideoViewController(
          rtcEngine: engine,
          canvas: const VideoCanvas(uid: 0),
        );
      }
    });

    await engine.joinChannel(
      token: '',
      channelId: widget.callId,
      uid: 0,
      options: ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: widget.video,
        publishMicrophoneTrack: true,
        publishCameraTrack: widget.video,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _engine?.muteLocalAudioStream(_muted);
  }

  Future<void> _toggleCamera() async {
    setState(() => _cameraOff = !_cameraOff);
    await _engine?.muteLocalVideoStream(_cameraOff);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speaker = !_speaker);
    await _engine?.setEnableSpeakerphone(_speaker);
  }

  String get _statusText {
    if (_remoteUid != null) {
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      return '$m:$s';
    }
    return widget.isCaller ? 'جاري الاتصال...' : 'جاري الانضمام...';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.otherName.isEmpty ? 'مستخدم' : widget.otherName;
    final showRemoteVideo =
        widget.video && _remoteController != null && _engine != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1A17),
        body: Stack(
          children: [
            if (showRemoteVideo)
              Positioned.fill(
                  child: AgoraVideoView(controller: _remoteController!))
            else
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    UserAvatar(name: name, radius: 64),
                    const SizedBox(height: 24),
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(_statusText,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 16)),
                  ],
                ),
              ),
            if (showRemoteVideo)
              Positioned(
                top: 56,
                left: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600)),
                    Text(_statusText,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            if (widget.video && _localController != null && !_cameraOff)
              Positioned(
                top: 48,
                right: 16,
                width: 110,
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AgoraVideoView(controller: _localController!),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _btn(_muted ? Icons.mic_off : Icons.mic, _toggleMute,
                      active: _muted),
                  if (widget.video)
                    _btn(
                        _cameraOff ? Icons.videocam_off : Icons.videocam,
                        _toggleCamera,
                        active: _cameraOff),
                  if (widget.video)
                    _btn(Icons.cameraswitch, () => _engine?.switchCamera()),
                  _btn(_speaker ? Icons.volume_up : Icons.volume_down,
                      _toggleSpeaker,
                      active: _speaker),
                  _btn(Icons.call_end, _end, red: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap,
      {bool active = false, bool red = false}) {
    final bg = red
        ? Colors.red
        : (active ? Colors.white : Colors.white24);
    final fg = red ? Colors.white : (active ? Colors.black : Colors.white);
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(icon, color: fg, size: 26),
        ),
      ),
    );
  }
}