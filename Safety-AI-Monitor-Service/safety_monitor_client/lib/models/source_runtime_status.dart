// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

class SourceRuntimeStatus {
  const SourceRuntimeStatus({
    required this.sourceKey,
    required this.sourceType,
    required this.sourceValue,
    required this.clientId,
    required this.sessionId,
    required this.state,
    required this.isRunning,
    required this.sourceFps,
    required this.sourceDurationSeconds,
    required this.lastFrameId,
    required this.lastSourceTimeSeconds,
    required this.avgObjectDetectionMs,
    required this.errorMessage,
    required this.updatedAt,
  });

  final String sourceKey;
  final String sourceType;
  final String sourceValue;
  final String clientId;
  final String sessionId;
  final String state;
  final bool isRunning;
  final double sourceFps;
  final double sourceDurationSeconds;
  final int lastFrameId;
  final double lastSourceTimeSeconds;
  final double avgObjectDetectionMs;
  final String errorMessage;
  final String updatedAt;

  factory SourceRuntimeStatus.fromJson(Map<String, dynamic> json) {
    return SourceRuntimeStatus(
      sourceKey: json['source_key']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
      sourceValue: json['source_value']?.toString() ?? '',
      clientId: json['client_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      isRunning: json['is_running'] == true,
      sourceFps: _toDouble(json['source_fps']),
      sourceDurationSeconds: _toDouble(json['source_duration_seconds']),
      lastFrameId: _toInt(json['last_frame_id']),
      lastSourceTimeSeconds: _toDouble(json['last_source_time_seconds']),
      avgObjectDetectionMs: _toDouble(json['avg_object_detection_ms']),
      errorMessage: json['error_message']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  static double _toDouble(Object? value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? -1;
    }
    return -1;
  }
}
