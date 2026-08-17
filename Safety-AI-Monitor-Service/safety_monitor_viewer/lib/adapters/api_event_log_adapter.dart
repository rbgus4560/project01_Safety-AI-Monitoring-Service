// API 모델을 화면 표시용 모델로 변환하는 파일입니다.
// 서버 응답 필드와 이벤트 로그 표시 필드의 매핑을 담당합니다.

import '../models/api_event_item.dart';
import '../models/event_log_item.dart';

// API 서버의 이벤트 JSON을 기존 화면 모델 EventLogItem으로 바꾸는 어댑터입니다.
// 덕분에 EventLogBox, VideoViewBox를 크게 바꾸지 않고 API 모드를 붙일 수 있습니다.
EventLogItem apiEventToLogItem(ApiEventItem item) {
  final timeText = _firstNonEmpty(item.sourceTimeText, item.createdAt, '-');
  final eventKeyText = _orDash(item.eventKey);
  final statusText = _orDash(item.status);
  final typeText = _orDash(item.eventType);
  final levelText = _orDash(item.level);
  final clipPathText = _orDash(item.clipPath);
  final thumbnailUrlText = _orDash(item.thumbnailUrl);

  return EventLogItem(
    timeText: timeText,
    frameText: _intText(item.frameId),
    eventKeyText: eventKeyText,
    sourceKeyText: _orDash(item.sourceKey),
    statusText: statusText,
    typeText: typeText,
    personIdText: item.personId?.toString() ?? 'unknown',
    levelText: levelText,
    startText: _orDash(item.startedSourceTimeText),
    startFrameText: _nullableIntText(item.startedFrameId),
    endText: _orDash(item.endedSourceTimeText),
    endFrameText: _nullableIntText(item.endedFrameId),
    durationText: _durationText(item.durationSeconds),
    clipPathText: clipPathText,
    thumbnailUrlText: thumbnailUrlText,
    messageText: item.message,
    rawText: _buildRawText(item, timeText),
  );
}

List<EventLogItem> apiEventsToLogItems(List<ApiEventItem> items) {
  return items.map(apiEventToLogItem).toList(growable: false);
}

String _orDash(String value) {
  if (value.trim().isEmpty) {
    return '-';
  }
  return value;
}

String _intText(int value) {
  return value.toString();
}

String _nullableIntText(int? value) {
  if (value == null) {
    return '-';
  }
  return value.toString();
}

String _durationText(double value) {
  if (value <= 0) {
    return '-';
  }
  return '${value.toStringAsFixed(1)}s';
}

String _firstNonEmpty(String first, String second, String fallback) {
  if (first.trim().isNotEmpty) {
    return first;
  }
  if (second.trim().isNotEmpty) {
    return second;
  }
  return fallback;
}

String _buildRawText(ApiEventItem item, String timeText) {
  // 파일 로그 모드와 비슷한 문자열 형태를 남겨 비교나 디버깅이 쉬우게 합니다.
  return [
    timeText,
    'frame=${_intText(item.frameId)}',
    'event_key=${_orDash(item.eventKey)}',
    'source_key=${_orDash(item.sourceKey)}',
    'status=${_orDash(item.status)}',
    'type=${_orDash(item.eventType)}',
    'person_id=${item.personId?.toString() ?? 'unknown'}',
    'level=${_orDash(item.level)}',
    'start=${_orDash(item.startedSourceTimeText)}',
    'start_frame=${_nullableIntText(item.startedFrameId)}',
    'end=${_orDash(item.endedSourceTimeText)}',
    'end_frame=${_nullableIntText(item.endedFrameId)}',
    'duration=${_durationText(item.durationSeconds)}',
    'clip_path=${_orDash(item.clipPath)}',
    'thumbnail_url=${_orDash(item.thumbnailUrl)}',
    'message=${item.message}',
  ].join(',');
}
