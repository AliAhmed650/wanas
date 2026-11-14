import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/media_service.dart';

/// بيسجّل رسالة صوتية (m4a/AAC) ويطلع منها [PickedMedia] جاهزة للرفع.
/// التسجيل مش مدعوم على الويب (المتصفح مش بيدعم AAC)، فالزرار بيتخفي هناك.
class VoiceRecorderController extends ChangeNotifier {
  VoiceRecorderController();

  static bool get supported => !kIsWeb;

  final AudioRecorder _rec = AudioRecorder();
  final List<double> levels = [];
  bool recording = false;
  Duration elapsed = Duration.zero;

  Timer? _ticker;
  StreamSubscription<Amplitude>? _ampSub;
  DateTime? _startedAt;
  bool _disposed = false;

  /// بيبدأ التسجيل. بيرجّع false لو مفيش إذن للميكروفون
  Future<bool> start() async {
    if (recording) return true;
    if (!await _rec.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );
    _startedAt = DateTime.now();
    elapsed = Duration.zero;
    levels.clear();
    recording = true;

    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      elapsed = DateTime.now().difference(_startedAt!);
      _notify();
    });
    _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(
      (a) {
        // الديسيبل بيبقى سالب (-160..0). بنعتبر -50 صمت ونحوّله لـ 0..1
        final level = ((a.current + 50) / 50).clamp(0.0, 1.0);
        levels.add(level);
        if (levels.length > 60) levels.removeAt(0);
        _notify();
      },
    );
    _notify();
    return true;
  }

  /// بيوقف التسجيل ويرجّع الملف. بيرجّع null لو التسجيل أقصر من ثانية
  Future<PickedMedia?> finish() async {
    if (!recording) return null;
    final duration = DateTime.now().difference(_startedAt!);
    await _teardown();
    final path = await _rec.stop();
    if (path == null) return null;
    if (duration < const Duration(seconds: 1)) {
      await _deleteQuietly(path);
      return null;
    }
    final file = XFile(path);
    return PickedMedia(
      name: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      type: MessageType.audio,
      size: await file.length(),
      readBytes: () => file.readAsBytes(),
      path: path,
      mime: 'audio/mp4',
      durationMs: duration.inMilliseconds,
    );
  }

  /// بيلغي التسجيل ويمسح الملف
  Future<void> cancel() async {
    if (!recording) return;
    await _teardown();
    await _rec.cancel();
  }

  Future<void> _teardown() async {
    _ticker?.cancel();
    _ticker = null;
    await _ampSub?.cancel();
    _ampSub = null;
    recording = false;
    _notify();
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ampSub?.cancel();
    if (recording) {
      _rec.cancel();
    }
    _rec.dispose();
    super.dispose();
  }
}

/// شريط التسجيل اللي بيحل مكان خانة الكتابة وقت التسجيل
class RecordingBar extends StatelessWidget {
  const RecordingBar({
    super.key,
    required this.controller,
    required this.onCancel,
    required this.onSend,
  });

  final VoiceRecorderController controller;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'إلغاء',
          onPressed: onCancel,
          icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
        ),
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const _BlinkingDot(),
                const SizedBox(width: 8),
                Text(
                  formatDuration(controller.elapsed),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _Waveform(levels: controller.levels)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'إرسال',
          onPressed: onSend,
          icon: const Icon(Icons.send_rounded),
        ),
      ],
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.levels});
  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, c) {
        const barW = 3.0;
        const gap = 2.0;
        final count = (c.maxWidth / (barW + gap)).floor().clamp(1, 60);
        final shown = levels.length > count
            ? levels.sublist(levels.length - count)
            : levels;
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final l in shown)
              Container(
                width: barW,
                height: 4 + 24 * l,
                margin: const EdgeInsets.symmetric(horizontal: gap / 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
