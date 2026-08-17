// 여러 화면에서 재사용하는 Flutter 위젯 파일입니다.
// 부모 화면에서 받은 값과 콜백을 바탕으로 UI를 구성합니다.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../controllers/video_panel_controller.dart';
import '../models/event_log_item.dart';
import '../models/source_rule_config.dart';
import '../models/video_overlay_detection.dart';
import 'video_event_overlay.dart';

class VideoViewBox extends StatelessWidget {
  const VideoViewBox({
    super.key,
    required this.controller,
    required this.overlayItems,
    required this.overlayDetections,
    required this.overlaySourceWidth,
    required this.overlaySourceHeight,
    required this.overlayStatusText,
    this.previewImageUrl = '',
    this.title = '',
    this.badgeText = '',
    this.badgeColor = Colors.green,
    this.isSelected = false,
    this.onTap,
    this.onTitleTap,
    this.footer,
    this.overlayAction,
    this.dangerZoneRoi,
    this.enableDangerZoneEditing = false,
    this.onDangerZoneChanged,
  });

  final VideoPanelController controller;
  final List<EventLogItem> overlayItems;
  final List<VideoOverlayDetection> overlayDetections;
  final double overlaySourceWidth;
  final double overlaySourceHeight;
  final String overlayStatusText;
  final String previewImageUrl;
  final String title;
  final String badgeText;
  final Color badgeColor;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onTitleTap;
  final Widget? footer;
  final Widget? overlayAction;
  final RoiRect? dangerZoneRoi;
  final bool enableDangerZoneEditing;
  final ValueChanged<RoiRect>? onDangerZoneChanged;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : Colors.white12;

    final child = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
      ),
      child: Column(
        children: [
          if (title.isNotEmpty || badgeText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTitleTap,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (badgeText.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: controller.hasVideo
                          ? Video(
                              controller: controller.videoController,
                              controls: NoVideoControls,
                            )
                          : _PreviewFallback(previewImageUrl: previewImageUrl),
                    ),
                    Positioned.fill(
                      child: VideoEventOverlay(
                        items: overlayItems,
                        detections: overlayDetections,
                        sourceWidth: overlaySourceWidth,
                        sourceHeight: overlaySourceHeight,
                      ),
                    ),
                    Positioned.fill(
                      child: _DangerZoneOverlay(
                        sourceWidth: overlaySourceWidth,
                        sourceHeight: overlaySourceHeight,
                        roi: dangerZoneRoi,
                        enableEditing: enableDangerZoneEditing,
                        onChanged: onDangerZoneChanged,
                      ),
                    ),
                    if (overlayStatusText.isNotEmpty)
                      Center(
                        child: Container(
                          width: 260,
                          constraints: const BoxConstraints(maxWidth: 320),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LinearProgressIndicator(minHeight: 3),
                              const SizedBox(height: 10),
                              Text(
                                overlayStatusText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (overlayAction != null)
                      Positioned(top: 8, right: 8, child: overlayAction!),
                  ],
                ),
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: footer!,
            ),
        ],
      ),
    );

    if (onTap == null) {
      return child;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: child,
    );
  }
}

class _PreviewFallback extends StatefulWidget {
  const _PreviewFallback({required this.previewImageUrl});

  final String previewImageUrl;

  @override
  State<_PreviewFallback> createState() => _PreviewFallbackState();
}

