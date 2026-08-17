// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

class FrameDetectionSnapshot {
  const FrameDetectionSnapshot({
    required this.frameId,
    required this.sourceKey,
    required this.sourceTimeSeconds,
    required this.sourceTimeText,
    required this.frameWidth,
    required this.frameHeight,
    required this.detections,
  });

  final int frameId;
  final String sourceKey;
  final double sourceTimeSeconds;
  final String sourceTimeText;
  final int frameWidth;
  final int frameHeight;
  final List<Map<String, dynamic>> detections;

  factory FrameDetectionSnapshot.fromJson(Map<String, dynamic> json) {
    return FrameDetectionSnapshot(
      frameId: _toIntValue(json['frame_id']) ?? 0,
      sourceKey: json['source_key']?.toString() ?? '',
      sourceTimeSeconds: _toDoubleValue(json['source_time_seconds']) ?? 0.0,
      sourceTimeText: json['source_time_text']?.toString() ?? '',
      frameWidth: _toIntValue(json['frame_width']) ?? 0,
      frameHeight: _toIntValue(json['frame_height']) ?? 0,
      detections: _toDetectionList(json['detections']),
    );
  }

  static int? _toIntValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _toDoubleValue(Object? value) {
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

  static List<Map<String, dynamic>> _toDetectionList(Object? value) {
    if (value is! List) {
      return const [];
    }

    final items = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is Map<String, dynamic>) {
        items.add(item);
      } else if (item is Map) {
        items.add(Map<String, dynamic>.from(item));
      }
    }
    return items;
  }
}
