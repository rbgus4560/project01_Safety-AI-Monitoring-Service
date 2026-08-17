// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

import 'dart:convert';

class ClipWindowArguments {
  const ClipWindowArguments({
    required this.baseUrl,
    required this.clipUrl,
    required this.sourceKey,
    required this.sourceStartSeconds,
    required this.title,
  });

  final String baseUrl;
  final String clipUrl;
  final String sourceKey;
  final double sourceStartSeconds;
  final String title;

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

  String toArgumentString() => jsonEncode(toJson());

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
        return null;
      }

      final baseUrl = json['base_url']?.toString() ?? '';
      final clipUrl = json['clip_url']?.toString() ?? '';
      final sourceKey = json['source_key']?.toString() ?? '';
      final title = json['title']?.toString() ?? 'Event Clip';
      final sourceStartSeconds = _toDouble(json['source_start_seconds']) ?? 0.0;
      if (baseUrl.isEmpty || clipUrl.isEmpty || sourceKey.isEmpty) {
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
