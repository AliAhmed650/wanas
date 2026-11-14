import 'dart:io' show File;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';

/// أنواع الرسايل اللي التطبيق بيدعمها
enum MessageType { text, image, video, audio, file }

MessageType messageTypeFromString(String? s) {
  for (final t in MessageType.values) {
    if (t.name == s) return t;
  }
  return MessageType.text;
}

/// الحد الأقصى لحجم أي مرفق (بالبايت). وده نفس حد الـ bucket في Supabase (50 ميجا)
const int kMaxUploadBytes = 50 * 1024 * 1024;

/// ملف جاهز للرفع: اسم + نوع + حجم + طريقة لقراءة البيانات.
/// على الموبايل لو معانا path بنرفع من الملف مباشرة (أوفر للذاكرة من الفيديوهات الكبيرة)
class PickedMedia {
  PickedMedia({
    required this.name,
    required this.type,
    required this.size,
    required this.readBytes,
    this.path,
    this.mime,
    this.durationMs,
  });

  final String name;
  final MessageType type;
  final int size;
  final Future<Uint8List> Function() readBytes;
  final String? path;
  final String? mime;
  final int? durationMs;
}

class UploadedMedia {
  UploadedMedia({required this.url, required this.storagePath});
  final String url;
  final String storagePath;
}

/// نوع المحتوى (content-type) من امتداد الملف. بنغطي الأنواع الشائعة وغير كده octet-stream
String guessMime(String name, MessageType type) {
  final dot = name.lastIndexOf('.');
  final ext = dot == -1 ? '' : name.substring(dot + 1).toLowerCase();
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4v': 'video/x-m4v',
    '3gp': 'video/3gpp',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'zip': 'application/zip',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx':
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };
  final m = map[ext];
  if (m != null) return m;
  switch (type) {
    case MessageType.image:
      return 'image/jpeg';
    case MessageType.video:
      return 'video/mp4';
    case MessageType.audio:
      return 'audio/mp4';
    default:
      return 'application/octet-stream';
  }
}

/// اسم ملف آمن للمسار في Storage: حروف إنجليزي وأرقام ونقط وشرطات بس
/// (Supabase بيرفض الحروف العربية والرموز في مفاتيح الملفات).
/// الاسم الأصلي بيتحفظ لوحده في حقل fileName جوه الرسالة.
String _safeName(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot == -1
      ? ''
      : name.substring(dot).replaceAll(RegExp(r'[^A-Za-z0-9.]'), '');
  final base = (dot == -1 ? name : name.substring(0, dot))
      .replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
  final trimmed = base.length > 40 ? base.substring(0, 40) : base;
  return '${trimmed.isEmpty ? 'file' : trimmed}$ext';
}

String _randomToken() {
  final r = Random.secure();
  return List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
}

/// رفع المرفقات على Supabase Storage عن طريق REST مباشرة (من غير حزمة Supabase)
class MediaService {
  MediaService() : _dio = Dio();
  final Dio _dio;

  /// بيرفع الملف على chats/{chatId}/... وبيبلّغ بالتقدم (0..1) على [onProgress]
  Future<UploadedMedia> upload({
    required String chatId,
    required PickedMedia media,
    void Function(double progress)? onProgress,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw Exception('Supabase مش متظبط: عدّل lib/core/config/supabase_config.dart');
    }
    if (media.size > kMaxUploadBytes) {
      throw Exception(
        'الملف أكبر من ${kMaxUploadBytes ~/ (1024 * 1024)} ميجا',
      );
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    // التوكن العشوائي بيخلّي رابط الملف مستحيل يتخمّن
    final storagePath =
        'chats/$chatId/${ts}_${_randomToken()}_${_safeName(media.name)}';
    final mime = media.mime ?? guessMime(media.name, media.type);
    final base = '${SupabaseConfig.url}/storage/v1/object';

    final Object body;
    final headers = <String, Object>{
      'apikey': SupabaseConfig.anonKey,
      // المفاتيح الجديدة (sb_publishable_...) بتتبعت في apikey بس.
      // الـ Bearer للمفاتيح القديمة (JWT بيبدأ بـ eyJ) بس.
      if (SupabaseConfig.anonKey.startsWith('eyJ'))
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      'x-upsert': 'false',
      'Cache-Control': 'max-age=31536000',
    };
    if (!kIsWeb && media.path != null) {
      // على الموبايل بنبعت الملف stream من غير ما نحمّله كله في الذاكرة
      body = File(media.path!).openRead();
      headers['Content-Length'] = media.size;
    } else {
      body = await media.readBytes();
    }

    try {
      await _dio.post<void>(
        '$base/${SupabaseConfig.bucket}/$storagePath',
        data: body,
        options: Options(headers: headers, contentType: mime),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress?.call(sent / total);
        },
      );
    } on DioException catch (e) {
      throw Exception(_describe(e));
    }

    final url =
        '$base/public/${SupabaseConfig.bucket}/$storagePath';
    return UploadedMedia(url: url, storagePath: storagePath);
  }

  String _describe(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    final msg = data is Map ? (data['message'] ?? data['error']) : null;
    if (code == 400 && '$msg'.contains('Bucket not found')) {
      return 'الـ bucket "${SupabaseConfig.bucket}" مش موجود في Supabase';
    }
    if (code == 401 || code == 403) {
      return 'Supabase رفض الرفع (سياسة الـ bucket أو المفتاح): ${msg ?? code}';
    }
    if (code == 413) return 'الملف أكبر من الحد المسموح في Supabase';
    if (code != null) return 'فشل الرفع ($code): ${msg ?? ''}';
    return 'فشل الاتصال بالسيرفر، اتأكد من النت';
  }
}

final mediaServiceProvider = Provider((ref) => MediaService());

/// حجم مقروء: 1.2 MB / 340 KB
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// مدة مقروءة: 0:07 / 1:05
String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
