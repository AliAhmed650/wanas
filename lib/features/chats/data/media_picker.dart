import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'media_service.dart';

/// اختيار الصور والفيديوهات والملفات وتحويلها لـ [PickedMedia] جاهزة للرفع
class MediaPicker {
  final ImagePicker _picker = ImagePicker();

  Future<PickedMedia> _fromXFile(XFile x, MessageType type) async {
    final name = x.name.isNotEmpty ? x.name : x.path.split('/').last;
    return PickedMedia(
      name: name,
      type: type,
      size: await x.length(),
      readBytes: () => x.readAsBytes(),
      path: x.path,
      mime: x.mimeType ?? guessMime(name, type),
    );
  }

  /// صور من المعرض (أكتر من صورة). بنصغّرها شوية عشان الرفع يبقى أسرع
  Future<List<PickedMedia>> pickImages() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    return [for (final x in files) await _fromXFile(x, MessageType.image)];
  }

  Future<PickedMedia?> takePhoto() async {
    final x = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    return x == null ? null : _fromXFile(x, MessageType.image);
  }

  Future<PickedMedia?> pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    return x == null ? null : _fromXFile(x, MessageType.video);
  }

  Future<PickedMedia?> recordVideo() async {
    final x = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 3),
    );
    return x == null ? null : _fromXFile(x, MessageType.video);
  }

  /// أي نوع ملف (PDF، Word، zip، ...)
  Future<List<PickedMedia>> pickFiles() async {
    final files = await FilePicker.pickFiles();
    final out = <PickedMedia>[];
    for (final f in files) {
      final size = await f.length();
      out.add(
        PickedMedia(
          name: f.name,
          type: MessageType.file,
          size: size,
          readBytes: () async => Uint8List.fromList(await f.readAsBytes()),
          mime: guessMime(f.name, MessageType.file),
        ),
      );
    }
    return out;
  }
}
