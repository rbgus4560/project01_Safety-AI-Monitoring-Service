import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/portfolio_api_service.dart';
import '../../session/auth_session.dart';
import '../../ui/portfolio_theme.dart';
import '../home_screen.dart';

class PortfolioLoginScreen extends StatefulWidget {
  const PortfolioLoginScreen({super.key});
  @override
  State<PortfolioLoginScreen> createState() => _PortfolioLoginScreenState();
}

class _PortfolioLoginScreenState extends State<PortfolioLoginScreen> {
  final _api = PortfolioApiService();
  final _serverController = TextEditingController(text: AuthSession.instance.serverBaseUrl);
  final _idController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: 'admin1234');
  bool _remember = true;
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadServerConfig();
  }

  Future<void> _loadServerConfig() async {
    try {
      final file = _resolveViewerConfigFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final value = decoded['api_base_url']?.toString().trim() ?? '';
      if (value.isEmpty || !mounted) return;
      _serverController.text = value;
      AuthSession.instance.serverBaseUrl = value;
    } catch (_) {}
  }

  File _resolveViewerConfigFile() {
    final starts = <Directory>[Directory.current.absolute, File(Platform.resolvedExecutable).parent.absolute];
    for (final start in starts) {
      Directory? current = start;
      for (var depth = 0; depth < 8 && current != null; depth++) {
        final pubspec = File('${current.path}${Platform.pathSeparator}pubspec.yaml');
        final libDir = Directory('${current.path}${Platform.pathSeparator}lib');
        if (pubspec.existsSync() && libDir.existsSync()) {
          return File('${current.path}${Platform.pathSeparator}server_config.json');
        }
        final parent = current.parent;
        current = parent.path == current.path ? null : parent;
      }
    }
    return File('${Directory.current.path}${Platform.pathSeparator}server_config.json');
  }

  @override
  void dispose() {
    _api.dispose();
    _serverController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = ''; });
    final result = await _api.login(
      baseUrl: _serverController.text,
      username: _idController.text,
      password: _passwordController.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (result == null || result['token'] == null) {
      setState(() => _error = '로그인에 실패했습니다. 서버 주소와 계정을 확인하세요.');
      return;
    }
    AuthSession.instance.signIn(
      baseUrl: _serverController.text,
      accessToken: result['token'].toString(),
      user: result['username']?.toString() ?? '',
      name: result['display_name']?.toString() ?? '',
      userRole: result['role']?.toString() ?? 'OPERATOR',
    );
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _IndustrialBackdrop(),
          Container(color: Colors.black.withValues(alpha: 0.52)),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(34),
                decoration: BoxDecoration(
                  color: PortfolioColors.panel.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PortfolioColors.border),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.shield_outlined, color: PortfolioColors.text, size: 44),
                    const SizedBox(height: 10),
                    const Text('SAFETY MONITOR', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
                    const Text('AI 기반 안전 관제 시스템', textAlign: TextAlign.center,
                      style: TextStyle(color: PortfolioColors.textMuted)),
                    const SizedBox(height: 30),
                    TextField(controller: _serverController, decoration: const InputDecoration(labelText: '중앙 서버', hintText: 'http://127.0.0.1:8000')),
                    const SizedBox(height: 12),
                    TextField(controller: _idController, decoration: const InputDecoration(labelText: '아이디')),
                    const SizedBox(height: 12),
                    TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: '비밀번호')),
                    Row(children: [
                      Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? false)),
                      const Text('아이디 저장', style: TextStyle(color: PortfolioColors.textMuted)),
                    ]),
                    if (_error.isNotEmpty) ...[
                      Text(_error, style: const TextStyle(color: PortfolioColors.danger)),
                      const SizedBox(height: 10),
                    ],
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('로그인'),
                    ),
                    const SizedBox(height: 12),
                    const Text('Demo: admin / admin1234 · operator / operator1234',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: PortfolioColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IndustrialBackdrop extends StatelessWidget {
  const _IndustrialBackdrop();
  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _IndustrialPainter());
  }
}

class _IndustrialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF09131B));
    final p = Paint()..color = const Color(0xFF183041)..strokeWidth = 2..style = PaintingStyle.stroke;
    for (double x = 0; x < size.width; x += 80) {
      canvas.drawLine(Offset(x, size.height), Offset(x + 180, size.height * .35), p);
    }
    for (double y = size.height * .55; y < size.height; y += 55) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y - 120), p);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
