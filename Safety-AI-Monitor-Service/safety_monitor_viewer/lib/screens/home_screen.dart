// 화면을 구성하는 Flutter 코드이며 상태값과 버튼 동작이 모여 있습니다.
// initState, 서버 통신 함수, build 메서드가 같은 화면 흐름을 구성합니다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/api_event_controller.dart';
import '../controllers/api_event_feed_source.dart';
import '../controllers/video_panel_controller.dart';
import '../models/api_event_item.dart';
import '../models/event_log_item.dart';
import '../models/frame_detection_snapshot.dart';
import '../models/source_item.dart';
import '../models/source_overview_item.dart';
import '../models/source_rule_config.dart';
import '../models/source_runtime_status.dart';
import '../models/video_overlay_detection.dart';
import '../services/event_api_service.dart';
import '../services/portfolio_api_service.dart';
import '../widgets/event_log_box.dart';
import '../widgets/video_view_box.dart';
import '../session/auth_session.dart';
import '../ui/portfolio_theme.dart';
import 'portfolio/admin_management_screen.dart';
import 'portfolio/event_history_screen.dart';
import 'portfolio/login_screen.dart';
import 'portfolio/rule_settings_screen.dart';

// 메인 화면입니다.
// API 서버 기준 이벤트 표시와 영상 재생을 함께 조합합니다.

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const bool _isViewerReadOnly = true;
  static const Duration _apiAutoRefreshInterval = Duration(seconds: 30);
  static const Duration _viewerClientHeartbeatTimeout = Duration(seconds: 20);
  late final VideoPanelController _emptyVideoController;
  late final EventApiService eventApiService;
  late final ApiEventController apiEventController;
  late final ApiEventFeedSource apiEventFeed;
  final PortfolioApiService _portfolioApi = PortfolioApiService();
  final ScrollController appScrollController = ScrollController();
  int _layoutCount = 4;
  int? _activeCameraGroupId;
  List<Map<String, dynamic>> _cameraGroups = const [];
  List<String> _savedSourceOrder = const [];
  bool _isSavingLayout = false;
  final ScrollController monitoringGridScrollController = ScrollController();
  final List<_SourcePanelSlot> _sourceSlots = [];
  final Set<String> _slotCreationSourceKeys = <String>{};
  String _activeSlotId = '';
  ApiEventItem? selectedApiEventDetail;
  bool isLoadingApiDetail = false;
  String? apiDetailErrorMessage;
  Timer? apiAutoRefreshTimer;
  Timer? frameDetectionRefreshTimer;
  Timer? sourceStatusSyncTimer;
  Timer? previewRefreshTimer;
  Timer? realtimeReconnectTimer;
  Timer? queuedRealtimeRefreshTimer;
  StreamSubscription? realtimeSocketSubscription;
  WebSocket? realtimeSocket;
  DateTime? frameDetectionLogModifiedAt;
  String frameDetectionSourceKey = '';
  List<FrameDetectionSnapshot> frameDetectionSnapshots = const [];
  Map<String, FrameDetectionSnapshot> frameDetectionBySourceKey = const {};
  Map<String, double> lastFrameDetectionRequestSecondsBySourceKey = const {};
  Map<String, String> lastFrameDetectionStatusUpdatedAtBySourceKey = const {};
  Map<String, SourceOverviewItem> sourceOverviewsByKey = const {};
  Map<String, SourceItem> registeredSourcesByKey = const {};
  Map<String, SourceRuntimeStatus> sourceStatusesByKey = const {};
  String lastFrameDetectionRequestSourceKey = '';
  double lastFrameDetectionRequestSeconds = -1;
  String lastFrameDetectionStatusUpdatedAt = '';
  bool isRealtimeConnected = false;
  bool pendingRealtimeEventsRefresh = false;
  bool pendingRealtimeSourcesRefresh = false;
  bool pendingRealtimeStatusesRefresh = false;
  bool isSavingRuleConfig = false;
  bool isEditingDangerZone = false;
  RoiRect? pendingDangerZoneRoi;
  String _maximizedSlotId = '';
  int _ruleConfigSaveTicket = 0;
  int previewRefreshCacheBust = 0;

  @override
  void initState() {
    super.initState();
    _emptyVideoController = VideoPanelController();
    eventApiService = EventApiService(baseUrl: AuthSession.instance.serverBaseUrl);
    apiEventController = ApiEventController(service: eventApiService);
    apiEventFeed = ApiEventFeedSource(apiEventController);
    unawaited(_initializeServerConnection());
    unawaited(_loadViewerPreferences());
    _startApiAutoRefresh();
    _startFrameDetectionRefresh();
    _startSourceStatusSync();
    _startPreviewRefresh();
  }

  @override
  void dispose() {
    apiAutoRefreshTimer?.cancel();
    frameDetectionRefreshTimer?.cancel();
    sourceStatusSyncTimer?.cancel();
    previewRefreshTimer?.cancel();
    realtimeReconnectTimer?.cancel();
    queuedRealtimeRefreshTimer?.cancel();
    realtimeSocketSubscription?.cancel();
    realtimeSocket?.close();
    for (final slot in _sourceSlots) {
      slot.controller.disposeController();
    }
    _emptyVideoController.disposeController();
    eventApiService.dispose();
    _portfolioApi.dispose();
    apiEventFeed.dispose();
    appScrollController.dispose();
    monitoringGridScrollController.dispose();
    super.dispose();
  }

  _SourcePanelSlot? get _activeSlot {
    for (final slot in _sourceSlots) {
      if (slot.slotId == _activeSlotId) {
        return slot;
      }
    }
    return null;
  }

  SourceItem? get _activeSourceItem {
    final sourceKey = selectedSourceKey.trim();
    if (sourceKey.isEmpty) {
      return null;
    }
    return registeredSourcesByKey[sourceKey];
  }

  SourceRuleConfig get _activeRuleConfig =>
      _activeSourceItem?.ruleConfig ??
      const SourceRuleConfig(
        useNoHelmetRule: true,
        useDangerZoneRule: false,
        dangerZoneRoi: null,
      );

  VideoPanelController get videoController =>
      _activeSlot?.controller ?? _emptyVideoController;

  String get selectedSourceType => _activeSlot?.sourceType ?? '';

  String get selectedSourceValue => _activeSlot?.sourceValue ?? '';

  String get selectedSourceKey => _activeSlot?.sourceKey ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, size: 24),
            const SizedBox(width: 8),
            const Text(
              'SAFETY MONITOR',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 22, color: PortfolioColors.border),
            const SizedBox(width: 16),
            Text(
              _formatDateTime(DateTime.now()),
              style: const TextStyle(
                color: PortfolioColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EventHistoryScreen()),
            ),
            icon: const Icon(Icons.event_note_outlined, size: 17),
            label: const Text('이벤트'),
          ),
          if (AuthSession.instance.isAdmin)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RuleSettingsScreen()),
              ),
              icon: const Icon(Icons.tune, size: 17),
              label: const Text('카메라 설정'),
            ),
          if (AuthSession.instance.isAdmin)
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminManagementScreen()),
              ),
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
              label: const Text('관리'),
            ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Container(width: 1, color: PortfolioColors.border),
          ),
          const SizedBox(width: 6),
          Center(
            child: Text(
              AuthSession.instance.displayName.isEmpty
                  ? AuthSession.instance.username
                  : AuthSession.instance.displayName,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '로그아웃',
            onPressed: () {
              AuthSession.instance.clear();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const PortfolioLoginScreen()),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout, size: 19),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          const minContentWidth = 1280.0;

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(constraints.maxWidth, minContentWidth),
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 왼쪽 카메라 목록
                    SizedBox(
                      width: 250,
                      child: _buildCameraListPanel(),
                    ),

                    const SizedBox(width: 10),

                    // 중앙 관제 화면
                    Expanded(
                      child: _buildViewerVideoGridPanel(),
                    ),

                    const SizedBox(width: 10),

                    // 오른쪽 이벤트 / 룰 설정
                    SizedBox(
                      width: 335,
                      child: _buildInspectorPanel(),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildViewerSourceHeader() {
    final activePath = videoController.videoPath.trim();
    final sourceLabel = activePath.isEmpty ? 'No source opened' : activePath;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server Source', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(sourceLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(
            _buildSourceHint(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            sourceOverviewsByKey.isEmpty
                ? 'No server sources available yet.'
                : 'Server sources: ${sourceOverviewsByKey.length} / Active panel: ${_buildActiveSourceLabel()}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (selectedSourceKey.isNotEmpty ||
              videoController.canReturnFromReplay) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (selectedSourceKey.isNotEmpty)
                  OutlinedButton(
                    onPressed: _clearSelectedSource,
                    child: const Text('Clear Selection'),
                  ),
                if (videoController.canReturnFromReplay) ...[
                  if (selectedSourceKey.isNotEmpty) const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _returnToLive,
                    child: const Text('Close Clip'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildViewerRoleBanner() {
    final overviewItems = sourceOverviewsByKey.values.toList(growable: false);
    final runningCount = overviewItems.where((item) => item.isRunning).length;
    final errorCount = overviewItems
        .where((item) => item.errorMessage.trim().isNotEmpty)
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131d2a),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF28415D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_outlined, color: Color(0xFF7EC8FF)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Viewer Mode',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'This app is for server data lookup only. Register sources, own weights, and run analysis from the client app.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildViewerStatChip(
                      label: 'Clients',
                      value: _countActiveViewerClients().toString(),
                    ),
                    _buildViewerStatChip(
                      label: 'Sources',
                      value: overviewItems.length.toString(),
                    ),
                    _buildViewerStatChip(
                      label: 'Running',
                      value: runningCount.toString(),
                      accentColor: Colors.green,
                    ),
                    _buildViewerStatChip(
                      label: 'Errors',
                      value: errorCount.toString(),
                      accentColor: errorCount > 0
                          ? Colors.redAccent
                          : Colors.blueGrey,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildViewerStatChip({
    required String label,
    required String value,
    Color accentColor = const Color(0xFF7EC8FF),
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF172435),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  String _buildViewerSidebarSubtitle(
    _SourcePanelSlot slot,
    SourceOverviewItem overview,
  ) {
    final state = _describeSlotStatus(slot);
    final progressText = _buildSourceProgressText(
      registeredSourcesByKey[slot.sourceKey.trim()],
      sourceStatusesByKey[slot.sourceKey.trim()],
    );
    final detailParts = <String>[
      if (overview.sourceType.trim().isNotEmpty) overview.sourceType.trim(),
      if (progressText.trim().isNotEmpty && progressText.trim() != '-')
        progressText.trim(),
      state,
    ];
    return detailParts.join(' | ');
  }

  Widget buildSourceSidebar() {
    final slots = [..._sourceSlots];
    slots.sort((left, right) {
      final leftOverview = sourceOverviewsByKey[left.sourceKey.trim()];
      final rightOverview = sourceOverviewsByKey[right.sourceKey.trim()];
      final leftClient = leftOverview?.clientId.trim() ?? '';
      final rightClient = rightOverview?.clientId.trim() ?? '';
      final clientOrder = leftClient.compareTo(rightClient);
      if (clientOrder != 0) {
        return clientOrder;
      }
      return left.label.compareTo(right.label);
    });
    return _buildPanelCard(
      title: '카메라 목록',
      child: slots.isEmpty
          ? const Center(child: Text('영상 또는 스트림을 추가하면 여기에 표시됩니다.'))
          : Column(
              children: [
                for (var index = 0; index < slots.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final slot = slots[index];
                      final isSelected = slot.slotId == _activeSlotId;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => unawaited(_setActiveSlot(slot.slotId)),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF242833)
                                : const Color(0xFF181B22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _colorForSlotStatus(slot),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      slot.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _describeSlotStatus(slot),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: '소스 삭제',
                                onPressed: _isViewerReadOnly
                                    ? null
                                    : () => unawaited(
                                        _handleSlotDeleteAction(slot),
                                      ),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }

  // ignore: unused_element
  Widget _buildServerSourceSidebar() {
    final slots = [..._sourceSlots];
    slots.sort((left, right) {
      final leftOverview = sourceOverviewsByKey[left.sourceKey.trim()];
      final rightOverview = sourceOverviewsByKey[right.sourceKey.trim()];
      final leftClient = leftOverview?.clientId.trim() ?? '';
      final rightClient = rightOverview?.clientId.trim() ?? '';
      final clientOrder = leftClient.compareTo(rightClient);
      if (clientOrder != 0) {
        return clientOrder;
      }
      return left.label.compareTo(right.label);
    });

    return _buildPanelCard(
      title: 'Server Sources',
      child: slots.isEmpty
          ? const Center(
              child: Text(
                'No source has been uploaded from connected clients yet.',
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < slots.length; index++) ...[
                  if (index > 0) const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final slot = slots[index];
                      final isSelected = slot.slotId == _activeSlotId;
                      final overview =
                          sourceOverviewsByKey[slot.sourceKey.trim()];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => unawaited(_setActiveSlot(slot.slotId)),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF242833)
                                : const Color(0xFF181B22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _colorForSlotStatus(slot),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _displayLabelForSlot(slot),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      overview == null
                                          ? _describeSlotStatus(slot)
                                          : _buildViewerSidebarSubtitle(
                                              slot,
                                              overview,
                                            ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white60),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.remove_red_eye_outlined,
                                color: Colors.white54,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }

  Widget buildVideoGridPanel() {
    if (_sourceSlots.isEmpty) {
      return _buildPanelCard(
        title: '실시간 모니터',
        child: const Center(
          child: Text('서버에 저장된 소스를 열면 여러 영상을 동시에 비교해서 볼 수 있습니다.'),
        ),
      );
    }

    return _buildPanelCard(
      title: '실시간 모니터',
      trailing: Text(
        '가로 2열',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.white60),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.08,
        ),
        itemCount: _sourceSlots.length,
        itemBuilder: (context, index) {
          final slot = _sourceSlots[index];
          return _buildDraggableVideoTile(slot);
        },
      ),
    );
  }

  Widget _buildCameraListPanel() {
    return _buildPanelCard(
      title: '카메라',
      child: _sourceSlots.isEmpty
          ? const Center(child: Text('연결된 카메라가 없습니다.'))
          : ListView.builder(
              itemCount: _sourceSlots.length,
              itemBuilder: (context, index) {
                final slot = _sourceSlots[index];
                return _buildDraggableCameraListItem(slot, index);
              },
            ),
      expandChild: true,
    );
  }

  Widget _buildDraggableCameraListItem(_SourcePanelSlot slot, int index) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;
        return DragTarget<_SourcePanelSlot>(
          onWillAcceptWithDetails: (details) =>
              details.data.slotId != slot.slotId,
          onAcceptWithDetails: (details) =>
              _swapSourceSlots(details.data.slotId, slot.slotId),
          builder: (context, candidateData, rejectedData) {
            final isDropTarget = candidateData.isNotEmpty;
            final item = _buildCameraListItem(
              slot,
              index,
              isDropTarget: isDropTarget,
            );
            return Padding(
              key: ValueKey(slot.slotId),
              padding: EdgeInsets.only(
                bottom: index == _sourceSlots.length - 1 ? 0 : 8,
              ),
              child: LongPressDraggable<_SourcePanelSlot>(
                data: slot,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: SizedBox(
                  width: itemWidth,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 12,
                    shadowColor: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                    child: Opacity(
                      opacity: 0.92,
                      child: _buildCameraListItem(
                        slot,
                        index,
                        isDragging: true,
                      ),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.30, child: item),
                child: item,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCameraListItem(
    _SourcePanelSlot slot,
    int index, {
    bool isDropTarget = false,
    bool isDragging = false,
  }) {
    final isSelected = slot.slotId == _activeSlotId;
    final sourceKey = slot.sourceKey.trim();
    final status = sourceStatusesByKey[sourceKey];
    final overview = sourceOverviewsByKey[sourceKey];
    final title = _buildCameraDisplayName(slot, index);
    final subtitle = _resolveClientConnectionStatus(slot).label;
    final baseColor = isSelected
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
        : const Color(0xFF11151B);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDropTarget
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: isDropTarget ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isDragging
              ? null
              : () => unawaited(_toggleActiveSlot(slot.slotId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: Colors.white54,
                ),
                const SizedBox(width: 6),
                _buildConnectionStatusDot(slot),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          if (AuthSession.instance.isAdmin)
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isDragging
                                  ? null
                                  : () => unawaited(_editDisplayNameForSlot(slot)),
                              child: const Padding(
                                padding: EdgeInsets.all(3),
                                child: Icon(Icons.edit_outlined, size: 15),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status?.state.trim().isNotEmpty == true
                            ? '${status!.state} · $subtitle'
                            : (overview?.state.trim().isNotEmpty == true
                                  ? '${overview!.state} · $subtitle'
                                  : subtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildCameraDisplayName(_SourcePanelSlot slot, int index) {
    return _displayLabelForSlot(slot, fallbackIndex: index);
  }

  String _displayLabelForSlot(_SourcePanelSlot slot, {int? fallbackIndex}) {
    final sourceKey = slot.sourceKey.trim();
    final source = registeredSourcesByKey[sourceKey];
    if (source != null) {
      return _displayLabelForSource(source, fallbackIndex: fallbackIndex);
    }
    final overview = sourceOverviewsByKey[sourceKey];
    final displayName = overview?.displayName.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return _buildNewCameraLabel(
      clientId: overview?.clientId ?? '',
      sessionId: overview?.sessionId ?? '',
      sourceValue: slot.sourceValue,
      fallbackIndex: fallbackIndex,
    );
  }

  String _displayLabelForSource(SourceItem source, {int? fallbackIndex}) {
    final displayName = source.displayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return _buildNewCameraLabel(
      clientId: source.clientId,
      sessionId: source.sessionId,
      sourceValue: source.sourceValue,
      fallbackIndex: fallbackIndex,
    );
  }

  String _displayLabelForSourceKey(String sourceKey) {
    final normalized = sourceKey.trim();
    if (normalized.isEmpty || normalized == '-') {
      return '';
    }
    final source = registeredSourcesByKey[normalized];
    if (source != null) {
      return _displayLabelForSource(source);
    }
    final overview = sourceOverviewsByKey[normalized];
    if (overview != null) {
      final displayName = overview.displayName.trim();
      if (displayName.isNotEmpty) {
        return displayName;
      }
      return _buildNewCameraLabel(
        clientId: overview.clientId,
        sessionId: overview.sessionId,
        sourceValue: overview.sourceValue,
      );
    }
    final slot = _findSourceSlotByKey(normalized);
    if (slot != null) {
      return _displayLabelForSlot(slot);
    }
    return '';
  }

  String _buildNewCameraLabel({
    required String clientId,
    required String sessionId,
    required String sourceValue,
    int? fallbackIndex,
  }) {
    final owner = (clientId.trim().isNotEmpty
        ? clientId.trim()
        : sessionId.trim());
    final cameraValue = sourceValue.trim().isEmpty ? '0' : sourceValue.trim();
    if (owner.isNotEmpty) {
      return '새 카메라 감지됨: $owner / camera $cameraValue';
    }
    final cameraNumber = fallbackIndex == null
        ? cameraValue
        : '${fallbackIndex + 1}';
    return '새 카메라 $cameraNumber / camera $cameraValue';
  }

  Future<void> _editDisplayNameForSlot(_SourcePanelSlot slot) async {
    final sourceKey = slot.sourceKey.trim();
    if (sourceKey.isEmpty) {
      return;
    }
    final currentSource = registeredSourcesByKey[sourceKey];
    final currentOverview = sourceOverviewsByKey[sourceKey];
    final controller = TextEditingController(
      text: currentSource?.displayName.trim().isNotEmpty == true
          ? currentSource!.displayName.trim()
          : (currentOverview?.displayName.trim() ?? ''),
    );
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('카메라 이름 편집'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '표시 이름',
              hintText: '예: 입구 카메라 또는 기존 표시 이름',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (nextName == null) {
      return;
    }
    final updated = await eventApiService.updateSourceDisplayName(
      sourceKey: sourceKey,
      displayName: nextName,
    );
    if (!mounted) {
      return;
    }
    if (updated == null) {
      _showInfoSnack('카메라 이름 저장에 실패했습니다.');
      return;
    }
    setState(() {
      registeredSourcesByKey = {
        ...registeredSourcesByKey,
        updated.sourceKey: updated,
      };
    });
    await _refreshSourceOverviews();
    _showInfoSnack('카메라 이름을 저장했습니다.');
  }

  Widget _buildViewerVideoGridPanel() {
    final groupSourceKeys = _activeGroupSourceKeys;
    var candidates = _sourceSlots.where((slot) {
      if (groupSourceKeys == null) return true;
      return groupSourceKeys.contains(slot.sourceKey.trim());
    }).toList(growable: false);

    if (_layoutCount == 1 && candidates.isNotEmpty) {
      final active = candidates.where((slot) => slot.slotId == _activeSlotId).toList();
      candidates = <_SourcePanelSlot>[active.isNotEmpty ? active.first : candidates.first];
    } else if (candidates.length > _layoutCount) {
      candidates = candidates.take(_layoutCount).toList(growable: false);
    }

    final maximizedSlot = _maximizedSlotId.isEmpty
        ? null
        : _findSourceSlotById(_maximizedSlotId);
    final visibleSlots = maximizedSlot == null
        ? candidates
        : <_SourcePanelSlot>[maximizedSlot];

    final columns = maximizedSlot != null
        ? 1
        : (_layoutCount == 1 ? 1 : _layoutCount == 9 ? 3 : 2);

    final trailing = Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _layoutButton(1),
        _layoutButton(4),
        _layoutButton(9),
        const SizedBox(width: 2),

        _buildCameraGroupFilter(),

        _buildMonitorToolbarIconButton(
          tooltip: '카메라 그룹 관리',
          onPressed: _showCameraGroupManager,
          child: const Icon(
            Icons.folder_copy_outlined,
            size: 18,
          ),
        ),

        _buildMonitorToolbarIconButton(
          tooltip: '현재 배치 저장',
          onPressed: _isSavingLayout
              ? null
              : () => unawaited(_saveViewerLayout()),
          child: _isSavingLayout
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons.save_outlined,
                  size: 18,
                ),
        ),
      ],
    );

    if (visibleSlots.isEmpty) {
      return _buildPanelCard(
        title: 'Live Monitoring',
        trailing: trailing,
        child: Center(
          child: Text(
            _activeCameraGroupId == null
                ? '연결된 카메라가 없습니다.'
                : '선택한 그룹에 등록된 카메라가 없습니다.',
            style: const TextStyle(color: PortfolioColors.textMuted),
          ),
        ),
        expandChild: true,
      );
    }

    final grid = GridView.builder(
      controller: monitoringGridScrollController,
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 16 / 9,
      ),
      itemCount: visibleSlots.length,
      itemBuilder: (context, index) => _buildDraggableVideoTile(visibleSlots[index]),
    );

    return _buildPanelCard(
      title: 'Live Monitoring',
      trailing: trailing,
      child: Scrollbar(
        controller: monitoringGridScrollController,
        thumbVisibility: visibleSlots.length > _layoutCount,
        child: grid,
      ),
      expandChild: true,
    );
  }

  Widget _layoutButton(int count) {
    final selected = _layoutCount == count;
    return SizedBox(
      height: 34,
      child: selected
          ? FilledButton.tonal(
              onPressed: () => setState(() => _layoutCount = count),
              child: Text('${count}분할'),
            )
          : OutlinedButton(
              onPressed: () => setState(() => _layoutCount = count),
              child: Text('${count}분할'),
            ),
    );
  }
  // ============================================================
  // 3. 카메라 그룹 선택
  // ============================================================
  Widget _buildCameraGroupFilter() {
    if (_cameraGroups.isEmpty) {
      return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF101A25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: PortfolioColors.border),
        ),
        child: const Text(
          '전체 카메라',
          style: TextStyle(fontSize: 14),
        ),
      );
    }

    return SizedBox(
      width: 150,
      height: 42,
      child: DropdownButtonFormField<int?>(
        value: _activeCameraGroupId,
        isDense: true,
        isExpanded: true,
        menuMaxHeight: 280,
        itemHeight: 48,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: const Color(0xFF24313F),
        iconSize: 18,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFF101A25),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: PortfolioColors.border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: PortfolioColors.accent,
              width: 1.2,
            ),
          ),
        ),
        items: [
          const DropdownMenuItem<int?>(
            value: null,
            child: Text(
              '전체 카메라',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ..._cameraGroups.map(
            (group) => DropdownMenuItem<int?>(
              value: _asInt(group['id']),
              child: Text(
                group['name']?.toString() ?? '카메라 그룹',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() => _activeCameraGroupId = value);
        },
      ),
    );
  }


  // ============================================================
  // 4. 관제화면 아이콘 버튼
  // ============================================================
  Widget _buildMonitorToolbarIconButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget child,
  }) {
    return SizedBox(
      width: 42,
      height: 42,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(42, 42),
            backgroundColor: const Color(0xFF101A25),
            side: const BorderSide(
              color: PortfolioColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
    
  Set<String>? get _activeGroupSourceKeys {
    final id = _activeCameraGroupId;
    if (id == null) return null;
    for (final group in _cameraGroups) {
      if (_asInt(group['id']) != id) continue;
      final raw = group['source_keys'];
      if (raw is! List) return <String>{};
      return raw.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toSet();
    }
    return <String>{};
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _loadViewerPreferences() async {
    final results = await Future.wait<Object?>([
      _portfolioApi.fetchCameraGroups(),
      _portfolioApi.fetchViewerLayout(),
    ]);
    if (!mounted) return;
    final groups = results[0] as List<Map<String, dynamic>>;
    final layout = results[1] as Map<String, dynamic>?;
    setState(() {
      _cameraGroups = groups;
      final grid = _asInt(layout?['grid_count']);
      _layoutCount = grid != null && const {1, 4, 9}.contains(grid) ? grid : 4;
      _activeCameraGroupId = _asInt(layout?['active_group_id']);
      final order = layout?['source_order'];
      _savedSourceOrder = order is List
          ? order.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList(growable: false)
          : const [];
      _applySavedSourceOrder();
    });
  }

  void _applySavedSourceOrder() {
    if (_savedSourceOrder.isEmpty || _sourceSlots.length < 2) return;
    final positions = <String, int>{};
    for (var i = 0; i < _savedSourceOrder.length; i++) {
      positions[_savedSourceOrder[i]] = i;
    }
    _sourceSlots.sort((a, b) {
      final ai = positions[a.sourceKey.trim()] ?? 999999;
      final bi = positions[b.sourceKey.trim()] ?? 999999;
      if (ai != bi) return ai.compareTo(bi);
      return a.slotId.compareTo(b.slotId);
    });
  }

  Future<void> _saveViewerLayout() async {
    setState(() => _isSavingLayout = true);
    final ok = await _portfolioApi.saveViewerLayout(
      gridCount: _layoutCount,
      activeGroupId: _activeCameraGroupId,
      sourceOrder: _sourceSlots.map((slot) => slot.sourceKey.trim()).where((key) => key.isNotEmpty).toList(),
    );
    if (!mounted) return;
    setState(() => _isSavingLayout = false);
    _showInfoSnack(ok ? '현재 관제 배치를 저장했습니다.' : '관제 배치 저장에 실패했습니다.');
  }

  Future<void> _showCameraGroupManager() async {
    final nameController = TextEditingController();
    final selected = <String>{};
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('카메라 그룹 생성'),
          content: SizedBox(
            width: 560,
            height: 470,
            child: Column(children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '그룹 이름', hintText: '예) 생산라인 A')),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: PortfolioColors.panelAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PortfolioColors.border),
                  ),
                  child: ListView(
                    children: _sourceSlots.map((slot) {
                      final key = slot.sourceKey.trim();
                      return CheckboxListTile(
                        value: selected.contains(key),
                        title: Text(_displayLabelForSlot(slot)),
                        subtitle: Text(key, style: const TextStyle(fontSize: 10, color: PortfolioColors.textMuted)),
                        onChanged: (value) => setLocal(() {
                          if (value == true) { selected.add(key); } else { selected.remove(key); }
                        }),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_cameraGroups.isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _cameraGroups.map((group) {
                      final id = _asInt(group['id']);
                      return InputChip(
                        label: Text(group['name']?.toString() ?? '그룹'),
                        onDeleted: id == null ? null : () async {
                          await _portfolioApi.deleteCameraGroup(id);
                          final groups = await _portfolioApi.fetchCameraGroups();
                          if (!mounted) return;
                          setState(() {
                            _cameraGroups = groups;
                            if (_activeCameraGroupId == id) _activeCameraGroupId = null;
                          });
                          if (dialogContext.mounted) Navigator.pop(dialogContext, false);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('닫기')),
            FilledButton(
              onPressed: () async {
                final groupName = nameController.text.trim();

                // 그룹 이름 확인
                if (groupName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('그룹 이름을 입력해주세요.'),
                    ),
                  );
                  return;
                }

                // 카메라 선택 확인
                if (selected.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('카메라를 하나 이상 선택해주세요.'),
                    ),
                  );
                  return;
                }

                final saved = await _portfolioApi.saveCameraGroup(
                  name: groupName,
                  sourceKeys: selected.toList(),
                );

                // 서버 저장 실패
                if (saved == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('그룹 저장에 실패했습니다.'),
                    ),
                  );
                  return;
                }

                // 저장 성공
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('그룹 저장'),
            ),            
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == true) {
      final groups = await _portfolioApi.fetchCameraGroups();
      if (!mounted) return;
      setState(() {
        _cameraGroups = groups;
        if (groups.isNotEmpty) _activeCameraGroupId = _asInt(groups.last['id']);
      });
    }
  }

  Widget _buildDraggableVideoTile(_SourcePanelSlot slot) {
    if (_maximizedSlotId.isNotEmpty) {
      return _buildVideoTile(slot);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final feedbackWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final feedbackHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : feedbackWidth * 9 / 16;
        return DragTarget<_SourcePanelSlot>(
          onWillAcceptWithDetails: (details) =>
              details.data.slotId != slot.slotId,
          onAcceptWithDetails: (details) =>
              _swapSourceSlots(details.data.slotId, slot.slotId),
          builder: (context, candidateData, rejectedData) {
            final isDropTarget = candidateData.isNotEmpty;
            final tile = _buildVideoTile(slot);
            return LongPressDraggable<_SourcePanelSlot>(
              data: slot,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: SizedBox(
                width: feedbackWidth,
                height: feedbackHeight,
                child: Material(
                  color: Colors.transparent,
                  elevation: 14,
                  shadowColor: Colors.black87,
                  borderRadius: BorderRadius.circular(14),
                  child: Opacity(opacity: 0.90, child: tile),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.30, child: tile),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: isDropTarget
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: tile,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVideoTile(_SourcePanelSlot slot) {
    final isSelected = slot.slotId == _activeSlotId;
    return AnimatedBuilder(
      animation: Listenable.merge([slot.controller, apiEventFeed]),
      builder: (context, _) {
        return VideoViewBox(
          controller: slot.controller,
          title: _displayLabelForSlot(slot),
          badgeText: '',
          isSelected: isSelected,
          onTap: () => unawaited(_toggleActiveSlot(slot.slotId)),
          overlayItems: const [],
          overlayDetections: const [],
          overlaySourceWidth: _getOverlaySourceWidthForSlot(slot),
          overlaySourceHeight: _getOverlaySourceHeightForSlot(slot),
          overlayStatusText: _buildStartupProgressText(slot),
          showOfflineOverlay:
              _isSlotOfflineForViewer(slot) && !slot.controller.isReplayMode,
          previewImageUrl: _buildPreviewImageUrlForSlot(slot),
          dangerZoneRoi: isSelected ? _visibleDangerZoneRoiForSlot(slot) : null,
          enableDangerZoneEditing: isSelected && isEditingDangerZone,
          onDangerZoneChanged: isSelected ? _handleDangerZoneChanged : null,
          overlayAction: _buildVideoTileActions(slot),
          onTitleTap: () => unawaited(_editDisplayNameForSlot(slot)),
        );
      },
    );
  }

  Widget _buildVideoTileActions(_SourcePanelSlot slot) {
    final isMaximized = _maximizedSlotId == slot.slotId;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildConnectionStatusDot(slot),
        const SizedBox(width: 6),
        if (slot.controller.isReplayMode)
          _buildOverlayIconButton(
            tooltip: '클립 닫기',
            icon: Icons.close,
            onPressed: () => unawaited(_closeReplayForSlot(slot)),
          ),
        if (slot.controller.isReplayMode) const SizedBox(width: 6),
        _buildOverlayIconButton(
          tooltip: isMaximized ? '원래 크기' : '최대화',
          icon: isMaximized ? Icons.fullscreen_exit : Icons.fullscreen,
          onPressed: () {
            setState(() {
              _maximizedSlotId = isMaximized ? '' : slot.slotId;
            });
          },
        ),
      ],
    );
  }

  Widget _buildConnectionStatusDot(_SourcePanelSlot slot) {
    final status = _resolveClientConnectionStatus(slot);
    return Tooltip(
      message: status.label,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: status.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: status.color.withValues(alpha: 0.45),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }

  RoiRect? _visibleDangerZoneRoiForSlot(_SourcePanelSlot slot) {
    if (isEditingDangerZone && slot.slotId == _activeSlotId) {
      return pendingDangerZoneRoi ?? _ruleConfigForSlot(slot).dangerZoneRoi;
    }
    final eventRoi = selectedApiEventDetail?.dangerZoneRoi;
    if (slot.controller.isReplayMode &&
        selectedApiEventDetail?.sourceKey.trim() == slot.sourceKey.trim() &&
        eventRoi != null) {
      return eventRoi;
    }
    return _ruleConfigForSlot(slot).dangerZoneRoi;
  }

  Future<void> _toggleDangerZoneEditing() async {
    final source = _activeSourceItem;
    if (source == null) {
      _showInfoSnack('먼저 카메라를 선택해 주세요.');
      return;
    }
    if (!isEditingDangerZone) {
      setState(() {
        pendingDangerZoneRoi = source.ruleConfig.dangerZoneRoi;
        isEditingDangerZone = true;
      });
      return;
    }

    final nextRoi = pendingDangerZoneRoi;
    setState(() {
      isEditingDangerZone = false;
      pendingDangerZoneRoi = null;
    });
    if (nextRoi != null) {
      await _saveRuleConfig(_activeRuleConfig.copyWith(dangerZoneRoi: nextRoi));
    }
  }

  SourceRuleConfig _ruleConfigForSlot(_SourcePanelSlot slot) {
    return registeredSourcesByKey[slot.sourceKey.trim()]?.ruleConfig ??
        const SourceRuleConfig(
          useNoHelmetRule: true,
          useDangerZoneRule: false,
          dangerZoneRoi: null,
        );
  }

  String _buildStartupProgressText(_SourcePanelSlot slot) {
    if (slot.controller.errorText.trim().isNotEmpty) {
      return '';
    }
    if (slot.controller.isReplayMode) {
      return '';
    }
    final sourceKey = slot.sourceKey.trim();
    final runtimeStatus = sourceStatusesByKey[sourceKey];
    final overview = sourceOverviewsByKey[sourceKey];
    if (_isSlotOfflineForViewer(slot)) {
      return '클라이언트 연결이 끊겼습니다. 재연결을 기다리는 중입니다.';
    }
    if (runtimeStatus == null) {
      return _hasViewerHistory(overview) ? '' : '서버에 소스를 등록하고 첫 상태를 기다리는 중입니다.';
    }
    final state = runtimeStatus.state.trim().toLowerCase();
    if (state == 'starting' || state == 'registered') {
      return '클라이언트가 카메라와 분석 런타임을 준비하는 중입니다.';
    }
    if (state == 'model_loading' || state == 'loading') {
      return '객체탐지 모델을 로딩하는 중입니다.';
    }
    if (!runtimeStatus.isRunning && !slot.controller.hasVideo) {
      return '실시간 프리뷰 스트림을 연결하는 중입니다.';
    }
    return '';
  }

  // ignore: unused_element
  Widget _buildViewerMonitorChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        '$label  $value',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: Colors.white70),
      ),
    );
  }

  // ignore: unused_element
  int _countEventsForSource(String sourceKey) {
    final normalized = sourceKey.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    return apiEventController.items
        .where((item) => item.sourceKey.trim() == normalized)
        .length;
  }

  // ignore: unused_element
  String _formatViewerUpdatedAt(String value) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) {
      return '-';
    }
    return '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}:'
        '${parsed.second.toString().padLeft(2, '0')}';
  }

  Widget _buildInspectorPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: apiEventFeed,
            builder: (context, _) {
              return EventLogBox(
                eventFeed: apiEventFeed,
                baseUrl: eventApiService.baseUrl,
                onTapItem: _onTapEventItem,
                sourceLabelResolver: _displayLabelForSourceKey,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _buildRuleConfigPanel(),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildSelectedSourceSummaryPanel() {
    final source = _activeSourceItem;
    final status = source == null
        ? null
        : sourceStatusesByKey[source.sourceKey];
    final overview = source == null
        ? null
        : sourceOverviewsByKey[source.sourceKey];
    final replayController = _activeSlot?.controller ?? videoController;
    return _buildPanelCard(
      title: '선택된 소스',
      child: source == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('소스를 선택하면 상태, 진행도, 이벤트, 클립 정보를 여기에서 확인할 수 있습니다.'),
                if (replayController.isReplayMode) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => unawaited(replayController.closeReplay()),
                    child: const Text('클립 닫기'),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayLabelForSource(source),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _buildDetailLine('type', source.sourceType),
                _buildDetailLine('status', status?.state ?? '-'),
                _buildDetailLine(
                  'progress',
                  _buildSourceProgressText(source, status),
                ),
                _buildDetailLine(
                  'owner',
                  _buildSourceOwnerLabel(
                    clientId: source.clientId,
                    sessionId: source.sessionId,
                  ),
                ),
                _buildDetailLine(
                  'analysis',
                  _buildViewerSourceAvailabilityText(source, status, overview),
                ),
                _buildDetailLine('sourceKey', source.sourceKey),
                if (replayController.isReplayMode) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => unawaited(replayController.closeReplay()),
                    child: const Text('클립 닫기'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildRuleConfigPanel() {
    final source = _activeSourceItem;
    final ruleConfig = _activeRuleConfig;
    return _buildPanelCard(
      title: '클라이언트별 룰 설정',
      trailing: isSavingRuleConfig
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: source == null
          ? const Text('먼저 소스를 선택해 주세요.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _buildSourceOwnerLabel(
                    clientId: source.clientId,
                    sessionId: source.sessionId,
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: ruleConfig.useNoHelmetRule,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('안전모 미착용 룰'),
                  subtitle: const Text('NO_Helmet 탐지 결과 기준'),
                  onChanged: (value) {
                    unawaited(
                      _saveRuleConfig(
                        ruleConfig.copyWith(useNoHelmetRule: value),
                      ),
                    );
                  },
                ),
                const Divider(height: 20),
                SwitchListTile(
                  value: ruleConfig.useDangerZoneRule,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('위험구역 룰'),
                  subtitle: Text(
                    ruleConfig.useDangerZoneRule
                        ? 'Person 탐지 박스가 ROI와 겹치면 이벤트가 발생합니다.'
                        : 'OFF 상태에서도 ROI 편집/저장은 가능합니다.',
                  ),
                  onChanged: (value) {
                    unawaited(
                      _saveRuleConfig(
                        ruleConfig.copyWith(useDangerZoneRule: value),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => unawaited(_toggleDangerZoneEditing()),
                      child: Text(
                        isEditingDangerZone ? '위험구역 편집 종료' : '위험구역 드래그 편집',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: ruleConfig.dangerZoneRoi == null
                          ? null
                          : () {
                              setState(() {
                                pendingDangerZoneRoi = null;
                              });
                              unawaited(
                                _saveRuleConfig(
                                  ruleConfig.copyWith(clearDangerZoneRoi: true),
                                ),
                              );
                            },
                      child: const Text('위험구역 초기화'),
                    ),
                  ],
                ),
                if (pendingDangerZoneRoi != null && isEditingDangerZone) ...[
                  const SizedBox(height: 8),
                  Text(
                    '편집 중 ROI: (${pendingDangerZoneRoi!.x1}, ${pendingDangerZoneRoi!.y1}) - (${pendingDangerZoneRoi!.x2}, ${pendingDangerZoneRoi!.y2})',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
                  ),
                ],
                if (ruleConfig.dangerZoneRoi != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ROI: (${ruleConfig.dangerZoneRoi!.x1}, ${ruleConfig.dangerZoneRoi!.y1}) '
                    '- (${ruleConfig.dangerZoneRoi!.x2}, ${ruleConfig.dangerZoneRoi!.y2})',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildPanelCard({
    required String title,
    required Widget child,
    Widget? trailing,
    bool expandChild = false,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (trailing case final Widget trailingWidget) trailingWidget,
            ],
          ),
          const SizedBox(height: 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget buildSourceTabs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('소스 화면 전환', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '총 ${_sourceSlots.length}개',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_sourceSlots.isEmpty)
            Text(
              '영상 추가 또는 스트림 추가를 누르면 소스가 여기에 쌓이고, 칩을 눌러 화면을 전환할 수 있습니다.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _sourceSlots)
                  InputChip(
                    selected: slot.slotId == _activeSlotId,
                    avatar: CircleAvatar(
                      radius: 10,
                      backgroundColor: _colorForSlotStatus(slot),
                    ),
                    label: Text(
                      '${_displayLabelForSlot(slot)} · ${_describeSlotStatus(slot)}',
                    ),
                    onSelected: (_) => unawaited(_setActiveSlot(slot.slotId)),
                    onDeleted: () => _confirmRemoveSourceSlot(slot),
                  ),
              ],
            ),
          if (registeredSourcesByKey.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildRegisteredSourcesSummary(),
          ],
        ],
      ),
    );
  }

  Widget _buildRegisteredSourcesSummary() {
    final sourceEntries = registeredSourcesByKey.values.toList(growable: false)
      ..sort((left, right) => left.sourceKey.compareTo(right.sourceKey));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('서버 등록 소스', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '서버에 저장된 소스의 상태, 진행도, 패널 열기를 여기에서 확인합니다.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          for (final source in sourceEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayLabelForSource(source),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text('type: ${source.sourceType}'),
                    Text('source_key: ${source.sourceKey}'),
                    Text(
                      'state: ${_describeServerSourceState(source.sourceKey)}',
                    ),
                    Text(
                      'progress: ${_buildSourceProgressText(source, sourceStatusesByKey[source.sourceKey])}',
                    ),
                    Text(
                      'client: ${source.clientId.isEmpty ? '-' : source.clientId}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(_openRegisteredSource(source)),
                          child: const Text('패널 열기'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildApiDetailPanel() {
    // 이벤트 목록 클릭 후 GET /api/events/detail 결과를 요약해서 보여 줍니다.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'API 이벤트 상세',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (videoController.canReturnFromReplay)
                OutlinedButton(
                  onPressed: _returnToLive,
                  child: const Text('클립 닫기'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isLoadingApiDetail)
            const Text('상세 정보 불러오는 중...')
          else if ((apiDetailErrorMessage ?? '').isNotEmpty)
            Text(apiDetailErrorMessage!)
          else if (selectedApiEventDetail == null)
            const Text('이벤트를 선택하면 상세 정보가 표시됩니다.')
          else
            _buildApiDetailContent(selectedApiEventDetail!),
        ],
      ),
    );
  }

  Widget buildApiServerHealthPanel() {
    // /health 호출 결과를 보여 주는 보조 패널입니다.
    // 서버가 꺼졌는지, events.jsonl을 찾았는지 빠르게 점검할 때 사용합니다.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AnimatedBuilder(
        animation: apiEventFeed,
        builder: (context, _) {
          final health = apiEventController.serverHealth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'API 서버 상태',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: apiEventController.isCheckingHealth
                        ? null
                        : _checkApiHealth,
                    child: const Text('상태 확인'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (apiEventController.isCheckingHealth)
                const Text('확인 중...')
              else ...[
                if ((apiEventController.healthErrorMessage ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(apiEventController.healthErrorMessage!),
                  ),
                if (health != null) ...[
                  _buildDetailLine('status', health.status),
                  _buildDetailLine(
                    'eventLogExists',
                    health.eventLogExists ? 'true' : 'false',
                  ),
                  _buildDetailLine('eventLogPath', health.eventLogPath),
                  _buildDetailLine(
                    'lastHealthCheckedAt',
                    _formatDateTime(apiEventController.lastHealthCheckedAt),
                  ),
                ] else
                  Text(
                    'API 모드 진입 시 서버 상태를 자동 확인합니다.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildApiDetailContent(ApiEventItem item) {
    // clipUrl 우선, clipPath fallback 정책과 서버 정규화 clip 필드를 여기서 눈으로 확인할 수 있습니다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailLine('eventKey', item.eventKey),
        _buildDetailLine('eventType', item.eventType),
        _buildDetailLine('status', item.status),
        _buildDetailLine('level', item.level),
        _buildDetailLine('message', item.message),
        _buildDetailLine('frameId', item.frameId.toString()),
        _buildDetailLine('personId', item.personId?.toString() ?? 'unknown'),
        _buildDetailLine(
          'durationSeconds',
          item.durationSeconds.toStringAsFixed(1),
        ),
        _buildDetailLine('sourceTimeText', item.sourceTimeText),
        _buildDetailLine(
          'clipPath',
          item.clipPath.isEmpty ? '-' : item.clipPath,
        ),
        _buildDetailLine(
          'clipAvailable',
          item.clipAvailable ? 'true' : 'false',
        ),
        _buildDetailLine(
          'preferredClipSource',
          item.preferredClipSource.isEmpty ? '-' : item.preferredClipSource,
        ),
        _buildDetailLine('clipUploadOk', item.clipUploadOk ? 'true' : 'false'),
        _buildDetailLine('clipUrl', item.clipUrl.isEmpty ? '-' : item.clipUrl),
        _buildDetailLine(
          'serverClipName',
          item.serverClipName.isEmpty ? '-' : item.serverClipName,
        ),
        _buildDetailLine(
          'serverClipPath',
          item.serverClipPath.isEmpty ? '-' : item.serverClipPath,
        ),
        _buildDetailLine('clipPolicy', _describeClipPolicy(item)),
        _buildDetailLine(
          'relatedDetections',
          item.relatedDetections.length.toString(),
        ),
        _buildRelatedDetections(item),
        if (_resolveApiClipSource(item).isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _openApiDetailClip(item),
                child: const Text('클립 재생'),
              ),
              if (videoController.canReturnFromReplay)
                OutlinedButton(
                  onPressed: _returnToLive,
                  child: const Text('클립 닫기'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildRelatedDetections(ApiEventItem detail) {
    if (detail.relatedDetections.isEmpty) {
      return const SizedBox.shrink();
    }

    // 탐지 근거는 너무 길어지지 않도록 일부만 보여 줍니다.
    final visibleDetections = detail.relatedDetections.take(5).toList();
    final remainingCount =
        detail.relatedDetections.length - visibleDetections.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('관련 탐지 객체', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final detection in visibleDetections) ...[
            Text(_formatDetectionSummary(detection)),
            Text(
              _formatDetectionBoxLine(detection),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 6),
          ],
          if (remainingCount > 0)
            Text(
              '외 $remainingCount개',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text('$label: ${value.isEmpty ? '-' : value}'),
    );
  }

  // ignore: unused_element
  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ignore: unused_element
  String _buildTileStatusText(_SourcePanelSlot slot) {
    final sourceKey = slot.sourceKey.trim();
    final runtimeStatus = sourceStatusesByKey[slot.sourceKey.trim()];
    final source = registeredSourcesByKey[sourceKey];
    final overview = sourceOverviewsByKey[sourceKey];
    if (slot.controller.errorText.trim().isNotEmpty) {
      return '영상 재생 오류: ${slot.controller.errorText.trim()}';
    }
    if (_isSlotOfflineForViewer(slot)) {
      return '소유 클라이언트 연결이 끊겨 현재 분석 상태가 오래되었습니다.';
    }
    if (runtimeStatus == null) {
      if (source != null) {
        return _buildViewerSourceAvailabilityText(source, null, overview);
      }
      return '분석 상태를 아직 받지 못했습니다.';
    }
    if (runtimeStatus.errorMessage.trim().isNotEmpty) {
      return runtimeStatus.errorMessage.trim();
    }
    if (!frameDetectionBySourceKey.containsKey(sourceKey)) {
      return runtimeStatus.isRunning ? '탐지 결과를 불러오는 중입니다.' : '탐지 대기 중입니다.';
    }
    if (runtimeStatus.sourceDurationSeconds > 0) {
      return _buildSourceProgressText(
        registeredSourcesByKey[slot.sourceKey.trim()],
        runtimeStatus,
      );
    }
    return runtimeStatus.isRunning ? '실시간 분석 중입니다.' : '대기 중입니다.';
  }

  Future<void> _saveRuleConfig(SourceRuleConfig nextRuleConfig) async {
    final source = _activeSourceItem;
    if (source == null) {
      return;
    }

    final nextTicket = ++_ruleConfigSaveTicket;
    setState(() {
      isSavingRuleConfig = true;
      registeredSourcesByKey = {
        ...registeredSourcesByKey,
        source.sourceKey: SourceItem(
          sourceKey: source.sourceKey,
          sourceSlug: source.sourceSlug,
          displayName: source.displayName,
          sourceType: source.sourceType,
          sourceValue: source.sourceValue,
          sourceDurationSeconds: source.sourceDurationSeconds,
          serverMediaPath: source.serverMediaPath,
          mediaUrl: source.mediaUrl,
          previewUrl: source.previewUrl,
          originalSourceType: source.originalSourceType,
          originalSourceValue: source.originalSourceValue,
          clientId: source.clientId,
          sessionId: source.sessionId,
          desiredRunning: source.desiredRunning,
          ruleConfig: nextRuleConfig,
          createdAt: source.createdAt,
          updatedAt: source.updatedAt,
        ),
      };
    });

    final updated = await eventApiService.updateSourceRuleConfig(
      sourceKey: source.sourceKey,
      ruleConfig: nextRuleConfig,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      isSavingRuleConfig = nextTicket != _ruleConfigSaveTicket;
      if (updated != null && nextTicket == _ruleConfigSaveTicket) {
        registeredSourcesByKey = {
          ...registeredSourcesByKey,
          updated.sourceKey: updated,
        };
      }
    });

    if (updated == null) {
      _showInfoSnack('룰 설정 저장에 실패했습니다.');
      return;
    }

    if (nextTicket == _ruleConfigSaveTicket) {
      await _refreshSourceOverviews();
      await _refreshSourceStatuses();
      await _refreshRegisteredSources();
      _showInfoSnack('클라이언트별 룰 설정을 저장했습니다.');
    }
  }

  void _handleDangerZoneChanged(RoiRect roi) {
    setState(() {
      pendingDangerZoneRoi = roi;
    });
  }

  String _formatDetectionSummary(Map<String, dynamic> detection) {
    final name = (detection['name']?.toString().trim().isNotEmpty ?? false)
        ? detection['name'].toString().trim()
        : 'unknown';
    final score = _formatScore(detection['score']);
    return '$name / score=$score';
  }

  String _formatDetectionBoxLine(Map<String, dynamic> detection) {
    return 'box=${_formatBox(detection['box'])}';
  }

  String _formatScore(Object? score) {
    if (score is num) {
      return score.toStringAsFixed(2);
    }

    if (score is String) {
      final parsed = double.tryParse(score);
      if (parsed != null) {
        return parsed.toStringAsFixed(2);
      }
    }

    return '-';
  }

  // ignore: unused_element
  double? _toDoubleValue(Object? value) {
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

  String buildDetectionLabel(
    ApiEventItem item,
    Map<String, dynamic> detection,
  ) {
    final name = (detection['name']?.toString().trim().isNotEmpty ?? false)
        ? detection['name'].toString().trim()
        : item.eventType;
    return name;
  }

  // ignore: unused_element
  String _buildFrameDetectionLabel(Map<String, dynamic> detection) {
    final name = (detection['name']?.toString().trim().isNotEmpty ?? false)
        ? detection['name'].toString().trim()
        : 'object';
    return name;
  }

  Color colorForLevel(String level) {
    switch (level.trim().toUpperCase()) {
      case 'DANGER':
        return Colors.redAccent;
      case 'WARNING':
        return Colors.orangeAccent;
      default:
        return Colors.lightBlueAccent;
    }
  }

  Color _colorForDetectionName(String name) {
    switch (name.trim().toLowerCase()) {
      case 'yes_helmet':
      case 'helmet':
      case 'hardhat':
        return Colors.greenAccent;
      case 'no_helmet':
      case 'without_helmet':
      case 'no helmet':
        return Colors.redAccent;
      case 'person':
        return Colors.amberAccent;
      default:
        return Colors.amberAccent;
    }
  }

  String _formatBox(Object? box) {
    if (box is! Map) {
      return '-';
    }

    final x1 = box['x1'];
    final y1 = box['y1'];
    final x2 = box['x2'];
    final y2 = box['y2'];
    if (x1 == null || y1 == null || x2 == null || y2 == null) {
      return '-';
    }

    return '($x1, $y1, $x2, $y2)';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '-';
    }

    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
  }

  FrameDetectionSnapshot? _getOverlaySnapshotForSlot(_SourcePanelSlot slot) {
    return frameDetectionBySourceKey[slot.sourceKey.trim()];
  }

  // ignore: unused_element
  List<VideoOverlayDetection> _getOverlayDetectionsForSlot(
    _SourcePanelSlot slot,
  ) {
    final snapshot = _getOverlaySnapshotForSlot(slot);
    if (snapshot == null || snapshot.detections.isEmpty) {
      return const [];
    }

    final items = <VideoOverlayDetection>[];
    for (final detection in snapshot.detections) {
      final box = detection['box'];
      if (box is! Map) {
        continue;
      }
      final x1 = _readDouble(box['x1']);
      final y1 = _readDouble(box['y1']);
      final x2 = _readDouble(box['x2']);
      final y2 = _readDouble(box['y2']);
      if (x1 == null || y1 == null || x2 == null || y2 == null) {
        continue;
      }
      final name = detection['name']?.toString().trim() ?? 'object';
      final score = _readDouble(detection['score']);
      final label = score == null ? name : '$name ${score.toStringAsFixed(2)}';
      final trackId = detection['track_id']?.toString().trim() ?? '';
      items.add(
        VideoOverlayDetection(
          key: '${snapshot.frameId}:$name:$trackId:$x1:$y1:$x2:$y2',
          label: label,
          color: _colorForDetectionName(name),
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
        ),
      );
    }
    return items;
  }

  double _getOverlaySourceWidthForSlot(_SourcePanelSlot slot) {
    final snapshot = _getOverlaySnapshotForSlot(slot);
    if (snapshot != null && snapshot.frameWidth > 0) {
      return snapshot.frameWidth.toDouble();
    }
    if (slot.controller.videoWidth > 0) {
      return slot.controller.videoWidth.toDouble();
    }
    final roi = _ruleConfigForSlot(slot).dangerZoneRoi;
    if (roi != null) {
      return math.max(1280, roi.x2).toDouble();
    }
    return 0;
  }

  String _buildPreviewImageUrlForSlot(_SourcePanelSlot slot) {
    if (_isSlotOfflineForViewer(slot) && !slot.controller.isReplayMode) {
      return '';
    }
    final sourceKey = slot.sourceKey.trim();
    if (sourceKey.isNotEmpty) {
      return eventApiService.buildSourceStreamUrl(sourceKey);
    }
    final source = registeredSourcesByKey[slot.sourceKey.trim()];
    final overview = sourceOverviewsByKey[slot.sourceKey.trim()];
    final previewUrl = overview?.previewUrl.trim().isNotEmpty == true
        ? overview!.previewUrl.trim()
        : source?.previewUrl.trim() ?? '';
    final statusCacheBust =
        sourceStatusesByKey[slot.sourceKey.trim()]?.updatedAt ??
        overview?.updatedAt ??
        '';
    final cacheBust = '${previewRefreshCacheBust}_$statusCacheBust';
    if (previewUrl.isNotEmpty) {
      return previewUrl.startsWith('http')
          ? previewUrl
          : '${eventApiService.baseUrl}$previewUrl${previewUrl.contains('?') ? '&' : '?'}t=$cacheBust';
    }
    return eventApiService.buildSourcePreviewUrl(
      slot.sourceKey,
      cacheBust: cacheBust,
    );
  }

  double _getOverlaySourceHeightForSlot(_SourcePanelSlot slot) {
    final snapshot = _getOverlaySnapshotForSlot(slot);
    if (snapshot != null && snapshot.frameHeight > 0) {
      return snapshot.frameHeight.toDouble();
    }
    if (slot.controller.videoHeight > 0) {
      return slot.controller.videoHeight.toDouble();
    }
    final roi = _ruleConfigForSlot(slot).dangerZoneRoi;
    if (roi != null) {
      return math.max(720, roi.y2).toDouble();
    }
    return 0;
  }

  String _effectiveOverlaySourceKey() {
    if (videoController.isReplayMode &&
        videoController.replaySourceKey.isNotEmpty) {
      return videoController.replaySourceKey;
    }
    return selectedSourceKey;
  }

  double? _readDouble(Object? value) {
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

  Future<void> _onTapEventItem(EventLogItem item) async {
    // 클릭 공통 동작:
    // 1) 선택 표시
    // 2) API 상세 조회
    // 3) 해당 소스 타일 강조
    // 4) 이벤트 시작 시점으로 이동
    apiEventFeed.selectLogItem(item);

    final eventKey = item.eventKeyText.trim();
    final sourceKey = item.sourceKeyText.trim();
    final exactItem = apiEventController.findExactItemForLogItem(item);
    ApiEventItem? detail;
    if (exactItem != null) {
      setState(() {
        apiDetailErrorMessage = null;
        selectedApiEventDetail = exactItem;
      });
    } else if (eventKey.isNotEmpty && eventKey != '-') {
      setState(() {
        isLoadingApiDetail = true;
        apiDetailErrorMessage = null;
        selectedApiEventDetail = null;
      });

      try {
        detail = await apiEventController.loadEventDetail(
          eventKey,
          sourceKey: sourceKey.isEmpty || sourceKey == '-' ? null : sourceKey,
        );
        setState(() {
          selectedApiEventDetail = detail;
          if (detail == null) {
            apiDetailErrorMessage = '상세 정보를 가져오지 못했습니다.';
          }
        });
      } finally {
        setState(() {
          isLoadingApiDetail = false;
        });
      }
    }

    final sourceItem =
        exactItem ??
        detail ??
        (sourceKey.isEmpty || sourceKey == '-'
            ? apiEventController.findItemByEventKey(item.eventKeyText)
            : apiEventController.findItemByEventKeyForSource(
                item.eventKeyText,
                sourceKey: sourceKey,
              ));
    if (sourceItem == null) {
      return;
    }

    final targetSlot = _findSourceSlotByKey(sourceItem.sourceKey);
    if (targetSlot == null) {
      final source = registeredSourcesByKey[sourceItem.sourceKey.trim()];
      if (source != null) {
        await _openRegisteredSource(source);
      }
    }

    final resolvedTargetSlot = _findSourceSlotByKey(sourceItem.sourceKey);
    if (resolvedTargetSlot == null) {
      if (mounted) {
        _showInfoSnack('해당 이벤트의 소스 화면을 열 수 없습니다.');
      }
      return;
    }

    if (_activeSlotId != resolvedTargetSlot.slotId) {
      await _setActiveSlot(resolvedTargetSlot.slotId);
    }

    final clipSource = _resolveApiClipSource(sourceItem);
    if (clipSource.isEmpty) {
      if (mounted) {
        _showInfoSnack('이 이벤트에는 재생할 클립이 없습니다.');
      }
      return;
    }

    await _openApiDetailClip(sourceItem);
  }

  Future<void> _returnToLive() async {
    await videoController.returnToLive();
  }

  Future<void> _openApiDetailClip(ApiEventItem item) async {
    final resolvedPath = _resolveApiClipSource(item);
    if (resolvedPath.isEmpty) {
      setState(() {
        apiDetailErrorMessage = '재생할 클립 경로가 비어 있습니다.';
      });
      return;
    }

    try {
      final binding = await _resolveClipTargetController(item);
      await binding.controller.openReplayClip(
        resolvedPath,
        replayStartSeconds: _resolveEventStartSeconds(item),
        sourceKey: item.sourceKey,
        preserveReturnContext: binding.preserveReturnContext,
      );
      await _refreshFrameDetectionsForSource(item.sourceKey);
      if (mounted) {
        _showInfoSnack(
          binding.preserveReturnContext
              ? '현재 패널을 이벤트 클립 재생으로 전환했습니다.'
              : '현재 패널에서 클립만 재생합니다.',
        );
      }
    } catch (error) {
      setState(() {
        apiDetailErrorMessage = '클립을 열 수 없습니다: $error';
      });
    }
  }

  double _resolveEventStartSeconds(ApiEventItem? item) {
    if (item == null) {
      return 0.0;
    }

    final parsed = _parseVideoTimeText(item.startedSourceTimeText);
    if (parsed != null) {
      return parsed;
    }
    return item.sourceTimeSeconds < 0 ? 0.0 : item.sourceTimeSeconds;
  }

  double? _parseVideoTimeText(String value) {
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

  Future<void> _refreshApiEvents() async {
    await apiEventController.loadEvents(limit: 5000);
  }

  Future<void> _checkApiHealth() async {
    await apiEventController.checkHealth();
  }

  void _startApiAutoRefresh() {
    // WebSocket이 끊긴 경우를 대비한 fallback polling입니다.
    _stopApiAutoRefresh();
    apiAutoRefreshTimer = Timer.periodic(_apiAutoRefreshInterval, (_) {
      if (isRealtimeConnected) {
        return;
      }
      unawaited(_refreshApiEventsIfNeeded());
    });
  }

  void _startFrameDetectionRefresh() {
    frameDetectionRefreshTimer?.cancel();
    frameDetectionRefreshTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) {
        unawaited(_refreshFrameDetectionsIfNeeded());
      },
    );
  }

  void _startSourceStatusSync() {
    sourceStatusSyncTimer?.cancel();
    sourceStatusSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (isRealtimeConnected) {
        return;
      }
      unawaited(_refreshSourceOverviews());
      unawaited(_refreshSourceStatuses());
      unawaited(_refreshRegisteredSources());
      unawaited(_syncActiveSlotFrameRateIfNeeded());
    });
  }

  void _startPreviewRefresh() {
    previewRefreshTimer?.cancel();
    previewRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _sourceSlots.isEmpty) {
        return;
      }
      setState(() {
        previewRefreshCacheBust = DateTime.now().millisecondsSinceEpoch;
      });
    });
  }

  void _stopApiAutoRefresh() {
    apiAutoRefreshTimer?.cancel();
    apiAutoRefreshTimer = null;
  }

  Future<void> _refreshApiEventsIfNeeded() async {
    if (!mounted) {
      return;
    }
    if (apiEventController.isLoading) {
      // 이미 요청 중이면 중복 호출을 피해서 화면 흔들림과 불필요한 서버 호출을 줄입니다.
      return;
    }
    await _refreshApiEvents();
  }

  Future<void> _refreshFrameDetectionsIfNeeded() async {
    if (!mounted) {
      return;
    }
    final slots = List<_SourcePanelSlot>.from(_sourceSlots);
    for (final slot in slots) {
      await _refreshFrameDetectionsForSlot(slot, silent: true);
    }
  }

  Future<void> _syncSlotAudioFocus() async {
    final activeSlotId = _activeSlotId;
    final slots = List<_SourcePanelSlot>.from(_sourceSlots);
    for (final slot in slots) {
      await slot.controller.setMuted(slot.slotId != activeSlotId);
    }
  }

  Future<void> _refreshFrameDetectionsForSource(String sourceKey) async {
    final slot = _findSourceSlotByKey(sourceKey);
    if (slot == null) {
      return;
    }
    await _refreshFrameDetectionsForSlot(slot, silent: false);
  }

  Future<void> _refreshFrameDetectionsForSlot(
    _SourcePanelSlot slot, {
    required bool silent,
  }) async {
    final sourceKey = slot.sourceKey.trim();
    if (sourceKey.isEmpty || !mounted) {
      return;
    }

    final runtimeStatus = sourceStatusesByKey[sourceKey];
    final currentOverlaySeconds = slot.controller.currentOverlaySeconds;
    final frameIntervalSeconds = slot.controller.frameRate <= 0
        ? (1 / 30)
        : (1 / slot.controller.frameRate);
    final isLiveLikeSource = !slot.controller.isReplayMode;
    final lastRequestedSeconds =
        lastFrameDetectionRequestSecondsBySourceKey[sourceKey] ?? -1;
    final lastStatusUpdatedAt =
        lastFrameDetectionStatusUpdatedAtBySourceKey[sourceKey] ?? '';
    final movedEnough =
        (currentOverlaySeconds - lastRequestedSeconds).abs() >=
        (frameIntervalSeconds * 0.5);
    final statusChanged =
        (runtimeStatus?.updatedAt ?? '') != lastStatusUpdatedAt;
    final existingSnapshot = frameDetectionBySourceKey[sourceKey];
    final hasUsableSnapshot =
        existingSnapshot != null &&
        (!isLiveLikeSource
            ? (existingSnapshot.sourceTimeSeconds - currentOverlaySeconds)
                      .abs() <=
                  math.max(0.08, frameIntervalSeconds * 1.5)
            : true);
    final isTerminalState =
        runtimeStatus != null &&
        (runtimeStatus.state == 'completed' ||
            runtimeStatus.state == 'stopped' ||
            runtimeStatus.state == 'error');
    if (silent &&
        !slot.controller.isPlaying &&
        !statusChanged &&
        isTerminalState &&
        hasUsableSnapshot) {
      return;
    }
    if (silent && !movedEnough && !statusChanged) {
      return;
    }

    final FrameDetectionSnapshot? snapshot;
    if (isLiveLikeSource) {
      snapshot = await eventApiService.fetchLatestFrameDetection(
        sourceKey: sourceKey,
      );
    } else {
      final toleranceSeconds = math.max(0.20, frameIntervalSeconds * 4.0);
      snapshot = await eventApiService.fetchCurrentFrameDetection(
        sourceKey: sourceKey,
        sourceTimeSeconds: currentOverlaySeconds,
        toleranceSeconds: toleranceSeconds,
      );
    }
    if (!mounted) {
      return;
    }

    setState(() {
      final nextSnapshotMap = <String, FrameDetectionSnapshot>{
        ...frameDetectionBySourceKey,
      };
      if (snapshot == null) {
        nextSnapshotMap.remove(sourceKey);
      } else {
        nextSnapshotMap[sourceKey] = snapshot;
      }
      frameDetectionBySourceKey = nextSnapshotMap;
      frameDetectionLogModifiedAt = DateTime.now();
      if (_activeSlot?.sourceKey.trim() == sourceKey) {
        frameDetectionSnapshots = snapshot == null ? const [] : [snapshot];
        frameDetectionSourceKey = sourceKey;
        lastFrameDetectionRequestSourceKey = sourceKey;
        lastFrameDetectionRequestSeconds = currentOverlaySeconds;
        lastFrameDetectionStatusUpdatedAt = runtimeStatus?.updatedAt ?? '';
      }
      lastFrameDetectionRequestSecondsBySourceKey = {
        ...lastFrameDetectionRequestSecondsBySourceKey,
        sourceKey: currentOverlaySeconds,
      };
      lastFrameDetectionStatusUpdatedAtBySourceKey = {
        ...lastFrameDetectionStatusUpdatedAtBySourceKey,
        sourceKey: runtimeStatus?.updatedAt ?? '',
      };
    });
  }

  String _resolveApiClipSource(ApiEventItem item) {
    // 서버가 clip_url 또는 server_clip_path를 돌려준 경우 이를 우선 사용합니다.
    final clipUrl = item.clipUrl.trim();
    if (clipUrl.isNotEmpty && clipUrl != '-') {
      return _resolveClipUrl(clipUrl);
    }
    final serverClipPath = item.serverClipPath.trim();
    if (serverClipPath.isNotEmpty && serverClipPath != '-') {
      return _resolveClipUrl(serverClipPath);
    }
    final clipPath = item.clipPath.trim();
    if (clipPath.isEmpty || clipPath == '-') {
      return '';
    }
    return clipPath;
  }

  String _describeClipPolicy(ApiEventItem item) {
    switch (item.preferredClipSource.trim()) {
      case 'server':
        return '서버 클립 우선 사용';
      case 'local':
        return '로컬 clipPath fallback 사용';
      default:
        if (item.clipUrl.trim().isNotEmpty) {
          return '서버 클립 우선 사용';
        }
        if (item.clipPath.trim().isNotEmpty) {
          return '로컬 clipPath fallback 사용';
        }
        return '사용 가능한 클립 정보 없음';
    }
  }

  String _resolveClipUrl(String clipUrl) {
    // /api/clips/파일명 형태의 상대 URL을 실제 접속 가능한 절대 URL로 바꿉니다.
    final trimmed = clipUrl.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return '';
    }

    final normalized = trimmed.toLowerCase();
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) {
      return '${eventApiService.baseUrl}$trimmed';
    }
    return '${eventApiService.baseUrl}/$trimmed';
  }

  Future<_SourcePanelSlot> _addOrActivateSourceSlot({
    required String sourceType,
    required String sourceValue,
    required String openPath,
    required String sourceKey,
    String? originalSourceType,
    String? originalSourceValue,
    String? nextSourceType,
  }) async {
    return _ensureSourceSlot(
      sourceType: sourceType,
      sourceValue: sourceValue,
      openPath: openPath,
      sourceKey: sourceKey,
      originalSourceType: originalSourceType,
      originalSourceValue: originalSourceValue,
      nextSourceType: nextSourceType,
      activate: true,
    );
  }

  Future<_SourcePanelSlot> _ensureSourceSlot({
    required String sourceType,
    required String sourceValue,
    required String openPath,
    required String sourceKey,
    String? originalSourceType,
    String? originalSourceValue,
    String? nextSourceType,
    required bool activate,
  }) async {
    final normalizedSourceKey = sourceKey.trim();
    if (normalizedSourceKey.isNotEmpty &&
        _slotCreationSourceKeys.contains(normalizedSourceKey)) {
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final existingSlot = _findSourceSlotByKey(normalizedSourceKey);
        if (existingSlot != null) {
          if (activate) {
            await _setActiveSlot(existingSlot.slotId);
            unawaited(_refreshApiEventsIfNeeded());
            unawaited(_refreshFrameDetectionsIfNeeded());
          }
          return existingSlot;
        }
        if (!_slotCreationSourceKeys.contains(normalizedSourceKey)) {
          break;
        }
      }
    }

    for (final slot in _sourceSlots) {
      if (slot.sourceKey != sourceKey) {
        continue;
      }
      if (activate) {
        await _setActiveSlot(slot.slotId);
        unawaited(_refreshApiEventsIfNeeded());
        unawaited(_refreshFrameDetectionsIfNeeded());
      }
      return slot;
    }

    if (normalizedSourceKey.isNotEmpty) {
      _slotCreationSourceKeys.add(normalizedSourceKey);
    }

    try {
      final slot = _SourcePanelSlot(
        slotId: 'slot_${DateTime.now().microsecondsSinceEpoch}',
        sourceType: sourceType,
        sourceValue: sourceValue,
        sourceKey: sourceKey,
        originalSourceType: originalSourceType ?? sourceType,
        originalSourceValue: originalSourceValue ?? sourceValue,
        label: _buildSlotLabel(
          sourceType: originalSourceType ?? sourceType,
          sourceValue: originalSourceValue ?? sourceValue,
        ),
        controller: VideoPanelController(),
      );
      try {
        if (openPath.trim().isNotEmpty) {
          await slot.controller.openVideo(
            openPath,
            nextSourceType: nextSourceType ?? sourceType,
          );
        }
      } catch (_) {
        slot.controller.disposeController();
        rethrow;
      }

      final duplicateSlot = _findSourceSlotByKey(sourceKey);
      if (duplicateSlot != null) {
        slot.controller.disposeController();
        if (activate) {
          await _setActiveSlot(duplicateSlot.slotId);
          unawaited(_refreshApiEventsIfNeeded());
          unawaited(_refreshFrameDetectionsIfNeeded());
        }
        return duplicateSlot;
      }

      setState(() {
        _sourceSlots.add(slot);
        if (activate || _activeSlotId.isEmpty) {
          _activeSlotId = slot.slotId;
        }
        selectedApiEventDetail = null;
        apiDetailErrorMessage = null;
        frameDetectionSnapshots = const [];
        frameDetectionLogModifiedAt = null;
        frameDetectionSourceKey = '';
      });
      if (activate || _activeSlotId == slot.slotId) {
        apiEventFeed.setSourceKeyFilter(slot.sourceKey.trim());
        unawaited(_refreshApiEventsIfNeeded());
      }
      await _syncSlotAudioFocus();
      unawaited(_refreshFrameDetectionsIfNeeded());
      return slot;
    } finally {
      if (normalizedSourceKey.isNotEmpty) {
        _slotCreationSourceKeys.remove(normalizedSourceKey);
      }
    }
  }

  void _swapSourceSlots(String draggedSlotId, String targetSlotId) {
    if (draggedSlotId == targetSlotId) {
      return;
    }
    final draggedIndex = _sourceSlots.indexWhere(
      (slot) => slot.slotId == draggedSlotId,
    );
    final targetIndex = _sourceSlots.indexWhere(
      (slot) => slot.slotId == targetSlotId,
    );
    if (draggedIndex < 0 || targetIndex < 0 || draggedIndex == targetIndex) {
      return;
    }
    setState(() {
      final draggedSlot = _sourceSlots[draggedIndex];
      _sourceSlots[draggedIndex] = _sourceSlots[targetIndex];
      _sourceSlots[targetIndex] = draggedSlot;
    });
  }

  Future<void> _removeSourceSlot(String slotId) async {
    _SourcePanelSlot? removedSlot;
    final nextSlots = <_SourcePanelSlot>[];
    for (final slot in _sourceSlots) {
      if (slot.slotId == slotId) {
        removedSlot = slot;
        continue;
      }
      nextSlots.add(slot);
    }
    if (removedSlot == null) {
      return;
    }

    removedSlot.controller.disposeController();
    setState(() {
      final nextSnapshotMap = <String, FrameDetectionSnapshot>{
        ...frameDetectionBySourceKey,
      };
      nextSnapshotMap.remove(removedSlot!.sourceKey.trim());
      final nextRequestSecondsMap = <String, double>{
        ...lastFrameDetectionRequestSecondsBySourceKey,
      };
      nextRequestSecondsMap.remove(removedSlot.sourceKey.trim());
      final nextStatusUpdatedMap = <String, String>{
        ...lastFrameDetectionStatusUpdatedAtBySourceKey,
      };
      nextStatusUpdatedMap.remove(removedSlot.sourceKey.trim());
      _sourceSlots
        ..clear()
        ..addAll(nextSlots);
      if (_activeSlotId == slotId) {
        _activeSlotId = _sourceSlots.isEmpty ? '' : _sourceSlots.last.slotId;
      }
      if (_maximizedSlotId == slotId) {
        _maximizedSlotId = '';
      }
      selectedApiEventDetail = null;
      apiDetailErrorMessage = null;
      frameDetectionSnapshots = const [];
      frameDetectionLogModifiedAt = null;
      frameDetectionSourceKey = '';
      frameDetectionBySourceKey = nextSnapshotMap;
      lastFrameDetectionRequestSecondsBySourceKey = nextRequestSecondsMap;
      lastFrameDetectionStatusUpdatedAtBySourceKey = nextStatusUpdatedMap;
    });

    await _syncSlotAudioFocus();
    apiEventFeed.setSourceKeyFilter(
      _sourceSlots.isEmpty ? '' : (_activeSlot?.sourceKey.trim() ?? ''),
    );
    apiEventFeed.clearSelection();
    await _refreshRegisteredSources();
    await _refreshSourceStatuses();
    if (_sourceSlots.isNotEmpty) {
      await _syncActiveSlotFrameRateIfNeeded();
    }
    unawaited(_refreshApiEventsIfNeeded());
    unawaited(_refreshFrameDetectionsIfNeeded());
  }

  Future<void> removeLocalSlotBySourceKey(String sourceKey) async {
    final normalizedSourceKey = sourceKey.trim();
    if (normalizedSourceKey.isEmpty) {
      return;
    }

    _SourcePanelSlot? removedSlot;
    final nextSlots = <_SourcePanelSlot>[];
    for (final slot in _sourceSlots) {
      if (slot.sourceKey.trim() == normalizedSourceKey) {
        removedSlot = slot;
        continue;
      }
      nextSlots.add(slot);
    }
    if (removedSlot == null) {
      return;
    }

    removedSlot.controller.disposeController();
    setState(() {
      final nextSnapshotMap = <String, FrameDetectionSnapshot>{
        ...frameDetectionBySourceKey,
      };
      nextSnapshotMap.remove(removedSlot!.sourceKey.trim());
      final nextRequestSecondsMap = <String, double>{
        ...lastFrameDetectionRequestSecondsBySourceKey,
      };
      nextRequestSecondsMap.remove(removedSlot.sourceKey.trim());
      final nextStatusUpdatedMap = <String, String>{
        ...lastFrameDetectionStatusUpdatedAtBySourceKey,
      };
      nextStatusUpdatedMap.remove(removedSlot.sourceKey.trim());
      _sourceSlots
        ..clear()
        ..addAll(nextSlots);
      if (_activeSlotId == removedSlot.slotId) {
        _activeSlotId = _sourceSlots.isEmpty ? '' : _sourceSlots.last.slotId;
      }
      if (_maximizedSlotId == removedSlot.slotId) {
        _maximizedSlotId = '';
      }
      selectedApiEventDetail = null;
      apiDetailErrorMessage = null;
      frameDetectionSnapshots = const [];
      frameDetectionLogModifiedAt = null;
      frameDetectionSourceKey = '';
      frameDetectionBySourceKey = nextSnapshotMap;
      lastFrameDetectionRequestSecondsBySourceKey = nextRequestSecondsMap;
      lastFrameDetectionStatusUpdatedAtBySourceKey = nextStatusUpdatedMap;
    });

    await _syncSlotAudioFocus();
    apiEventFeed.setSourceKeyFilter(
      _sourceSlots.isEmpty ? '' : (_activeSlot?.sourceKey.trim() ?? ''),
    );
    apiEventFeed.clearSelection();
    if (_sourceSlots.isNotEmpty) {
      await _syncActiveSlotFrameRateIfNeeded();
    }
    unawaited(_refreshApiEventsIfNeeded());
    unawaited(_refreshFrameDetectionsIfNeeded());
  }

  Future<void> _setActiveSlot(String slotId) async {
    if (_activeSlotId == slotId) {
      return;
    }
    _SourcePanelSlot? nextSlot;
    for (final slot in _sourceSlots) {
      if (slot.slotId == slotId) {
        nextSlot = slot;
        break;
      }
    }
    final nextSourceKey = nextSlot?.sourceKey.trim() ?? '';
    final nextSnapshot = frameDetectionBySourceKey[nextSourceKey];
    setState(() {
      _activeSlotId = slotId;
      selectedApiEventDetail = null;
      apiDetailErrorMessage = null;
      frameDetectionSnapshots = nextSnapshot == null
          ? const []
          : [nextSnapshot];
      frameDetectionLogModifiedAt = null;
      frameDetectionSourceKey = nextSourceKey;
      isEditingDangerZone = false;
      pendingDangerZoneRoi = null;
    });
    apiEventFeed.setSourceKeyFilter(nextSourceKey);
    await _syncSlotAudioFocus();
    apiEventFeed.clearSelection();
    unawaited(_refreshApiEventsIfNeeded());
    unawaited(_syncActiveSlotFrameRateIfNeeded());
    unawaited(_refreshFrameDetectionsIfNeeded());
  }

  Future<void> _toggleActiveSlot(String slotId) async {
    if (_activeSlotId == slotId) {
      setState(() {
        _activeSlotId = '';
        selectedApiEventDetail = null;
        apiDetailErrorMessage = null;
        frameDetectionSnapshots = const [];
        frameDetectionLogModifiedAt = null;
        frameDetectionSourceKey = '';
        isEditingDangerZone = false;
        pendingDangerZoneRoi = null;
      });
      apiEventFeed.setSourceKeyFilter('');
      apiEventFeed.clearSelection();
      unawaited(_refreshApiEventsIfNeeded());
      return;
    }
    await _setActiveSlot(slotId);
  }

  _SourcePanelSlot? _findSourceSlotById(String slotId) {
    final normalized = slotId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final slot in _sourceSlots) {
      if (slot.slotId == normalized) {
        return slot;
      }
    }
    return null;
  }

  Future<void> _closeReplayForSlot(_SourcePanelSlot slot) async {
    await slot.controller.closeReplay();
    apiEventFeed.clearSelection();
    if (selectedApiEventDetail?.sourceKey.trim() == slot.sourceKey.trim()) {
      setState(() {
        selectedApiEventDetail = null;
        apiDetailErrorMessage = null;
      });
    }
    await _refreshFrameDetectionsForSource(slot.sourceKey);
  }

  String _buildSlotLabel({
    required String sourceType,
    required String sourceValue,
  }) {
    if (sourceType == 'video') {
      final normalized = sourceValue.replaceAll('\\', '/');
      final parts = normalized.split('/');
      return parts.isEmpty ? sourceValue : parts.last;
    }
    return sourceValue;
  }

  Future<void> _syncFrameRateFromStatus({
    required String sourceType,
    required String sourceValue,
    required VideoPanelController controller,
  }) async {
    final sourceKey = _buildSourceKey(
      sourceType: sourceType,
      sourceValue: sourceValue,
    );
    final runtimeStatus = sourceStatusesByKey[sourceKey.trim()];
    if (runtimeStatus == null) {
      return;
    }

    if (runtimeStatus.sourceType.trim() != sourceType.trim()) {
      return;
    }

    if (!_isSameSourceValue(runtimeStatus.sourceValue, sourceValue)) {
      return;
    }

    controller.setFrameRate(runtimeStatus.sourceFps);
  }

  Future<void> _refreshSourceStatuses() async {
    final entries = await eventApiService.fetchSourceStatuses();
    if (!mounted) {
      return;
    }

    final nextMap = <String, SourceRuntimeStatus>{};
    for (final entry in entries) {
      final sourceKey = entry.sourceKey.trim();
      if (sourceKey.isEmpty) {
        continue;
      }
      nextMap[sourceKey] = entry;
    }

    setState(() {
      sourceStatusesByKey = nextMap;
    });
  }

  Future<void> _refreshSourceOverviews() async {
    final items = await eventApiService.fetchSourceOverviews();
    if (!mounted) {
      return;
    }

    final nextMap = <String, SourceOverviewItem>{};
    for (final item in items) {
      final sourceKey = item.sourceKey.trim();
      if (sourceKey.isEmpty) {
        continue;
      }
      nextMap[sourceKey] = item;
    }

    setState(() {
      sourceOverviewsByKey = nextMap;
    });
  }

  Future<void> _refreshRegisteredSources() async {
    final items = await eventApiService.fetchSources();
    if (!mounted) {
      return;
    }

    final nextMap = <String, SourceItem>{};
    for (final item in items) {
      final sourceKey = item.sourceKey.trim();
      if (sourceKey.isEmpty) {
        continue;
      }
      if (!_shouldShowViewerSource(item)) {
        continue;
      }
      nextMap[sourceKey] = item;
    }

    final removedSlotLabels = await _pruneLocalSlotsForRemovedRegisteredSources(
      nextMap.keys.toSet(),
    );

    setState(() {
      registeredSourcesByKey = nextMap;
    });

    await _restoreRegisteredSourceSlots(nextMap.values.toList(growable: false));
    if (mounted) {
      setState(_applySavedSourceOrder);
    }

    if (removedSlotLabels.isNotEmpty) {
      apiEventFeed.clearSelection();
      if (_sourceSlots.isNotEmpty) {
        await _syncActiveSlotFrameRateIfNeeded();
      }
      unawaited(_refreshApiEventsIfNeeded());
      unawaited(_refreshFrameDetectionsIfNeeded());
      if (mounted) {
        _showInfoSnack('삭제된 서버 소스 화면을 자동으로 닫았습니다.');
      }
    }
  }

  Future<void> _restoreRegisteredSourceSlots(List<SourceItem> sources) async {
    final previousActiveSlotId = _activeSlotId;
    for (final source in sources) {
      if (!_shouldShowViewerSource(source)) {
        continue;
      }
      final existingSlot = _findSourceSlotByKey(source.sourceKey);
      if (existingSlot != null) {
        continue;
      }

      final openPath = _resolveRegisteredSourceOpenPath(source);
      final isPreviewOnlySource = _isPreviewOnlySourceType(source.sourceType);
      if (openPath.isEmpty && !isPreviewOnlySource) {
        continue;
      }

      await _ensureSourceSlot(
        sourceType: source.sourceType,
        sourceValue: source.sourceValue,
        openPath: openPath,
        sourceKey: source.sourceKey,
        originalSourceType: source.originalSourceType,
        originalSourceValue: source.originalSourceValue,
        nextSourceType: source.sourceType,
        activate: false,
      );
    }

    if (!mounted) {
      return;
    }

    if (previousActiveSlotId.isNotEmpty &&
        _sourceSlots.any((slot) => slot.slotId == previousActiveSlotId)) {
      setState(() {
        _activeSlotId = previousActiveSlotId;
      });
      apiEventFeed.setSourceKeyFilter(_activeSlot?.sourceKey.trim() ?? '');
      await _syncSlotAudioFocus();
      unawaited(_refreshFrameDetectionsIfNeeded());
      return;
    }

    if (_activeSlotId.isEmpty && _sourceSlots.isNotEmpty) {
      setState(() {
        _activeSlotId = _sourceSlots.first.slotId;
      });
      apiEventFeed.setSourceKeyFilter(_activeSlot?.sourceKey.trim() ?? '');
      await _syncSlotAudioFocus();
      unawaited(_refreshFrameDetectionsIfNeeded());
    }
  }

  bool _shouldShowViewerSource(SourceItem source) {
    final sourceKey = source.sourceKey.trim();
    if (sourceKey.isEmpty) return false;
    final type = source.sourceType.trim().toLowerCase();
    return type == 'camera' || type == 'video' || type == 'stream';
  }

  Future<List<String>> _pruneLocalSlotsForRemovedRegisteredSources(
    Set<String> remainingSourceKeys,
  ) async {
    final normalizedRemaining = remainingSourceKeys
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final removedSlots = _sourceSlots
        .where((slot) => !normalizedRemaining.contains(slot.sourceKey.trim()))
        .toList(growable: false);
    if (removedSlots.isEmpty) {
      return const [];
    }

    final nextSlots = _sourceSlots
        .where((slot) => normalizedRemaining.contains(slot.sourceKey.trim()))
        .toList(growable: false);
    final removedActive = removedSlots.any(
      (slot) => slot.slotId == _activeSlotId,
    );

    for (final slot in removedSlots) {
      slot.controller.disposeController();
    }

    if (!mounted) {
      return removedSlots.map((slot) => slot.label).toList(growable: false);
    }

    setState(() {
      _sourceSlots
        ..clear()
        ..addAll(nextSlots);
      if (removedActive) {
        _activeSlotId = _sourceSlots.isEmpty ? '' : _sourceSlots.last.slotId;
      }
      if (!_sourceSlots.any((slot) => slot.slotId == _maximizedSlotId)) {
        _maximizedSlotId = '';
      }
      selectedApiEventDetail = null;
      apiDetailErrorMessage = null;
      frameDetectionSnapshots = const [];
      frameDetectionLogModifiedAt = null;
      frameDetectionSourceKey = '';
    });

    return removedSlots.map((slot) => slot.label).toList(growable: false);
  }

  bool _isSameSourceValue(String left, String right) {
    final normalizedLeft = left.trim().replaceAll('\\', '/').toLowerCase();
    final normalizedRight = right.trim().replaceAll('\\', '/').toLowerCase();
    return normalizedLeft == normalizedRight;
  }

  String _buildSourceHint() {
    if (selectedSourceKey.isEmpty) {
      return '서버에 저장된 소스를 열면 여기서 진행 중 영상과 완료된 영상, 이벤트, 클립을 함께 조회할 수 있습니다.';
    }

    return '현재 선택한 서버 소스의 영상, 객체 박스, 이벤트, 클립 재생 상태를 확인하는 화면입니다.';
  }

  String buildOverlayStatusText() {
    if (videoController.errorText.trim().isNotEmpty) {
      return '영상 재생 오류: ${videoController.errorText.trim()}';
    }

    final sourceKey = _effectiveOverlaySourceKey().trim();
    if (sourceKey.isEmpty) {
      return '선택된 소스가 없어 전체 로그만 표시 중입니다.';
    }

    if (videoController.isReplayMode) {
      return '클립 재생 중입니다. 박스는 원본 영상 시간축 기준으로 맞춰집니다.';
    }

    if (!sourceStatusesByKey.containsKey(sourceKey)) {
      return '이 소스는 아직 분석 준비 중입니다. 서버 상태가 갱신되면 박스가 표시됩니다.';
    }

    final status = sourceStatusesByKey[sourceKey];

    if (frameDetectionSourceKey != sourceKey ||
        frameDetectionSnapshots.isEmpty) {
      return '아직 이 소스의 프레임 탐지 결과를 기다리는 중입니다.';
    }

    final snapshot = frameDetectionSnapshots.isEmpty
        ? null
        : frameDetectionSnapshots.first;
    if (snapshot != null) {
      final snapshotTimeDelta =
          (snapshot.sourceTimeSeconds - videoController.currentOverlaySeconds)
              .abs();
      if (snapshotTimeDelta <= 0.15) {
        if (snapshot.detections.isEmpty) {
          return '현재 시점에는 탐지된 객체가 없습니다.';
        }
        return '';
      }
    }

    if (snapshot == null) {
      return '현재 재생 시점과 맞는 분석 프레임을 기다리는 중입니다.';
    }

    if (status != null &&
        status.state.trim().toLowerCase() != 'completed' &&
        status.lastSourceTimeSeconds + 0.02 <
            videoController.currentOverlaySeconds) {
      return '현재 재생 시점의 분석 결과가 아직 서버에 도착하지 않았습니다.';
    }

    if (snapshot.detections.isEmpty) {
      return '현재 시점에는 탐지된 객체가 없습니다.';
    }

    return '';
  }

  String _buildActiveSourceLabel() {
    final slot = _activeSlot;
    if (slot == null) {
      if (_sourceSlots.isEmpty) {
        return '없음';
      }
      return '전체 로그 보기';
    }
    return slot.label;
  }

  _SourcePanelSlot? _findSourceSlotByKey(String sourceKey) {
    final normalizedSourceKey = sourceKey.trim();
    if (normalizedSourceKey.isEmpty) {
      return null;
    }
    for (final slot in _sourceSlots) {
      if (slot.sourceKey.trim() == normalizedSourceKey) {
        return slot;
      }
    }
    return null;
  }

  _SourcePanelSlot? findSourceSlot({
    required String sourceType,
    required String sourceValue,
  }) {
    final nextSourceKey = _buildSourceKey(
      sourceType: sourceType,
      sourceValue: sourceValue,
    );
    for (final slot in _sourceSlots) {
      if (slot.sourceKey == nextSourceKey) {
        return slot;
      }
      if (slot.originalSourceType.trim() == sourceType.trim() &&
          _isSameSourceValue(slot.originalSourceValue, sourceValue)) {
        return slot;
      }
    }
    return null;
  }

  Future<void> _syncActiveSlotFrameRateIfNeeded() async {
    final slot = _activeSlot;
    if (slot == null) {
      return;
    }
    await _syncFrameRateFromStatus(
      sourceType: slot.sourceType,
      sourceValue: slot.sourceValue,
      controller: slot.controller,
    );
  }

  Future<bool> _activateSlotForSourceKey(String sourceKey) async {
    final targetSlot = _findSourceSlotByKey(sourceKey);
    if (targetSlot == null) {
      return false;
    }
    if (_activeSlotId != targetSlot.slotId) {
      await _setActiveSlot(targetSlot.slotId);
    }
    await _syncFrameRateFromStatus(
      sourceType: targetSlot.sourceType,
      sourceValue: targetSlot.sourceValue,
      controller: targetSlot.controller,
    );
    return true;
  }

  Future<bool> _ensureSlotForEventSource(ApiEventItem item) async {
    final activated = await _activateSlotForSourceKey(item.sourceKey);
    if (activated) {
      return true;
    }

    final sourceType = item.sourceType.trim();
    final sourceValue = item.sourceValue.trim();
    if (sourceType.isEmpty || sourceValue.isEmpty) {
      return false;
    }

    try {
      await _addOrActivateSourceSlot(
        sourceType: sourceType,
        sourceValue: sourceValue,
        openPath: sourceValue,
        sourceKey: item.sourceKey,
        originalSourceType: sourceType,
        originalSourceValue: sourceValue,
        nextSourceType: sourceType,
      );
      await _syncActiveSlotFrameRateIfNeeded();
      if (mounted) {
        _showInfoSnack('이벤트 원본 소스를 화면에 추가하고 전환했습니다.');
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<_ClipTargetBinding> _resolveClipTargetController(
    ApiEventItem item,
  ) async {
    final ensured = await _ensureSlotForEventSource(item);
    if (ensured) {
      final targetSlot = _findSourceSlotByKey(item.sourceKey);
      if (targetSlot != null) {
        return _ClipTargetBinding(
          controller: targetSlot.controller,
          preserveReturnContext: true,
        );
      }
    }

    if (mounted) {
      _showInfoSnack('원본 소스를 열 수 없어 현재 화면에서 클립만 재생합니다.');
    }
    return _ClipTargetBinding(
      controller: videoController,
      preserveReturnContext: videoController.videoPath.trim().isNotEmpty,
    );
  }

  Future<void> _confirmRemoveSourceSlot(_SourcePanelSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('패널 닫기'),
          content: Text('"${slot.label}" 소스 화면만 닫습니다. 계속할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('패널 닫기'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _removeSourceSlot(slot.slotId);
    if (mounted) {
      _showInfoSnack('"${slot.label}" 소스 화면을 닫았습니다.');
    }
  }

  Future<void> _handleSlotDeleteAction(_SourcePanelSlot slot) async {
    await _confirmRemoveSourceSlot(slot);
  }

  Future<void> _openRegisteredSource(SourceItem source) async {
    final existingSlot = _findSourceSlotByKey(source.sourceKey);
    if (existingSlot != null) {
      await _setActiveSlot(existingSlot.slotId);
      return;
    }

    final openPath = _resolveRegisteredSourceOpenPath(source);
    final isPreviewOnlySource = _isPreviewOnlySourceType(source.sourceType);
    if (openPath.isEmpty && !isPreviewOnlySource) {
      if (mounted) {
        _showInfoSnack('이 소스는 현재 화면에서 열 수 있는 재생 경로가 없습니다.');
      }
      return;
    }

    await _addOrActivateSourceSlot(
      sourceType: source.sourceType,
      sourceValue: source.sourceValue,
      openPath: openPath,
      nextSourceType: source.sourceType,
      sourceKey: source.sourceKey,
      originalSourceType: source.originalSourceType,
      originalSourceValue: source.originalSourceValue,
    );
    await _syncActiveSlotFrameRateIfNeeded();
    if (mounted) {
      _showInfoSnack('"${source.sourceSlug}" 소스를 화면에 열었습니다.');
    }
  }

  String _resolveRegisteredSourceOpenPath(SourceItem source) {
    final sourceType = source.sourceType.trim().toLowerCase();
    if (sourceType == 'camera' ||
        sourceType == 'stream' ||
        sourceType == 'video') {
      return '';
    }

    final mediaUrl = source.mediaUrl.trim();
    if (mediaUrl.isNotEmpty) {
      return _resolveClipUrl(mediaUrl);
    }

    final original = source.originalSourceValue.trim();
    if (original.isNotEmpty) {
      return original;
    }
    return source.sourceValue.trim();
  }

  bool _isPreviewOnlySourceType(String sourceType) {
    final normalized = sourceType.trim().toLowerCase();
    return normalized == 'camera' ||
        normalized == 'stream' ||
        normalized == 'video';
  }

  String _describeServerSourceState(String sourceKey) {
    final normalized = sourceKey.trim();
    if (normalized.isEmpty) {
      return 'unknown';
    }
    final runtimeStatus = sourceStatusesByKey[normalized];
    if (runtimeStatus == null) {
      return 'unknown';
    }
    final state = runtimeStatus.state.trim().toLowerCase();
    if (state == 'completed') {
      return 'complete';
    }
    return runtimeStatus.state.trim().isEmpty
        ? 'unknown'
        : runtimeStatus.state.trim();
  }

  String _buildSourceProgressText(
    SourceItem? source,
    SourceRuntimeStatus? status,
  ) {
    final durationSeconds =
        source?.sourceDurationSeconds ?? status?.sourceDurationSeconds ?? 0.0;
    final lastSeconds = status?.lastSourceTimeSeconds ?? 0.0;
    if (durationSeconds <= 0) {
      if (lastSeconds > 0) {
        return '${lastSeconds.toStringAsFixed(1)}s';
      }
      return '-';
    }

    final clampedSeconds = lastSeconds.clamp(0.0, durationSeconds);
    final percent = (clampedSeconds / durationSeconds) * 100.0;
    return '${clampedSeconds.toStringAsFixed(1)} / ${durationSeconds.toStringAsFixed(1)}s (${percent.toStringAsFixed(1)}%)';
  }

  String _describeSlotStatus(_SourcePanelSlot slot) {
    final sourceKey = slot.sourceKey.trim();
    if (slot.controller.errorText.trim().isNotEmpty) {
      return '오류';
    }
    final runtimeStatus = sourceStatusesByKey[sourceKey];
    if (_isSlotOfflineForViewer(slot)) {
      return '오프라인';
    }
    if (runtimeStatus == null) {
      return '등록됨';
    }
    if (runtimeStatus.errorMessage.trim().isNotEmpty ||
        runtimeStatus.state.trim().toLowerCase() == 'error') {
      return '오류';
    }
    final runtimeState = runtimeStatus.state.trim().toLowerCase();
    if (runtimeState == 'completed') {
      final hasEvents = apiEventController.items.any(
        (item) => item.sourceKey.trim() == sourceKey,
      );
      return hasEvents ? '분석 완료 · 이벤트 있음' : '분석 완료';
    }
    if (runtimeState == 'source_changed' || runtimeState == 'stopped') {
      return '중지됨';
    }
    if (slot.slotId == _activeSlotId &&
        frameDetectionSourceKey == sourceKey &&
        frameDetectionSnapshots.isNotEmpty) {
      return '분석중';
    }
    final hasEvents = apiEventController.items.any(
      (item) => item.sourceKey.trim() == sourceKey,
    );
    if (hasEvents) {
      return '이벤트 있음';
    }
    if (runtimeStatus.isRunning) {
      return '백그라운드 분석';
    }
    return '대기중';
  }

  Color _colorForSlotStatus(_SourcePanelSlot slot) {
    switch (_describeSlotStatus(slot)) {
      case '오류':
        return Colors.redAccent;
      case '분석중':
        return Colors.green;
      case '이벤트 있음':
        return Colors.orangeAccent;
      case '백그라운드 분석':
        return Colors.blueAccent;
      case '대기중':
        return Colors.blueGrey;
      case '분석 완료':
        return Colors.teal;
      case '분석 완료 · 이벤트 있음':
        return Colors.tealAccent.shade700;
      case '중지됨':
        return Colors.blueGrey;
      case '오프라인':
        return Colors.grey;
      case '등록됨':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  _ClientConnectionStatus _resolveClientConnectionStatus(
    _SourcePanelSlot slot,
  ) {
    if (slot.controller.errorText.trim().isNotEmpty) {
      return const _ClientConnectionStatus(
        color: Colors.redAccent,
        label: '클라이언트 연결 오류',
      );
    }

    final sourceKey = slot.sourceKey.trim();
    final runtimeStatus = sourceStatusesByKey[sourceKey];
    if (_isSlotOfflineForViewer(slot)) {
      return const _ClientConnectionStatus(
        color: Colors.grey,
        label: '클라이언트 오프라인',
      );
    }
    if (runtimeStatus == null) {
      return const _ClientConnectionStatus(
        color: Colors.orangeAccent,
        label: '클라이언트 연결 대기',
      );
    }

    final runtimeState = runtimeStatus.state.trim().toLowerCase();
    if (runtimeStatus.errorMessage.trim().isNotEmpty ||
        runtimeState == 'error') {
      return const _ClientConnectionStatus(
        color: Colors.redAccent,
        label: '클라이언트 오류',
      );
    }

    if (runtimeStatus.isRunning ||
        runtimeState == 'running' ||
        runtimeState == 'analyzing') {
      return const _ClientConnectionStatus(
        color: Colors.green,
        label: '클라이언트 연결됨',
      );
    }

    return const _ClientConnectionStatus(
      color: Colors.orangeAccent,
      label: '클라이언트 연결됨 · 분석 대기',
    );
  }

  // ignore: unused_element
  int _countActiveViewerClients() {
    final activeClientIds = <String>{};
    for (final status in sourceStatusesByKey.values) {
      if (_isViewerSourceOffline(
        status,
        sourceOverviewsByKey[status.sourceKey.trim()],
      )) {
        continue;
      }
      final clientId = status.clientId.trim();
      if (clientId.isNotEmpty) {
        activeClientIds.add(clientId);
      }
    }
    return activeClientIds.length;
  }

  bool _isStatusTimestampStale(String updatedAt) {
    final parsed = DateTime.tryParse(updatedAt.trim());
    if (parsed == null) {
      return true;
    }
    return DateTime.now().difference(parsed.toLocal()) >
        _viewerClientHeartbeatTimeout;
  }

  bool _hasRecentClientHeartbeat({
    required String clientId,
    required String sessionId,
    String excludeSourceKey = '',
  }) {
    final normalizedClientId = clientId.trim();
    final normalizedSessionId = sessionId.trim();
    if (normalizedClientId.isEmpty && normalizedSessionId.isEmpty) {
      return false;
    }
    for (final status in sourceStatusesByKey.values) {
      if (status.sourceKey.trim() == excludeSourceKey.trim()) {
        continue;
      }
      if (status.clientId.trim() != normalizedClientId ||
          status.sessionId.trim() != normalizedSessionId) {
        continue;
      }
      if (!_isStatusTimestampStale(status.updatedAt)) {
        return true;
      }
    }
    return false;
  }

  bool _isViewerSourceOffline(
    SourceRuntimeStatus status,
    SourceOverviewItem? overview,
  ) {
    if (!_isStatusTimestampStale(status.updatedAt)) {
      return false;
    }
    final clientId = status.clientId.trim().isNotEmpty
        ? status.clientId.trim()
        : overview?.clientId.trim() ?? '';
    final sessionId = status.sessionId.trim().isNotEmpty
        ? status.sessionId.trim()
        : overview?.sessionId.trim() ?? '';
    return !_hasRecentClientHeartbeat(
      clientId: clientId,
      sessionId: sessionId,
      excludeSourceKey: status.sourceKey,
    );
  }

  bool _isSlotOfflineForViewer(_SourcePanelSlot slot) {
    final sourceKey = slot.sourceKey.trim();
    final runtimeStatus = sourceStatusesByKey[sourceKey];
    final overview = sourceOverviewsByKey[sourceKey];
    if (runtimeStatus == null) {
      return _hasViewerHistory(overview);
    }
    if (_isViewerSourceOffline(runtimeStatus, overview)) {
      return true;
    }
    final runtimeState = runtimeStatus.state.trim().toLowerCase();
    final lastFrameReceivedAt = overview?.lastFrameReceivedAt.trim() ?? '';
    if ((runtimeStatus.isRunning ||
            runtimeState == 'running' ||
            runtimeState == 'analyzing') &&
        lastFrameReceivedAt.isNotEmpty &&
        _isStatusTimestampStale(lastFrameReceivedAt)) {
      return true;
    }
    return false;
  }

  bool _hasViewerHistory(SourceOverviewItem? overview) {
    if (overview == null) {
      return false;
    }
    return overview.lastEventReceivedAt.trim().isNotEmpty ||
        overview.lastFrameReceivedAt.trim().isNotEmpty;
  }

  String _buildSourceOwnerLabel({
    required String clientId,
    required String sessionId,
  }) {
    final normalizedClientId = clientId.trim();
    final normalizedSessionId = sessionId.trim();
    if (normalizedClientId.isEmpty && normalizedSessionId.isEmpty) {
      return '알 수 없음';
    }
    if (normalizedSessionId.isEmpty) {
      return normalizedClientId;
    }
    if (normalizedClientId.isEmpty) {
      return normalizedSessionId;
    }
    return '$normalizedClientId / $normalizedSessionId';
  }

  // ignore: unused_element
  String _buildRuleConfigSummary(SourceRuleConfig ruleConfig) {
    final noHelmet = ruleConfig.useNoHelmetRule ? '안전모 ON' : '안전모 OFF';
    final dangerZone = ruleConfig.useDangerZoneRule
        ? ruleConfig.dangerZoneRoi == null
              ? '위험구역 ON'
              : '위험구역 ON (ROI 저장됨)'
        : '위험구역 OFF';
    return '$noHelmet, $dangerZone';
  }

  String _buildViewerSourceAvailabilityText(
    SourceItem source,
    SourceRuntimeStatus? status,
    SourceOverviewItem? overview,
  ) {
    if (status != null) {
      if (_isViewerSourceOffline(status, overview)) {
        return '소유 클라이언트가 현재 연결되어 있지 않아 분석이 멈춘 상태입니다.';
      }
      if (status.errorMessage.trim().isNotEmpty) {
        return '분석 오류: ${status.errorMessage.trim()}';
      }
      final runtimeState = status.state.trim().toLowerCase();
      if (status.isRunning) {
        return '소유 클라이언트에서 현재 분석 중입니다.';
      }
      if (runtimeState == 'completed') {
        return '분석이 완료된 영상입니다.';
      }
      if (runtimeState == 'registered' || runtimeState == 'starting') {
        return '소유 클라이언트에서 분석 준비 중입니다.';
      }
      if (runtimeState == 'stopped') {
        return '소유 클라이언트에 등록되어 있지만 현재 분석은 중지되어 있습니다.';
      }
    }

    if (_hasViewerHistory(overview)) {
      return '이전에 분석 기록은 있지만 현재 소유 클라이언트 상태는 연결되어 있지 않습니다.';
    }
    if (source.desiredRunning) {
      return '소유 클라이언트가 꺼져 있거나 아직 이 소스 분석을 시작하지 않았습니다.';
    }
    return '현재 분석이 비활성화된 소스입니다.';
  }

  void _showInfoSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _clearSelectedSource() async {
    apiEventFeed.clearSelection();
    apiEventFeed.setSourceKeyFilter('');
    if (_activeSlotId.isNotEmpty) {
      setState(() {
        _activeSlotId = '';
        selectedApiEventDetail = null;
        apiDetailErrorMessage = null;
        frameDetectionSnapshots = const [];
        frameDetectionLogModifiedAt = null;
        frameDetectionSourceKey = '';
        isEditingDangerZone = false;
        pendingDangerZoneRoi = null;
      });
      if (mounted) {
        _showInfoSnack('소스 선택을 해제하고 전체 이벤트 로그 보기로 전환했습니다.');
      }
      unawaited(_refreshApiEventsIfNeeded());
      return;
    }
    setState(() {
      selectedApiEventDetail = null;
      apiDetailErrorMessage = null;
      frameDetectionSnapshots = const [];
      frameDetectionLogModifiedAt = null;
      frameDetectionSourceKey = '';
      isEditingDangerZone = false;
      pendingDangerZoneRoi = null;
    });
    unawaited(_refreshApiEventsIfNeeded());
  }

  String _buildSourceKey({
    required String sourceType,
    required String sourceValue,
  }) {
    final normalizedType = sourceType.trim().toLowerCase();
    final normalizedValue = sourceValue
        .trim()
        .replaceAll('\\', '/')
        .toLowerCase();
    return '$normalizedType|$normalizedValue';
  }

  Future<void> _initializeServerConnection() async {
    final configuredBaseUrl = await _loadServerBaseUrlConfig();
    if (configuredBaseUrl.isNotEmpty) {
      eventApiService.updateBaseUrl(configuredBaseUrl);
    }
    unawaited(_connectRealtimeUpdates());
    await apiEventController.checkHealth();
    await _refreshSourceOverviews();
    await _refreshApiEventsIfNeeded();
    await _refreshSourceStatuses();
    await _refreshRegisteredSources();
  }

  Future<void> _connectRealtimeUpdates() async {
    realtimeReconnectTimer?.cancel();
    await _disconnectRealtimeUpdates();
    try {
      final socket = await WebSocket.connect(
        eventApiService.buildRealtimeUpdatesUri().toString(),
      );
      realtimeSocket = socket;
      if (mounted) {
        setState(() {
          isRealtimeConnected = true;
        });
      } else {
        isRealtimeConnected = true;
      }
      realtimeSocketSubscription = socket.listen(
        _handleRealtimeUpdateMessage,
        onDone: _handleRealtimeSocketClosed,
        onError: (_) => _handleRealtimeSocketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRealtimeReconnect();
    }
  }

  Future<void> _disconnectRealtimeUpdates() async {
    final subscription = realtimeSocketSubscription;
    realtimeSocketSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    final socket = realtimeSocket;
    realtimeSocket = null;
    if (socket != null) {
      await socket.close();
    }
    if (mounted) {
      setState(() {
        isRealtimeConnected = false;
      });
    } else {
      isRealtimeConnected = false;
    }
  }

  void _handleRealtimeSocketClosed() {
    realtimeSocketSubscription = null;
    realtimeSocket = null;
    if (mounted) {
      setState(() {
        isRealtimeConnected = false;
      });
    } else {
      isRealtimeConnected = false;
    }
    _scheduleRealtimeReconnect();
  }

  void _scheduleRealtimeReconnect() {
    realtimeReconnectTimer?.cancel();
    realtimeReconnectTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_connectRealtimeUpdates());
    });
  }

  void _handleRealtimeUpdateMessage(dynamic data) {
    if (data is! String) {
      return;
    }
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final type = decoded['type']?.toString().trim() ?? '';
      switch (type) {
        case 'source_changed':
          _queueRealtimeRefresh(
            refreshSources: true,
            refreshStatuses: true,
            refreshEvents: true,
          );
          break;
        case 'source_status_changed':
          _queueRealtimeRefresh(refreshStatuses: true);
          break;
        case 'event_changed':
          _queueRealtimeRefresh(refreshEvents: true);
          break;
      }
    } catch (_) {
      return;
    }
  }

  void _queueRealtimeRefresh({
    bool refreshEvents = false,
    bool refreshSources = false,
    bool refreshStatuses = false,
  }) {
    pendingRealtimeEventsRefresh =
        pendingRealtimeEventsRefresh || refreshEvents;
    pendingRealtimeSourcesRefresh =
        pendingRealtimeSourcesRefresh || refreshSources;
    pendingRealtimeStatusesRefresh =
        pendingRealtimeStatusesRefresh || refreshStatuses;
    queuedRealtimeRefreshTimer ??= Timer(
      const Duration(milliseconds: 200),
      () async {
        queuedRealtimeRefreshTimer = null;
        final shouldRefreshSources = pendingRealtimeSourcesRefresh;
        final shouldRefreshStatuses = pendingRealtimeStatusesRefresh;
        final shouldRefreshEvents = pendingRealtimeEventsRefresh;
        pendingRealtimeSourcesRefresh = false;
        pendingRealtimeStatusesRefresh = false;
        pendingRealtimeEventsRefresh = false;
        if (shouldRefreshSources) {
          await _refreshSourceOverviews();
          await _refreshRegisteredSources();
        }
        if (shouldRefreshStatuses) {
          await _refreshSourceOverviews();
          await _refreshSourceStatuses();
          await _syncActiveSlotFrameRateIfNeeded();
        }
        if (shouldRefreshEvents) {
          await _refreshApiEventsIfNeeded();
        }
      },
    );
  }

  Future<String> _loadServerBaseUrlConfig() async {
    try {
      final configPath = _resolveViewerConfigFile();
      if (!await configPath.exists()) {
        return '';
      }
      final decoded = jsonDecode(await configPath.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return '';
      }
      final value = decoded['api_base_url']?.toString().trim() ?? '';
      return value;
    } catch (_) {
      return '';
    }
  }

  File _resolveViewerConfigFile() {
    final projectRoot = _findViewerProjectRoot();
    return File(
      '${projectRoot.path}${Platform.pathSeparator}server_config.json',
    );
  }

  Directory _findViewerProjectRoot() {
    final roots = <Directory>{
      Directory.current.absolute,
      File(Platform.resolvedExecutable).parent.absolute,
    };
    for (final root in roots) {
      Directory? current = root;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        final pubspec = File(
          '${current.path}${Platform.pathSeparator}pubspec.yaml',
        );
        final libDir = Directory('${current.path}${Platform.pathSeparator}lib');
        if (pubspec.existsSync() && libDir.existsSync()) {
          return current;
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return Directory.current.absolute;
  }
}

class _SourcePanelSlot {
  _SourcePanelSlot({
    required this.slotId,
    required this.sourceType,
    required this.sourceValue,
    required this.sourceKey,
    required this.originalSourceType,
    required this.originalSourceValue,
    required this.label,
    required this.controller,
  });

  final String slotId;
  final String sourceType;
  final String sourceValue;
  final String sourceKey;
  final String originalSourceType;
  final String originalSourceValue;
  final String label;
  final VideoPanelController controller;
}

class _ClientConnectionStatus {
  const _ClientConnectionStatus({required this.color, required this.label});

  final Color color;
  final String label;
}

class _ClipTargetBinding {
  const _ClipTargetBinding({
    required this.controller,
    required this.preserveReturnContext,
  });

  final VideoPanelController controller;
  final bool preserveReturnContext;
}
