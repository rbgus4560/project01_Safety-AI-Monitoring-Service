// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

import 'package:flutter/material.dart';

// API 이벤트의 related_detections를 영상 오버레이용으로 정규화한 모델입니다.
class VideoOverlayDetection {
  const VideoOverlayDetection({
    required this.key,
    required this.label,
    required this.color,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final String key;
  final String label;
  final Color color;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}
