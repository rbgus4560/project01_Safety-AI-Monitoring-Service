import 'package:flutter/material.dart';

/// 포트폴리오 버전 UI의 색상은 이 파일만 바꾸면 전체에 반영됩니다.
class PortfolioColors {
  static const background = Color(0xFF070D12);
  static const header = Color(0xFF0B1219);
  static const panel = Color(0xFF111A23);
  static const panelAlt = Color(0xFF172330);
  static const field = Color(0xFF101A24);
  static const border = Color(0xFF2B3A47);
  static const accent = Color(0xFF19B9BE);
  static const accentDark = Color(0xFF0E7C84);
  static const success = Color(0xFF35D46F);
  static const warning = Color(0xFFF2C94C);
  static const danger = Color(0xFFFF4D4F);
  static const text = Color(0xFFE8EEF3);
  static const textMuted = Color(0xFF90A0AD);
}

class PortfolioTheme {
  static ThemeData build() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: PortfolioColors.background,
      colorScheme: const ColorScheme.dark(
        primary: PortfolioColors.accent,
        secondary: PortfolioColors.accent,
        surface: PortfolioColors.panel,
        error: PortfolioColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: PortfolioColors.header,
        foregroundColor: PortfolioColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: PortfolioColors.panel,
        margin: EdgeInsets.zero,
      ),
      dividerColor: PortfolioColors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: PortfolioColors.field,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PortfolioColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PortfolioColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: PortfolioColors.accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: PortfolioColors.accentDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PortfolioColors.text,
          side: const BorderSide(color: PortfolioColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: PortfolioColors.header,
        indicatorColor: PortfolioColors.accentDark,
      ),
    );
  }
}
