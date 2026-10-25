import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/user_avatar.dart';
import '../data/chat_repository.dart';
import 'chat_screen.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('محادثة جديدة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: users.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('خطأ: $e')),
              data: (all) {
                final list = all
                    .where((u) => u.name.toLowerCase().contains(_query))
                    .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        all.isEmpty
                            ? 'مفيش مستخدمين تانيين لسه.'
                            : 'مفيش نتايج للبحث ده.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final u = list[i];
                    final name = u.name.isEmpty ? 'مستخدم' : u.name;
                    return ListTile(
                      leading:
                          UserAvatar(name: name, photoB64: u.photoB64),
                      title: Text(name),
                      subtitle: u.bio.isEmpty
                          ? null
                          : Text(u.bio,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(other: u)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}