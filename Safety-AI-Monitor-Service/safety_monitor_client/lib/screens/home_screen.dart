// 화면을 구성하는 Flutter 코드이며 상태값과 버튼 동작이 모여 있습니다.
// initState, 서버 통신 함수, build 메서드가 같은 화면 흐름을 구성합니다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../controllers/api_event_controller.dart';
import '../controllers/api_event_feed_source.dart';
import '../controllers/video_panel_controller.dart';
import '../models/api_event_item.dart';
import '../models/client_runtime_config.dart';
import '../models/event_log_item.dart';
import '../models/frame_detection_snapshot.dart';
import '../models/source_item.dart';
import '../models/source_runtime_status.dart';
import '../models/video_overlay_detection.dart';
import '../services/event_api_service.dart';
import '../services/embedded_backend_service.dart';
import '../widgets/event_log_box.dart';
import '../widgets/video_view_box.dart';
import '../services/client_identity_service.dart';
import '../ui/portfolio_theme.dart';
import 'portfolio/camera_add_dialog.dart';

// 메인 화면입니다.
// API 서버 기준 이벤트 표시와 영상 재생을 함께 조합합니다.

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const bool _isViewerReadOnly = false;
  static const String _defaultApiServerBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8100',
  );
  static const String _defaultRemoteServerBaseUrl = 'http://127.0.0.1:8000';
  static const Duration _apiAutoRefreshInterval = Duration(seconds: 30);
  late final VideoPanelController _emptyVideoController;
  late final EventApiService eventApiService;
  late final EventApiService remoteEventApiService;
  late final ApiEventController apiEventController;
  late final ApiEventFeedSource apiEventFeed;
  final ScrollController appScrollController = ScrollController();
  final TextEditingController streamTextController = TextEditingController();
  final TextEditingController cameraTextController = TextEditingController(
    text: '0',
  );
  final TextEditingController serverBaseUrlTextController =
      TextEditingController(text: _defaultRemoteServerBaseUrl);
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
  Timer? cameraEnsureTimer;
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
  Map<String, SourceItem> registeredSourcesByKey = const {};
  Map<String, SourceRuntimeStatus> sourceStatusesByKey = const {};
  ClientRuntimeConfig? clientRuntimeConfig;
  String lastFrameDetectionRequestSourceKey = '';
  double lastFrameDetectionRequestSeconds = -1;
  String lastFrameDetectionStatusUpdatedAt = '';
  String clientId = '';
  bool isRealtimeConnected = false;
  bool pendingRealtimeEventsRefresh = false;
  bool pendingRealtimeSourcesRefresh = false;
  bool pendingRealtimeStatusesRefresh = false;
  bool _didAutoRegisterCamera = false;
  bool _isEnsuringCameraSource = false;
  int previewRefreshCacheBust = 0;

  @override
  void initState() {
    super.initState();
    // 화면이 열리면 재생 컨트롤러와 서버 연결, 자동 새로고침/동기화 루프를 시작한다.
    _emptyVideoController = VideoPanelController();
    eventApiService = EventApiService(baseUrl: _defaultApiServerBaseUrl);
    remoteEventApiService = EventApiService(
      baseUrl: _defaultRemoteServerBaseUrl,
    );
    apiEventController = ApiEventController(service: remoteEventApiService);
    apiEventFeed = ApiEventFeedSource(apiEventController);
    unawaited(_initializeServerConnection());
    _startApiAutoRefresh();
    _startFrameDetectionRefresh();
    _startSourceStatusSync();
    _startPreviewRefresh();
    _startCameraAutoEnsure();
  }

  @override
  void dispose() {
    // 화면이 사라질 때는 백그라운드 타이머와 WebSocket 연결을 모두 정리한다.
    apiAutoRefreshTimer?.cancel();
    frameDetectionRefreshTimer?.cancel();
    sourceStatusSyncTimer?.cancel();
    previewRefreshTimer?.cancel();
    cameraEnsureTimer?.cancel();
    realtimeReconnectTimer?.cancel();
    queuedRealtimeRefreshTimer?.cancel();
    realtimeSocketSubscription?.cancel();
    realtimeSocket?.close();
    for (final slot in _sourceSlots) {
      slot.controller.disposeController();
    }
    _emptyVideoController.disposeController();
    eventApiService.dispose();
    remoteEventApiService.dispose();
    apiEventFeed.dispose();
    appScrollController.dispose();
    streamTextController.dispose();
    cameraTextController.dispose();
    serverBaseUrlTextController.dispose();
    super.dispose();
  }

  Future<void> _refreshAllApiData() async {
  await _refreshClientRuntimeConfig();
  await _refreshRegisteredSources();
  await _refreshSourceStatuses();
  await _refreshApiEventsIfNeeded();

  if (mounted) {
    setState(() {});
    }
  }

  _SourcePanelSlot? get _activeSlot {
    // 현재 선택된 슬롯 ID와 일치하는 패널 정보를 찾아 반환한다.
    for (final slot in _sourceSlots) {
      if (slot.slotId == _activeSlotId) {
        return slot;
      }
    }
    return null;
  }

  SourceItem? get _activeSourceItem {
    // 현재 선택된 소스 키가 있으면 등록된 소스 맵에서 해당 소스 정보를 꺼낸다.
    final sourceKey = selectedSourceKey.trim();
    if (sourceKey.isEmpty) {
      return null;
    }
    return registeredSourcesByKey[sourceKey];
  }

  VideoPanelController get videoController =>
      // 선택된 슬롯이 있으면 그 슬롯의 컨트롤러를 쓰고, 없으면 빈 플레이어 컨트롤러를 사용한다.
      _activeSlot?.controller ?? _emptyVideoController;

  String get selectedSourceType => _activeSlot?.sourceType ?? '';

  String get selectedSourceValue => _activeSlot?.sourceValue ?? '';

  String get selectedSourceKey => _activeSlot?.sourceKey ?? '';

  @override
  Widget build(BuildContext context) {
    final identity = ClientIdentityService.current;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 14,
        title: Row(children: [
          const Icon(Icons.shield_outlined, size: 24),
          const SizedBox(width: 8),
          const Text('SAFETY CLIENT', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(width: 16),
          Container(width: 1, height: 22, color: PortfolioColors.border),
          const SizedBox(width: 16),
          Text(identity?.clientName ?? '현장 Client', style: const TextStyle(fontSize: 13, color: PortfolioColors.textMuted)),
        ]),
        actions: [
          AnimatedBuilder(
            animation: EmbeddedBackendService.instance,
            builder: (context, _) {
              final backend = EmbeddedBackendService.instance;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(child: Row(children: [
                  Icon(Icons.circle, size: 9, color: backend.isRunning ? PortfolioColors.success : backend.isStarting ? PortfolioColors.warning : PortfolioColors.danger),
                  const SizedBox(width: 6),
                  Text(backend.isRunning ? 'AI RUNNING' : backend.isStarting ? 'AI STARTING' : 'AI OFFLINE', style: const TextStyle(fontSize: 11, color: PortfolioColors.textMuted)),
                ])),
              );
            },
          ),
          IconButton(tooltip: '새로고침', onPressed: () => unawaited(_refreshAllApiData()), icon: const Icon(Icons.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          _buildEngineProgressPanel(),
          Expanded(child: Row(children: [
            SizedBox(width: 300, child: _buildPortfolioClientInfo(identity)),
            const SizedBox(width: 10),
            Expanded(child: _buildPortfolioCameraArea()),
          ])),
        ]),
      ),
    );
  }

  Widget _buildPortfolioClientInfo(ClientIdentity? identity) {
    final runtime = clientRuntimeConfig;
    return _buildPanelCard(
      title: 'Client 정보',
      expandChild: true,
      child: ListView(children: [
        _buildPortfolioInfoLine('이름', identity?.clientName ?? '-'),
        _buildPortfolioInfoLine('Client ID', identity?.clientId ?? clientId),
        _buildPortfolioInfoLine('서버 연결', serverBaseUrlTextController.text),
        _buildPortfolioInfoLine('AI 모델', runtime?.modelType ?? 'YOLO'),
        _buildPortfolioInfoLine('연산 장치', runtime?.analysisDevice ?? '-'),
        _buildPortfolioInfoLine('TensorRT', runtime?.engineExists == true ? 'Ready' : 'Preparing / Not built'),
        const SizedBox(height: 18),
        _buildClientApiControls(),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: EmbeddedBackendService.instance,
          builder: (context, _) {
            final backend = EmbeddedBackendService.instance;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: PortfolioColors.panelAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: PortfolioColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AI 상태', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(backend.isRunning ? '● 실행 중' : backend.isStarting ? '● 시작 중' : '● 중지', style: TextStyle(color: backend.isRunning ? PortfolioColors.success : backend.isStarting ? PortfolioColors.warning : PortfolioColors.danger)),
                if (backend.lastErrorMessage.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(backend.lastErrorMessage, style: const TextStyle(color: PortfolioColors.danger, fontSize: 11)),
                ],
              ]),
            );
          },
        ),
      ]),
    );
  }

  Widget _buildPortfolioInfoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 82, child: Text(label, style: const TextStyle(color: PortfolioColors.textMuted, fontSize: 11))),
        Expanded(child: Text(value.isEmpty ? '-' : value, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _buildPortfolioCameraArea() {
    return _buildPanelCard(
      title: '카메라 목록',
      trailing: FilledButton.icon(
        onPressed: () => unawaited(_showPortfolioCameraAdd()),
        icon: const Icon(Icons.add, size: 17),
        label: const Text('카메라 추가'),
      ),
      expandChild: true,
      child: Column(children: [
        Expanded(child: _buildVideoGridPanel()),
        const SizedBox(height: 10),
        Row(children: [
          FilledButton.tonalIcon(onPressed: () => unawaited(_startAllSources()), icon: const Icon(Icons.play_arrow), label: const Text('모두 시작')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: () => unawaited(_stopAllSources()), icon: const Icon(Icons.stop), label: const Text('모두 중지')),
          const Spacer(),
          Text('등록 ${_sourceSlots.length}대', style: const TextStyle(color: PortfolioColors.textMuted)),
        ]),
      ]),
    );
  }

  Future<void> _showPortfolioCameraAdd() async {
    final result = await showCameraAddDialog(context);
    if (result == null) return;
    final beforeKeys = registeredSourcesByKey.keys.toSet();
    if (result.videoFile) {
      await _pickVideoFile();
    } else {
      await _openCamera(cameraIndex: result.cameraIndex);
    }

    await _refreshRegisteredSources();
    final sourceType = result.videoFile ? 'video' : 'camera';
    SourceItem? created;
    for (final source in registeredSourcesByKey.values) {
      if (source.sourceType.trim().toLowerCase() != sourceType) continue;
      if (!result.videoFile && source.sourceValue.trim() != result.cameraIndex.toString()) continue;
      if (!_isCurrentClientSource(source)) continue;
      if (!beforeKeys.contains(source.sourceKey)) {
        created = source;
        break;
      }
      created ??= source;
    }
    if (created != null && result.displayName.trim().isNotEmpty) {
      final updated = await eventApiService.updateSourceDisplayName(
        sourceKey: created.sourceKey,
        displayName: result.displayName.trim(),
      );
      if (updated != null) {
        setState(() => registeredSourcesByKey = {...registeredSourcesByKey, updated.sourceKey: updated});
      }
    }
    if (created != null && !result.startImmediately) {
      await _stopRegisteredSource(created);
    }
  }

  Future<void> _startAllSources() async {
    final sources = registeredSourcesByKey.values.toList(growable: false);
    for (final source in sources) {
      await _startRegisteredSource(source);
    }
  }

  Future<void> _stopAllSources() async {
    final sources = registeredSourcesByKey.values.toList(growable: false);
    for (final source in sources) {
      await _stopRegisteredSource(source);
    }
  }

  Widget _buildClientApiControls() {
    // 원격 서버 주소 입력과 연결 상태를 보여주는 상단 제어 패널이다.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
                'Server Connection',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: serverBaseUrlTextController,
                  decoration: const InputDecoration(
                    labelText: 'Remote server URL',
                    hintText: 'http://127.0.0.1:8000',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => unawaited(_applyRemoteServerBaseUrl()),
                child: const Text('Apply Server'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: apiEventFeed,
            builder: (context, _) {
              return _buildApiStatusText();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEngineProgressPanel() {
    // TensorRT 엔진 생성 중이면 진행 상태를 상단에 표시해 사용자가 대기 중임을 알 수 있게 한다.
    return AnimatedBuilder(
      animation: EmbeddedBackendService.instance,
      builder: (context, _) {
        final backend = EmbeddedBackendService.instance;
        if (!backend.isPreparingEngine) {
          return const SizedBox.shrink();
        }
        final message = backend.engineProgressMessage.trim().isEmpty
            ? 'TensorRT engine 생성 중입니다.'
            : backend.engineProgressMessage.trim();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPanelCard(
            title: 'Engine 준비 중',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Widget _buildClientRoleBanner() {
    final runtime = clientRuntimeConfig;
    return AnimatedBuilder(
      animation: EmbeddedBackendService.instance,
      builder: (context, _) {
        final backend = EmbeddedBackendService.instance;
        final engineValue = backend.isStarting
            ? 'Starting'
            : backend.isRunning
            ? 'Running'
            : 'Stopped';
        final engineColor = backend.isStarting
            ? Colors.orangeAccent
            : backend.isRunning
            ? Colors.green
            : Colors.redAccent;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF131d2a),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2F6E47)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.memory_outlined, color: Color(0xFF8EE6A2)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Client Analysis Mode',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This app owns local video sources, weights, and TensorRT engines. It runs analysis on this machine and sends detections, events, and clips to the server.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildRuntimeChip(
                          label: 'Remote Server',
                          value:
                              runtime?.remoteServerBaseUrl ??
                              'Loading from client runtime...',
                        ),
                        _buildRuntimeChip(
                          label: 'Embedded Engine',
                          value: engineValue,
                          accentColor: engineColor,
                        ),
                        _buildRuntimeChip(
                          label: 'Device',
                          value: runtime?.analysisDevice ?? 'Unknown',
                        ),
                        _buildRuntimeChip(
                          label: 'Weights',
                          value: runtime == null
                              ? 'Checking...'
                              : runtime.modelExists
                              ? 'Ready'
                              : 'Missing',
                          accentColor: runtime == null
                              ? Colors.blueGrey
                              : runtime.modelExists
                              ? Colors.green
                              : Colors.redAccent,
                        ),
                        _buildRuntimeChip(
                          label: 'TensorRT Engine',
                          value: runtime == null
                              ? 'Checking...'
                              : runtime.engineExists
                              ? 'Ready'
                              : 'Not built',
                          accentColor: runtime == null
                              ? Colors.blueGrey
                              : runtime.engineExists
                              ? Colors.green
                              : Colors.orangeAccent,
                        ),
                      ],
                    ),
                    if (backend.lastErrorMessage.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        backend.lastErrorMessage,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFF9D9D),
                        ),
                      ),
                      if (backend.logFilePath.trim().isNotEmpty)
                        Text(
                          'Log: ${backend.logFilePath}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white54),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRuntimeChip({
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

  // ignore: unused_element
  Widget _buildSourceSidebar() {
    final slots = [..._sourceSlots];
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

  Widget _buildVideoGridPanel() {
    if (_sourceSlots.isEmpty) {
      return Container(
        decoration: BoxDecoration(color: PortfolioColors.panelAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: PortfolioColors.border)),
        child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off_outlined, size: 62, color: PortfolioColors.textMuted),
          SizedBox(height: 12),
          Text('등록된 카메라가 없습니다.'),
          SizedBox(height: 4),
          Text('카메라 추가 버튼으로 USB Camera 또는 테스트 영상을 추가하세요.', style: TextStyle(color: PortfolioColors.textMuted, fontSize: 12)),
        ])),
      );
    }
    final columns = _sourceSlots.length <= 1 ? 1 : _sourceSlots.length <= 4 ? 2 : 3;
    return GridView.builder(
      padding: EdgeInsets.zero,
      itemCount: _sourceSlots.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 16 / 10),
      itemBuilder: (context, index) {
        final slot = _sourceSlots[index];
        return Container(
          decoration: BoxDecoration(color: PortfolioColors.panelAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: slot.slotId == _activeSlotId ? PortfolioColors.accent : PortfolioColors.border)),
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(slot.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _colorForSlotStatus(slot).withValues(alpha: .12), borderRadius: BorderRadius.circular(10), border: Border.all(color: _colorForSlotStatus(slot))), child: Text(_describeSlotStatus(slot), style: TextStyle(fontSize: 10, color: _colorForSlotStatus(slot)))),
              IconButton(iconSize: 18, tooltip: '설정/삭제', onPressed: () => unawaited(_handleSlotDeleteAction(slot)), icon: const Icon(Icons.settings_outlined)),
            ]),
            Expanded(child: _buildVideoTile(slot)),
          ]),
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
          title: '',
          badgeText: '',
          badgeColor: _colorForSlotStatus(slot),
          isSelected: isSelected,
          onTap: () => unawaited(_setActiveSlot(slot.slotId)),
          overlayItems: const [],
          overlayDetections: const [],
          overlaySourceWidth: _getOverlaySourceWidthForSlot(slot),
          overlaySourceHeight: _getOverlaySourceHeightForSlot(slot),
          overlayStatusText: _buildStartupProgressText(slot),
          previewImageUrl: _buildPreviewImageUrlForSlot(slot),
          dangerZoneRoi: null,
          enableDangerZoneEditing: false,
          onDangerZoneChanged: null,
        );
      },
    );
  }


  String _buildStartupProgressText(_SourcePanelSlot slot) {
    final backend = EmbeddedBackendService.instance;
    if (backend.isPreparingEngine) {
      return backend.engineProgressMessage.trim().isEmpty
          ? 'TensorRT engine을 준비하는 중입니다.'
          : backend.engineProgressMessage.trim();
    }
    if (backend.isStarting && !backend.isRunning) {
      return '내장 분석 백엔드를 시작하고 health 응답을 기다리는 중입니다.';
    }
    if (_isEnsuringCameraSource) {
      return '0번 카메라 소스를 서버에 등록하고 분석 시작을 요청하는 중입니다.';
    }
    final sourceKey = slot.sourceKey.trim();
    final status = sourceStatusesByKey[sourceKey];
    if (status == null) {
      return '카메라 소스 상태를 동기화하는 중입니다.';
    }
    if (status.errorMessage.trim().isNotEmpty) {
      return '';
    }
    final state = status.state.trim().toLowerCase();
    if (state == 'starting' || state == 'registered') {
      return '카메라 입력과 분석 런타임을 준비하는 중입니다.';
    }
    if (state == 'model_loading' || state == 'loading') {
      return '객체탐지 모델을 로딩하는 중입니다.';
    }
    if (!status.isRunning && !slot.controller.hasVideo) {
      return '로컬 프리뷰 스트림을 연결하는 중입니다.';
    }
    return '';
  }

  // ignore: unused_element
  Widget _buildInspectorPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSelectedSourceSummaryPanel(),
        const SizedBox(height: 12),
        SizedBox(
          height: 420,
          child: AnimatedBuilder(
            animation: apiEventFeed,
            builder: (context, _) {
              return EventLogBox(
                eventFeed: apiEventFeed,
                baseUrl: remoteEventApiService.baseUrl,
                onTapItem: _onTapEventItem,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildApiDetailPanel(),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildSelectedSourceSummaryPanel() {
    final source = _activeSourceItem;
    final status = source == null
        ? null
        : sourceStatusesByKey[source.sourceKey];
    final replayController = _activeSlot?.controller ?? videoController;
    return _buildPanelCard(
      title: '선택된 소스',
      child: source == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('소스를 선택하면 상태, 진행도, 이벤트를 여기에서 확인할 수 있습니다.'),
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
                  source.sourceSlug,
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
                  'engine inference 평균',
                  _buildAverageDetectionTimeText(source, status),
                ),
                _buildDetailLine('sourceKey', source.sourceKey),
                if (replayController.isReplayMode) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => unawaited(replayController.closeReplay()),
                    child: const Text('클립 닫기'),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_openRegisteredSource(source)),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('패널 열기'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_startRegisteredSource(source)),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('분석 시작'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_stopRegisteredSource(source)),
                      icon: const Icon(Icons.stop),
                      label: const Text('분석 중지'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_restartRegisteredSource(source)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('분석 재시작'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _activeSlot == null
                          ? null
                          : () => unawaited(
                              _confirmCloseSourcePanel(_activeSlot!),
                            ),
                      icon: const Icon(Icons.close),
                      label: const Text('화면/분석 제거'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _isViewerReadOnly
                          ? null
                          : () => unawaited(
                              _confirmDeleteRegisteredSource(source),
                            ),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('소스 삭제'),
                    ),
                  ],
                ),
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
          const SizedBox(height: 8),
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
                    label: Text('${slot.label} · ${_describeSlotStatus(slot)}'),
                    onSelected: (_) => unawaited(_setActiveSlot(slot.slotId)),
                    onDeleted: () => _confirmCloseSourcePanel(slot),
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
            '현재 클라이언트에 등록된 소스의 상태, 진행도, 패널 열기, 삭제를 여기에서 관리합니다.',
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
                      source.sourceSlug,
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
                      'engine inference 평균: ${_buildAverageDetectionTimeText(source, sourceStatusesByKey[source.sourceKey])}',
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
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(_startRegisteredSource(source)),
                          child: const Text('분석 시작'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(_stopRegisteredSource(source)),
                          child: const Text('분석 중지'),
                        ),
                        OutlinedButton(
                          onPressed: () =>
                              unawaited(_restartRegisteredSource(source)),
                          child: const Text('분석 재시작'),
                        ),
                        OutlinedButton(
                          onPressed: _isViewerReadOnly
                              ? null
                              : () => unawaited(
                                  _confirmDeleteRegisteredSource(source),
                                ),
                          child: const Text('소스 삭제'),
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
  Widget _buildApiStatusText() {
    String text = '3초마다 자동 새로고침되며 "API 새로고침"으로 수동 갱신도 가능합니다.';

    if (apiEventController.isLoading) {
      text = 'API 이벤트 불러오는 중...';
    } else if ((apiEventController.errorMessage ?? '').isNotEmpty) {
      text = apiEventController.errorMessage!;
    } else if (apiEventController.lastUpdatedAt != null) {
      final updatedAt = apiEventController.lastUpdatedAt!;
      final timestamp =
          '${updatedAt.year.toString().padLeft(4, '0')}-'
          '${updatedAt.month.toString().padLeft(2, '0')}-'
          '${updatedAt.day.toString().padLeft(2, '0')} '
          '${updatedAt.hour.toString().padLeft(2, '0')}:'
          '${updatedAt.minute.toString().padLeft(2, '0')}:'
          '${updatedAt.second.toString().padLeft(2, '0')}';
      text = '마지막 갱신: $timestamp';
    }

    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Colors.black54),
    );
  }

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
          Text('API 이벤트 상세', style: Theme.of(context).textTheme.titleMedium),
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
          FilledButton(
            onPressed: () => _openApiDetailClip(item),
            child: const Text('클립 재생'),
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
    final runtimeStatus = sourceStatusesByKey[slot.sourceKey.trim()];
    if (slot.controller.errorText.trim().isNotEmpty) {
      return '영상 재생 오류: ${slot.controller.errorText.trim()}';
    }
    if (runtimeStatus == null) {
      return '분석 준비 중입니다.';
    }
    if (runtimeStatus.errorMessage.trim().isNotEmpty) {
      return runtimeStatus.errorMessage.trim();
    }
    if (!frameDetectionBySourceKey.containsKey(slot.sourceKey.trim())) {
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

  // ignore: unused_element
  Future<void> _pickVideoFile() async {
    if (_isViewerReadOnly) {
      _showInfoSnack(
        'Viewer is read-only. Register local sources from the client app.',
      );
      return;
    }
    try {
      const group = XTypeGroup(
        label: 'video',
        extensions: ['mp4', 'mov', 'avi', 'mkv'],
      );

      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) {
        return;
      }

      final existingSlot = _findSourceSlot(
        sourceType: 'video',
        sourceValue: file.path,
      );
      if (existingSlot != null) {
        if (existingSlot.controller.isReplayMode &&
            existingSlot.controller.canReturnFromReplay) {
          await existingSlot.controller.returnToLive();
        }
        await _setActiveSlot(existingSlot.slotId);
        await _syncFrameRateFromStatus(
          sourceType: existingSlot.sourceType,
          sourceValue: existingSlot.sourceValue,
          controller: existingSlot.controller,
        );
        if (mounted) {
          _showInfoSnack('이미 등록된 영상 소스로 전환했습니다.');
        }
        return;
      }

      final registeredSource = await _registerSourceOnServer(
        sourceType: 'video',
        sourceValue: file.path,
        resetExisting: true,
      );
      if (registeredSource == null) {
        return;
      }

      final openPath = _resolveRegisteredSourceOpenPath(registeredSource);
      final slot = await _addOrActivateSourceSlot(
        sourceType: registeredSource.sourceType,
        sourceValue: registeredSource.sourceValue,
        openPath: openPath,
        sourceKey: registeredSource.sourceKey,
        originalSourceType: registeredSource.originalSourceType,
        originalSourceValue: file.path,
      );
      await _syncFrameRateFromStatus(
        sourceType: registeredSource.sourceType,
        sourceValue: registeredSource.sourceValue,
        controller: slot.controller,
      );
      if (slot.controller.errorText.trim().isNotEmpty && mounted) {
        _showInfoSnack(slot.controller.errorText.trim());
      }
      unawaited(_refreshApiEventsIfNeeded());
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        apiDetailErrorMessage = '영상 추가 중 오류가 발생했습니다: $error';
        selectedApiEventDetail = null;
      });
      _showInfoSnack('영상 추가 중 오류가 발생했습니다.');
    }
  }

  // ignore: unused_element
  Future<void> _openStream() async {
    if (_isViewerReadOnly) {
      _showInfoSnack(
        'Viewer is read-only. Register local sources from the client app.',
      );
      return;
    }
    final streamUrl = streamTextController.text.trim();
    if (streamUrl.isEmpty) {
      if (mounted) {
        _showInfoSnack('RTSP/HTTP 스트림 주소를 입력해 주세요.');
      }
      return;
    }
    final streamUri = Uri.tryParse(streamUrl);
    final streamScheme = streamUri?.scheme.toLowerCase() ?? '';
    if (streamUri == null ||
        !streamUri.hasScheme ||
        !{'rtsp', 'http', 'https'}.contains(streamScheme)) {
      if (mounted) {
        _showInfoSnack('스트림 주소는 rtsp://, http://, https:// 형식이어야 합니다.');
      }
      return;
    }

    final existingSlot = _findSourceSlot(
      sourceType: 'stream',
      sourceValue: streamUrl,
    );
    if (existingSlot != null) {
      if (existingSlot.controller.isReplayMode &&
          existingSlot.controller.canReturnFromReplay) {
        await existingSlot.controller.returnToLive();
      }
      await _setActiveSlot(existingSlot.slotId);
      await _syncFrameRateFromStatus(
        sourceType: existingSlot.sourceType,
        sourceValue: existingSlot.sourceValue,
        controller: existingSlot.controller,
      );
      if (mounted) {
        _showInfoSnack('이미 등록된 스트림 소스로 전환했습니다.');
      }
      return;
    }

    final registeredSource = await _registerSourceOnServer(
      sourceType: 'stream',
      sourceValue: streamUrl,
      resetExisting: true,
    );
    if (registeredSource == null) {
      return;
    }
    final slot = await _addOrActivateSourceSlot(
      sourceType: registeredSource.sourceType,
      sourceValue: registeredSource.sourceValue,
      openPath: registeredSource.sourceValue,
      nextSourceType: registeredSource.sourceType,
      sourceKey: registeredSource.sourceKey,
      originalSourceType: registeredSource.originalSourceType,
      originalSourceValue: registeredSource.originalSourceValue,
    );
    await _syncFrameRateFromStatus(
      sourceType: registeredSource.sourceType,
      sourceValue: registeredSource.sourceValue,
      controller: slot.controller,
    );
    unawaited(_refreshApiEventsIfNeeded());
  }

  // ignore: unused_element
  Future<void> _openCamera({int cameraIndex = 0, bool silent = false}) async {
    if (_isViewerReadOnly) {
      if (!silent) {
        _showInfoSnack(
          'Viewer is read-only. Register local sources from the client app.',
        );
      }
      return;
    }
    cameraTextController.text = cameraIndex.toString();

    final existingSlot = _findSourceSlot(
      sourceType: 'camera',
      sourceValue: cameraIndex.toString(),
    );
    if (existingSlot != null) {
      await _setActiveSlot(existingSlot.slotId);
      await _syncFrameRateFromStatus(
        sourceType: existingSlot.sourceType,
        sourceValue: existingSlot.sourceValue,
        controller: existingSlot.controller,
      );
      final source = registeredSourcesByKey[existingSlot.sourceKey.trim()];
      if (source != null) {
        await _ensureRegisteredSourceRunning(source);
      }
      return;
    }

    final registeredSource = await _registerSourceOnServer(
      sourceType: 'camera',
      sourceValue: cameraIndex.toString(),
      resetExisting: true,
    );
    if (registeredSource == null) {
      return;
    }

    await _addOrActivateSourceSlot(
      sourceType: registeredSource.sourceType,
      sourceValue: registeredSource.sourceValue,
      openPath: '',
      nextSourceType: registeredSource.sourceType,
      sourceKey: registeredSource.sourceKey,
      originalSourceType: registeredSource.originalSourceType,
      originalSourceValue: registeredSource.originalSourceValue,
    );
    await _refreshSourceStatuses();
    unawaited(_refreshApiEventsIfNeeded());
  }

  // ignore: unused_element
  List<EventLogItem> _getOverlayItemsForSlot(_SourcePanelSlot slot) {
    if (slot.sourceKey.trim().isEmpty) {
      return const [];
    }

    return apiEventController.getLogItemsForTimeForSource(
      slot.controller.currentOverlaySeconds,
      sourceKey: slot.sourceKey,
    );
  }

  FrameDetectionSnapshot? _getOverlaySnapshotForSlot(_SourcePanelSlot slot) {
    return frameDetectionBySourceKey[slot.sourceKey.trim()];
  }

  // ignore: unused_element
  List<VideoOverlayDetection> _getOverlayDetectionsForSlot(
    _SourcePanelSlot slot,
  ) {
    final snapshot = _getOverlaySnapshotForSlot(slot);
    if (snapshot == null) {
      return const [];
    }

    final detections = <VideoOverlayDetection>[];
    final seenKeys = <String>{};
    for (final detection in snapshot.detections) {
      final box = detection['box'];
      if (box is! Map) {
        continue;
      }

      final x1 = _toDoubleValue(box['x1']);
      final y1 = _toDoubleValue(box['y1']);
      final x2 = _toDoubleValue(box['x2']);
      final y2 = _toDoubleValue(box['y2']);
      if (x1 == null || y1 == null || x2 == null || y2 == null) {
        continue;
      }

      final key =
          '${snapshot.frameId}:${detection['track_id']}:${detection['name']}:$x1:$y1:$x2:$y2';
      if (!seenKeys.add(key)) {
        continue;
      }

      detections.add(
        VideoOverlayDetection(
          key: key,
          label: _buildFrameDetectionLabel(detection),
          color: _colorForDetectionName(detection['name']?.toString() ?? ''),
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
        ),
      );
    }

    return detections;
  }

  double _getOverlaySourceWidthForSlot(_SourcePanelSlot slot) {
    final snapshot = _getOverlaySnapshotForSlot(slot);
    if (snapshot != null && snapshot.frameWidth > 0) {
      return snapshot.frameWidth.toDouble();
    }
    return slot.controller.videoWidth.toDouble();
  }

  String _buildPreviewImageUrlForSlot(_SourcePanelSlot slot) {
    final sourceKey = slot.sourceKey.trim();
    if (sourceKey.isNotEmpty) {
      return eventApiService.buildSourceStreamUrl(sourceKey);
    }
    final source = registeredSourcesByKey[sourceKey];
    final previewUrl = source?.previewUrl.trim() ?? '';
    final statusCacheBust =
        lastFrameDetectionStatusUpdatedAtBySourceKey[sourceKey] ??
        sourceStatusesByKey[sourceKey]?.updatedAt ??
        '';
    final cacheBust = '${previewRefreshCacheBust}_$statusCacheBust';
    if (previewUrl.isNotEmpty) {
      return previewUrl.startsWith('http')
          ? previewUrl
          : '${eventApiService.baseUrl}$previewUrl${previewUrl.contains('?') ? '&' : '?'}t=$cacheBust';
    }
    return eventApiService.buildSourcePreviewUrl(
      sourceKey,
      cacheBust: cacheBust,
    );
  }

  double _getOverlaySourceHeightForSlot(_SourcePanelSlot slot) {
    final snapshot = _getOverlaySnapshotForSlot(slot);
    if (snapshot != null && snapshot.frameHeight > 0) {
      return snapshot.frameHeight.toDouble();
    }
    return slot.controller.videoHeight.toDouble();
  }

  String _effectiveOverlaySourceKey() {
    if (videoController.isReplayMode &&
        videoController.replaySourceKey.isNotEmpty) {
      return videoController.replaySourceKey;
    }
    return selectedSourceKey;
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

    final targetSeconds = _resolveEventStartSeconds(sourceItem);
    if (targetSeconds < 0) {
      return;
    }

    final targetController = resolvedTargetSlot.controller;
    if (targetController.isReplayMode && targetController.canReturnFromReplay) {
      await targetController.returnToLive();
    }

    if (targetController.sourceType == 'stream') {
      await _refreshFrameDetectionsForSource(sourceItem.sourceKey);
      return;
    }

    final targetMs = (targetSeconds * 1000).round();
    final ratio = targetController.totalDuration.inMilliseconds <= 0
        ? 0.0
        : targetMs / targetController.totalDuration.inMilliseconds;
    await targetController.moveToRatio(ratio);
    await _refreshFrameDetectionsForSource(sourceItem.sourceKey);
  }

  // ignore: unused_element
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

  Future<void> _refreshClientRuntimeConfig() async {
    final runtime = await eventApiService.fetchClientRuntimeConfig();
    final savedRemoteServerUrl = await _readSavedRemoteServerBaseUrl();
    var nextRemoteServerUrl = runtime?.remoteServerBaseUrl.trim() ?? '';
    if (savedRemoteServerUrl.isNotEmpty &&
        savedRemoteServerUrl != nextRemoteServerUrl) {
      nextRemoteServerUrl = savedRemoteServerUrl;
      unawaited(
        eventApiService.updateRemoteServerBaseUrl(savedRemoteServerUrl),
      );
    }
    if (nextRemoteServerUrl.isNotEmpty) {
      remoteEventApiService.updateBaseUrl(nextRemoteServerUrl);
    }
    if (!mounted) {
      clientRuntimeConfig = runtime;
      return;
    }
    setState(() {
      clientRuntimeConfig = runtime;
      if (nextRemoteServerUrl.isNotEmpty &&
          serverBaseUrlTextController.text.trim() != nextRemoteServerUrl) {
        serverBaseUrlTextController.text = nextRemoteServerUrl;
      }
    });
  }

  Future<void> _applyRemoteServerBaseUrl() async {
    final nextBaseUrl = serverBaseUrlTextController.text.trim();
    if (nextBaseUrl.isEmpty) {
      if (mounted) {
        _showInfoSnack('서버 주소를 입력해 주세요.');
      }
      return;
    }
    final serverUri = Uri.tryParse(nextBaseUrl);
    final serverScheme = serverUri?.scheme.toLowerCase() ?? '';
    if (serverUri == null ||
        !serverUri.hasScheme ||
        !{'http', 'https'}.contains(serverScheme) ||
        (serverUri.host.trim().isEmpty)) {
      if (mounted) {
        _showInfoSnack('서버 주소는 http:// 또는 https:// 형식이어야 합니다.');
      }
      return;
    }
    final updated = await eventApiService.updateRemoteServerBaseUrl(
      nextBaseUrl,
    );
    if (!updated) {
      if (mounted) {
        _showInfoSnack('Failed to update the remote server address.');
      }
      return;
    }
    await _refreshClientRuntimeConfig();
    final appliedRemoteUrl =
        clientRuntimeConfig?.remoteServerBaseUrl.trim().isNotEmpty == true
        ? clientRuntimeConfig!.remoteServerBaseUrl
        : nextBaseUrl;
    remoteEventApiService.updateBaseUrl(appliedRemoteUrl);
    await apiEventController.checkHealth();
    await _refreshRegisteredSources();
    await _refreshSourceStatuses();
    await _ensureSingleCameraSource(force: true, silent: true);
    await _refreshApiEventsIfNeeded();
    if (mounted) {
      final healthText = apiEventController.serverHealth == null
          ? ' 원격 서버 health 확인은 실패했습니다.'
          : '';
      _showInfoSnack(
        'Remote server updated to ${remoteEventApiService.baseUrl}.$healthText',
      );
    }
  }

  Future<SourceItem?> _registerSourceOnServer({
    required String sourceType,
    required String sourceValue,
    bool resetExisting = true,
  }) async {
    if (_isViewerReadOnly) {
      _showInfoSnack('Viewer does not register sources. Use the client app.');
      return null;
    }
    final registeredSource = sourceType.trim() == 'video'
        ? await eventApiService.uploadVideoSource(
            filePath: sourceValue,
            clientId: clientId,
            resetExisting: resetExisting,
            startImmediately: true,
          )
        : await eventApiService.registerSource(
            sourceType: sourceType,
            sourceValue: sourceValue,
            clientId: clientId,
            resetExisting: resetExisting,
            startImmediately: true,
          );
    if (registeredSource == null && mounted) {
      setState(() {
        apiDetailErrorMessage = sourceType.trim() == 'video'
            ? '서버에 영상 파일을 업로드하지 못했습니다.'
            : '서버에 소스를 등록하지 못했습니다.';
        selectedApiEventDetail = null;
      });
      return null;
    }

    if (mounted) {
      setState(() {
        apiDetailErrorMessage = null;
        selectedApiEventDetail = null;
      });
    }
    unawaited(_refreshRegisteredSources());
    unawaited(_refreshSourceStatuses());
    return registeredSource;
  }

  Future<void> _startRegisteredSource(SourceItem source) async {
    final ok = await eventApiService.startSource(source.sourceKey);
    if (!ok) {
      if (mounted) {
        _showInfoSnack('분석 시작 요청에 실패했습니다.');
      }
      return;
    }
    await _refreshRegisteredSources();
    await _refreshSourceStatuses();
    unawaited(_refreshApiEventsIfNeeded());
    if (mounted) {
      _showInfoSnack('"${source.sourceSlug}" 분석 시작을 요청했습니다.');
    }
  }

  Future<void> _stopRegisteredSource(SourceItem source) async {
    final ok = await eventApiService.stopSource(source.sourceKey);
    if (!ok) {
      if (mounted) {
        _showInfoSnack('분석 중지 요청에 실패했습니다.');
      }
      return;
    }
    await _refreshRegisteredSources();
    await _refreshSourceStatuses();
    unawaited(_refreshApiEventsIfNeeded());
    if (mounted) {
      _showInfoSnack('"${source.sourceSlug}" 분석 중지를 요청했습니다.');
    }
  }

  Future<void> _restartRegisteredSource(SourceItem source) async {
    final ok = await eventApiService.restartSource(source.sourceKey);
    if (!ok) {
      if (mounted) {
        _showInfoSnack('분석 재시작 요청에 실패했습니다.');
      }
      return;
    }
    await _refreshRegisteredSources();
    await _refreshSourceStatuses();
    unawaited(_refreshApiEventsIfNeeded());
    if (mounted) {
      _showInfoSnack('"${source.sourceSlug}" 분석 재시작을 요청했습니다.');
    }
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
      unawaited(_refreshSourceStatuses());
      unawaited(_refreshRegisteredSources());
      unawaited(_syncActiveSlotFrameRateIfNeeded());
    });
  }

  void _startCameraAutoEnsure() {
    cameraEnsureTimer?.cancel();
    cameraEnsureTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_ensureSingleCameraSource(force: true, silent: true));
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
    final isLiveLikeSource =
        slot.sourceType == 'camera' ||
        (slot.controller.isStreamMode && !slot.controller.isReplayMode);
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
      return '${remoteEventApiService.baseUrl}$trimmed';
    }
    return '${remoteEventApiService.baseUrl}/$trimmed';
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

  Future<void> _removeLocalSlotBySourceKey(String sourceKey) async {
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
    });
    apiEventFeed.setSourceKeyFilter(nextSourceKey);
    await _syncSlotAudioFocus();
    apiEventFeed.clearSelection();
    unawaited(_refreshApiEventsIfNeeded());
    unawaited(_syncActiveSlotFrameRateIfNeeded());
    unawaited(_refreshFrameDetectionsIfNeeded());
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
      if (!_isCurrentClientStatus(entry)) {
        continue;
      }
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

  Future<void> _refreshRegisteredSources() async {
    final items = await eventApiService.fetchSources();
    if (!mounted) {
      return;
    }

    final nextMap = <String, SourceItem>{};
    for (final item in items) {
      if (!_isPolicyCameraSource(item.sourceType, item.sourceValue)) {
        continue;
      }
      if (!_isCurrentClientSource(item)) {
        continue;
      }
      final sourceKey = item.sourceKey.trim();
      if (sourceKey.isEmpty) {
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

    if (removedSlotLabels.isNotEmpty) {
      apiEventFeed.clearSelection();
      if (_sourceSlots.isNotEmpty) {
        await _syncActiveSlotFrameRateIfNeeded();
      }
      unawaited(_refreshApiEventsIfNeeded());
      unawaited(_refreshFrameDetectionsIfNeeded());
    }
  }

  Future<void> _restoreRegisteredSourceSlots(List<SourceItem> sources) async {
    final previousActiveSlotId = _activeSlotId;
    for (final source in sources) {
      if (!_isPolicyCameraSource(source.sourceType, source.sourceValue)) {
        continue;
      }
      final existingSlot = _findSourceSlotByKey(source.sourceKey);
      if (existingSlot != null) {
        continue;
      }

      final openPath = _resolveRegisteredSourceOpenPath(source);
      final isCameraSource = source.sourceType.trim().toLowerCase() == 'camera';
      if (openPath.isEmpty && !isCameraSource) {
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
      await _syncSlotAudioFocus();
      unawaited(_refreshFrameDetectionsIfNeeded());
      return;
    }

    if (_activeSlotId.isEmpty && _sourceSlots.isNotEmpty) {
      setState(() {
        _activeSlotId = _sourceSlots.first.slotId;
      });
      await _syncSlotAudioFocus();
      unawaited(_refreshFrameDetectionsIfNeeded());
    }
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

  // ignore: unused_element
  String _buildSourceHint() {
    if (selectedSourceKey.isEmpty) {
      return '비디오, 스트림, 카메라를 등록하면 여기서 각 소스의 오버레이와 이벤트를 바로 확인할 수 있습니다.';
    }

    return '현재 선택한 로컬 소스의 영상, 객체 박스, 이벤트, 클립 재생 상태를 확인하는 화면입니다.';
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
      return '이 소스 분석 준비 중입니다. Python worker가 서버에 상태를 보내면 박스가 갱신됩니다.';
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
      return '현재 재생 시점은 아직 Python 분석이 끝나지 않았습니다.';
    }

    if (snapshot.detections.isEmpty) {
      return '현재 시점에는 탐지된 객체가 없습니다.';
    }

    return '';
  }

  // ignore: unused_element
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

  _SourcePanelSlot? _findSourceSlot({
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
      preserveReturnContext: false,
    );
  }

  Future<void> _confirmCloseSourcePanel(_SourcePanelSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('패널 닫기'),
          content: Text(
            '"${slot.label}" 패널만 닫습니다.\n'
            '등록된 소스와 분석은 계속 유지되며, 나중에 다시 열 수 있습니다.\n'
            '계속할까요?',
          ),
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
      _showInfoSnack('"${slot.label}" 패널만 닫았습니다. 분석은 계속 유지됩니다.');
    }
  }

  Future<void> confirmRemoveSourceSlot(_SourcePanelSlot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('패널 닫기'),
          content: Text('"${slot.label}" 소스 화면을 닫고 분석도 중단합니다. 계속할까요?'),
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
      _showInfoSnack('"${slot.label}" 소스 분석을 중단하고 화면에서 제거했습니다.');
    }
  }

  Future<void> _handleSlotDeleteAction(_SourcePanelSlot slot) async {
    final registeredSource = registeredSourcesByKey[slot.sourceKey.trim()];
    if (registeredSource != null) {
      await _confirmDeleteRegisteredSource(registeredSource);
      return;
    }
    await _confirmCloseSourcePanel(slot);
  }

  Future<void> _confirmDeleteRegisteredSource(SourceItem source) async {
    if (_isViewerReadOnly) {
      _showInfoSnack(
        'Viewer is read-only. Remove sources from the client app.',
      );
      return;
    }
    final runtimeStatus = sourceStatusesByKey[source.sourceKey];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('소스 삭제'),
          content: Text(
            '"${source.sourceSlug}"\n'
            'type: ${source.sourceType}\n'
            'state: ${runtimeStatus?.state ?? 'unknown'}\n\n'
            '이 소스와 관련된 서버 이벤트 로그, 프레임 탐지 데이터, 클립 파일, 업로드 원본 영상을 함께 삭제합니다. 계속할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('소스 삭제'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final ok = await eventApiService.deleteSource(
      source.sourceKey,
      clearData: true,
    );
    if (!ok) {
      if (mounted) {
        _showInfoSnack('소스 삭제에 실패했습니다.');
      }
      return;
    }

    await _removeLocalSlotBySourceKey(source.sourceKey);
    await _refreshRegisteredSources();
    await _refreshSourceStatuses();
    unawaited(_refreshApiEventsIfNeeded());
    unawaited(_refreshFrameDetectionsIfNeeded());

    if (mounted) {
      _showInfoSnack('"${source.sourceSlug}" 소스와 관련 데이터 삭제를 완료했습니다.');
    }
  }

  Future<void> _openRegisteredSource(SourceItem source) async {
    final existingSlot = _findSourceSlotByKey(source.sourceKey);
    if (existingSlot != null) {
      await _setActiveSlot(existingSlot.slotId);
      return;
    }

    final openPath = _resolveRegisteredSourceOpenPath(source);
    final isCameraSource = source.sourceType.trim().toLowerCase() == 'camera';
    if (openPath.isEmpty && !isCameraSource) {
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
    if (sourceType == 'camera') {
      return '';
    }
    if (sourceType == 'stream') {
      final original = source.originalSourceValue.trim();
      if (original.isNotEmpty) {
        return original;
      }
      return source.sourceValue.trim();
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

  bool _isPolicyCameraSource(String sourceType, String sourceValue) {
    final type = sourceType.trim().toLowerCase();
    return const {'camera', 'video', 'stream'}.contains(type);
  }

  String _buildAverageDetectionTimeText(
    SourceItem? source,
    SourceRuntimeStatus? status,
  ) {
    final averageMs = status?.avgObjectDetectionMs ?? 0.0;
    if (averageMs <= 0) {
      return '-';
    }
    final suffix = source?.sourceType.trim().toLowerCase() == 'video'
        ? ' (첫 50회 제외)'
        : '';
    return '${averageMs.toStringAsFixed(1)} ms/frame$suffix';
  }

  String _describeSlotStatus(_SourcePanelSlot slot) {
    final sourceKey = slot.sourceKey.trim();
    if (slot.controller.errorText.trim().isNotEmpty) {
      return '오류';
    }
    final runtimeStatus = sourceStatusesByKey[sourceKey];
    if (runtimeStatus == null) {
      return '준비중';
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
      default:
        return Colors.grey;
    }
  }

  void _showInfoSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // ignore: unused_element
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
    // 앱 시작 시 클라이언트 식별자, 서버 주소, 런타임 설정, 이벤트/소스 상태를 순서대로 준비한다.
    clientId = await _resolveClientIdentity();
    await _loadSavedRemoteServerBaseUrl();
    await EmbeddedBackendService.instance.ensureStarted();
    unawaited(_connectRealtimeUpdates());
    await _refreshClientRuntimeConfig();
    await apiEventController.checkHealth();
    await _refreshApiEventsIfNeeded();
    await _refreshSourceStatuses();
    await _refreshRegisteredSources();
    await _ensureSingleCameraSource();
  }

  Future<String> _resolveClientIdentity() async {
    // 최초 등록 화면에서 발급받은 EDGE Client ID가 있으면 가장 우선해 사용합니다.
    final registered = ClientIdentityService.current ?? ClientIdentityService().load();
    if (registered != null && registered.clientId.trim().isNotEmpty) {
      await _saveClientIdentityConfig(
        registered.clientId.trim(),
        machineId: _buildCurrentMachineId(),
      );
      return registered.clientId.trim();
    }

    // 레거시/개발 모드에서는 현재 PC 호스트명으로 만든 식별자를 사용합니다.
    final configPath = _resolveLegacyClientSettingsFile();
    final currentMachineId = _buildCurrentMachineId();
    final generated = _buildDefaultClientId();
    try {
      if (await configPath.exists()) {
        final decoded = jsonDecode(await configPath.readAsString());
        if (decoded is Map<String, dynamic>) {
          final configured = decoded['client_id']?.toString().trim() ?? '';
          final configuredMachineId = decoded['machine_id']?.toString().trim() ?? '';
          if (configured.isNotEmpty && configuredMachineId == currentMachineId) {
            return configured;
          }
        }
      }
    } catch (_) {}

    await _saveClientIdentityConfig(generated, machineId: currentMachineId);
    return generated;
  }

  String _buildCurrentMachineId() {
    return 'host_${_buildNormalizedHostToken()}';
  }

  String _buildDefaultClientId() {
    return 'client_${_buildNormalizedHostToken()}';
  }

  String _buildNormalizedHostToken() {
    final host = Platform.localHostname.trim().toLowerCase();
    final normalizedHost = host
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalizedHost.isEmpty ? 'local' : normalizedHost;
  }

  Future<void> _saveClientIdentityConfig(
    String nextClientId, {
    required String machineId,
  }) async {
    try {
      final configPath = _resolveLegacyClientSettingsFile();
      final payload = <String, dynamic>{};
      if (await configPath.exists()) {
        final decoded = jsonDecode(await configPath.readAsString());
        if (decoded is Map<String, dynamic>) {
          payload.addAll(decoded);
        }
      }
      payload['client_id'] = nextClientId.trim();
      payload['machine_id'] = machineId.trim();
      payload['remote_server_base_url'] =
          payload['remote_server_base_url']?.toString().trim().isNotEmpty ==
              true
          ? payload['remote_server_base_url'].toString().trim()
          : serverBaseUrlTextController.text.trim();
      await configPath.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (_) {
      // client_id 저장 실패는 현재 실행을 막지 않습니다.
    }
  }

  Future<void> _ensureSingleCameraSource({
    bool force = false,
    bool silent = true,
  }) async {
    // 앱이 시작될 때 기본 카메라 소스가 하나만 등록되도록 보장한다.
    if (_isViewerReadOnly || _isEnsuringCameraSource) {
      return;
    }
    if (_didAutoRegisterCamera && !force) {
      return;
    }

    _isEnsuringCameraSource = true;
    try {
      _didAutoRegisterCamera = true;
      cameraTextController.text = '0';
      await _refreshRegisteredSources();
      await _refreshSourceStatuses();

      // 이미 현재 클라이언트 소스가 있으면 재등록하지 않고, 없으면 서버에 새로 등록한다.
      var source = _findRegisteredCameraZeroSource();
      source ??= await eventApiService.registerSource(
        sourceType: 'camera',
        sourceValue: '0',
        clientId: clientId,
        resetExisting: false,
        startImmediately: true,
      );
      if (source == null) {
        if (!silent && mounted) {
          _showInfoSnack('카메라 0 소스 등록에 실패했습니다.');
        }
        return;
      }

      await _ensureSourceSlot(
        sourceType: source.sourceType,
        sourceValue: source.sourceValue,
        openPath: '',
        sourceKey: source.sourceKey,
        originalSourceType: source.originalSourceType,
        originalSourceValue: source.originalSourceValue,
        nextSourceType: source.sourceType,
        activate: _activeSlotId.isEmpty,
      );
      await _ensureRegisteredSourceRunning(source);
      await _refreshRegisteredSources();
      await _refreshSourceStatuses();
    } finally {
      _isEnsuringCameraSource = false;
    }
  }

  SourceItem? _findRegisteredCameraZeroSource() {
    for (final source in registeredSourcesByKey.values) {
      if (source.sourceType.trim().toLowerCase() == 'camera' &&
          source.sourceValue.trim() == '0' &&
          _isCurrentClientSource(source)) {
        return source;
      }
    }
    return null;
  }

  bool _isCurrentClientSource(SourceItem source) {
    final currentClientId = clientId.trim();
    if (currentClientId.isEmpty) {
      return false;
    }
    return source.clientId.trim() == currentClientId;
  }

  bool _isCurrentClientStatus(SourceRuntimeStatus status) {
    final currentClientId = clientId.trim();
    if (currentClientId.isEmpty) {
      return false;
    }
    return status.clientId.trim() == currentClientId;
  }

  Future<void> _loadSavedRemoteServerBaseUrl() async {
    final savedRemoteServerUrl = await _readSavedRemoteServerBaseUrl();
    if (savedRemoteServerUrl.isEmpty) {
      return;
    }
    remoteEventApiService.updateBaseUrl(savedRemoteServerUrl);
    if (!mounted) {
      serverBaseUrlTextController.text = savedRemoteServerUrl;
      return;
    }
    setState(() {
      serverBaseUrlTextController.text = savedRemoteServerUrl;
    });
  }

  Future<String> _readSavedRemoteServerBaseUrl() async {
    try {
      final configPath = _resolveLegacyClientSettingsFile();
      if (!await configPath.exists()) {
        return '';
      }
      final decoded = jsonDecode(await configPath.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return '';
      }
      return decoded['remote_server_base_url']?.toString().trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _ensureRegisteredSourceRunning(SourceItem source) async {
    // 소스가 이미 시작 중이거나 재연결 중이면 다시 요청하지 않는다.
    final status = sourceStatusesByKey[source.sourceKey.trim()];
    final state = status?.state.trim().toLowerCase() ?? '';
    if (status?.isRunning == true ||
        state == 'starting' ||
        state == 'running' ||
        state == 'reconnecting') {
      return;
    }
    await eventApiService.startSource(source.sourceKey);
  }

  Future<void> _connectRealtimeUpdates() async {
    // 서버의 실시간 이벤트 채널에 연결해 소스/상태/이벤트 변경을 즉시 반영한다.
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
    // 기존 WebSocket 구독과 소켓을 안전하게 해제해 재연결 시 중복 이벤트를 막는다.
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
    // 소켓이 끊기면 연결 상태를 비활성화하고 자동 재연결을 예약한다.
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
    // 네트워크가 잠깐 끊겼을 때 재연결을 몇 초 후에 시도해 과도한 반복 연결을 방지한다.
    realtimeReconnectTimer?.cancel();
    realtimeReconnectTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_connectRealtimeUpdates());
    });
  }

  void _handleRealtimeUpdateMessage(dynamic data) {
    // 서버로부터 들어온 실시간 메시지를 파싱해 어떤 데이터가 바뀌었는지 판단한다.
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
    // 실시간 이벤트가 여러 번 들어오면 바로 갱신하지 않고, 짧은 지연 후 한 번에 처리한다.
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
          await _refreshRegisteredSources();
        }
        if (shouldRefreshStatuses) {
          await _refreshSourceStatuses();
          await _syncActiveSlotFrameRateIfNeeded();
        }
        if (shouldRefreshEvents) {
          await _refreshApiEventsIfNeeded();
        }
      },
    );
  }

  Future<void> saveServerBaseUrlConfig(String baseUrl) async {
    try {
      final configPath = _resolveLegacyClientSettingsFile();
      final payload = <String, dynamic>{};
      if (await configPath.exists()) {
        final decoded = jsonDecode(await configPath.readAsString());
        if (decoded is Map<String, dynamic>) {
          payload.addAll(decoded);
        }
      }
      payload['remote_server_base_url'] = baseUrl;
      if (clientId.trim().isNotEmpty) {
        payload['client_id'] = clientId.trim();
      }
      await configPath.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
    } catch (_) {
      // 설정 파일 저장 실패는 앱 동작을 막지 않습니다.
    }
  }

  File _resolveLegacyClientSettingsFile() {
    final roots = <Directory>{
      Directory.current.absolute,
      File(Platform.resolvedExecutable).parent.absolute,
    };
    for (final root in roots) {
      Directory? current = root;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        final backendEntry = File(
          '${current.path}${Platform.pathSeparator}embedded_backend${Platform.pathSeparator}main.py',
        );
        if (backendEntry.existsSync()) {
          return File(
            '${current.path}${Platform.pathSeparator}client_settings.json',
          );
        }
        current = current.parent.path == current.path ? null : current.parent;
      }
    }
    return File(
      '${Directory.current.path}${Platform.pathSeparator}client_settings.json',
    );
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

class _ClipTargetBinding {
  const _ClipTargetBinding({
    required this.controller,
    required this.preserveReturnContext,
  });

  final VideoPanelController controller;
  final bool preserveReturnContext;
}



