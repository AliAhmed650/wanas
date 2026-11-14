import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/chat_repository.dart';
import '../../data/media_service.dart';
import 'media_viewers.dart';

/// فقاعة رسالة: نص أو صورة أو فيديو أو صوت أو ملف، مع الوقت وعلامات القراءة
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.msg,
    required this.mine,
    required this.onLongPress,
    this.showTail = true,
  });

  final Message msg;
  final bool mine;
  final VoidCallback onLongPress;
  final bool showTail;

  String _time(DateTime? t) {
    if (t == null) return '';
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final meta = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg.withValues(alpha: 0.6),
        );

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine || !showTail ? 18 : 4),
      bottomRight: Radius.circular(mine && showTail ? 4 : 18),
    );

    final isVisual =
        msg.type == MessageType.image || msg.type == MessageType.video;
    final maxW = MediaQuery.of(context).size.width * (isVisual ? 0.68 : 0.78);

    Widget content;
    switch (msg.type) {
      case MessageType.image:
        content = _ImageContent(msg: msg);
        break;
      case MessageType.video:
        content = _VideoContent(msg: msg);
        break;
      case MessageType.audio:
        content = _AudioContent(msg: msg, color: fg, accent: scheme.primary);
        break;
      case MessageType.file:
        content = _FileContent(msg: msg, color: fg);
        break;
      case MessageType.text:
        content = const SizedBox.shrink();
        break;
    }

    final hasCaption = msg.text.isNotEmpty;
    final metaRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (msg.edited) Text('معدّلة · ', style: meta),
        Text(_time(msg.createdAt), style: meta),
        if (mine) ...[
          const SizedBox(width: 4),
          _Ticks(msg: msg, scheme: scheme),
        ],
      ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: EdgeInsets.only(top: 2, bottom: showTail ? 6 : 2),
          constraints: BoxConstraints(maxWidth: maxW),
          decoration: BoxDecoration(color: bg, borderRadius: radius),
          clipBehavior: Clip.antiAlias,
          padding: isVisual
              ? const EdgeInsets.all(3)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.isMedia) content,
              if (hasCaption)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isVisual ? 9 : 0,
                    msg.isMedia ? 6 : 0,
                    isVisual ? 9 : 0,
                    0,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SelectableText(
                      msg.text,
                      style: TextStyle(color: fg, fontSize: 15.5, height: 1.35),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isVisual ? 9 : 0,
                  3,
                  isVisual ? 9 : 0,
                  isVisual ? 4 : 0,
                ),
                child: metaRow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ticks extends StatelessWidget {
  const _Ticks({required this.msg, required this.scheme});
  final Message msg;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (msg.pending) {
      return Icon(Icons.access_time, size: 13, color: scheme.outline);
    }
    if (msg.status == 'read') {
      return Icon(Icons.done_all, size: 15, color: scheme.primary);
    }
    return Icon(Icons.done, size: 15, color: scheme.outline);
  }
}

// ---------------------------------------------------------------- صورة

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.msg});
  final Message msg;

  @override
  Widget build(BuildContext context) {
    final url = msg.url;
    if (url == null) return const SizedBox.shrink();
    final tag = 'img_${msg.id}';
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerScreen(url: url, heroTag: tag),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Hero(
          tag: tag,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 320),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- فيديو

class _VideoContent extends StatelessWidget {
  const _VideoContent({required this.msg});
  final Message msg;

  @override
  Widget build(BuildContext context) {
    final url = msg.url;
    if (url == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: url)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 180,
          width: double.infinity,
          color: Colors.black87,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 60,
              ),
              Positioned(
                left: 10,
                bottom: 8,
                child: Row(
                  children: [
                    const Icon(Icons.videocam, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      msg.fileSize == null ? 'فيديو' : formatBytes(msg.fileSize!),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- صوت

class _AudioContent extends StatefulWidget {
  const _AudioContent({
    required this.msg,
    required this.color,
    required this.accent,
  });
  final Message msg;
  final Color color;
  final Color accent;

  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  /// مشغّل واحد بس في نفس الوقت: لما واحد يشتغل التاني بيقف
  static _AudioContentState? _active;

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  late Duration _total = Duration(milliseconds: widget.msg.durationMs ?? 0);

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    }));
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _total = d);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    }));
  }

  @override
  void dispose() {
    if (_active == this) _active = null;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  bool get _playing => _state == PlayerState.playing;

  Future<void> _toggle() async {
    final url = widget.msg.url;
    if (url == null) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_active != null && _active != this) {
      await _active!._player.pause();
    }
    _active = this;
    if (_state == PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(UrlSource(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _total.inMilliseconds;
    final progress = totalMs == 0
        ? 0.0
        : (_pos.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          IconButton.filled(
            onPressed: _toggle,
            style: IconButton.styleFrom(backgroundColor: widget.accent),
            icon: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    value: progress,
                    activeColor: widget.accent,
                    inactiveColor: widget.color.withValues(alpha: 0.2),
                    onChanged: totalMs == 0
                        ? null
                        : (v) => _player.seek(
                              Duration(milliseconds: (v * totalMs).round()),
                            ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    formatDuration(_playing || _pos > Duration.zero ? _pos : _total),
                    style: TextStyle(
                      color: widget.color.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ملف

class _FileContent extends StatelessWidget {
  const _FileContent({required this.msg, required this.color});
  final Message msg;
  final Color color;

  IconData _icon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _open(BuildContext context) async {
    final url = msg.url;
    if (url == null) return;
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الملف')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = msg.fileName ?? 'ملف';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: SizedBox(
        width: 230,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon(name), color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (msg.fileSize != null)
                    Text(
                      formatBytes(msg.fileSize!),
                      style: TextStyle(
                        color: color.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.download_rounded, color: color.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}
