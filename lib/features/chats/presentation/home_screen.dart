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
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'مفيش محادثات لسه.\nاضغط على القلم تحت وابدأ محادثة 👋',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
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

    return ListTile(
      leading: UserAvatar(name: name, photoB64: other?.photoB64),
      title: Text(name),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        time,
        style: Theme.of(context).textTheme.labelSmall,
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