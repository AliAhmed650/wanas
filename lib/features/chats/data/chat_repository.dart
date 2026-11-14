import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'media_service.dart';

class AppUser {
  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.bio = '',
    this.photoB64,
  });

  final String uid;
  final String name;
  final String email;
  final String bio;
  final String? photoB64;

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
    uid: m['uid'] ?? '',
    name: m['name'] ?? '',
    email: m['email'] ?? '',
    bio: m['bio'] ?? '',
    photoB64: m['photoB64'],
  );
}

class Message {
  Message({
    required this.id,
    required this.senderId,
    required this.text,
    this.createdAt,
    this.status = 'sent',
    this.pending = false,
    this.edited = false,
    this.type = MessageType.text,
    this.url,
    this.fileName,
    this.fileSize,
    this.durationMs,
  });

  final String id;
  final String senderId;
  final String text; // نص الرسالة، أو الكابشن لو مرفق
  final DateTime? createdAt;
  final String status; // sent | read
  final bool pending; // لسه ماوصلش السيرفر
  final bool edited; // اتعدّلت بعد الإرسال
  final MessageType type;
  final String? url; // رابط المرفق (لو الرسالة ميديا)
  final String? fileName;
  final int? fileSize;
  final int? durationMs; // مدة الرسالة الصوتية

  bool get isMedia => type != MessageType.text;

  factory Message.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return Message(
      id: d.id,
      senderId: m['senderId'] ?? '',
      text: m['text'] ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      status: m['status'] ?? 'sent',
      pending: d.metadata.hasPendingWrites,
      edited: m['edited'] == true,
      type: messageTypeFromString(m['type'] as String?),
      url: m['url'] as String?,
      fileName: m['fileName'] as String?,
      fileSize: (m['fileSize'] as num?)?.toInt(),
      durationMs: (m['durationMs'] as num?)?.toInt(),
    );
  }
}

/// المعاينة اللي بتظهر في قايمة المحادثات لآخر رسالة
String previewFor(MessageType type, String text, {String? fileName}) {
  switch (type) {
    case MessageType.text:
      return text;
    case MessageType.image:
      return text.isEmpty ? '📷 صورة' : '📷 $text';
    case MessageType.video:
      return text.isEmpty ? '🎥 فيديو' : '🎥 $text';
    case MessageType.audio:
      return '🎤 رسالة صوتية';
    case MessageType.file:
      return '📎 ${fileName ?? 'ملف'}';
  }
}

class ChatRepository {
  ChatRepository(this._db);
  final FirebaseFirestore _db;

  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  Stream<List<AppUser>> usersStream(String myUid) {
    return _db
        .collection('users')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => AppUser.fromMap(d.data()))
              .where((u) => u.uid != myUid)
              .toList(),
        );
  }

  Stream<List<Message>> messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.docs.map(Message.fromDoc).toList());
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final batch = _db.batch();
    batch.set(chatRef.collection('messages').doc(), {
      'senderId': senderId,
      'text': text,
      'status': 'sent',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(chatRef, {
      'participants': [senderId, receiverId],
      'lastMessage': text,
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// بيبعت رسالة مرفق (صورة/فيديو/صوت/ملف) بعد ما الرفع يخلص
  Future<void> sendMedia({
    required String chatId,
    required String senderId,
    required String receiverId,
    required MessageType type,
    required String url,
    required String storagePath,
    required String fileName,
    required int fileSize,
    String caption = '',
    int? durationMs,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final batch = _db.batch();
    batch.set(chatRef.collection('messages').doc(), {
      'senderId': senderId,
      'type': type.name,
      'text': caption,
      'url': url,
      'storagePath': storagePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'durationMs': ?durationMs,
      'status': 'sent',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(chatRef, {
      'participants': [senderId, receiverId],
      'lastMessage': previewFor(type, caption, fileName: fileName),
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// تعديل نص رسالة بعتّها. لو هي آخر رسالة بنحدّث معاينة قايمة المحادثات كمان
  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String text,
    required bool isLast,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final batch = _db.batch();
    batch.update(chatRef.collection('messages').doc(messageId), {
      'text': text,
      'edited': true,
    });
    if (isLast) {
      batch.update(chatRef, {'lastMessage': text});
    }
    await batch.commit();
  }

  /// علّم رسايل الطرف التاني كمقروءة
  Future<void> markRead(
    String chatId,
    String myUid,
    List<Message> messages,
  ) async {
    final unread = messages.where(
      (m) => m.senderId != myUid && m.status != 'read',
    );
    if (unread.isEmpty) return;
    final col = _db.collection('chats').doc(chatId).collection('messages');
    final batch = _db.batch();
    for (final m in unread) {
      batch.update(col.doc(m.id), {'status': 'read'});
    }
    await batch.commit();
  }

  Future<void> setTyping(String chatId, String myUid, bool typing) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(myUid)
        .set({'typing': typing, 'at': FieldValue.serverTimestamp()});
  }

  Stream<bool> typingStream(String chatId, String otherUid) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(otherUid)
        .snapshots()
        .map((d) {
          final m = d.data();
          if (m == null || m['typing'] != true) return false;
          final at = (m['at'] as Timestamp?)?.toDate();
          if (at == null) return true;
          return DateTime.now().difference(at).inSeconds < 10;
        });
  }
}

final chatRepositoryProvider = Provider(
  (ref) => ChatRepository(FirebaseFirestore.instance),
);

final usersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return ref.watch(chatRepositoryProvider).usersStream(uid);
});

final messagesProvider = StreamProvider.autoDispose
    .family<List<Message>, String>((ref, chatId) {
      return ref.watch(chatRepositoryProvider).messagesStream(chatId);
    });

final typingProvider = StreamProvider.autoDispose
    .family<bool, ({String chatId, String otherUid})>((ref, a) {
      return ref
          .watch(chatRepositoryProvider)
          .typingStream(a.chatId, a.otherUid);
    });