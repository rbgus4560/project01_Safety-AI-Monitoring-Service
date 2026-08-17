// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

class SourceOverviewItem {
  const SourceOverviewItem({
    required this.clientId,
    required this.sessionId,
    required this.sourceKey,
    required this.sourceSlug,
    required this.displayName,
    required this.sourceType,
    required this.sourceValue,
    required this.sourceDurationSeconds,
    required this.mediaUrl,
    required this.previewUrl,
    required this.desiredRunning,
    required this.state,
    required this.isRunning,
    required this.sourceFps,
    required this.lastFrameId,
    required this.lastSourceTimeSeconds,
    required this.lastEventReceivedAt,
    required this.lastFrameReceivedAt,
    required this.errorMessage,
    required this.updatedAt,
  });

  final String clientId;
  final String sessionId;
  final String sourceKey;
  final String sourceSlug;
  final String displayName;
  final String sourceType;
  final String sourceValue;
  final double sourceDurationSeconds;
  final String mediaUrl;
  final String previewUrl;
  final bool desiredRunning;
  final String state;
  final bool isRunning;
  final double sourceFps;
  final int lastFrameId;
  final double lastSourceTimeSeconds;
  final String lastEventReceivedAt;
  final String lastFrameReceivedAt;
  final String errorMessage;
  final String updatedAt;

  factory SourceOverviewItem.fromJson(Map<String, dynamic> json) {
    return SourceOverviewItem(
      clientId: json['client_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      sourceKey: json['source_key']?.toString() ?? '',
      sourceSlug: json['source_slug']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
      sourceValue: json['source_value']?.toString() ?? '',
      sourceDurationSeconds: _toDouble(json['source_duration_seconds']),
      mediaUrl: json['media_url']?.toString() ?? '',
      previewUrl: json['preview_url']?.toString() ?? '',
      desiredRunning: json['desired_running'] == true,
      state: json['state']?.toString() ?? '',
      isRunning: json['is_running'] == true,
      sourceFps: _toDouble(json['source_fps']),
      lastFrameId: _toInt(json['last_frame_id'], defaultValue: -1),
      lastSourceTimeSeconds: _toDouble(json['last_source_time_seconds']),
      lastEventReceivedAt: json['last_event_received_at']?.toString() ?? '',
      lastFrameReceivedAt: json['last_frame_received_at']?.toString() ?? '',
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

  static int _toInt(Object? value, {required int defaultValue}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }
}
