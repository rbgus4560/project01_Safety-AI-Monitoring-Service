// Flutter 쪽에서 서버 API나 로컬 프로세스 같은 외부 기능을 호출하는 파일입니다.
// HTTP 주소 생성, 요청 전송, 응답 JSON 변환 흐름이 포함되어 있습니다.

import 'dart:async';
import 'dart:io';

import '../models/event_log_item.dart';

// 이 파일은 기존 txt 로그 파일을 읽고 변화 여부를 감시하는 서비스입니다.
// 파일 로그 모드에서만 사용되며, API 모드와는 별도 흐름입니다.

class EventLogService {
  Timer? _timer;
  String _lastSignature = '';

  void startWatch({
    required String path,
    required void Function(List<EventLogItem> items) onChanged,
  }) {
    stopWatch();
    _lastSignature = '';

    // 일정 시간마다 로그 파일을 다시 읽는다
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      try {
        final items = await readItems(path);
        final signature = _buildSignature(items);
        if (signature == _lastSignature) {
          return;
        }

        _lastSignature = signature;
        onChanged(items);
      } on FileSystemException {
        // 다른 프로세스가 파일을 갱신 중이면 다음 주기에 다시 읽는다
      } catch (_) {
        // 일시적인 읽기 문제는 다음 주기에 다시 시도한다
      }
    });
  }

  void stopWatch() {
    _timer?.cancel();
    _timer = null;
    _lastSignature = '';
  }

  Future<List<EventLogItem>> readItems(String path) async {
    if (path.isEmpty) {
      return const [];
    }

    final file = File(path);
    if (!await file.exists()) {
      return const [];
    }

    final lines = await file.readAsLines();
    final latestMap = <String, EventLogItem>{};

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty || !trimmedLine.contains('event_key=')) {
        continue;
      }

      final item = EventLogItem.fromLine(trimmedLine);
      final eventGroupKey = item.eventGroupKey;
      if (eventGroupKey.isEmpty || eventGroupKey == '-') {
        continue;
      }

      // 같은 이벤트는 가장 마지막 줄만 사용한다
      latestMap.remove(eventGroupKey);
      latestMap[eventGroupKey] = item;
    }

    return latestMap.values.toList().reversed.toList();
  }

  String _buildSignature(List<EventLogItem> items) {
    return items.map((item) => item.rawText).join('\n');
  }
}
