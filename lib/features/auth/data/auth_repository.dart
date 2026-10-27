import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthRepository {
  AuthRepository(this._auth, this._db);
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authStateChanges() => _auth.authStateChanges().map((u) {
        if (u != null) _ensureSearchField(u);
        return u;
      });

  // الحسابات القديمة بتاخد حقل البحث تلقائياً أول ما صاحبها يفتح التطبيق
  Future<void> _ensureSearchField(User u) async {
    final name = (u.displayName ?? '').trim();
    if (name.isEmpty) return;
    try {
      await _db.collection('users').doc(u.uid).set(
        {'nameLower': name.toLowerCase()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<void> signUp(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    final user = cred.user!;
    await user.updateDisplayName(name);
    // الإيميل مش بيتخزّن في Firestore (خصوصية)، بيفضل في Authentication بس
    await _db.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name,
      'nameLower': name.trim().toLowerCase(),
      'bio': '',
      'photoUrl': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(FirebaseAuth.instance, FirebaseFirestore.instance),
);

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);