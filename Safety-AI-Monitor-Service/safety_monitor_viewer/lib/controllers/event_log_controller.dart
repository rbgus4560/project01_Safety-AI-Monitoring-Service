// 화면에서 사용하는 데이터와 로딩 상태를 관리하는 controller 파일입니다.
// 상태 변경 후 notifyListeners로 연결된 UI 갱신을 요청합니다.

import 'package:flutter/foundation.dart';

import '../models/event_log_item.dart';
import '../services/event_log_service.dart';

// 기존 txt 로그 파일을 읽고, 화면에서 바로 쓸 이벤트 목록으로 유지하는 controller입니다.
class EventLogController extends ChangeNotifier {
  EventLogController({EventLogService? service})
      : _service = service ?? EventLogService();

  final EventLogService _service;

  String logPath = '';
  String errorText = '';
  List<EventLogItem> items = const [];
  Set<String> selectedKeys = <String>{};

  Future<void> loadLog(String path) async {
    // 파일 로그 모드의 진입점입니다.
    // 로그 파일을 읽고, 이후 파일 변경도 watch해서 UI를 계속 갱신합니다.
    logPath = path;
    errorText = '';

    if (path.isEmpty) {
      items = const [];
      notifyListeners();
      return;
    }

    final nextItems = await _service.readItems(path);
    if (!_isSameItems(items, nextItems)) {
      items = nextItems;
    }

    _service.startWatch(
      path: path,
      onChanged: (nextItems) {
        if (_isSameItems(items, nextItems)) {
          return;
        }
        items = nextItems;
        notifyListeners();
      },
    );
    notifyListeners();
  }

  Future<void> loadLogIfExists(String path) async {
    if (path.isEmpty) {
      return;
    }
    await loadLog(path);
  }

  void disposeController() {
    _service.stopWatch();
  }

  List<EventLogItem> getItemsForFrame(int frameValue) {
    // 같은 event_key가 여러 번 기록될 수 있으므로 최신 항목만 남겨 오버레이 중복을 줄입니다.
    final selectedMap = <String, EventLogItem>{};
    for (final item in items) {
      if (!item.matchesFrame(frameValue)) {
        continue;
      }
      selectedMap[item.eventKeyText] = item;
    }
    return selectedMap.values.toList();
  }

  void selectItem(EventLogItem item) {
    selectedKeys = {item.eventKeyText};
    notifyListeners();
  }

  void clearSelection() {
    selectedKeys = <String>{};
    notifyListeners();
  }

  bool _isSameItems(List<EventLogItem> left, List<EventLogItem> right) {
    // 파일 watch 중 같은 내용으로 여러 번 이벤트가 오면 불필요한 UI 갱신을 줄입니다.
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }

    for (var index = 0; index < left.length; index++) {
      if (left[index].rawText != right[index].rawText) {
        return false;
      }
    }
    return true;
  }
}
