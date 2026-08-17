// 서버 JSON이나 화면 상태를 Dart 객체로 표현하는 모델 파일입니다.
// 필드 정의와 fromJson/toJson 변환 흐름이 포함되어 있습니다.

// 이 파일은 기존 txt 로그 한 줄을 Flutter UI가 쓰기 쉬운 형태로 바꾼 모델입니다.
class EventLogItem {
  const EventLogItem({
    required this.timeText,
    required this.frameText,
    required this.eventKeyText,
    required this.sourceKeyText,
    required this.statusText,
    required this.typeText,
    required this.personIdText,
    required this.levelText,
    required this.startText,
    required this.startFrameText,
    required this.endText,
    required this.endFrameText,
    required this.durationText,
    required this.clipPathText,
    required this.messageText,
    required this.rawText,
  });

  final String timeText;
  final String frameText;
  final String eventKeyText;
  final String sourceKeyText;
  final String statusText;
  final String typeText;
  final String personIdText;
  final String levelText;
  final String startText;
  final String startFrameText;
  final String endText;
  final String endFrameText;
  final String durationText;
  final String clipPathText;
  final String messageText;
  final String rawText;

  String get eventGroupKey {
    final normalizedSourceKey = sourceKeyText.trim();
    final normalizedEventKey = eventKeyText.trim();
    if (normalizedSourceKey.isEmpty || normalizedSourceKey == '-') {
      return normalizedEventKey;
    }
    return '$normalizedSourceKey|$normalizedEventKey';
  }

  String get selectionKey {
    final normalizedRawText = rawText.trim();
    if (normalizedRawText.isNotEmpty) {
      return normalizedRawText;
    }
    return [
      eventGroupKey,
      statusText.trim(),
      timeText.trim(),
      frameText.trim(),
      clipPathText.trim(),
    ].join('|');
  }

  int? get frameValue => _toInt(frameText);
  int? get startFrameValue => _toInt(startFrameText);
  int? get endFrameValue => _toInt(endFrameText);
  bool get hasClip => clipPathText.isNotEmpty && clipPathText != '-';

  bool matchesFrame(int frameValue) {
    // 현재 프레임이 이벤트 시작~종료 구간 안에 있는지 계산해 오버레이 표시에 사용합니다.
    final startFrame = startFrameValue;
    final endFrame = endFrameValue;
    if (startFrame == null) {
      return false;
    }

    if (endFrame != null) {
      return frameValue >= startFrame && frameValue <= endFrame;
    }

    return this.frameValue == frameValue || frameValue >= startFrame;
  }

  static int? _toInt(String value) {
    if (value.isEmpty || value == '-') {
      return null;
    }
    return int.tryParse(value);
  }

  factory EventLogItem.fromLine(String line) {
    final values = <String, String>{};
    final parts = line.split(',');

    String timeText = '-';
    if (parts.isNotEmpty) {
      timeText = parts.first.trim();
    }

    for (final part in parts.skip(1)) {
      final index = part.indexOf('=');
      if (index <= 0) {
        continue;
      }

      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      values[key] = value;
    }

    return EventLogItem(
      timeText: timeText,
      frameText: values['frame'] ?? '-',
      eventKeyText: values['event_key'] ?? '-',
      sourceKeyText: values['source_key'] ?? '-',
      statusText: values['status'] ?? '-',
      typeText: values['type'] ?? '-',
      personIdText: values['person_id'] ?? '-',
      levelText: values['level'] ?? '-',
      startText: values['start'] ?? '-',
      startFrameText: values['start_frame'] ?? '-',
      endText: values['end'] ?? '-',
      endFrameText: values['end_frame'] ?? '-',
      durationText: values['duration'] ?? '-',
      clipPathText: values['clip_path'] ?? '-',
      messageText: values['message'] ?? '',
      rawText: line,
    );
  }
}
