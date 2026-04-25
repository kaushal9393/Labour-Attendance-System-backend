import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary       = Color(0xFF0F6E56);
  static const Color accent        = Color(0xFF0F6E56);
  static const Color accentLight   = Color(0xFFE8F5F0);
  static const Color success       = Color(0xFF2E7D32);
  static const Color error         = Color(0xFFD32F2F);
  static const Color errorLight    = Color(0xFFFFEBEE);
  static const Color warning       = Color(0xFFF57C00);
  static const Color warningLight  = Color(0xFFFFF3E0);
  static const Color surface       = Color(0xFFF7F8FA);
  static const Color cardBg        = Color(0xFFFFFFFF);
  static const Color textPrimary   = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider       = Color(0xFFE5E7EB);
  static const Color blueAccent    = Color(0xFF1565C0);
  static const Color blueLight     = Color(0xFFE3F2FD);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: surface,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.light(
      primary:   accent,
      secondary: accent,
      surface:   cardBg,
      error:     error,
      onPrimary: Colors.white,
      onSurface: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x14000000),
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    cardTheme: const CardThemeData(
      color: cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: divider),
      ),
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 5),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: error),
      ),
      labelStyle: TextStyle(color: textSecondary, fontSize: 14),
      hintStyle: TextStyle(color: Color(0xFFBDC1C6), fontSize: 14),
      prefixIconColor: textSecondary,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    textTheme: const TextTheme(
      displayLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
      displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
      headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
      headlineMedium:TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleLarge:    TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
      titleMedium:   TextStyle(color: textPrimary, fontWeight: FontWeight.w500),
      bodyLarge:     TextStyle(color: textPrimary),
      bodyMedium:    TextStyle(color: textSecondary),
      labelLarge:    TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
    ),
    dividerTheme: const DividerThemeData(color: divider, thickness: 1, space: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: accent,
      unselectedItemColor: textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 12,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: textPrimary,
      contentTextStyle: TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: surface,
      labelStyle: TextStyle(color: textPrimary, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
  );
}
