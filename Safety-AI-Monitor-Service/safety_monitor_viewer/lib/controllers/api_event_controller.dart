// 화면에서 사용하는 데이터와 로딩 상태를 관리하는 controller 파일입니다.
// 상태 변경 후 notifyListeners로 연결된 UI 갱신을 요청합니다.

import 'package:flutter/foundation.dart';

import '../adapters/api_event_log_adapter.dart';
import '../models/api_event_item.dart';
import '../models/api_server_health.dart';
import '../models/event_log_item.dart';
import '../services/event_api_service.dart';

// FastAPI 서버에서 이벤트와 health 정보를 가져와 API 모드 상태를 관리하는 controller입니다.
class ApiEventController extends ChangeNotifier {
  ApiEventController({EventApiService? service})
    : _service = service ?? EventApiService();

  final EventApiService _service;

  List<ApiEventItem> items = const [];
  Set<String> selectedKeys = <String>{};
  bool isLoading = false;
  String? errorMessage;
  DateTime? lastUpdatedAt;
  ApiServerHealth? serverHealth;
  bool isCheckingHealth = false;
  String? healthErrorMessage;
  DateTime? lastHealthCheckedAt;

  // 화면 위젯은 기존 EventLogItem을 기대하므로 API 응답을 어댑터로 변환해서 노출합니다.
  List<EventLogItem> get logItems =>
      apiEventsToLogItems(_visibleLogItems(items));

  List<EventLogItem> getLogItemsForSource(String sourceKey) {
    final normalizedSourceKey = sourceKey.trim();
    if (normalizedSourceKey.isEmpty) {
      return logItems;
    }
    final filteredItems = items
        .where((item) => item.sourceKey.trim() == normalizedSourceKey)
        .toList(growable: false);
    return apiEventsToLogItems(_visibleLogItems(filteredItems));
  }

  Future<void> loadLatestEvents({
    int? limit,
    String? eventType,
    String? status,
  }) async {
    await loadEvents(
      latestOnly: true,
      limit: limit,
      eventType: eventType,
      status: status,
    );
  }

  Future<void> loadEvents({
    bool latestOnly = false,
    int? limit,
    String? eventType,
    String? status,
  }) async {
    // GET /api/events 또는 latest_only=true 조회를 담당합니다.
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final nextItems = await _service.fetchEvents(
        latestOnly: latestOnly,
        limit: limit,
        eventType: eventType,
        status: status,
      );
      items = nextItems;
      lastUpdatedAt = DateTime.now();
    } catch (error) {
      errorMessage = 'Failed to load API events: $error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<ApiEventItem?> loadEventDetail(
    String eventKey, {
    String? sourceKey,
  }) async {
    // 선택한 이벤트 한 건의 상세 정보를 GET /api/events/detail로 조회합니다.
    final normalizedEventKey = eventKey.trim();
    if (normalizedEventKey.isEmpty) {
      errorMessage = 'eventKey is required.';
      notifyListeners();
      return null;
    }

    try {
      errorMessage = null;
      final item = await _service.fetchEventDetail(
        normalizedEventKey,
        sourceKey: sourceKey,
      );
      if (item == null) {
        errorMessage = 'Failed to load API event detail.';
      }
      notifyListeners();
      return item;
    } catch (error) {
      errorMessage = 'Failed to load API event detail: $error';
      notifyListeners();
      return null;
    }
  }

  Future<void> checkHealth() async {
    // GET /health로 서버 상태와 events.jsonl 존재 여부를 확인합니다.
    isCheckingHealth = true;
    healthErrorMessage = null;
    notifyListeners();

    try {
      final nextHealth = await _service.fetchHealth();
      serverHealth = nextHealth;
      if (nextHealth == null) {
        healthErrorMessage = 'API 서버 상태를 확인할 수 없습니다.';
      }
      lastHealthCheckedAt = DateTime.now();
    } catch (_) {
      serverHealth = null;
      healthErrorMessage = 'API 서버 상태를 확인할 수 없습니다.';
      lastHealthCheckedAt = DateTime.now();
    } finally {
      isCheckingHealth = false;
      notifyListeners();
    }
  }

