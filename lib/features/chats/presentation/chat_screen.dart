import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/chat_repository.dart';
import '../../calls/data/call_repository.dart';
import '../../calls/presentation/call_screen.dart';

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

  Timer? _typingTimer;
  bool _isTyping = false;

  @override
  void dispose() {
    _typingTimer?.cancel();
    if (_isTyping) _repo.setTyping(_chatId, _myUid, false);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
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
    _stopTyping();
    await _repo.sendMessage(
      chatId: _chatId,
      senderId: _myUid,
      receiverId: widget.other.uid,
      text: text,
    );
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
    final mine = msg.senderId == _myUid;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('نسخ'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: msg.text));
              },
            ),
            if (mine)
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

  String _time(DateTime? t) {
    if (t == null) return '';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _ticks(Message m, ColorScheme scheme) {
    if (m.pending) {
      return Icon(Icons.access_time, size: 14, color: scheme.outline);
    }
    if (m.status == 'read') {
      return Icon(Icons.done_all, size: 16, color: scheme.primary);
    }
    return Icon(Icons.done, size: 16, color: scheme.outline);
  }

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
                if (list.isEmpty) {
                  return const Center(child: Text('ابدأ المحادثة 👋'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final msg = list[i];
                    final mine = msg.senderId == _myUid;
                    final isLast = i == 0; // القايمة مرتبة من الأحدث
                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _onLongPress(msg, isLast),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: mine
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(msg.text),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (msg.edited)
                                    Text(
                                      'معدّلة · ',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: scheme.outline),
                                    ),
                                  Text(
                                    _time(msg.createdAt),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(color: scheme.outline),
                                  ),
                                  if (mine) ...[
                                    const SizedBox(width: 4),
                                    _ticks(msg, scheme),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
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
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
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