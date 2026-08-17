import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/source_item.dart';
import '../../models/source_rule_config.dart';
import '../../services/event_api_service.dart';
import '../../session/auth_session.dart';
import '../../ui/portfolio_theme.dart';
import 'page_frame.dart';

class RuleSettingsScreen extends StatefulWidget {
  const RuleSettingsScreen({super.key});
  @override
  State<RuleSettingsScreen> createState() => _RuleSettingsScreenState();
}

class _RuleSettingsScreenState extends State<RuleSettingsScreen> {
  late final EventApiService _api;
  List<SourceItem> _sources = const [];
  SourceItem? _selected;
  bool _noHelmet = true;
  bool _dangerZone = false;
  double _confidence = .60;
  double _cooldown = 10;
  RoiRect? _roi;
  Offset? _dragStart;
  Offset? _dragEnd;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _api = EventApiService(baseUrl: AuthSession.instance.serverBaseUrl);
    unawaited(_load());
  }

  @override
  void dispose() { _api.dispose(); super.dispose(); }

  Future<void> _load() async {
    final sources = await _api.fetchSources();
    if (!mounted) return;
    setState(() { _sources = sources; if (sources.isNotEmpty) _select(sources.first); });
  }

  void _select(SourceItem source) {
    _selected = source;
    _noHelmet = source.ruleConfig.useNoHelmetRule;
    _dangerZone = source.ruleConfig.useDangerZoneRule;
    _roi = source.ruleConfig.dangerZoneRoi;
    _confidence = source.ruleConfig.confidenceThreshold.clamp(.1, .95).toDouble();
    _cooldown = source.ruleConfig.eventCooldownSeconds.clamp(1, 60).toDouble();
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _saving = true);
    final updated = await _api.updateSourceRuleConfig(
      sourceKey: selected.sourceKey,
      ruleConfig: SourceRuleConfig(
        useNoHelmetRule: _noHelmet,
        useDangerZoneRule: _dangerZone,
        dangerZoneRoi: _roi,
        confidenceThreshold: _confidence,
        eventCooldownSeconds: _cooldown,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(updated == null ? '규칙 저장에 실패했습니다.' : '카메라 규칙을 서버에 저장했습니다.')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return const PortfolioPageFrame(title: '카메라 룰 설정', child: Center(child: Text('관리자만 접근할 수 있습니다.')));
    }
    return PortfolioPageFrame(
      title: '카메라 룰 설정',
      child: PortfolioPanel(
        title: '카메라 룰 설정${_selected == null ? '' : ' - ${_displayName(_selected!)}'}',
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(width: 275, child: _leftSettings()),
            const SizedBox(width: 16),
            Expanded(child: _roiEditor()),
          ]),
        ),
      ),
    );
  }

  Widget _leftSettings() => ListView(children: [
    DropdownButtonFormField<SourceItem>(
      value: _selected,
      decoration: const InputDecoration(labelText: '카메라'),
      items: _sources.map((s) => DropdownMenuItem(value: s, child: Text(_displayName(s), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (s) => setState(() { if (s != null) _select(s); }),
    ),
    const SizedBox(height: 22),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('안전모 미착용 감지'), value: _noHelmet, onChanged: (v) => setState(() => _noHelmet = v)),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('위험구역 감지'), value: _dangerZone, onChanged: (v) => setState(() => _dangerZone = v)),
    const SizedBox(height: 16),
    const Text('Confidence 임계값', style: TextStyle(color: PortfolioColors.textMuted)),
    Row(children: [Expanded(child: Slider(value: _confidence, min: .1, max: .95, divisions: 17, onChanged: (v) => setState(() => _confidence = v))), Text(_confidence.toStringAsFixed(2))]),
    const SizedBox(height: 10),
    const Text('Event Cooldown (초)', style: TextStyle(color: PortfolioColors.textMuted)),
    Row(children: [Expanded(child: Slider(value: _cooldown, min: 1, max: 60, divisions: 59, onChanged: (v) => setState(() => _cooldown = v))), Text('${_cooldown.round()}')]),
    const SizedBox(height: 24),
    FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? '저장 중...' : '저장 및 적용')),
  ]);

  Widget _roiEditor() {
    final selected = _selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('위험구역 설정 (ROI)', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('영상 위에서 드래그해 사각형 위험구역을 지정합니다. 좌표는 1920×1080 기준으로 저장됩니다.', style: TextStyle(color: PortfolioColors.textMuted, fontSize: 12)),
      const SizedBox(height: 12),
      Expanded(child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        Rect? displayRect;
        if (_dragStart != null && _dragEnd != null) {
          displayRect = Rect.fromPoints(_dragStart!, _dragEnd!);
        } else if (_roi != null) {
          displayRect = Rect.fromLTRB(
            _roi!.x1 / 1920 * size.width, _roi!.y1 / 1080 * size.height,
            _roi!.x2 / 1920 * size.width, _roi!.y2 / 1080 * size.height,
          );
        }
        final preview = selected == null ? '' : _resolvePreview(selected.previewUrl);
        return GestureDetector(
          onPanStart: (d) => setState(() { _dragStart = d.localPosition; _dragEnd = d.localPosition; }),
          onPanUpdate: (d) => setState(() => _dragEnd = Offset(d.localPosition.dx.clamp(0.0, size.width).toDouble(), d.localPosition.dy.clamp(0.0, size.height).toDouble())),
          onPanEnd: (_) {
            if (_dragStart == null || _dragEnd == null) return;
            final r = Rect.fromPoints(_dragStart!, _dragEnd!);
            if (r.width < 5 || r.height < 5) return;
            setState(() {
              _roi = RoiRect.normalized(
                x1: (r.left / size.width * 1920).round(), y1: (r.top / size.height * 1080).round(),
                x2: (r.right / size.width * 1920).round(), y2: (r.bottom / size.height * 1080).round(),
              );
              _dragStart = null; _dragEnd = null;
            });
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(fit: StackFit.expand, children: [
              Container(color: Colors.black),
              if (preview.isNotEmpty) Image.network(preview, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.videocam_off_outlined, size: 60, color: PortfolioColors.textMuted)))
              else const Center(child: Icon(Icons.videocam_outlined, size: 70, color: PortfolioColors.textMuted)),
              if (displayRect != null) Positioned.fromRect(rect: displayRect, child: Container(decoration: BoxDecoration(color: PortfolioColors.danger.withValues(alpha: .14), border: Border.all(color: PortfolioColors.danger, width: 2)))),
            ]),
          ),
        );
      })),
      const SizedBox(height: 10),
      Row(children: [
        OutlinedButton.icon(onPressed: () => setState(() { _roi = null; _dragStart = null; _dragEnd = null; }), icon: const Icon(Icons.restart_alt), label: const Text('초기화')),
        const Spacer(),
        Text(_roi == null ? 'ROI 미설정' : 'ROI ${_roi!.x1},${_roi!.y1} → ${_roi!.x2},${_roi!.y2}', style: const TextStyle(color: PortfolioColors.textMuted)),
      ]),
    ]);
  }

  String _displayName(SourceItem s) => s.displayName.trim().isEmpty ? s.sourceKey : s.displayName;
  String _resolvePreview(String raw) {
    if (raw.trim().isEmpty) return '';
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return raw;
    final base = Uri.parse(AuthSession.instance.serverBaseUrl);
    return base.replace(path: raw.startsWith('/') ? raw : '/$raw', queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()}).toString();
  }
}
