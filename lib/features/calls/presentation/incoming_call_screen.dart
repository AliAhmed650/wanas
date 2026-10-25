import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/call_repository.dart';
import 'call_screen.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key, required this.call});
  final Call call;

  @override
  ConsumerState<IncomingCallScreen> createState() =>
      _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  bool _handled = false;

  Future<void> _accept() async {
    _handled = true;
    await ref
        .read(callRepositoryProvider)
        .setStatus(widget.call.id, 'accepted');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: widget.call.id,
          otherName: widget.call.callerName,
          video: widget.call.video,
          isCaller: false,
        ),
      ),
    );
  }

  Future<void> _decline() async {
    _handled = true;
    await ref
        .read(callRepositoryProvider)
        .setStatus(widget.call.id, 'declined');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // لو المتصل قفل قبل ما أرد، اقفل الشاشة
    ref.listen<AsyncValue<Call?>>(callProvider(widget.call.id), (prev, next) {
      final c = next.value;
      if (!_handled && c != null && c.status != 'ringing' && mounted) {
        Navigator.of(context).pop();
      }
    });

    final name =
        widget.call.callerName.isEmpty ? 'مستخدم' : widget.call.callerName;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1A17),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              UserAvatar(name: name, radius: 64),
              const SizedBox(height: 24),
              Text(name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                widget.call.video
                    ? 'مكالمة فيديو واردة...'
                    : 'مكالمة صوتية واردة...',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(flex: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundButton(Icons.call_end, Colors.red, _decline),
                  _roundButton(
                    widget.call.video ? Icons.videocam : Icons.call,
                    Colors.green,
                    _accept,
                  ),
                ],
              ),
              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}