import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../chats/data/chat_repository.dart';

class ProfileRepository {
  Stream<AppUser?> watchMe() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((d) => d.data() == null ? null : AppUser.fromMap(d.data()!));
  }

  Future<void> save({
    required String name,
    required String bio,
    String? photoB64,
  }) async {
    final user = FirebaseAuth.instance.currentUser!;
    await user.updateDisplayName(name);
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'name': name,
      'bio': bio,
      'photoB64': ?photoB64,
    }, SetOptions(merge: true));
  }
}

final profileRepositoryProvider = Provider((ref) => ProfileRepository());

final myProfileProvider = StreamProvider.autoDispose<AppUser?>(
  (ref) => ref.watch(profileRepositoryProvider).watchMe(),
);
