import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/constants.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  DateTime? _lastBackPress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _goAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyMode, AppConstants.modeAdmin);
    if (!mounted) return;

    // If PIN + credentials saved → PIN screen, else login
    final pin   = prefs.getString('admin_pin');
    final email = prefs.getString('saved_email');
    final pass  = prefs.getString('saved_password');
    if (pin != null && email != null && pass != null) {
      context.go('/admin/pin');
    } else {
      context.go('/admin/login');
    }
  }

  Future<void> _goKiosk() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(AppConstants.keyCompanyCode);
    if (!mounted) return;

    if (code == null || code.isEmpty) {
      _showSetupDialog();
      return;
    }

    await prefs.setString(AppConstants.keyMode, AppConstants.modeKiosk);
    if (!mounted) return;
    context.go('/kiosk/splash');
  }

  void _showSetupDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Setup zaroori hai',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Employee scan shuru karne se pehle owner ko ek baar '
          'login karna hoga. Pehle "Admin Login" karo.',
          style: TextStyle(
              color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/admin/login');
            },
            child: const Text('Admin Login'),
          ),
        ],
      ),
    );
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
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final isTablet = w >= 600;
                  final hPad = isTablet ? ((w - 500) / 2).clamp(32.0, 120.0) : 24.0;
                  final iconSize = isTablet ? 110.0 : 88.0;
                  final titleSize = isTablet ? 34.0 : 28.0;

                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: hPad),
                    child: Column(
                      children: [
                        SizedBox(height: isTablet ? 60 : 48),

                        // Logo
                        Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            color: AppTheme.accentLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.3),
                                width: 2),
                          ),
                          child: Icon(Icons.garage_rounded,
                              color: AppTheme.accent,
                              size: iconSize * 0.52),
                        ),
                        SizedBox(height: isTablet ? 28 : 20),
                        Text(
                          'FaceScan',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Live face attendance for your team',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                        ),

                        SizedBox(height: isTablet ? 56 : 40),

                        // Cards — side by side on tablet
                        if (isTablet)
                          Row(children: [
                            Expanded(
                              child: _ModeCard(
                                icon: Icons.face_retouching_natural,
                                title: 'Employee Check-In',
                                subtitle: 'Staff apna chehra scan karke attendance lagayein',
                                iconColor: AppTheme.accent,
                                bgColor: AppTheme.accentLight,
                                onTap: _goKiosk,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _ModeCard(
                                icon: Icons.admin_panel_settings_outlined,
                                title: 'Owner / Admin',
                                subtitle: 'Employees manage karo, reports aur salary dekho',
                                iconColor: AppTheme.blueAccent,
                                bgColor: AppTheme.blueLight,
                                onTap: _goAdmin,
                              ),
                            ),
                          ])
                        else ...[
                          _ModeCard(
                            icon: Icons.face_retouching_natural,
                            title: 'Employee Check-In',
                            subtitle: 'Staff apna chehra scan karke attendance lagayein',
                            iconColor: AppTheme.accent,
                            bgColor: AppTheme.accentLight,
                            onTap: _goKiosk,
                          ),
                          const SizedBox(height: 14),
                          _ModeCard(
                            icon: Icons.admin_panel_settings_outlined,
                            title: 'Owner / Admin',
                            subtitle: 'Employees manage karo, reports aur salary dekho',
                            iconColor: AppTheme.blueAccent,
                            bgColor: AppTheme.blueLight,
                            onTap: _goAdmin,
                          ),
                        ],

                        SizedBox(height: isTablet ? 48 : 32),
                        const Text('v1.0.0',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12)),
                        const SizedBox(height: 24),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconColor,
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
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
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
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_forward_ios,
                  color: iconColor, size: 13),
            ),
          ]),
        ),
      ),
    );
  }
}
