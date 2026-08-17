import 'package:flutter/material.dart';
import '../../services/client_identity_service.dart';
import '../../ui/portfolio_theme.dart';
import '../home_screen.dart';

class ClientGateScreen extends StatefulWidget {
  const ClientGateScreen({super.key});
  @override
  State<ClientGateScreen> createState() => _ClientGateScreenState();
}

class _ClientGateScreenState extends State<ClientGateScreen> {
  final _identityService = ClientIdentityService();
  late bool _hasIdentity;
  @override
  void initState() { super.initState(); _hasIdentity = _identityService.load() != null; }
  @override
  Widget build(BuildContext context) => _hasIdentity
      ? const HomeScreen()
      : ClientRegistrationScreen(onRegistered: () => setState(() => _hasIdentity = true));
}

class ClientRegistrationScreen extends StatefulWidget {
  const ClientRegistrationScreen({super.key, required this.onRegistered});
  final VoidCallback onRegistered;
  @override
  State<ClientRegistrationScreen> createState() => _ClientRegistrationScreenState();
}

class _ClientRegistrationScreenState extends State<ClientRegistrationScreen> {
  final _service = ClientIdentityService();
  final _name = TextEditingController(text: '생산라인 PC-01');
  late final TextEditingController _server;
  final _code = TextEditingController(text: 'SM-DEMO-2026');
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: _service.loadConfiguredServerBaseUrl());
  }

  @override
  void dispose() { _name.dispose(); _server.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _register() async {
    setState(() { _loading = true; _error = ''; });
    final identity = await _service.register(serverBaseUrl: _server.text, clientName: _name.text, registrationCode: _code.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (identity == null) {
      setState(() => _error = '등록에 실패했습니다. 서버 실행 여부와 등록 코드를 확인하세요.');
      return;
    }
    widget.onRegistered();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 920,
          height: 570,
          child: Container(
            decoration: BoxDecoration(color: PortfolioColors.panel, border: Border.all(color: PortfolioColors.border), borderRadius: BorderRadius.circular(14)),
            clipBehavior: Clip.antiAlias,
            child: Row(children: [
              Expanded(child: Container(
                color: PortfolioColors.header,
                child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.videocam_outlined, size: 85, color: PortfolioColors.accent),
                  SizedBox(height: 24),
                  Icon(Icons.more_vert, color: PortfolioColors.textMuted),
                  Icon(Icons.dns_outlined, size: 70, color: PortfolioColors.textMuted),
                  SizedBox(height: 20),
                  Text('현장 Client를 중앙 서버에\n최초 1회 등록합니다.', textAlign: TextAlign.center, style: TextStyle(color: PortfolioColors.textMuted)),
                ]),
              )),
              Expanded(flex: 2, child: Padding(
                padding: const EdgeInsets.all(38),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('중앙 서버 등록', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 28),
                  TextField(controller: _name, decoration: const InputDecoration(labelText: 'Client 이름', hintText: '예) 생산라인 PC-01')),
                  const SizedBox(height: 14),
                  TextField(controller: _server, decoration: const InputDecoration(labelText: '서버 주소', hintText: 'http://192.168.0.10:8000')),
                  const SizedBox(height: 14),
                  TextField(controller: _code, decoration: const InputDecoration(labelText: '등록 코드', helperText: '최초 테스트 기본 코드: SM-DEMO-2026')),
                  if (_error.isNotEmpty) ...[const SizedBox(height: 10), Text(_error, style: const TextStyle(color: PortfolioColors.danger))],
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _loading ? null : _register, child: Text(_loading ? '등록 중...' : '등록 및 연결')),
                ]),
              )),
            ]),
          ),
        ),
      ),
    );
  }
}
