import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../screens/kiosk/splash_screen.dart';
import '../screens/kiosk/liveness_scan_screen.dart';
import '../screens/kiosk/success_screen.dart';
import '../screens/kiosk/failed_screen.dart';
import '../screens/kiosk/admin_panel_screen.dart';
import '../screens/kiosk/employee_registration_screen.dart';
import '../screens/kiosk/outside_window_screen.dart';
import '../screens/admin/login_screen.dart';
import '../screens/admin/signup_screen.dart';
import '../screens/admin/pin_login_screen.dart';
import '../screens/admin/dashboard_screen.dart';
import '../screens/admin/employee_list_screen.dart';
import '../screens/admin/attendance_history_screen.dart';
import '../screens/admin/monthly_report_screen.dart';
import '../screens/admin/salary_view_screen.dart';
import '../screens/admin/notifications_screen.dart';
import '../screens/admin/settings_screen.dart';
import '../screens/admin/manual_checkout_screen.dart';
import '../screens/admin/privacy_policy_screen.dart';
import '../screens/admin/terms_screen.dart';
import '../screens/admin/help_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/employee_report_screen.dart';
import '../models/employee.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/welcome',
    redirect: (context, state) async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.keyToken);
      final mode  = prefs.getString(AppConstants.keyMode);

      final loc = state.matchedLocation;

      final isPublicRoute = loc == '/welcome'        ||
                            loc == '/admin/login'    ||
                            loc == '/admin/signup'   ||
                            loc == '/admin/pin'      ||
                            loc == '/admin/privacy'  ||
                            loc == '/admin/terms'    ||
                            loc == '/admin/help';

      // 1. Kiosk mode active → keep in kiosk flow
      if (mode == AppConstants.modeKiosk && !loc.startsWith('/kiosk')) {
        return '/kiosk/splash';
      }

      // 2. Welcome screen always shows (user picks admin or kiosk each time)
      // No redirect away from welcome needed.

      // 3. Admin area without token → login (covers token expiry too)
      if (loc.startsWith('/admin') && token == null && !isPublicRoute) {
        return '/admin/login';
      }

      // 4. Logged-in admin on welcome → dashboard
      if (loc == '/welcome' && token != null) {
        return null; // let welcome show — user picks mode each time
      }

      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),

      // ── Kiosk ──────────────────────────────────────────────
      GoRoute(path: '/kiosk/splash',    builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/kiosk/scan',      builder: (_, __) => const LivenessScanScreen()),
      GoRoute(
        path: '/kiosk/success',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SuccessScreen(
            employeeName: extra['employee_name'] ?? '',
            checkInTime:  extra['time'] ?? '',
            action:       extra['action'] ?? 'check_in',
          );
        },
      ),
      GoRoute(
        path: '/kiosk/failed',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return FailedScreen(reason: extra['reason'] as String? ?? 'face_not_found');
        },
      ),
      GoRoute(
        path: '/kiosk/outside-window',
        builder: (_, state) {
          final e = state.extra as Map<String, dynamic>? ?? {};
          return OutsideWindowScreen(
            employeeName: e['employee_name'] ?? '',
            action:       e['action'] ?? 'check_in',
            windowStart:  e['window_start'] ?? '',
            windowEnd:    e['window_end'] ?? '',
          );
        },
      ),
      GoRoute(path: '/kiosk/admin',     builder: (_, __) => const KioskAdminPanelScreen()),
      GoRoute(path: '/kiosk/register',  builder: (_, __) => const EmployeeRegistrationScreen(fromAdmin: false)),

      // ── Admin ───────────────────────────────────────────────
      GoRoute(path: '/admin/login',     builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/admin/signup',    builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/admin/pin',       builder: (_, __) => const PinLoginScreen()),
      GoRoute(path: '/admin/register',  builder: (_, __) => const EmployeeRegistrationScreen(fromAdmin: true)),
      GoRoute(
        path: '/employee-report',
        builder: (context, state) {
          final emp = state.extra as Employee;
          return EmployeeReportScreen(employee: emp);
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin/dashboard',   builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/admin/employees',   builder: (_, __) => const EmployeeListScreen()),
          GoRoute(path: '/admin/attendance',  builder: (_, __) => const AttendanceHistoryScreen()),
          GoRoute(path: '/admin/reports',     builder: (_, __) => const MonthlyReportScreen()),
          GoRoute(path: '/admin/salary',      builder: (_, __) => const SalaryViewScreen()),
          GoRoute(path: '/admin/notifications',      builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/admin/settings',           builder: (_, __) => const AdminSettingsScreen()),
          GoRoute(path: '/admin/manual-checkout',    builder: (_, __) => const ManualCheckoutScreen()),
        ],
      ),

      GoRoute(path: '/admin/privacy',  builder: (_, __) => const PrivacyPolicyScreen()),
      GoRoute(path: '/admin/terms',    builder: (_, __) => const TermsScreen()),
      GoRoute(path: '/admin/help',     builder: (_, __) => const HelpScreen()),
    ],
  );
});

class AdminShell extends StatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _routes = const [
    '/admin/dashboard',
    '/admin/employees',
    '/admin/attendance',
    '/admin/salary',
    '/admin/settings',
  ];

  int _indexFromLocation(String location) {
    for (int i = 0; i < _routes.length; i++) {
      if (location.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  DateTime? _lastBackPress;

  Future<bool> _handleBack(BuildContext context, int currentIndex) async {
    // If not on Dashboard, jump to Dashboard instead of popping.
    if (currentIndex != 0) {
      context.go(_routes[0]);
      return false;
    }
    // On Dashboard — double-press-to-exit.
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          backgroundColor: AppTheme.surface,
        ),
      );
      return false;
    }
    return true;
  }

  static const _icons = [
    Icons.dashboard_rounded,
    Icons.people_rounded,
    Icons.calendar_month_rounded,
    Icons.payments_rounded,
    Icons.settings_rounded,
  ];
  static const _labels = [
    'Dashboard', 'Employees', 'Attendance', 'Salary', 'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexFromLocation(location);
    final isTablet = MediaQuery.sizeOf(context).width >= 600;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handleBack(context, currentIndex);
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: isTablet
          ? Scaffold(
              body: Row(children: [
                NavigationRail(
                  backgroundColor: AppTheme.surface,
                  selectedIndex: currentIndex,
                  onDestinationSelected: (i) => context.go(_routes[i]),
                  extended: MediaQuery.sizeOf(context).width >= 900,
                  minWidth: 72,
                  minExtendedWidth: 180,
                  selectedIconTheme:
                      const IconThemeData(color: AppTheme.accent, size: 26),
                  unselectedIconTheme: const IconThemeData(
                      color: AppTheme.textSecondary, size: 24),
                  selectedLabelTextStyle: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                  unselectedLabelTextStyle: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                  useIndicator: true,
                  indicatorColor: AppTheme.accentLight,
                  destinations: List.generate(
                    _labels.length,
                    (i) => NavigationRailDestination(
                      icon: Icon(_icons[i]),
                      label: Text(_labels[i]),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: widget.child),
              ]),
            )
          : Scaffold(
              body: widget.child,
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: currentIndex,
                type: BottomNavigationBarType.fixed,
                backgroundColor: AppTheme.surface,
                selectedItemColor: AppTheme.accent,
                unselectedItemColor: AppTheme.textSecondary,
                onTap: (i) => context.go(_routes[i]),
                items: List.generate(
                  _labels.length,
                  (i) => BottomNavigationBarItem(
                    icon: Icon(_icons[i]),
                    label: _labels[i],
                  ),
                ),
              ),
            ),
    );
  }
}
