// 여러 화면에서 재사용하는 Flutter 위젯 파일입니다.
// 부모 화면에서 받은 값과 콜백을 바탕으로 UI를 구성합니다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/event_log_item.dart';
import '../models/video_overlay_detection.dart';

// 현재 프레임 이벤트를 카드와 바운딩 박스로 함께 영상 위에 덧그립니다.
class VideoEventOverlay extends StatelessWidget {
  const VideoEventOverlay({
    super.key,
    required this.items,
    required this.detections,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final List<EventLogItem> items;
  final List<VideoOverlayDetection> detections;
  final double sourceWidth;
  final double sourceHeight;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty && detections.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounds = Size(constraints.maxWidth, constraints.maxHeight);
          final videoRect = _resolveVideoRect(bounds);
          final canShowEventCards =
              constraints.maxWidth >= 220 && constraints.maxHeight >= 110;

          return Stack(
            children: [
              if (videoRect != null)
                ...detections.map((detection) {
                  return _buildDetectionBox(context, detection, videoRect);
                }),
              if (items.isNotEmpty && canShowEventCards)
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: math.min(260, constraints.maxWidth - 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: items.take(2).map((item) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${item.typeText} / ${item.levelText}\n${item.messageText}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Rect? _resolveVideoRect(Size bounds) {
    if (bounds.width <= 0 ||
        bounds.height <= 0 ||
        sourceWidth <= 0 ||
        sourceHeight <= 0) {
      return null;
    }

    final videoAspect = sourceWidth / sourceHeight;
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

  Widget _buildDetectionBox(
    BuildContext context,
    VideoOverlayDetection detection,
    Rect videoRect,
  ) {
    final left = _scaleX(detection.x1, videoRect);
    final top = _scaleY(detection.y1, videoRect);
    final right = _scaleX(detection.x2, videoRect);
    final bottom = _scaleY(detection.y2, videoRect);

    final boxLeft = math.min(left, right);
    final boxTop = math.min(top, bottom);
    final boxWidth = math.max(2.0, (right - left).abs());
    final boxHeight = math.max(2.0, (bottom - top).abs());

    return Positioned(
      left: boxLeft,
      top: boxTop,
      width: boxWidth,
      height: boxHeight,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: detection.color, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: detection.color.withValues(alpha: 0.9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(2),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              detection.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _scaleX(double value, Rect videoRect) {
    final clamped = value.clamp(0.0, sourceWidth).toDouble();
    return videoRect.left + (clamped / sourceWidth) * videoRect.width;
  }

  double _scaleY(double value, Rect videoRect) {
    final clamped = value.clamp(0.0, sourceHeight).toDouble();
    return videoRect.top + (clamped / sourceHeight) * videoRect.height;
  }
}

