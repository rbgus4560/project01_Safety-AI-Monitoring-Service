// 화면에서 사용하는 데이터와 로딩 상태를 관리하는 controller 파일입니다.
// 상태 변경 후 notifyListeners로 연결된 UI 갱신을 요청합니다.

import 'package:flutter/foundation.dart';

import '../models/event_log_item.dart';

// 파일 로그 모드와 API 서버 모드가 같은 UI 위젯을 재사용할 수 있게 만든
// 공통 이벤트 피드 인터페이스입니다.
abstract class EventFeedSource extends ChangeNotifier {
  // 화면에 표시할 이벤트 목록은 모두 기존 EventLogItem 형태로 노출합니다.
  List<EventLogItem> get logItems;
  Set<String> get selectedKeys;
  String get errorText;
  bool get isLoading;
  DateTime? get lastUpdatedAt;

  // 현재 프레임에 겹쳐 보여줄 이벤트만 골라 오버레이에 전달합니다.
  List<EventLogItem> getLogItemsForFrame(int frameValue);
  void selectLogItem(EventLogItem item);
  void clearSelection();
}
