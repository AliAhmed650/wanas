import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../contacts/contacts_repository.dart';
import '../../contacts/phone_repository.dart';
import '../../contacts/phone_screen.dart';
import '../data/chat_repository.dart';
import '../data/user_search.dart';
import 'chat_screen.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  late final String _me = FirebaseAuth.instance.currentUser!.uid;
  Timer? _debounce;
  int _seq = 0;
  String _query = '';
  bool _phoneMode = false;
  bool _loading = false;
  String? _error;
  List<AppUser> _results = [];

  bool get _searching => _phoneMode || _query.length >= 2;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _looksLikePhone(String q) =>
      RegExp(r'^[+\d][\d\s\-]{6,}$').hasMatch(q) && normalizePhone(q) != null;

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    final phone = _looksLikePhone(q);
    if (!phone && q.length < 2) {
      _seq++;
      setState(() {
        _query = q;
        _phoneMode = false;
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _phoneMode = phone;
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final seq = ++_seq;
      try {
        List<AppUser> r;
        if (phone) {
          final u = await ref.read(phoneRepositoryProvider).findByPhone(q);
          r = (u == null || u.uid == _me) ? [] : [u];
        } else {
          r = await searchUsers(q);
        }
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = r;
          _loading = false;
          _error = null;
        });
      } catch (e) {
        if (!mounted || seq != _seq) return;
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    });
  }

  void _openChat(AppUser u) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ChatScreen(other: u)),
    );
  }

  // حفظ جهة اتصال بالاسم اللي تختاره
  Future<void> _saveContact(AppUser u) async {
    final ctrl = TextEditingController(text: u.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ جهة اتصال'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'الاسم'),
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
    if (name == null || name.isEmpty) return;
    await ref.read(contactsRepositoryProvider).save(_me, u.uid, name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ $name في جهات الاتصال')),
    );
  }

  // ضغطة مطولة على جهة اتصال: تغيير الاسم أو الحذف
  void _contactMenu(Contact c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تغيير الاسم'),
              onTap: () {
                Navigator.pop(ctx);
                _renameContact(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove),
              title: const Text('حذف من جهات الاتصال'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(contactsRepositoryProvider).remove(_me, c.uid);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameContact(Contact c) async {
    final ctrl = TextEditingController(text: c.savedName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم جهة الاتصال'),
        content: TextField(controller: ctrl, autofocus: true, maxLength: 40),
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
    if (newName == null || newName.isEmpty) return;
    await ref.read(contactsRepositoryProvider).save(_me, c.uid, newName);
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );

  Widget _phoneBanner() => Card(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ListTile(
          leading: const Icon(Icons.phone_android),
          title: const Text('اربط رقم تليفونك'),
          subtitle: const Text('عشان أصحابك يقدروا يضيفوك برقمك'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PhoneScreen()),
          ),
        ),
      );

  // الوضع العادي: جهات الاتصال المحفوظة بس
  Widget _contactsBody() {
    final contacts = ref.watch(contactsProvider);
    return contacts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _message('خطأ: $e'),
      data: (list) {
        if (list.isEmpty) {
          return _message(
              'مفيش جهات اتصال محفوظة لسه.\nاكتب رقم صاحبك أو اسمه في البحث واضغط حفظ 🔍');
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final c = list[i];
            return _ContactTile(
              contact: c,
              onOpen: (user, name) => _openChat(AppUser(
                uid: user.uid,
                name: name,
                email: '',
                bio: user.bio,
                photoB64: user.photoB64,
              )),
              onMenu: () => _contactMenu(c),
            );
          },
        );
      },
    );
  }

  // وضع البحث (بالاسم أو بالرقم)
  Widget _searchBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _message('خطأ: $_error');
    if (_results.isEmpty) {
      return _message(_phoneMode
          ? 'مفيش حد مسجّل بالرقم ده في ونس.'
          : 'مفيش نتايج للبحث ده.');
    }
    final saved =
        (ref.watch(contactsProvider).value ?? []).map((c) => c.uid).toSet();
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final u = _results[i];
        final name = u.name.isEmpty ? 'مستخدم' : u.name;
        final isSaved = saved.contains(u.uid);
        return ListTile(
          leading: UserAvatar(name: name, photoB64: u.photoB64),
          title: Text(name),
          subtitle: u.bio.isEmpty
              ? null
              : Text(u.bio, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: isSaved
              ? const Icon(Icons.check_circle, color: Colors.green)
              : IconButton(
                  tooltip: 'حفظ في جهات الاتصال',
                  icon: const Icon(Icons.person_add_alt_1),
                  onPressed: () => _saveContact(u),
                ),
          onTap: () => _openChat(u),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final banner = ref
        .watch(myPhoneProvider)
        .whenOrNull(data: (p) => p == null ? _phoneBanner() : null);
    return Scaffold(
      appBar: AppBar(title: const Text('محادثة جديدة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو برقم التليفون...',
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
                    ?banner,
          Expanded(child: _searching ? _searchBody() : _contactsBody()),
        ],
      ),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  const _ContactTile({
    required this.contact,
    required this.onOpen,
    required this.onMenu,
  });

  final Contact contact;
  final void Function(AppUser user, String name) onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByIdProvider(contact.uid)).value;
    final name = contact.savedName.isNotEmpty
        ? contact.savedName
        : (user?.name ?? 'مستخدم');
    return ListTile(
      leading: UserAvatar(name: name, photoB64: user?.photoB64),
      title: Text(name),
      subtitle: (user == null || user.bio.isEmpty)
          ? null
          : Text(user.bio, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: user == null ? null : () => onOpen(user, name),
      onLongPress: onMenu,
    );
  }
}