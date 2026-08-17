import 'package:flutter/material.dart';
import '../../session/auth_session.dart';
import '../../ui/portfolio_theme.dart';
import 'login_screen.dart';

class PortfolioPageFrame extends StatelessWidget {
  const PortfolioPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final session = AuthSession.instance;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        title: Row(children: [
          const Icon(Icons.shield_outlined, size: 23),
          const SizedBox(width: 9),
          const Text('SAFETY MONITOR', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(width: 18),
          Container(width: 1, height: 22, color: PortfolioColors.border),
          const SizedBox(width: 18),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          ...actions,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              const Icon(Icons.circle, color: PortfolioColors.success, size: 9),
              const SizedBox(width: 6),
              const Text('SERVER', style: TextStyle(fontSize: 11, color: PortfolioColors.textMuted)),
              const SizedBox(width: 18),
              Text(session.displayName.isEmpty ? session.username : session.displayName),
              const SizedBox(width: 6),
              Text(session.isAdmin ? 'ADMIN' : 'OPERATOR', style: const TextStyle(fontSize: 11, color: PortfolioColors.accent)),
              IconButton(
                tooltip: '로그아웃',
                onPressed: () {
                  session.clear();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const PortfolioLoginScreen()), (_) => false);
                },
                icon: const Icon(Icons.logout, size: 19),
              ),
            ]),
          ),
        ],
      ),
      body: Padding(padding: const EdgeInsets.all(10), child: child),
    );
  }
}

class PortfolioPanel extends StatelessWidget {
  const PortfolioPanel({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PortfolioColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortfolioColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing!,
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ]),
    );
  }
}
