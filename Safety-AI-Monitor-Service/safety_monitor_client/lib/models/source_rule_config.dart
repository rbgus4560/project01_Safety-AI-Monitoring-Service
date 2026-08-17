// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

class SourceRuleConfig {
  const SourceRuleConfig({
    required this.useNoHelmetRule,
    required this.useDangerZoneRule,
    required this.dangerZoneRoi,
    this.confidenceThreshold = 0.30,
    this.eventCooldownSeconds = 3.0,
  });

  final bool useNoHelmetRule;
  final bool useDangerZoneRule;
  final RoiRect? dangerZoneRoi;
  final double confidenceThreshold;
  final double eventCooldownSeconds;

  factory SourceRuleConfig.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return SourceRuleConfig(
      useNoHelmetRule: data['use_no_helmet_rule'] != false,
      useDangerZoneRule: data['use_danger_zone_rule'] == true,
      dangerZoneRoi: RoiRect.fromJsonOrNull(data['danger_zone_roi']),
      confidenceThreshold: _toDouble(data['confidence_threshold']) ?? 0.30,
      eventCooldownSeconds: _toDouble(data['event_cooldown_seconds']) ?? 3.0,
    );
  }

  SourceRuleConfig copyWith({
    bool? useNoHelmetRule,
    bool? useDangerZoneRule,
    RoiRect? dangerZoneRoi,
    double? confidenceThreshold,
    double? eventCooldownSeconds,
    bool clearDangerZoneRoi = false,
  }) {
    return SourceRuleConfig(
      useNoHelmetRule: useNoHelmetRule ?? this.useNoHelmetRule,
      useDangerZoneRule: useDangerZoneRule ?? this.useDangerZoneRule,
      dangerZoneRoi: clearDangerZoneRoi
          ? null
          : (dangerZoneRoi ?? this.dangerZoneRoi),
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      eventCooldownSeconds: eventCooldownSeconds ?? this.eventCooldownSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'use_no_helmet_rule': useNoHelmetRule,
      'use_danger_zone_rule': useDangerZoneRule,
      'danger_zone_roi': dangerZoneRoi?.toJson(),
      'confidence_threshold': confidenceThreshold,
      'event_cooldown_seconds': eventCooldownSeconds,
    };
  }
  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class RoiRect {
  const RoiRect({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final int x1;
  final int y1;
  final int x2;
  final int y2;

  factory RoiRect.normalized({
    required int x1,
    required int y1,
    required int x2,
    required int y2,
  }) {
    final left = x1 < x2 ? x1 : x2;
    final right = x1 < x2 ? x2 : x1;
    final top = y1 < y2 ? y1 : y2;
    final bottom = y1 < y2 ? y2 : y1;
    return RoiRect(x1: left, y1: top, x2: right, y2: bottom);
  }

  static RoiRect? fromJsonOrNull(Object? value) {
    if (value is! Map) {
      return null;
    }
    final x1 = _toInt(value['x1']);
    final y1 = _toInt(value['y1']);
    final x2 = _toInt(value['x2']);
    final y2 = _toInt(value['y2']);
    if (x1 == null || y1 == null || x2 == null || y2 == null) {
      return null;
    }
    if (x1 == x2 || y1 == y2) {
      return null;
    }
    return RoiRect.normalized(x1: x1, y1: y1, x2: x2, y2: y2);
  }

  Map<String, dynamic> toJson() {
    return {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2};
  }

  static int? _toInt(Object? value) {
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
}
