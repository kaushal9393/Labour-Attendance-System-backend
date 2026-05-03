import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../providers/employee_provider.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class EmployeeListScreen extends ConsumerWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(employeesProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Employees'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.read(employeesProvider.notifier).load(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Employee', style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () async {
          await context.push('/admin/register');
          ref.read(employeesProvider.notifier).load();
        },
      ),
      body: empAsync.when(
        loading: () => const ShimmerList(),
        error: (e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.read(employeesProvider.notifier).load()),
        data: (employees) {
          if (employees.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: AppTheme.accentLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_add_outlined,
                        color: AppTheme.accent, size: 52),
                  ),
                  const SizedBox(height: 20),
                  const Text('No employees yet',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap the button below to add\nyour first employee.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add First Employee'),
                    onPressed: () async {
                      await context.push('/admin/register');
                      ref.read(employeesProvider.notifier).load();
                    },
                  ),
                ]),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: employees.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            itemBuilder: (_, i) => _EmployeeCard(employee: employees[i]),
          );
        },
      ),
    );
  }
}

class _EmployeeCard extends ConsumerStatefulWidget {
  final Employee employee;
  const _EmployeeCard({required this.employee});

  @override
  ConsumerState<_EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends ConsumerState<_EmployeeCard> {

  void _onDeleteTap() {
    final name      = widget.employee.name;
    final empId     = widget.employee.id;
    final messenger = ScaffoldMessenger.of(context);
    final notifier  = ref.read(employeesProvider.notifier);

    // Delete immediately — show SnackBar with Undo option
    notifier.deleteOptimistic(empId);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$name deleted'),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;

    return GestureDetector(
      onTap: () => context.push('/employee-report', extra: e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          // Avatar
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.accentLight,
            backgroundImage: e.profilePhotoUrl != null
                ? CachedNetworkImageProvider(e.profilePhotoUrl!)
                : null,
            child: e.profilePhotoUrl == null
                ? Text(e.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 20,
                        fontWeight: FontWeight.w700))
                : null,
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.name,
                  style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 3),
              if (e.phone != null)
                Text(e.phone!,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              Text(
                'Joined ${DateFormat('dd MMM yyyy').format(DateTime.parse(e.joiningDate))}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ]),
          ),

          // Right side
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '₹${NumberFormat('#,##,###').format(e.monthlyScalary)}',
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accentLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('ACTIVE',
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _onDeleteTap,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.errorLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_outline,
                    color: AppTheme.error, size: 18),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
