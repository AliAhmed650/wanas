import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/chat_repository.dart';
import '../data/media_picker.dart';
import '../data/media_service.dart';
import '../../calls/data/call_repository.dart';
import '../../calls/presentation/call_screen.dart';
import 'widgets/message_bubble.dart';
import 'widgets/voice_recorder.dart';

/// مرفق لسه بيترفع (أو فشل رفعه) بيظهر في الشات قبل ما يوصل
class _Upload {
  _Upload(this.media);
  final PickedMedia media;
  double progress = 0;
  bool failed = false;
  bool cancelled = false;
  String? error;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.other});
  final AppUser other;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  late final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  late final String _chatId =
      ChatRepository.chatIdFor(_myUid, widget.other.uid);
  late final ChatRepository _repo = ref.read(chatRepositoryProvider);

  final MediaPicker _picker = MediaPicker();
  final VoiceRecorderController _voice = VoiceRecorderController();
  final List<_Upload> _uploads = [];
  bool _hasText = false;

  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _voice.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_isTyping) _repo.setTyping(_chatId, _myUid, false);
    _controller.dispose();
    _voice.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onChanged(String value) {
    final has = value.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (value.trim().isEmpty) {
      _stopTyping();
      return;
    }
    if (!_isTyping) {
      _isTyping = true;
      _repo.setTyping(_chatId, _myUid, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  void _stopTyping() {
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      _repo.setTyping(_chatId, _myUid, false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _hasText = false);
    _stopTyping();
    await _repo.sendMessage(
      chatId: _chatId,
      senderId: _myUid,
      receiverId: widget.other.uid,
      text: text,
    );
  }

  // ---------------------------------------------------------- مرفقات

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, String value, Color color) {
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(ctx, value),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runSpacing: 12,
              spacing: 12,
              children: [
                item(Icons.photo_library_rounded, 'صور', 'images',
                    Colors.purple),
                item(Icons.photo_camera_rounded, 'كاميرا', 'camera',
                    Colors.pink),
                item(Icons.video_library_rounded, 'فيديو', 'video',
                    Colors.orange),
                item(Icons.videocam_rounded, 'تصوير فيديو', 'recordVideo',
                    Colors.red),
                item(Icons.insert_drive_file_rounded, 'ملف', 'file',
                    Colors.blue),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;

    try {
      final List<PickedMedia> picked;
      switch (choice) {
        case 'images':
          picked = await _picker.pickImages();
        case 'camera':
          final m = await _picker.takePhoto();
          picked = [?m];
        case 'video':
          final m = await _picker.pickVideo();
          picked = [?m];
        case 'recordVideo':
          final m = await _picker.recordVideo();
          picked = [?m];
        default:
          picked = await _picker.pickFiles();
      }
      for (final m in picked) {
        _startUpload(m);
      }
    } catch (e) {
      _toast('تعذر اختيار الملف: $e');
    }
  }

  void _startUpload(PickedMedia media) {
    final u = _Upload(media);
    setState(() => _uploads.add(u));
    _runUpload(u);
  }

  Future<void> _runUpload(_Upload u) async {
    setState(() {
      u.failed = false;
      u.error = null;
      u.progress = 0;
    });
    try {
      final res = await ref.read(mediaServiceProvider).upload(
            chatId: _chatId,
            media: u.media,
            onProgress: (p) {
              if (mounted) setState(() => u.progress = p);
            },
          );
      if (u.cancelled) return;
      await _repo.sendMedia(
        chatId: _chatId,
        senderId: _myUid,
        receiverId: widget.other.uid,
        type: u.media.type,
        url: res.url,
        storagePath: res.storagePath,
        fileName: u.media.name,
        fileSize: u.media.size,
        durationMs: u.media.durationMs,
      );
      if (mounted) setState(() => _uploads.remove(u));
    } catch (e) {
      if (!mounted || u.cancelled) return;
      setState(() {
        u.failed = true;
        u.error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _dismissUpload(_Upload u) {
    u.cancelled = true;
    setState(() => _uploads.remove(u));
  }

  // ---------------------------------------------------------- تسجيل صوتي

  Future<void> _startRecording() async {
    try {
      final ok = await _voice.start();
      if (!ok) _toast('محتاجين إذن الميكروفون عشان نسجّل صوت');
    } catch (e) {
      _toast('تعذر بدء التسجيل: $e');
    }
  }

  Future<void> _sendRecording() async {
    try {
      final media = await _voice.finish();
      if (media == null) {
        _toast('التسجيل قصير جدًا');
        return;
      }
      _startUpload(media);
    } catch (e) {
      _toast('تعذر حفظ التسجيل: $e');
    }
  }

  Future<void> _startCall(bool video) async {
    final me = FirebaseAuth.instance.currentUser!;
    final callId = await ref.read(callRepositoryProvider).startCall(
          calleeId: widget.other.uid,
          callerName: me.displayName ?? 'مستخدم',
          video: video,
        );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          otherName: widget.other.name,
          video: video,
          isCaller: true,
        ),
      ),
    );
  }

  // ضغطة مطولة على رسالة: نسخ للكل، وتعديل لرسايلك إنت
  void _onLongPress(Message msg, bool isLast) {
    if (msg.pending) return;
    if (msg.text.isEmpty && msg.type != MessageType.text) return;
    final mine = msg.senderId == _myUid;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (msg.text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('نسخ'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.text));
                },
              ),
            if (mine && msg.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('تعديل'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(msg, isLast);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editMessage(Message msg, bool isLast) async {
    final ctrl = TextEditingController(text: msg.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الرسالة'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 4000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (newText == null || newText.isEmpty || newText == msg.text) return;
    try {
      await _repo.editMessage(
        chatId: _chatId,
        messageId: msg.id,
        text: newText,
        isLast: isLast,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تعديل الرسالة: $e')),
      );
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${d.day}/${d.month}/${d.year}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final messages = ref.watch(messagesProvider(_chatId));
    final typing = ref
            .watch(typingProvider(
                (chatId: _chatId, otherUid: widget.other.uid)))
            .value ??
        false;

    // أي رسالة جديدة من الطرف التاني وإنت فاتح الشات = مقروءة
    ref.listen<AsyncValue<List<Message>>>(
      messagesProvider(_chatId),
      (prev, next) {
        final list = next.value;
        if (list != null) _repo.markRead(_chatId, _myUid, list);
      },
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _startCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(true),
          ),
        ],
        title: Row(
          children: [
            UserAvatar(
              name: widget.other.name,
              photoB64: widget.other.photoB64,
              radius: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.other.name,
                      style: const TextStyle(fontSize: 18)),
                  if (typing)
                    Text(
                      'بيكتب الآن...',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.primary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (list) {
                if (list.isEmpty && _uploads.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UserAvatar(
                          name: widget.other.name,
                          photoB64: widget.other.photoB64,
                          radius: 40,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          widget.other.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ابدأ المحادثة 👋',
                          style: TextStyle(color: scheme.outline),
                        ),
                      ],
                    ),
                  );
                }
                // الأحدث الأول (القايمة reverse): المرفقات اللي بتترفع فوق الرسايل
                final ups = _uploads.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: ups.length + list.length,
                  itemBuilder: (context, i) {
                    if (i < ups.length) {
                      return _UploadTile(
                        upload: ups[i],
                        onRetry: () => _runUpload(ups[i]),
                        onDismiss: () => _dismissUpload(ups[i]),
                      );
                    }
                    final k = i - ups.length;
                    final msg = list[k];
                    final mine = msg.senderId == _myUid;
                    final isLast = k == 0; // القايمة مرتبة من الأحدث
                    final newer = k > 0 ? list[k - 1] : null;
                    final older = k + 1 < list.length ? list[k + 1] : null;
                    final showTail =
                        newer == null || newer.senderId != msg.senderId;
                    final showDay = msg.createdAt != null &&
                        (older?.createdAt == null ||
                            !_sameDay(msg.createdAt!, older!.createdAt!));
                    return Column(
                      children: [
                        if (showDay)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _dayLabel(msg.createdAt!),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                        MessageBubble(
                          msg: msg,
                          mine: mine,
                          showTail: showTail,
                          onLongPress: () => _onLongPress(msg, isLast),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: _voice.recording
                  ? RecordingBar(
                      controller: _voice,
                      onCancel: _voice.cancel,
                      onSend: _sendRecording,
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'إرفاق',
                          onPressed: _attach,
                          icon: Icon(
                            Icons.attach_file_rounded,
                            color: scheme.primary,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            onChanged: _onChanged,
                            minLines: 1,
                            maxLines: 5,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: InputDecoration(
                              hintText: 'اكتب رسالة...',
                              filled: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_hasText || !VoiceRecorderController.supported)
                          IconButton.filled(
                            tooltip: 'إرسال',
                            onPressed: _hasText ? _send : null,
                            icon: const Icon(Icons.send_rounded),
                          )
                        else
                          IconButton.filled(
                            tooltip: 'تسجيل صوتي',
                            onPressed: _startRecording,
                            icon: const Icon(Icons.mic_rounded),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة مرفق لسه بيترفع: أيقونة + اسم + شريط تقدم، أو زرار إعادة المحاولة لو فشل
class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.upload,
    required this.onRetry,
    required this.onDismiss,
  });
  final _Upload upload;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  IconData get _icon {
    switch (upload.media.type) {
      case MessageType.image:
        return Icons.image_rounded;
      case MessageType.video:
        return Icons.videocam_rounded;
      case MessageType.audio:
        return Icons.mic_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: upload.failed
              ? Border.all(color: scheme.error.withValues(alpha: 0.6))
              : null,
        ),
        child: Row(
          children: [
            Icon(_icon, color: scheme.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    upload.media.type == MessageType.audio
                        ? 'رسالة صوتية'
                        : upload.media.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  if (upload.failed)
                    Text(
                      upload.error ?? 'فشل الإرسال',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.error, fontSize: 12),
                    )
                  else
                    LinearProgressIndicator(
                      value: upload.progress == 0 ? null : upload.progress,
                      borderRadius: BorderRadius.circular(4),
                    ),
                ],
              ),
            ),
            if (upload.failed)
              IconButton(
                tooltip: 'إعادة المحاولة',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
            IconButton(
              tooltip: 'إلغاء',
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
