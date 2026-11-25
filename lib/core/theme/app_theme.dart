// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color brandBlue = Color(0xFF1261A0);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandBlue,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: const Color(0xFFF6F8FB),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: Color(0xFFF6F8FB),
        foregroundColor: Color(0xFF172B45),
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE7ECF2)),
        ),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandBlue,
          brightness: Brightness.dark,
        ),
        fontFamily: 'Cairo',
      );
}
