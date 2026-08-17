// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

import 'source_rule_config.dart';

class SourceItem {
  const SourceItem({
    required this.sourceKey,
    required this.sourceSlug,
    required this.displayName,
    required this.sourceType,
    required this.sourceValue,
    required this.sourceDurationSeconds,
    required this.serverMediaPath,
    required this.mediaUrl,
    required this.previewUrl,
    required this.originalSourceType,
    required this.originalSourceValue,
    required this.clientId,
    required this.sessionId,
    required this.desiredRunning,
    required this.ruleConfig,
    required this.createdAt,
    required this.updatedAt,
  });

  final String sourceKey;
  final String sourceSlug;
  final String displayName;
  final String sourceType;
  final String sourceValue;
  final double sourceDurationSeconds;
  final String serverMediaPath;
  final String mediaUrl;
  final String previewUrl;
  final String originalSourceType;
  final String originalSourceValue;
  final String clientId;
  final String sessionId;
  final bool desiredRunning;
  final SourceRuleConfig ruleConfig;
  final String createdAt;
  final String updatedAt;

  factory SourceItem.fromJson(Map<String, dynamic> json) {
    return SourceItem(
      sourceKey: json['source_key']?.toString() ?? '',
      sourceSlug: json['source_slug']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      sourceType: json['source_type']?.toString() ?? '',
      sourceValue: json['source_value']?.toString() ?? '',
      sourceDurationSeconds: _toDouble(json['source_duration_seconds']),
      serverMediaPath: json['server_media_path']?.toString() ?? '',
      mediaUrl: json['media_url']?.toString() ?? '',
      previewUrl: json['preview_url']?.toString() ?? '',
      originalSourceType: json['original_source_type']?.toString() ?? '',
      originalSourceValue: json['original_source_value']?.toString() ?? '',
      clientId: json['client_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      desiredRunning: json['desired_running'] == true,
      ruleConfig: SourceRuleConfig.fromJson(
        json['rule_config'] is Map<String, dynamic>
            ? json['rule_config'] as Map<String, dynamic>
            : json['rule_config'] is Map
            ? Map<String, dynamic>.from(json['rule_config'] as Map)
            : null,
      ),
      createdAt: json['created_at']?.toString() ?? '',
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
}
