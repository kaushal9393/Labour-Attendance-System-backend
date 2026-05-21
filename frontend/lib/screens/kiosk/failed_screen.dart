import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class FailedScreen extends StatefulWidget {
  final String reason;
  const FailedScreen({super.key, this.reason = 'face_not_found'});

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
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _FailureInfo get _info {
    switch (widget.reason) {
      case 'no_company_code':
        return const _FailureInfo(
          icon: Icons.business_outlined,
          title: 'Setup Incomplete',
          message:
              'Company setup nahi hua hai.\n'
              'Pehle Owner/Admin mode mein login karo.',
          showSettings: true,
        );
      case 'cant_start_session':
        return const _FailureInfo(
          icon: Icons.wifi_off_rounded,
          title: 'Server se connect nahi hua',
          message:
              'Internet connection check karo aur dobara try karo.',
          showSettings: false,
        );
      case 'cant_open_browser':
        return const _FailureInfo(
          icon: Icons.open_in_browser,
          title: 'Camera nahi khula',
          message:
              'Browser open nahi ho saka. App ko camera permission di hai?',
          showSettings: false,
        );
      case 'no_reference_image':
      case 'liveness_failed':
      case 'liveness_low_confidence':
        return const _FailureInfo(
          icon: Icons.face_retouching_off,
          title: 'Liveness Check Fail',
          message:
              'Live face detect nahi hua.\n'
              '• Achhi roshni mein karo\n'
              '• Camera ke seedha samne raho\n'
              '• Photo ya mask use mat karo',
          showSettings: false,
        );
      case 'face_not_recognized':
      case 'face_not_found':
      default:
        return const _FailureInfo(
          icon: Icons.face_retouching_off,
          title: 'Face Not Recognized',
          message:
              'Aapka chehra pehchana nahi gaya.\n'
              '• Achhi roshni mein scan karo\n'
              '• Admin se face register karwao\n'
              '• Glasses hata ke try karo',
          showSettings: false,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth;
          final iconSize = (w >= 600 ? 150.0 : 120.0);
          final titleSize = (w >= 600 ? 28.0 : 24.0);
          final hPad = w >= 600 ? (w - 480) / 2 : 32.0;
          return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad.clamp(24.0, 120.0), vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                      parent: _controller, curve: Curves.elasticOut),
                  child: Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: AppTheme.errorLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.error, width: 3),
                    ),
                    child: Icon(info.icon, color: AppTheme.error, size: iconSize * 0.53),
                  ),
                ),
                const SizedBox(height: 28),
                Text(info.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  info.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.6),
                ),
                const SizedBox(height: 40),
                if (!info.showSettings)
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
                if (info.showSettings) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(AppConstants.keyMode);
                      if (context.mounted) context.go('/admin/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      minimumSize: const Size(200, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Owner Login pe jao',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
          );
        }),
      ),
    );
  }
}

class _FailureInfo {
  final IconData icon;
  final String title;
  final String message;
  final bool showSettings;
  const _FailureInfo({
    required this.icon,
    required this.title,
    required this.message,
    required this.showSettings,
  });
}
