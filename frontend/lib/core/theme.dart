import 'package:flutter/material.dart';

class AppTheme {
  // Brand colours
  static const Color primary       = Color(0xFF0F6E56); // Teal green (accent stays same)
  static const Color accent        = Color(0xFF0F6E56); // Teal green
  static const Color success       = Color(0xFF2E7D32); // Green
  static const Color error         = Color(0xFFD32F2F); // Red
  static const Color warning       = Color(0xFFF57C00); // Orange
  static const Color surface       = Color(0xFFF5F5F5); // Light grey surface
  static const Color cardBg        = Color(0xFFFFFFFF); // White card
  static const Color textPrimary   = Color(0xFF1A1A1A); // Near black
  static const Color textSecondary = Color(0xFF757575); // Grey
  static const Color divider       = Color(0xFFE0E0E0); // Light divider

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: surface,
    colorScheme: const ColorScheme.light(
      primary:    accent,
      secondary:  accent,
      surface:    cardBg,
      error:      error,
      onPrimary:  Colors.white,
      onSurface:  textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x1A000000),
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardBg,
      elevation: 2,
      shadowColor: const Color(0x1A000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accent, width: 2),
      ),
      labelStyle: const TextStyle(color: textSecondary),
      hintStyle: const TextStyle(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    textTheme: const TextTheme(
      displayLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
      headlineMedium:TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleLarge:    TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleMedium:   TextStyle(color: textPrimary),
      bodyLarge:     TextStyle(color: textPrimary),
      bodyMedium:    TextStyle(color: textSecondary),
      labelLarge:    TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
    ),
    dividerTheme: const DividerThemeData(color: divider, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: accent,
      unselectedItemColor: textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
  );
}
