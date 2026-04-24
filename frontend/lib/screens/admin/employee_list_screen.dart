import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../providers/employee_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class EmployeeListScreen extends ConsumerWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empAsync = ref.watch(employeesProvider);

    return Scaffold(
      backgroundColor: AppTheme.primary,
      appBar: AppBar(
        title: const Text('Employees'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(employeesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Employee'),
        onPressed: () async {
          await context.push('/admin/register');
          ref.invalidate(employeesProvider);
        },
      ),
      body: empAsync.when(
        loading: () => const ShimmerList(),
        error: (e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(employeesProvider)),
        data: (employees) {
          if (employees.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.group_add,
                          color: AppTheme.accent, size: 56),
                    ),
                    const SizedBox(height: 20),
                    const Text('No employees yet',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap the button below to add\nyour first employee and capture\ntheir face for attendance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add First Employee'),
                      onPressed: () async {
                        await context.push('/admin/register');
                        ref.invalidate(employeesProvider);
                      },
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
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
    // Use postFrameCallback so dialog opens after current frame/gesture is done
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Delete Employee',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(
            'Are you sure you want to delete "${widget.employee.name}"?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
              child:
                  const Text('Delete', style: TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      // Optimistic: refresh list immediately, then call API in background
      ref.invalidate(employeesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${widget.employee.name} deleted'),
            backgroundColor: AppTheme.error),
      );
      ApiService().deleteEmployee(widget.employee.id).catchError((e) {
        ref.invalidate(employeesProvider);
        throw e;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final isActive = employee.status == 'active';

    return GestureDetector(
      onTap: () => context.push('/employee-report', extra: employee),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: (isActive ? AppTheme.accent : AppTheme.error)
                  .withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.surface,
            backgroundImage: employee.profilePhotoUrl != null
                ? CachedNetworkImageProvider(employee.profilePhotoUrl!)
                : null,
            child: employee.profilePhotoUrl == null
                ? Text(employee.name[0].toUpperCase(),
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.name,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 3),
                  if (employee.phone != null)
                    Text(employee.phone!,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  Text(
                    'Joined ${DateFormat('dd MMM yyyy').format(DateTime.parse(employee.joiningDate))}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '₹${NumberFormat('#,##,###').format(employee.monthlyScalary)}',
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isActive ? AppTheme.accent : AppTheme.error)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                employee.status.toUpperCase(),
                style: TextStyle(
                    color: isActive ? AppTheme.accent : AppTheme.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 4),
            IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline,
                        color: AppTheme.error, size: 20),
                    onPressed: _onDeleteTap,
                  ),
          ]),
        ]),
      ),
    );
  }
}
