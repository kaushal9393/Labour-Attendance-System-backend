import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class SuccessScreen extends StatefulWidget {
  final String employeeName;
  final String checkInTime;
  final String action;

  const SuccessScreen({
    super.key,
    required this.employeeName,
    required this.checkInTime,
    required this.action,
  });

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  int _countdown = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        if (mounted) context.go('/kiosk/scan');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.action == 'check_in';
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Success icon
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.accentLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.accent, width: 3),
                    ),
                    child: const Icon(Icons.check_circle_outline,
                        color: AppTheme.accent, size: 72),
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  isCheckIn ? 'Welcome!' : 'Goodbye!',
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.employeeName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 26,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),

                // Time badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: AppTheme.divider),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isCheckIn ? Icons.login : Icons.logout,
                      color: AppTheme.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${isCheckIn ? "Check-In" : "Check-Out"}: ${widget.checkInTime}',
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),

                const SizedBox(height: 48),
                Text(
                  'Returning in $_countdown…',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
