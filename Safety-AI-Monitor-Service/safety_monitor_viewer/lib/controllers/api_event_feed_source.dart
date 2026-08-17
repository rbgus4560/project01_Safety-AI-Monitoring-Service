// 화면에서 사용하는 데이터와 로딩 상태를 관리하는 controller 파일입니다.
// 상태 변경 후 notifyListeners로 연결된 UI 갱신을 요청합니다.

import '../models/event_log_item.dart';
import 'api_event_controller.dart';
import 'event_feed_source.dart';

// API 서버에서 가져온 이벤트를 기존 UI가 같은 방식으로 소비할 수 있게 하는 어댑터입니다.
class ApiEventFeedSource extends EventFeedSource {
  ApiEventFeedSource(this.controller) {
    controller.addListener(_handleControllerChanged);
  }

  final ApiEventController controller;
  String _sourceKeyFilter = '';

  @override
  List<EventLogItem> get logItems => _sourceKeyFilter.isEmpty
      ? controller.logItems
      : controller.getLogItemsForSource(_sourceKeyFilter);

  @override
  Set<String> get selectedKeys => controller.selectedKeys;

  @override
  String get errorText => controller.errorMessage ?? '';

  @override
  bool get isLoading => controller.isLoading;

  @override
  DateTime? get lastUpdatedAt => controller.lastUpdatedAt;

  @override
  List<EventLogItem> getLogItemsForFrame(int frameValue) {
    return controller.getLogItemsForFrame(frameValue);
  }

  @override
  void selectLogItem(EventLogItem item) {
    controller.selectLogItem(item);
  }

  @override
  void clearSelection() {
    controller.clearSelection();
  }

  void setSourceKeyFilter(String sourceKey) {
    final normalized = sourceKey.trim();
    if (_sourceKeyFilter == normalized) {
      return;
    }
    _sourceKeyFilter = normalized;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    // API controller의 상태 변화도 EventFeedSource 변화로 연결합니다.
    notifyListeners();
  }
}
