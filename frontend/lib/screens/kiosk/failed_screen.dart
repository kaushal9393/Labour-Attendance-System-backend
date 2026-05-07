import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

class FailedScreen extends StatefulWidget {
  const FailedScreen({super.key});

  @override
  State<FailedScreen> createState() => _FailedScreenState();
}

class _FailedScreenState extends State<FailedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _controller.forward();
    // Auto-retry intentionally disabled for liveness flow: the AWS session
    // expires fast and an automatic retry tends to fire before the WebView
    // has cleaned up. User taps "Try Again" instead.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                      parent: _controller, curve: Curves.elasticOut),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppTheme.errorLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.error, width: 3),
                    ),
                    child: const Icon(Icons.face_retouching_off,
                        color: AppTheme.error, size: 64),
                  ),
                ),
                const SizedBox(height: 28),
                const Text('Face Not Recognized',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text(
                  'Please try again or contact your administrator.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 15,
                      height: 1.5),
                ),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: () => context.go('/kiosk/scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    minimumSize: const Size(200, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
