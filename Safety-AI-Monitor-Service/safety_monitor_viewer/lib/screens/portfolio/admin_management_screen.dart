import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/source_overview_item.dart';
import '../../services/event_api_service.dart';
import '../../services/portfolio_api_service.dart';
import '../../session/auth_session.dart';
import '../../ui/portfolio_theme.dart';
import 'page_frame.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});
  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _portfolio = PortfolioApiService();
  late final EventApiService _eventApi;
  List<Map<String, dynamic>> _clients = const [];
  List<Map<String, dynamic>> _users = const [];
  List<SourceOverviewItem> _sources = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _eventApi = EventApiService(baseUrl: AuthSession.instance.serverBaseUrl);
    unawaited(_reload());
  }

  @override
  void dispose() { _tabs.dispose(); _portfolio.dispose(); _eventApi.dispose(); super.dispose(); }

  Future<void> _reload() async {
    if (!AuthSession.instance.isAdmin) return;
    setState(() => _loading = true);
    final results = await Future.wait<Object>([
      _portfolio.fetchClients(), _portfolio.fetchUsers(), _eventApi.fetchSourceOverviews(),
    ]);
    if (!mounted) return;
    setState(() {
      _clients = results[0] as List<Map<String, dynamic>>;
      _users = results[1] as List<Map<String, dynamic>>;
      _sources = results[2] as List<SourceOverviewItem>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return const PortfolioPageFrame(title: '관리자 관리', child: Center(child: Text('관리자만 접근할 수 있습니다.')));
    }
    return PortfolioPageFrame(
      title: '관리자 관리',
      actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      child: PortfolioPanel(
        title: '관리',
        trailing: SizedBox(width: 330, child: TabBar(controller: _tabs, tabs: const [Tab(text: 'Client / Camera 관리'), Tab(text: '사용자 관리')])),
        child: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabs, children: [_clientTab(), _userTab()]),
      ),
    );
  }

  Widget _clientTab() {
    final grouped = <String, List<SourceOverviewItem>>{};
    for (final source in _sources) {
      final key = source.clientId.trim().isEmpty ? 'UNREGISTERED' : source.clientId;
      grouped.putIfAbsent(key, () => []).add(source);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Text('등록 Client ${_clients.length}대 · 카메라 ${_sources.length}대', style: const TextStyle(color: PortfolioColors.textMuted)),
          const Spacer(),
          FilledButton.icon(onPressed: _newRegistrationCode, icon: const Icon(Icons.add_link), label: const Text('Client 등록 코드 생성')),
        ]),
      ),
      const Divider(height: 1),
      Expanded(child: ListView(children: [
        ..._clients.map((client) {
          final id = client['client_id']?.toString() ?? '';
          final sources = grouped[id] ?? const [];
          final active = client['is_active'] == true;
          return ExpansionTile(
            leading: Icon(Icons.computer, color: active ? PortfolioColors.success : PortfolioColors.danger),
            title: Text(client['client_name']?.toString() ?? id),
            subtitle: Text('$id · ${client['last_ip'] ?? '-'} · Camera ${sources.length}', style: const TextStyle(color: PortfolioColors.textMuted)),
            trailing: Switch(value: active, onChanged: (v) async { await _portfolio.setClientActive(id, v); await _reload(); }),
            children: sources.map((s) => ListTile(
              leading: Icon(Icons.videocam, color: s.isRunning ? PortfolioColors.success : PortfolioColors.danger),
              title: Text(s.displayName.isEmpty ? s.sourceKey : s.displayName),
              subtitle: Text('${s.sourceFps.toStringAsFixed(1)} FPS · ${s.state} · ${s.errorMessage.isEmpty ? '정상' : s.errorMessage}'),
            )).toList(),
          );
        }),
        if (_clients.isEmpty && grouped.isNotEmpty)
          ...grouped.entries.map((entry) => ExpansionTile(
            title: Text('현재 연결 Client · ${entry.key}'),
            children: entry.value.map((s) => ListTile(title: Text(s.displayName.isEmpty ? s.sourceKey : s.displayName), subtitle: Text('${s.state} · ${s.sourceFps.toStringAsFixed(1)} FPS'))).toList(),
          )),
      ])),
    ]);
  }

  Widget _userTab() => Column(children: [
    Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Text('사용자 ${_users.length}명', style: const TextStyle(color: PortfolioColors.textMuted)),
        const Spacer(), FilledButton.icon(onPressed: _showCreateUser, icon: const Icon(Icons.person_add_alt_1), label: const Text('사용자 추가')),
      ]),
    ),
    const Divider(height: 1),
    Expanded(child: ListView.separated(
      itemCount: _users.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final u = _users[index];
        final active = u['is_active'] == true;
        final username = u['username']?.toString() ?? '';
        return ListTile(
          leading: const CircleAvatar(backgroundColor: PortfolioColors.panelAlt, child: Icon(Icons.person_outline)),
          title: Text(u['display_name']?.toString() ?? username),
          subtitle: Text('$username · ${u['role']}', style: const TextStyle(color: PortfolioColors.textMuted)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            _RoleBadge(role: u['role']?.toString() ?? ''),
            const SizedBox(width: 14),
            Switch(value: active, onChanged: username == AuthSession.instance.username ? null : (v) async { await _portfolio.setUserActive(username, v); await _reload(); }),
          ]),
        );
      },
    )),
  ]);

  Future<void> _newRegistrationCode() async {
    final code = await _portfolio.createRegistrationCode();
    if (!mounted) return;
    showDialog<void>(context: context, builder: (_) => AlertDialog(
      title: const Text('Client 등록 코드'),
      content: SelectableText(code.isEmpty ? '코드 생성에 실패했습니다.' : code, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: PortfolioColors.accent)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    ));
  }

  Future<void> _showCreateUser() async {
    final id = TextEditingController();
    final pw = TextEditingController();
    final name = TextEditingController();
    String role = 'OPERATOR';
    final created = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: const Text('사용자 추가'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: id, decoration: const InputDecoration(labelText: '아이디')),
        const SizedBox(height: 10), TextField(controller: name, decoration: const InputDecoration(labelText: '표시 이름')),
        const SizedBox(height: 10), TextField(controller: pw, obscureText: true, decoration: const InputDecoration(labelText: '비밀번호 (4자 이상)')),
        const SizedBox(height: 10), DropdownButtonFormField<String>(value: role, items: const [DropdownMenuItem(value: 'OPERATOR', child: Text('운영자')), DropdownMenuItem(value: 'ADMIN', child: Text('관리자'))], onChanged: (v) => setLocal(() => role = v ?? 'OPERATOR')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
        FilledButton(onPressed: () async {
          final ok = await _portfolio.createUser(username: id.text, password: pw.text, role: role, displayName: name.text);
          if (dialogContext.mounted) Navigator.pop(dialogContext, ok);
        }, child: const Text('추가')),
      ],
    )));
    id.dispose(); pw.dispose(); name.dispose();
    if (created == true) await _reload();
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;
  @override
  Widget build(BuildContext context) {
    final admin = role.toUpperCase() == 'ADMIN';
    final color = admin ? PortfolioColors.accent : PortfolioColors.textMuted;
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(12)), child: Text(admin ? '관리자' : '운영자', style: TextStyle(fontSize: 11, color: color)));
  }
}