class _PreviewFallbackState extends State<_PreviewFallback> {
  HttpClient? _client;
  HttpClientResponse? _response;
  StreamSubscription<List<int>>? _subscription;
  Uint8List? _latestImageBytes;
  bool _isLoading = false;
  String _lastConnectedUrl = '';

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  @override
  void didUpdateWidget(covariant _PreviewFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewImageUrl != widget.previewImageUrl) {
      unawaited(_connect());
    }
  }

  @override
  void dispose() {
    unawaited(_disconnect());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewImageUrl = widget.previewImageUrl.trim();
    if (previewImageUrl.isEmpty) {
      return const Center(
        child: Text(
          'Preview will appear here.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final latestImageBytes = _latestImageBytes;
    if (latestImageBytes == null) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(
        child: Text(
          'Waiting for live preview.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Image.memory(
      latestImageBytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Text(
            'Waiting for live preview.',
            style: TextStyle(color: Colors.white70),
          ),
        );
      },
    );
  }

  Future<void> _connect() async {
    final nextUrl = widget.previewImageUrl.trim();
    if (nextUrl.isEmpty) {
      return;
    }
    await _disconnect();
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _latestImageBytes = null;
      _lastConnectedUrl = nextUrl;
    });

    final client = HttpClient();
    _client = client;
    try {
      final request = await client.getUrl(Uri.parse(nextUrl));
      final response = await request.close();
      _response = response;
      final mimeType =
          response.headers.contentType?.mimeType.toLowerCase() ?? '';
      if (!mimeType.startsWith('multipart/x-mixed-replace')) {
        final bytes = await _readAllBytes(response);
        _trySetFrame(Uint8List.fromList(bytes), nextUrl);
        return;
      }

      final boundaryToken =
          response.headers.contentType?.parameters['boundary'] ?? 'frame';
      final boundaryBytes = Uint8List.fromList('--$boundaryToken'.codeUnits);
      final buffer = <int>[];

      _subscription = response.listen(
        (chunk) {
          buffer.addAll(chunk);
          while (true) {
            final boundaryIndex = _indexOfPattern(buffer, boundaryBytes);
            if (boundaryIndex < 0) {
              break;
            }
            if (boundaryIndex > 0) {
              final frameBytes = Uint8List.fromList(
                buffer.sublist(0, boundaryIndex),
              );
              _trySetFrame(_extractJpegBytes(frameBytes), nextUrl);
            }
            buffer.removeRange(0, boundaryIndex + boundaryBytes.length);
          }
        },
        onDone: () {
          if (!mounted || _lastConnectedUrl != nextUrl) {
            return;
          }
          setState(() {
            _isLoading = false;
          });
        },
        onError: (_) {
          if (!mounted || _lastConnectedUrl != nextUrl) {
            return;
          }
          setState(() {
            _isLoading = false;
          });
        },
        cancelOnError: true,
      );
    } catch (_) {
      if (!mounted || _lastConnectedUrl != nextUrl) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _response
        ?.detachSocket()
        .then((socket) => socket.destroy())
        .catchError((_) {
          return null;
        });
    _response = null;
    _client?.close(force: true);
    _client = null;
  }

  void _trySetFrame(Uint8List? jpegBytes, String expectedUrl) {
    if (jpegBytes == null || !mounted || _lastConnectedUrl != expectedUrl) {
      return;
    }
    setState(() {
      _latestImageBytes = jpegBytes;
      _isLoading = false;
    });
  }

  Future<List<int>> _readAllBytes(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  int _indexOfPattern(List<int> source, List<int> pattern) {
    if (pattern.isEmpty || source.length < pattern.length) {
      return -1;
    }
    for (var index = 0; index <= source.length - pattern.length; index++) {
      var matches = true;
      for (var offset = 0; offset < pattern.length; offset++) {
        if (source[index + offset] != pattern[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return index;
      }
    }
    return -1;
  }

  Uint8List? _extractJpegBytes(Uint8List rawBytes) {
    const jpegStart = [0xFF, 0xD8];
    const jpegEnd = [0xFF, 0xD9];

    final startIndex = _indexOfPattern(rawBytes, jpegStart);
    if (startIndex < 0) {
      return null;
    }

    final endSearch = rawBytes.sublist(startIndex);
    final endRelativeIndex = _indexOfPattern(endSearch, jpegEnd);
    if (endRelativeIndex < 0) {
      return null;
    }

    final endIndex = startIndex + endRelativeIndex + jpegEnd.length;
    return Uint8List.sublistView(rawBytes, startIndex, endIndex);
  }
}

class _DangerZoneOverlay extends StatefulWidget {
  const _DangerZoneOverlay({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.roi,
    required this.enableEditing,
    required this.onChanged,
  });

  final double sourceWidth;
  final double sourceHeight;
  final RoiRect? roi;
  final bool enableEditing;
  final ValueChanged<RoiRect>? onChanged;

  @override
  State<_DangerZoneOverlay> createState() => _DangerZoneOverlayState();
}

class _DangerZoneOverlayState extends State<_DangerZoneOverlay> {
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  Widget build(BuildContext context) {
    if (widget.sourceWidth <= 0 || widget.sourceHeight <= 0) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      ignoring: !widget.enableEditing,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final videoRect = _resolveVideoRect(
            Size(constraints.maxWidth, constraints.maxHeight),
          );
          if (videoRect == null) {
            return const SizedBox.shrink();
          }

          final activeRoi = _buildDraftRoi(videoRect) ?? widget.roi;

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: widget.enableEditing
                ? (details) {
                    setState(() {
                      _dragStart = details.localPosition;
                      _dragCurrent = details.localPosition;
                    });
                  }
                : null,
            onPanUpdate: widget.enableEditing
                ? (details) {
                    setState(() {
                      _dragCurrent = details.localPosition;
                    });
                  }
                : null,
            onPanEnd: widget.enableEditing
                ? (_) {
                    final nextRoi = _buildDraftRoi(videoRect);
                    setState(() {
                      _dragStart = null;
                      _dragCurrent = null;
                    });
                    if (nextRoi != null && widget.onChanged != null) {
                      widget.onChanged!(nextRoi);
                    }
                  }
                : null,
            child: CustomPaint(
              painter: _DangerZonePainter(
                roi: activeRoi,
                videoRect: videoRect,
                sourceWidth: widget.sourceWidth,
                sourceHeight: widget.sourceHeight,
                isEditing: widget.enableEditing,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }

  RoiRect? _buildDraftRoi(Rect videoRect) {
    final start = _dragStart;
    final current = _dragCurrent;
    if (start == null || current == null) {
      return null;
    }

    if ((current.dx - start.dx).abs() < 4 ||
        (current.dy - start.dy).abs() < 4) {
      return null;
    }

    return RoiRect.normalized(
      x1: _displayXToSource(start.dx, videoRect),
      y1: _displayYToSource(start.dy, videoRect),
      x2: _displayXToSource(current.dx, videoRect),
      y2: _displayYToSource(current.dy, videoRect),
    );
  }

  Rect? _resolveVideoRect(Size bounds) {
    if (bounds.width <= 0 || bounds.height <= 0) {
      return null;
    }

    final videoAspect = widget.sourceWidth / widget.sourceHeight;
    final boundsAspect = bounds.width / bounds.height;

    // The preview frame is rendered with BoxFit.cover, so overlays must use the
    // same geometry. The resolved rect may extend outside the visible bounds.
    if (videoAspect >= boundsAspect) {
      final displayHeight = bounds.height;
      final displayWidth = displayHeight * videoAspect;
      final left = (bounds.width - displayWidth) / 2;
      return Rect.fromLTWH(left, 0, displayWidth, displayHeight);
    }

    final displayWidth = bounds.width;
    final displayHeight = displayWidth / videoAspect;
    final top = (bounds.height - displayHeight) / 2;
    return Rect.fromLTWH(0, top, displayWidth, displayHeight);
  }

  int _displayXToSource(double value, Rect videoRect) {
    final normalized = ((value - videoRect.left) / videoRect.width).clamp(
      0.0,
      1.0,
    );
    return (normalized * widget.sourceWidth).round();
  }

  int _displayYToSource(double value, Rect videoRect) {
    final normalized = ((value - videoRect.top) / videoRect.height).clamp(
      0.0,
      1.0,
    );
    return (normalized * widget.sourceHeight).round();
  }
}

class _DangerZonePainter extends CustomPainter {
  const _DangerZonePainter({
    required this.roi,
    required this.videoRect,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.isEditing,
  });

  final RoiRect? roi;
  final Rect videoRect;
  final double sourceWidth;
  final double sourceHeight;
  final bool isEditing;

  @override
  void paint(Canvas canvas, Size size) {
    if (roi == null) {
      if (isEditing) {
        final painter = TextPainter(
          text: const TextSpan(
            text: 'Drag to set a danger zone.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width - 24);
        painter.paint(canvas, const Offset(12, 12));
      }
      return;
    }

    final rect = Rect.fromLTRB(
      _scaleX(roi!.x1.toDouble()),
      _scaleY(roi!.y1.toDouble()),
      _scaleX(roi!.x2.toDouble()),
      _scaleY(roi!.y2.toDouble()),
    );
    final fillPaint = Paint()..color = const Color(0x44FF5A5A);
    final borderPaint = Paint()
      ..color = const Color(0xFFFF7A7A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, borderPaint);
  }

  double _scaleX(double value) {
    final clamped = value.clamp(0.0, sourceWidth).toDouble();
    return videoRect.left + (clamped / sourceWidth) * videoRect.width;
  }

  double _scaleY(double value) {
    final clamped = value.clamp(0.0, sourceHeight).toDouble();
    return videoRect.top + (clamped / sourceHeight) * videoRect.height;
  }

  @override
  bool shouldRepaint(covariant _DangerZonePainter oldDelegate) {
    return roi != oldDelegate.roi ||
        videoRect != oldDelegate.videoRect ||
        sourceWidth != oldDelegate.sourceWidth ||
        sourceHeight != oldDelegate.sourceHeight ||
        isEditing != oldDelegate.isEditing;
  }
}


