import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../calls/agora_config.dart';

/// بينادي على سيرفر ونس (Vercel) عشان يبعت إشعار للطرف التاني.
/// بيتنادى بعد ما الرسالة/المكالمة تتكتب في Firestore. لو فشل مبنوقفش حاجة،
/// الرسالة نفسها وصلت والإشعار بس هو اللي مش هيظهر.
class NotifyApi {
  static String get _url => tokenServerUrl.replaceFirst('/token', '/notify');

  static Future<void> message({
    required String toUid,
    required String chatId,
  }) =>
      _post({'type': 'message', 'toUid': toUid, 'chatId': chatId});

  static Future<void> call({
    required String toUid,
    required String callId,
  }) =>
      _post({'type': 'call', 'toUid': toUid, 'callId': callId});

  static Future<void> _post(Map<String, String> body) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      final res = await http
          .post(
            Uri.parse(_url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('notify failed ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('notify error: $e');
    }
  }
}
