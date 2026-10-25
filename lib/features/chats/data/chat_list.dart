import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatSummary {
  ChatSummary({
    required this.chatId,
    required this.otherUid,
    required this.lastMessage,
    required this.lastSenderId,
    this.updatedAt,
  });

  final String chatId;
  final String otherUid;
  final String lastMessage;
  final String lastSenderId;
  final DateTime? updatedAt;
}

final chatListProvider = StreamProvider.autoDispose<List<ChatSummary>>((ref) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance
      .collection('chats')
      .where('participants', arrayContains: uid)
      .snapshots()
      .map((snap) {
        final list = snap.docs
            .map((d) {
              final m = d.data();
              final parts = List<String>.from(m['participants'] ?? []);
              final other = parts.firstWhere((p) => p != uid, orElse: () => '');
              return ChatSummary(
                chatId: d.id,
                otherUid: other,
                lastMessage: m['lastMessage'] ?? '',
                lastSenderId: m['lastSenderId'] ?? '',
                updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
              );
            })
            .where((c) => c.otherUid.isNotEmpty)
            .toList();
        // الترتيب في التطبيق بدل Firestore عشان منحتاجش index
        final now = DateTime.now();
        list.sort((a, b) => (b.updatedAt ?? now).compareTo(a.updatedAt ?? now));
        return list;
      });
});
