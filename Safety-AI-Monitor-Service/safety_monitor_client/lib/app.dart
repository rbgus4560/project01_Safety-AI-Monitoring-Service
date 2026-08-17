import 'package:flutter/material.dart';

import 'screens/portfolio/client_gate_screen.dart';
import 'ui/portfolio_theme.dart';

class SafetyMonitorClientApp extends StatelessWidget {
  const SafetyMonitorClientApp({
    super.key,
    this.home,
    this.title = 'Safety Monitor Client',
  });

  final Widget? home;
  final String title;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: PortfolioTheme.build(),
      home: home ?? const ClientGateScreen(),
    );
  }
}