  Future<bool> resetServerData({
    required String sourceKey,
    required String sourceSlug,
  }) async {
    try {
      final ok = await _service.resetServerData(
        sourceKey: sourceKey,
        sourceSlug: sourceSlug,
      );
      if (!ok) {
        errorMessage = '서버 이벤트/클립 초기화에 실패했습니다.';
        notifyListeners();
      }
      return ok;
    } catch (error) {
      errorMessage = '서버 이벤트/클립 초기화에 실패했습니다: $error';
      notifyListeners();
      return false;
    }
  }


  Future<bool> clearAllEventData() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final ok = await _service.clearAllEventData();
      if (ok) {
        items = const [];
        selectedKeys.clear();
        lastUpdatedAt = DateTime.now();
      } else {
        errorMessage = '이벤트 DB/클립 초기화에 실패했습니다.';
      }
      return ok;
    } catch (error) {
      errorMessage = '이벤트 DB/클립 초기화에 실패했습니다: $error';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
  List<EventLogItem> getLogItemsForTime(double secondsValue) {
    return apiEventsToLogItems(getItemsForTime(secondsValue));
  }

  List<EventLogItem> getLogItemsForTimeForSource(
    double secondsValue, {
    required String sourceKey,
  }) {
    return apiEventsToLogItems(
      getItemsForTimeForSource(secondsValue, sourceKey: sourceKey),
    );
  }

  List<EventLogItem> getLogItemsForFrame(int frameValue) {
    // 기존 공통 인터페이스 호환용 메서드입니다.
    // 현재 화면의 실제 오버레이/이동은 source_time_seconds 기준을 사용합니다.
    return logItems;
  }

  List<ApiEventItem> getItemsForTime(double secondsValue) {
    return _getItemsForTimeFromSourceList(items, secondsValue);
  }

  List<ApiEventItem> getItemsForTimeForSource(
    double secondsValue, {
    required String sourceKey,
  }) {
    final normalizedSourceKey = sourceKey.trim();
    if (normalizedSourceKey.isEmpty) {
      return const [];
    }
    final sourceItems = items
        .where((item) => item.sourceKey.trim() == normalizedSourceKey)
        .toList(growable: false);
    return _getItemsForTimeFromSourceList(sourceItems, secondsValue);
  }

  List<ApiEventItem> _getItemsForTimeFromSourceList(
    List<ApiEventItem> sourceItems,
    double secondsValue,
  ) {
    final selectedMap = <String, ApiEventItem>{};
    final orderedItems = [...sourceItems]..sort(_compareByTimeline);
    for (final item in orderedItems) {
      if (item.sourceTimeSeconds.isNaN ||
          item.sourceTimeSeconds > secondsValue) {
        continue;
      }
      final compositeKey = _sourceEventKey(item.sourceKey, item.eventKey);
      if (selectedMap.containsKey(compositeKey)) {
        selectedMap.remove(compositeKey);
      }
      selectedMap[compositeKey] = item;
    }
    selectedMap.removeWhere((_, item) => !_isVisibleAtTime(item, secondsValue));
    return selectedMap.values.toList(growable: false);
  }

  ApiEventItem? findItemByEventKey(String eventKey) {
    final normalizedEventKey = eventKey.trim();
    if (normalizedEventKey.isEmpty) {
      return null;
    }

    final orderedItems = [...items]..sort(_compareByTimeline);
    for (final item in orderedItems.reversed) {
      if (item.eventKey == normalizedEventKey) {
        return item;
      }
    }
    return null;
  }

  ApiEventItem? findItemByEventKeyForSource(
    String eventKey, {
    required String sourceKey,
  }) {
    final normalizedEventKey = eventKey.trim();
    final normalizedSourceKey = sourceKey.trim();
    if (normalizedEventKey.isEmpty || normalizedSourceKey.isEmpty) {
      return null;
    }

    final orderedItems = [...items]..sort(_compareByTimeline);
    for (final item in orderedItems.reversed) {
      if (item.eventKey == normalizedEventKey &&
          item.sourceKey.trim() == normalizedSourceKey) {
        return item;
      }
    }
    return null;
  }

  ApiEventItem? findExactItemForLogItem(EventLogItem logItem) {
    final normalizedRawText = logItem.rawText.trim();
    final normalizedSelectionKey = logItem.selectionKey.trim();
    final orderedItems = [...items]..sort(_compareByTimeline);
    for (final item in orderedItems.reversed) {
      final candidateLogItem = apiEventToLogItem(item);
      if (normalizedRawText.isNotEmpty &&
          candidateLogItem.rawText.trim() == normalizedRawText) {
        return item;
      }
      if (candidateLogItem.selectionKey.trim() == normalizedSelectionKey) {
        return item;
      }
    }
    return null;
  }

  void selectLogItem(EventLogItem item) {
    selectedKeys = {item.selectionKey};
    notifyListeners();
  }

  void clearSelection() {
    selectedKeys = <String>{};
    notifyListeners();
  }

  void clear() {
    items = const [];
    selectedKeys = <String>{};
    errorMessage = null;
    lastUpdatedAt = null;
    notifyListeners();
  }

  // ignore: unused_element
  List<ApiEventItem> _latestItemsBySourceAndEventKey(
    List<ApiEventItem> sourceItems,
  ) {
    final selectedMap = <String, ApiEventItem>{};
    final orderedItems = [...sourceItems]..sort(_compareByTimeline);
    for (final item in orderedItems) {
      final compositeKey = _sourceEventKey(item.sourceKey, item.eventKey);
      if (selectedMap.containsKey(compositeKey)) {
        selectedMap.remove(compositeKey);
      }
      selectedMap[compositeKey] = item;
    }
    return selectedMap.values.toList(growable: false);
  }

  List<ApiEventItem> _visibleLogItems(List<ApiEventItem> sourceItems) {
    final visibleItems = _latestItemsBySourceAndEventKey(sourceItems)
      ..sort(_compareByTimeline);
    return visibleItems;
  }

  String _sourceEventKey(String sourceKey, String eventKey) {
    final normalizedSourceKey = sourceKey.trim();
    final normalizedEventKey = eventKey.trim();
    if (normalizedSourceKey.isEmpty) {
      return normalizedEventKey;
    }
    return '$normalizedSourceKey|$normalizedEventKey';
  }

  int _compareByTimeline(ApiEventItem left, ApiEventItem right) {
    final timeCompare = left.sourceTimeSeconds.compareTo(
      right.sourceTimeSeconds,
    );
    if (timeCompare != 0) {
      return timeCompare;
    }
    return _statusOrder(left.status).compareTo(_statusOrder(right.status));
  }

  bool _isVisibleAtTime(ApiEventItem item, double secondsValue) {
    final startTime = _resolveStartTime(item);
    if (startTime == null || secondsValue < startTime) {
      return false;
    }

    final endTime = _resolveEndTime(item);
    if (endTime != null && secondsValue > endTime) {
      return false;
    }

    return true;
  }

  double? _resolveStartTime(ApiEventItem item) {
    final parsed = _parseVideoTime(item.startedSourceTimeText);
    if (parsed != null) {
      return parsed;
    }
    if (!item.sourceTimeSeconds.isNaN) {
      return item.sourceTimeSeconds;
    }
    return null;
  }

  double? _resolveEndTime(ApiEventItem item) {
    final parsed = _parseVideoTime(item.endedSourceTimeText);
    if (parsed != null) {
      return parsed;
    }
    if (item.status.trim().toUpperCase() == 'END' &&
        !item.sourceTimeSeconds.isNaN) {
      return item.sourceTimeSeconds;
    }
    return null;
  }

  double? _parseVideoTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return null;
    }

    final parts = trimmed.split(':');
    if (parts.length < 2 || parts.length > 3) {
      return null;
    }

    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]);
      final seconds = double.tryParse(parts[1]);
      if (minutes == null || seconds == null) {
        return null;
      }
      return (minutes * 60) + seconds;
    }

    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }
    return (hours * 3600) + (minutes * 60) + seconds;
  }

  int _statusOrder(String status) {
    switch (status.trim().toUpperCase()) {
      case 'START':
        return 0;
      case 'ACTIVE':
        return 1;
      case 'END':
        return 2;
      default:
        return 3;
    }
  }
}
