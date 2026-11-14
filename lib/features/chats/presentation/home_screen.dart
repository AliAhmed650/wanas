import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../contacts/contacts_repository.dart';
import '../../profile/presentation/profile_screen.dart';
import '../data/chat_list.dart';
import '../data/chat_repository.dart';
import 'chat_screen.dart';
import 'users_screen.dart';
import '../../calls/data/call_repository.dart';
import '../../calls/presentation/incoming_call_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _time(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) {
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${t.day}/${t.month}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatListProvider);
    final contacts = ref.watch(contactsProvider).value ?? <Contact>[];
    final savedNames = {for (final c in contacts) c.uid: c.savedName};
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    ref.listen<AsyncValue<Call?>>(incomingCallProvider, (prev, next) {
      final call = next.value;
      if (call != null && prev?.value?.id != call.id) {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => IncomingCallScreen(call: call),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('ونس'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('متأكد إنك عايز تخرج من حسابك؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('خروج'),
                    ),
                  ],
                ),
              );
              if (ok == true) ref.read(authRepositoryProvider).signOut();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const UsersScreen())),
        child: const Icon(Icons.edit_rounded),
      ),
      body: chats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('خطأ: $e')),
        data: (list) {
          if (list.isEmpty) {
            final scheme = Theme.of(context).colorScheme;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 72,
                      color: scheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'مفيش محادثات لسه',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'اضغط على القلم تحت وابدأ محادثة 👋',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              indent: 80,
              endIndent: 16,
            ),
            itemBuilder: (context, i) {
              final c = list[i];
              return _ChatTile(
                chat: c,
                savedName: savedNames[c.otherUid],
                myUid: myUid,
                time: _time(c.updatedAt),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({
    required this.chat,
    required this.savedName,
    required this.myUid,
    required this.time,
  });

  final ChatSummary chat;
  final String? savedName;
  final String myUid;
  final String time;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // بنجيب بيانات الشخص ده بس (مش كل المستخدمين)
    final other = ref.watch(userByIdProvider(chat.otherUid)).value;
    final name = (savedName != null && savedName!.isNotEmpty)
        ? savedName!
        : (other == null
            ? '...'
            : (other.name.isEmpty ? 'مستخدم' : other.name));
    final preview =
        chat.lastSenderId == myUid ? 'أنت: ${chat.lastMessage}' : chat.lastMessage;

    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: UserAvatar(name: name, photoB64: other?.photoB64, radius: 26),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        time,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.outline),
      ),
      onTap: other == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    other: AppUser(
                      uid: other.uid,
                      name: name,
                      email: '',
                      bio: other.bio,
                      photoB64: other.photoB64,
                    ),
                  ),
                ),
              ),
    );
  }
}