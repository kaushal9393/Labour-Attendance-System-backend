import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/attendance_tile.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayAttendanceProvider);
    final auth       = ref.watch(authProvider);
    final today      = DateFormat('EEEE, dd MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/admin/notifications'),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.account_circle_outlined),
            color: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (_) => [
              PopupMenuItem(
                child: const Row(children: [
                  Icon(Icons.logout, color: AppTheme.error, size: 18),
                  SizedBox(width: 8),
                  Text('Logout', style: TextStyle(color: AppTheme.error)),
                ]),
                onTap: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/admin/login');
                },
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async => ref.invalidate(todayAttendanceProvider),
        child: CustomScrollView(slivers: [

          // Welcome header
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.accent, Color(0xFF0A5240)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Welcome, ${auth.adminName ?? "Admin"} 👋',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(today,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.today, color: Colors.white, size: 28),
                ),
              ]),
            ),
          ),

          // Stat cards
          todayAsync.when(
            loading: () => SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 0.95,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, __) => const ShimmerBox(width: 100, height: 100),
                  childCount: 3,
                ),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
                child: ErrorView(
                    message: e.toString(),
                    onRetry: () => ref.invalidate(todayAttendanceProvider))),
            data: (data) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 10,
                  mainAxisSpacing: 10, childAspectRatio: 0.95,
                ),
                delegate: SliverChildListDelegate([
                  StatCard(
                      title: 'Present',
                      value: '${data.totalPresent}',
                      icon: Icons.check_circle_outline,
                      color: AppTheme.accent),
                  StatCard(
                      title: 'Absent',
                      value: '${data.totalAbsent}',
                      icon: Icons.cancel_outlined,
                      color: AppTheme.error),
                  StatCard(
                      title: 'Late',
                      value: '${data.totalLate}',
                      icon: Icons.access_time,
                      color: AppTheme.warning),
                ]),
              ),
            ),
          ),

          // Quick actions title
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text('Quick Actions',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),

          // Quick actions grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12,
                mainAxisSpacing: 12, childAspectRatio: 2.4,
              ),
              delegate: SliverChildListDelegate([
                _QuickAction(
                  icon: Icons.person_add_alt_1_outlined,
                  label: 'Employees',
                  color: AppTheme.accent,
                  bgColor: AppTheme.accentLight,
                  onTap: () => context.go('/admin/employees'),
                ),
                _QuickAction(
                  icon: Icons.receipt_long_outlined,
                  label: 'Salary',
                  color: AppTheme.blueAccent,
                  bgColor: AppTheme.blueLight,
                  onTap: () => context.go('/admin/salary'),
                ),
                _QuickAction(
                  icon: Icons.calendar_month_outlined,
                  label: 'Attendance',
                  color: AppTheme.warning,
                  bgColor: AppTheme.warningLight,
                  onTap: () => context.go('/admin/attendance'),
                ),
                _QuickAction(
                  icon: Icons.logout_outlined,
                  label: 'Checkout',
                  color: AppTheme.error,
                  bgColor: AppTheme.errorLight,
                  onTap: () => context.go('/admin/manual-checkout'),
                ),
              ]),
            ),
          ),

          // Today's check-ins
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text("Today's Check-ins",
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          ),

          todayAsync.when(
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                  (_, __) => const ShimmerCard(), childCount: 5),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
            data: (data) => data.records.isEmpty
                ? const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.inbox_outlined,
                              color: AppTheme.textSecondary, size: 48),
                          SizedBox(height: 12),
                          Text('No check-ins yet today',
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 15)),
                        ]),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => AttendanceTile(record: data.records[i]),
                      childCount: data.records.length,
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final Color        bgColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
