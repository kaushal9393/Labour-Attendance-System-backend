import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/constants.dart';

class ModeSelectScreen extends StatefulWidget {
  const ModeSelectScreen({super.key});

  @override
  State<ModeSelectScreen> createState() => _ModeSelectScreenState();
}

class _ModeSelectScreenState extends State<ModeSelectScreen> {
  DateTime? _lastBackPress;

  Future<void> _selectMode(BuildContext context, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyMode, mode);
    if (!context.mounted) return;
    if (mode == AppConstants.modeKiosk) {
      context.go('/kiosk/splash');
    } else {
      context.go('/admin/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // App logo
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppTheme.accentLight,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.25), width: 2),
                    ),
                    child: const Icon(Icons.garage_rounded,
                        color: AppTheme.accent, size: 48),
                  ),
                ),
                const SizedBox(height: 24),

                const Center(
                  child: Text('Garage Attendance',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5)),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text('Choose how you want to use this app',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ),
                const SizedBox(height: 48),

                // Employee / Kiosk card
                _ModeCard(
                  icon: Icons.face_retouching_natural,
                  title: 'Employee Check-In',
                  subtitle: 'For staff — scan your face to mark attendance',
                  color: AppTheme.accent,
                  bgColor: AppTheme.accentLight,
                  onTap: () => _selectMode(context, AppConstants.modeKiosk),
                ),
                const SizedBox(height: 16),

                // Admin card
                _ModeCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Owner / Admin',
                  subtitle: 'Manage employees, view reports & salary',
                  color: AppTheme.blueAccent,
                  bgColor: AppTheme.blueLight,
                  onTap: () => _selectMode(context, AppConstants.modeAdmin),
                ),

                const SizedBox(height: 48),
                const Center(
                  child: Text('v1.0.0',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final Color        color;
  final Color        bgColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4)),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_ios, color: color, size: 14),
            ),
          ]),
        ),
      ),
    );
  }
}
