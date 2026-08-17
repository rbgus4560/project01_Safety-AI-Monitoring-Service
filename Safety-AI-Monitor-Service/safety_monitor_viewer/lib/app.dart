import 'package:flutter/material.dart';

import 'screens/portfolio/login_screen.dart';
import 'ui/portfolio_theme.dart';

class SafetyMonitorViewerApp extends StatelessWidget {
  const SafetyMonitorViewerApp({
    super.key,
    this.home,
    this.title = 'Safety Monitor Viewer',
  });

  final Widget? home;
  final String title;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: PortfolioTheme.build(),
      home: home ?? const PortfolioLoginScreen(),
    );
  }
}
