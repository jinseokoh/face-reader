import 'package:flutter/material.dart';

class AppTheme {
  // Background
  static const background = Colors.white;
  static const surface = Color(0xFFF5F5F5);

  // Text
  static const textPrimary = Color(0xFF333333);
  static const textSecondary = Color(0xFF777777);
  static const textHint = Color(0xFFAAAAAA);

  // Accent
  static const accent = Color(0xFF555555);
  static const border = Color(0xFFE0E0E0);

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          titleTextStyle: TextStyle(
            fontFamily: 'SongMyung',
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        useMaterial3: true,
      );
}
