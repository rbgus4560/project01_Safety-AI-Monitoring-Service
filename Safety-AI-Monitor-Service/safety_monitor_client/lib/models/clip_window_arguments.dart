// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

import 'dart:convert';

class ClipWindowArguments {
  /// 클립 재생 윈도우를 열 때 필요한 정보를 담는 모델입니다.
  const ClipWindowArguments({
    required this.baseUrl,
    required this.clipUrl,
    required this.sourceKey,
    required this.sourceStartSeconds,
    required this.title,
  });

  /// 클립이 위치한 서버의 기본 주소입니다.
  final String baseUrl;
  /// 재생할 클립의 실제 URL입니다.
  final String clipUrl;
  /// 해당 클립이 속한 소스 식별자입니다.
  final String sourceKey;
  /// 클립 재생을 시작할 오프셋 시간(초)입니다.
  final double sourceStartSeconds;
  /// 윈도우 상단에 표시할 제목입니다.
  final String title;

  /// 객체를 서버/플랫폼 간 전달용 JSON으로 변환합니다.
  Map<String, dynamic> toJson() {
    return {
      'window_type': 'clip_player',
      'base_url': baseUrl,
      'clip_url': clipUrl,
      'source_key': sourceKey,
      'source_start_seconds': sourceStartSeconds,
      'title': title,
    };
  }

  /// JSON 문자열로 바로 전달할 수 있도록 인코딩된 문자열을 반환합니다.
  String toArgumentString() => jsonEncode(toJson());

  /// 전달된 문자열을 모델로 복원합니다. 형식이 다르면 null을 반환합니다.
  static ClipWindowArguments? tryParse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      if (json['window_type']?.toString() != 'clip_player') {
        // 이 모델이 기대하는 윈도우 타입이 아니면 파싱하지 않는다.
        return null;
      }

      final baseUrl = json['base_url']?.toString() ?? '';
      final clipUrl = json['clip_url']?.toString() ?? '';
      final sourceKey = json['source_key']?.toString() ?? '';
      final title = json['title']?.toString() ?? 'Event Clip';
      final sourceStartSeconds = _toDouble(json['source_start_seconds']) ?? 0.0;
      if (baseUrl.isEmpty || clipUrl.isEmpty || sourceKey.isEmpty) {
        // 필수 정보가 빠지면 잘못된 인자라고 보고 null을 반환한다.
        return null;
      }

      return ClipWindowArguments(
        baseUrl: baseUrl,
        clipUrl: clipUrl,
        sourceKey: sourceKey,
        sourceStartSeconds: sourceStartSeconds,
        title: title,
      );
    } catch (_) {
      return null;
    }
  }

  /// 다양한 숫자형 입력을 double로 변환합니다.
  static double? _toDouble(Object? value) {
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
