import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../chats/data/chat_repository.dart';
import '../chats/presentation/chat_screen.dart';

/// مفتاح الـ Navigator العام عشان نفتح شاشة المحادثة لما المستخدم يضغط على إشعار
final navigatorKey = GlobalKey<NavigatorState>();

/// تسجيل توكن الجهاز في Firestore واستقبال الضغط على الإشعارات.
/// الإشعارات نفسها بتتعرض من النظام (الرسالة من السيرفر فيها notification)،
/// فمش محتاجين نعمل حاجة والتطبيق مقفول أو في الخلفية.
class NotificationService {
  static final _fm = FirebaseMessaging.instance;
  static final _db = FirebaseFirestore.instance;

  static StreamSubscription<String>? _refreshSub;
  static StreamSubscription<RemoteMessage>? _openedSub;
  static String? _token;
  static bool _initialHandled = false;

  /// بيتنادى بعد تسجيل الدخول (آمن لو اتنادى أكتر من مرة)
  static Future<void> init(String uid) async {
    try {
      final settings = await _fm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await _fm.getToken();
      if (token != null) await _save(uid, token);

      await _refreshSub?.cancel();
      _refreshSub = _fm.onTokenRefresh.listen((t) => _save(uid, t));

      await _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_open);

      // لو التطبيق اتفتح من إشعار وهو مقفول تمامًا
      if (!_initialHandled) {
        _initialHandled = true;
        final initial = await _fm.getInitialMessage();
        if (initial != null) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          await _open(initial);
        }
      }
    } catch (e) {
      debugPrint('notifications init failed: $e');
    }
  }

  static Future<void> _save(String uid, String token) async {
    _token = token;
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// بيتنادى قبل تسجيل الخروج: بنشيل توكن الجهاز ده من الحساب،
  /// عشان إشعارات الحساب ده ماتوصلش لمين يدخل بعده من نفس الموبايل
  static Future<void> clear(String uid) async {
    try {
      await _refreshSub?.cancel();
      _refreshSub = null;
      await _openedSub?.cancel();
      _openedSub = null;
      final t = _token ?? await _fm.getToken();
      if (t != null) {
        await _db.collection('users').doc(uid).update({
          'fcmTokens': FieldValue.arrayRemove([t]),
        });
      }
      _token = null;
    } catch (e) {
      debugPrint('notifications clear failed: $e');
    }
  }

  /// الضغط على إشعار رسالة بيفتح المحادثة. إشعار المكالمة بيفتح التطبيق،
  /// وشاشة المكالمة الواردة بتظهر لوحدها لو المكالمة لسه بترن
  static Future<void> _open(RemoteMessage m) async {
    final data = m.data;
    if (data['type'] != 'message') return;
    final fromUid = data['fromUid'];
    if (fromUid == null || fromUid.isEmpty) return;
    try {
      final doc = await _db.collection('users').doc(fromUid).get();
      final map = doc.data();
      if (map == null) return;
      final other = AppUser.fromMap({...map, 'uid': fromUid});
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ChatScreen(other: other)),
      );
    } catch (e) {
      debugPrint('open chat from notification failed: $e');
    }
  }
}
