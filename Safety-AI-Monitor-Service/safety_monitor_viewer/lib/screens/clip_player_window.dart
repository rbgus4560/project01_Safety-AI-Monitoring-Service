// 화면을 구성하는 Flutter 코드이며 상태값과 버튼 동작이 모여 있습니다.
// initState, 서버 통신 함수, build 메서드가 같은 화면 흐름을 구성합니다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/video_panel_controller.dart';
import '../models/clip_window_arguments.dart';
import '../models/frame_detection_snapshot.dart';
import '../models/video_overlay_detection.dart';
import '../services/event_api_service.dart';
import '../widgets/video_control_bar.dart';
import '../widgets/video_view_box.dart';

class ClipPlayerWindow extends StatefulWidget {
  const ClipPlayerWindow({super.key, required this.arguments});

  final ClipWindowArguments arguments;

  @override
  State<ClipPlayerWindow> createState() => _ClipPlayerWindowState();
}

class _ClipPlayerWindowState extends State<ClipPlayerWindow> {
  late final VideoPanelController _controller;
  late final EventApiService _eventApiService;
  Timer? _refreshTimer;
  FrameDetectionSnapshot? _snapshot;
  double _lastRequestedSeconds = -1;
  bool _isFetching = false;
  bool _isClosing = false;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _controller = VideoPanelController();
    _eventApiService = EventApiService(baseUrl: widget.arguments.baseUrl);
    _controller.addListener(_handleControllerChanged);
    unawaited(_openClip());
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_refreshDetectionIfNeeded()),
    );
  }

  @override
  void dispose() {
    _isClosing = true;
    _refreshTimer?.cancel();
    _controller.removeListener(_handleControllerChanged);
    _controller.disposeController();
    _eventApiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.arguments.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ClipHeader(
                  sourceKey: widget.arguments.sourceKey,
                  clipUrl: widget.arguments.clipUrl,
                  overlayTimeText: _snapshot?.sourceTimeText ?? '-',
                  detectionCount: _snapshot?.detections.length ?? 0,
                  errorText: _errorText.isNotEmpty
                      ? _errorText
                      : _controller.errorText,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: VideoViewBox(
                    controller: _controller,
                    title: '',
                    badgeText: '이벤트 클립',
                    badgeColor: const Color(0xFF5BC0BE),
                    overlayItems: const [],
                    overlayDetections: _buildOverlayDetections(),
                    overlaySourceWidth: _snapshot?.frameWidth.toDouble() ?? 0,
                    overlaySourceHeight: _snapshot?.frameHeight.toDouble() ?? 0,
                    overlayStatusText: _buildOverlayStatusText(),
                    footer: VideoControlBar(controller: _controller),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openClip() async {
    await _controller.openReplayClip(
      widget.arguments.clipUrl,
      replayStartSeconds: widget.arguments.sourceStartSeconds,
      sourceKey: widget.arguments.sourceKey,
      preserveReturnContext: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    await _refreshDetectionIfNeeded(force: true);
  }

  void _handleControllerChanged() {
    if (!_controller.hasVideo || !_controller.isPlaying) {
      return;
    }
    unawaited(_refreshDetectionIfNeeded());
  }

  Future<void> _refreshDetectionIfNeeded({bool force = false}) async {
    if (_isClosing || _isFetching || !_controller.hasVideo) {
      return;
    }

    final sourceSeconds = _controller.currentOverlaySeconds;
    if (!force && (sourceSeconds - _lastRequestedSeconds).abs() < 0.05) {
      return;
    }

    _isFetching = true;
    try {
      final snapshot = await _eventApiService.fetchCurrentFrameDetection(
        sourceKey: widget.arguments.sourceKey,
        sourceTimeSeconds: sourceSeconds,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _lastRequestedSeconds = sourceSeconds;
        _errorText = snapshot == null ? '해당 시점 프레임 탐지 결과가 없습니다.' : '';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '프레임 탐지 조회 실패: $error';
      });
    } finally {
      if (!_isClosing) {
        _isFetching = false;
      }
    }
  }

  List<VideoOverlayDetection> _buildOverlayDetections() {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const [];
    }

    final items = <VideoOverlayDetection>[];
    final seenKeys = <String>{};
    for (final detection in snapshot.detections) {
      final box = detection['box'];
      if (box is! Map) {
        continue;
      }

      final x1 = _toDouble(box['x1']);
      final y1 = _toDouble(box['y1']);
      final x2 = _toDouble(box['x2']);
      final y2 = _toDouble(box['y2']);
      if (x1 == null || y1 == null || x2 == null || y2 == null) {
        continue;
      }

      final key =
          '${snapshot.frameId}:${detection['track_id']}:${detection['name']}:$x1:$y1:$x2:$y2';
      if (!seenKeys.add(key)) {
        continue;
      }

      items.add(
        VideoOverlayDetection(
          key: key,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          label: _buildDetectionLabel(detection),
          color: _resolveDetectionColor(detection['name']?.toString() ?? ''),
        ),
      );
    }
    return items;
  }

  String _buildOverlayStatusText() {
    if (_controller.errorText.isNotEmpty) {
      return _controller.errorText;
    }
    if (_errorText.isNotEmpty) {
      return _errorText;
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return '프레임 탐지 결과를 조회 중입니다.';
    }
    return '원본 시각 ${snapshot.sourceTimeText} · 탐지 ${snapshot.detections.length}건';
  }

  String _buildDetectionLabel(Map<String, dynamic> detection) {
    final name = detection['name']?.toString() ?? 'object';
    final confidence = _toDouble(detection['confidence']);
    if (confidence == null) {
      return name;
    }
    return '$name ${(confidence * 100).toStringAsFixed(0)}%';
  }

  Color _resolveDetectionColor(String label) {
    switch (label.trim().toLowerCase()) {
      case 'yes_helmet':
      case 'helmet':
      case 'hardhat':
        return Colors.greenAccent;
      case 'no_helmet':
      case 'without_helmet':
      case 'no helmet':
        return Colors.redAccent;
      case 'person':
        return Colors.amberAccent;
      default:
        return Colors.amberAccent;
    }
  }

  double? _toDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}

class _ClipHeader extends StatelessWidget {
  const _ClipHeader({
    required this.sourceKey,
    required this.clipUrl,
    required this.overlayTimeText,
    required this.detectionCount,
    required this.errorText,
  });

  final String sourceKey;
  final String clipUrl;
  final String overlayTimeText;
  final int detectionCount;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sourceKey,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '원본 시각: $overlayTimeText · 탐지 수: $detectionCount',
            style: textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            clipUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: Colors.white54),
          ),
          if (errorText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              errorText,
              style: textTheme.bodySmall?.copyWith(color: const Color(0xFFFF8A80)),
            ),
          ],
        ],
      ),
    );
  }
}
