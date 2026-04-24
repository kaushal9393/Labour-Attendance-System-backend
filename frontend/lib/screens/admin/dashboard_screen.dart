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
    final auth = ref.watch(authProvider);
    final today = DateFormat('EEEE, dd MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppTheme.primary,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => context.go('/admin/notifications'),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.account_circle_outlined),
            color: AppTheme.cardBg,
            itemBuilder: (_) => [
              PopupMenuItem(
                child: const Text('Logout',
                    style: TextStyle(color: AppTheme.error)),
                onTap: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) context.go('/admin/login');
                },
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.cardBg,
        onRefresh: () async => ref.invalidate(todayAttendanceProvider),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome, ${auth.adminName ?? "Admin"}',
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(today,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  ]),
            ),
          ),

          // Stat cards
          todayAsync.when(
            loading: () => SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.95,
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
            data: (today) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildListDelegate([
                  StatCard(
                      title: 'Present',
                      value: '${today.totalPresent}',
                      icon: Icons.check_circle,
                      color: AppTheme.accent),
                  StatCard(
                      title: 'Absent',
                      value: '${today.totalAbsent}',
                      icon: Icons.cancel,
                      color: AppTheme.error),
                  StatCard(
                      title: 'Late',
                      value: '${today.totalLate}',
                      icon: Icons.access_time,
                      color: AppTheme.warning),
                ]),
              ),
            ),
          ),

          // Quick actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.person_add_alt_1,
                      label: 'Add\nEmployee',
                      color: AppTheme.accent,
                      onTap: () => context.go('/admin/employees'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.receipt_long,
                      label: 'Salary\nReports',
                      color: const Color(0xFF1565C0),
                      onTap: () => context.go('/admin/salary'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.calendar_month,
                      label: 'Attendance\nHistory',
                      color: AppTheme.warning,
                      onTap: () => context.go('/admin/attendance'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.logout,
                      label: 'Manual\nCheckout',
                      color: AppTheme.error,
                      onTap: () => context.go('/admin/manual-checkout'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),

          // Section title
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text("Today's Check-ins",
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ),

          // Attendance list
          todayAsync.when(
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                  (_, __) => const ShimmerCard(), childCount: 5),
            ),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox()),
            data: (today) => today.records.isEmpty
                ? const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No check-ins yet today',
                            style: TextStyle(color: AppTheme.textSecondary)),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => AttendanceTile(record: today.records[i]),
                      childCount: today.records.length,
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
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
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
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.3)),
          ]),
        ),
      ),
    );
  }
}
