import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../screens/kiosk/splash_screen.dart';
import '../screens/kiosk/face_scan_screen.dart';
import '../screens/kiosk/success_screen.dart';
import '../screens/kiosk/failed_screen.dart';
import '../screens/kiosk/admin_panel_screen.dart';
import '../screens/kiosk/employee_registration_screen.dart';
import '../screens/kiosk/outside_window_screen.dart';
import '../screens/admin/login_screen.dart';
import '../screens/admin/dashboard_screen.dart';
import '../screens/admin/employee_list_screen.dart';
import '../screens/admin/attendance_history_screen.dart';
import '../screens/admin/monthly_report_screen.dart';
import '../screens/admin/salary_view_screen.dart';
import '../screens/admin/notifications_screen.dart';
import '../screens/admin/settings_screen.dart';
import '../screens/mode_select_screen.dart';
import '../screens/employee_report_screen.dart';
import '../models/employee.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/mode-select',
    redirect: (context, state) async {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.keyToken);
      final mode  = prefs.getString(AppConstants.keyMode);

      final isAuthRoute = state.matchedLocation == '/admin/login' ||
                          state.matchedLocation == '/mode-select';

      if (mode == AppConstants.modeKiosk &&
          !state.matchedLocation.startsWith('/kiosk')) {
        return '/kiosk/splash';
      }
      if (mode == AppConstants.modeAdmin && token == null && !isAuthRoute) {
        return '/admin/login';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/mode-select', builder: (_, __) => const ModeSelectScreen()),

      // ── Kiosk ──────────────────────────────────────────────
      GoRoute(path: '/kiosk/splash',    builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/kiosk/scan',      builder: (_, __) => const FaceScanScreen()),
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
      GoRoute(path: '/kiosk/failed',    builder: (_, __) => const FailedScreen()),
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
          GoRoute(path: '/admin/notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: '/admin/settings',    builder: (_, __) => const AdminSettingsScreen()),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _indexFromLocation(location);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handleBack(context, currentIndex);
        if (shouldExit && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppTheme.surface,
          selectedItemColor: AppTheme.accent,
          unselectedItemColor: AppTheme.textSecondary,
          onTap: (i) => context.go(_routes[i]),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.people),    label: 'Employees'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Attendance'),
            BottomNavigationBarItem(icon: Icon(Icons.payments),  label: 'Salary'),
            BottomNavigationBarItem(icon: Icon(Icons.settings),  label: 'Settings'),
          ],
        ),
      ),
    );
  }
}
