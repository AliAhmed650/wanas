import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../chats/data/chat_repository.dart';

/// بيحوّل أي صيغة رقم لأرقام بس مع كود الدولة (مصر هي الافتراضي).
String? normalizePhone(String input) {
  var s = input.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('+')) {
    s = s.substring(1);
  } else if (s.startsWith('00')) {
    s = s.substring(2);
  } else if (s.startsWith('0')) {
    s = '20${s.substring(1)}';
  } else if (s.length == 10 && s.startsWith('1')) {
    s = '20$s';
  }
  if (!RegExp(r'^\d{8,15}$').hasMatch(s)) return null;
  return s;
}

String _hash(String digits) =>
    sha256.convert(utf8.encode('wanas:$digits')).toString();

class PhoneRepository {
  final _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _mine(String me) =>
      _db.collection('users').doc(me).collection('private').doc('phone');

  Stream<String?> watchMine(String me) =>
      _mine(me).snapshots().map((d) => d.data()?['digits'] as String?);

  /// تسجيل رقمي (أو تغييره)
  Future<void> saveMine(String me, String input) async {
    final digits = normalizePhone(input);
    if (digits == null) throw Exception('الرقم مش صحيح');
    final h = _hash(digits);
    final newRef = _db.collection('phones').doc(h);
    await _db.runTransaction((tx) async {
      final mineSnap = await tx.get(_mine(me));
      final existing = await tx.get(newRef);
      if (existing.exists && existing.data()?['uid'] != me) {
        throw Exception('الرقم ده مستخدم في حساب تاني');
      }
      final oldHash = mineSnap.data()?['hash'] as String?;
      if (oldHash != null && oldHash != h) {
        tx.delete(_db.collection('phones').doc(oldHash));
      }
      tx.set(newRef, {'uid': me});
      tx.set(_mine(me), {'digits': digits, 'hash': h});
    });
  }

  /// دوّر على مستخدم برقمه
  Future<AppUser?> findByPhone(String input) async {
    final digits = normalizePhone(input);
    if (digits == null) return null;
    final doc = await _db.collection('phones').doc(_hash(digits)).get();
    if (!doc.exists) return null;
    final uid = doc.data()?['uid'] as String?;
    if (uid == null) return null;
    final u = await _db.collection('users').doc(uid).get();
    if (!u.exists || u.data() == null) return null;
    return AppUser.fromMap(u.data()!);
  }
}

final phoneRepositoryProvider = Provider((ref) => PhoneRepository());

final myPhoneProvider = StreamProvider.autoDispose<String?>((ref) {
  final me = FirebaseAuth.instance.currentUser!.uid;
  return ref.watch(phoneRepositoryProvider).watchMine(me);
});