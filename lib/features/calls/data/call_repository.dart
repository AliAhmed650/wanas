import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Call {
  Call({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.callerName,
    required this.video,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String callerId;
  final String calleeId;
  final String callerName;
  final bool video;
  final String status; // ringing | accepted | declined | ended | missed
  final DateTime? createdAt;

  factory Call.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Call(
      id: d.id,
      callerId: m['callerId'] ?? '',
      calleeId: m['calleeId'] ?? '',
      callerName: m['callerName'] ?? '',
      video: m['video'] ?? false,
      status: m['status'] ?? 'ended',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class CallRepository {
  final _col = FirebaseFirestore.instance.collection('calls');

  Future<String> startCall({
    required String calleeId,
    required String callerName,
    required bool video,
  }) async {
    final me = FirebaseAuth.instance.currentUser!;
    final ref = _col.doc();
    await ref.set({
      'callerId': me.uid,
      'calleeId': calleeId,
      'callerName': callerName,
      'video': video,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setStatus(String callId, String status) async {
    try {
      await _col.doc(callId).update({'status': status});
    } catch (_) {}
  }

  Stream<Call?> watchCall(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Call.fromDoc(d) : null);

  /// أحدث مكالمة بترن عندي (وعمرها أقل من دقيقة)
  Stream<Call?> incomingCalls(String myUid) {
    return _col
        .where('calleeId', isEqualTo: myUid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      final fresh = snap.docs
          .map(Call.fromDoc)
          .where((c) =>
              c.createdAt == null ||
              now.difference(c.createdAt!).inSeconds < 60)
          .toList();
      return fresh.isEmpty ? null : fresh.first;
    });
  }
}

final callRepositoryProvider = Provider((ref) => CallRepository());

final incomingCallProvider = StreamProvider.autoDispose<Call?>((ref) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return ref.watch(callRepositoryProvider).incomingCalls(uid);
});

final callProvider =
    StreamProvider.autoDispose.family<Call?, String>((ref, id) {
  return ref.watch(callRepositoryProvider).watchCall(id);
});