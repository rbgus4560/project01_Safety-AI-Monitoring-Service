import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/api_event_item.dart';
import '../../models/clip_window_arguments.dart';
import '../../services/event_api_service.dart';
import '../../services/portfolio_api_service.dart';
import '../../session/auth_session.dart';
import '../../ui/portfolio_theme.dart';
import '../clip_player_window.dart';
import 'page_frame.dart';

class EventHistoryScreen extends StatefulWidget {
  const EventHistoryScreen({super.key});
  @override
  State<EventHistoryScreen> createState() => _EventHistoryScreenState();
}

class _EventHistoryScreenState extends State<EventHistoryScreen> {
  late final EventApiService _eventApi;
  final _portfolioApi = PortfolioApiService();
  final _search = TextEditingController();
  List<ApiEventItem> _events = const [];
  bool _loading = true;
  String _type = '전체 이벤트';
  String _status = '전체 상태';

  @override
  void initState() {
    super.initState();
    _eventApi = EventApiService(baseUrl: AuthSession.instance.serverBaseUrl);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _eventApi.dispose();
    _portfolioApi.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final items = await _eventApi.fetchEvents(limit: 300);
    if (!mounted) return;
    setState(() { _events = items.reversed.toList(growable: false); _loading = false; });
  }

  List<ApiEventItem> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _events.where((e) {
      final typeOk = _type == '전체 이벤트' || _eventLabel(e).contains(_type.replaceAll(' ', '')) || e.eventType == _type;
      final statusOk = _status == '전체 상태' || (_status == '확인' ? e.acknowledged : !e.acknowledged);
      final searchOk = query.isEmpty || '${e.sourceKey} ${e.message} ${e.eventType}'.toLowerCase().contains(query);
      return typeOk && statusOk && searchOk;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return PortfolioPageFrame(
      title: '이벤트 기록',
      actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      child: Row(children: [
        SizedBox(width: 270, child: _buildSourceSummary()),
        const SizedBox(width: 10),
        Expanded(child: PortfolioPanel(title: '이벤트 기록', child: _buildHistory())),
      ]),
    );
  }

  Widget _buildSourceSummary() {
    final keys = <String, int>{};
    for (final e in _events) { keys[e.sourceKey] = (keys[e.sourceKey] ?? 0) + 1; }
    return PortfolioPanel(
      title: '카메라 목록',
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: keys.entries.map((entry) => ListTile(
          dense: true,
          leading: const Icon(Icons.circle, size: 10, color: PortfolioColors.success),
          title: Text(entry.key.isEmpty ? '미지정 카메라' : entry.key),
          trailing: Text('${entry.value}', style: const TextStyle(color: PortfolioColors.textMuted)),
        )).toList(),
      ),
    );
  }

  Widget _buildHistory() {
    final items = _filtered;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          SizedBox(width: 210, child: DropdownButtonFormField<String>(
            initialValue: _type,
            items: const ['전체 이벤트', '안전모 미착용', '위험구역 진입'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _type = v ?? '전체 이벤트'),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 170, child: DropdownButtonFormField<String>(
            initialValue: _status,
            items: const ['전체 상태', '미확인', '확인'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() => _status = v ?? '전체 상태'),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '카메라 / 이벤트 검색'))),
        ]),
      ),
      const Divider(height: 1),
      if (_loading) const Expanded(child: Center(child: CircularProgressIndicator()))
      else Expanded(child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final e = items[index];
          return InkWell(
            onTap: () => _showDetail(e),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(children: [
                SizedBox(width: 145, child: Text(_timeText(e.createdAt), style: const TextStyle(color: PortfolioColors.textMuted))),
                Expanded(flex: 2, child: Text(e.sourceKey.isEmpty ? '-' : e.sourceKey)),
                Expanded(flex: 2, child: Text(_eventLabel(e))),
                SizedBox(width: 95, child: _StatusBadge(acknowledged: e.acknowledged)),
                SizedBox(width: 110, height: 58, child: _thumbnail(e)),
              ]),
            ),
          );
        },
      )),
    ]);
  }

  Widget _thumbnail(ApiEventItem e) {
    final url = _resolveUrl(e.thumbnailUrl);
    if (url.isEmpty) return Container(color: PortfolioColors.panelAlt, child: const Icon(Icons.image_not_supported_outlined));
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: PortfolioColors.panelAlt, child: const Icon(Icons.broken_image_outlined))),
    );
  }

  Future<void> _showDetail(ApiEventItem e) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: PortfolioColors.panel,
        child: SizedBox(
          width: 850,
          height: 560,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Text('이벤트 상세', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
              ]),
              const Divider(),
              Expanded(child: Row(children: [
                Expanded(flex: 3, child: Container(
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(9)),
                  clipBehavior: Clip.antiAlias,
                  child: _thumbnail(e),
                )),
                const SizedBox(width: 18),
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _detail('이벤트 종류', _eventLabel(e)),
                  _detail('발생 시간', _timeText(e.createdAt)),
                  _detail('카메라', e.sourceKey),
                  _detail('상태', e.acknowledged ? '확인' : '미확인'),
                  _detail('메시지', e.message.isEmpty ? '-' : e.message),
                  const Spacer(),
                  if (e.hasClip) FilledButton.icon(
                    onPressed: () {
                      final clip = _resolveUrl(e.clipUrl.isNotEmpty ? e.clipUrl : e.clipPath);
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClipPlayerWindow(arguments: ClipWindowArguments(
                        baseUrl: AuthSession.instance.serverBaseUrl,
                        clipUrl: clip,
                        sourceKey: e.sourceKey,
                        sourceStartSeconds: 0,
                        title: '${_eventLabel(e)} · ${e.sourceKey}',
                      ))));
                    },
                    icon: const Icon(Icons.play_arrow), label: const Text('클립 재생'),
                  ),
                  const SizedBox(height: 8),
                  if (!e.acknowledged) FilledButton.tonalIcon(
                    onPressed: () async {
                      final ok = await _portfolioApi.acknowledgeEvent(e.eventKey, e.sourceKey);
                      if (ok && mounted) { Navigator.pop(dialogContext); await _reload(); }
                    },
                    icon: const Icon(Icons.check), label: const Text('확인 처리'),
                  ),
                ])),
              ])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: PortfolioColors.textMuted)),
      const SizedBox(height: 4), Text(value.isEmpty ? '-' : value),
    ]),
  );

  String _resolveUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') return '';
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return value;
    final base = Uri.parse(AuthSession.instance.serverBaseUrl);
    return base.replace(path: value.startsWith('/') ? value : '/$value', queryParameters: const {}).toString();
  }

  String _eventLabel(ApiEventItem e) {
    final raw = '${e.eventType} ${e.message}'.toLowerCase();
    if (raw.contains('no_helmet') || raw.contains('no helmet') || raw.contains('helmet')) return '안전모 미착용';
    if (raw.contains('danger')) return '위험구역 진입';
    return e.eventType.isEmpty ? '안전 이벤트' : e.eventType;
  }

  String _timeText(String raw) {
    if (raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.acknowledged});
  final bool acknowledged;
  @override
  Widget build(BuildContext context) {
    final color = acknowledged ? PortfolioColors.success : PortfolioColors.danger;
    return Align(alignment: Alignment.centerLeft, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(12), color: color.withValues(alpha: .08)),
      child: Text(acknowledged ? '확인' : '미확인', style: TextStyle(color: color, fontSize: 11)),
    ));
  }
}
