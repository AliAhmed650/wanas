import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_repository.dart';

Future<QuerySnapshot<Map<String, dynamic>>> _prefix(String field, String q) {
  return FirebaseFirestore.instance
      .collection('users')
      .where(field, isGreaterThanOrEqualTo: q)
      .where(field, isLessThan: '$q\uf8ff')
      .limit(20)
      .get();
}

/// بحث بالاسم (من أول الاسم). مفيش قايمة مستخدمين بتتعرض غير نتايج البحث.
/// بيدوّر على الحقل الجديد وعلى الاسم الأصلي، فيلاقي الحسابات القديمة كمان.
Future<List<AppUser>> searchUsers(String query) async {
  final raw = query.trim();
  if (raw.length < 2) return [];
  final me = FirebaseAuth.instance.currentUser?.uid;

  final lower = raw.toLowerCase();
  final cap = lower[0].toUpperCase() + lower.substring(1);

  final snaps = await Future.wait([
    _prefix('nameLower', lower),
    _prefix('name', raw),
    if (cap != raw) _prefix('name', cap),
    if (lower != raw) _prefix('name', lower),
  ]);

  final byUid = <String, AppUser>{};
  for (final s in snaps) {
    for (final d in s.docs) {
      final u = AppUser.fromMap(d.data());
      if (u.uid.isNotEmpty && u.uid != me) byUid[u.uid] = u;
    }
  }
  return byUid.values.take(20).toList();
}