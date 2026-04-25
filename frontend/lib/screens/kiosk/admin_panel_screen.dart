import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../providers/attendance_provider.dart';
import '../../widgets/attendance_tile.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class KioskAdminPanelScreen extends ConsumerWidget {
  const KioskAdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayAttendanceProvider);

    return Scaffold(
      backgroundColor: AppTheme.primary,
      appBar: AppBar(
        title: const Text('Today\'s Attendance'),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/kiosk/scan'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: AppTheme.accent),
            tooltip: 'Register Employee',
            onPressed: () => context.go('/kiosk/register'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accent),
            onPressed: () => ref.invalidate(todayAttendanceProvider),
          ),
        ],
      ),
      body: todayAsync.when(
        loading: () => const ShimmerList(),
        error: (e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(todayAttendanceProvider)),
        data: (today) => Column(
          children: [
            // Summary cards
            Container(
              color: AppTheme.surface,
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                _SummaryChip(
                    label: 'Present',
                    value: today.totalPresent,
                    color: AppTheme.accent),
                const SizedBox(width: 10),
                _SummaryChip(
                    label: 'Absent',
                    value: today.totalAbsent,
                    color: AppTheme.error),
                const SizedBox(width: 10),
                _SummaryChip(
                    label: 'Late',
                    value: today.totalLate,
                    color: AppTheme.warning),
              ]),
            ),
            Expanded(
              child: today.records.isEmpty
                  ? const Center(
                      child: Text('No attendance recorded today',
                          style: TextStyle(color: AppTheme.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: today.records.length,
                      itemBuilder: (_, i) =>
                          AttendanceTile(record: today.records[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int    value;
  final Color  color;
  const _SummaryChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text('$value',
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
        ]),
      ),
    );
  }
}
