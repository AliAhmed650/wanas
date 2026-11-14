import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// عرض صورة بملء الشاشة مع تكبير بالأصابع
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.url, this.heroTag});
  final String url;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    Widget img = InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 64,
          ),
        ),
      ),
    );
    if (heroTag != null) img = Hero(tag: heroTag!, child: img);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: img,
    );
  }
}

/// مشغّل فيديو بملء الشاشة
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.url});
  final String url;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _c;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _c.addListener(() {
      if (mounted) setState(() {});
    });
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'تعذر تشغيل الفيديو');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: Colors.white70))
            : !_ready
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _c.value.aspectRatio,
                        child: GestureDetector(
                          onTap: () => _c.value.isPlaying
                              ? _c.pause()
                              : _c.play(),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_c),
                              if (!_c.value.isPlaying)
                                const Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Colors.white70,
                                  size: 72,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: VideoProgressIndicator(
                          _c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
