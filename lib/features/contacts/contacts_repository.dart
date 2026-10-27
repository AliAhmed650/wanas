import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chats/data/chat_repository.dart';

class Contact {
  Contact({required this.uid, required this.savedName});
  final String uid;
  final String savedName;
}

class ContactsRepository {
  CollectionReference<Map<String, dynamic>> _col(String me) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('contacts');

  Stream<List<Contact>> watch(String me) => _col(me).snapshots().map((s) {
        final list = s.docs
            .map((d) => Contact(
                  uid: d.id,
                  savedName: (d.data()['savedName'] ?? '') as String,
                ))
            .toList();
        list.sort((a, b) =>
            a.savedName.toLowerCase().compareTo(b.savedName.toLowerCase()));
        return list;
      });

  // حفظ جهة اتصال أو تغيير اسمها
  Future<void> save(String me, String uid, String name) => _col(me).doc(uid).set(
        {'savedName': name, 'addedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

  Future<void> remove(String me, String uid) => _col(me).doc(uid).delete();
}

final contactsRepositoryProvider = Provider((ref) => ContactsRepository());

final contactsProvider = StreamProvider.autoDispose<List<Contact>>((ref) {
  final me = FirebaseAuth.instance.currentUser!.uid;
  return ref.watch(contactsRepositoryProvider).watch(me);
});

// بيانات مستخدم واحد (الصورة والنبذة) بالـ uid
final userByIdProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((d) => d.data() == null ? null : AppUser.fromMap(d.data()!));
});