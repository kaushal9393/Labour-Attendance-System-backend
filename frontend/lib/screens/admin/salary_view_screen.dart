import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../models/salary.dart';
import '../../providers/employee_provider.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class SalaryViewScreen extends ConsumerStatefulWidget {
  const SalaryViewScreen({super.key});

  @override
  ConsumerState<SalaryViewScreen> createState() => _SalaryViewScreenState();
}

class _SalaryViewScreenState extends ConsumerState<SalaryViewScreen> {
  Employee? _employee;
  DateTime  _month = DateTime.now();
  SalaryRecord? _salary;
  bool   _loading = false;
  String? _error;

  Future<void> _fetch() async {
    if (_employee == null) return;
    setState(() { _loading = true; _error = null; });

    final cacheKey = 'salary_${_employee!.id}_${_month.year}_${_month.month}';

    // Show cached data instantly if available
    final cached = await CacheService.get(cacheKey);
    if (cached != null) {
      setState(() { _salary = SalaryRecord.fromJson(cached); _loading = false; });
    }

    try {
      final resp = await ApiService().getMonthlySalary(
        employeeId: _employee!.id,
        month:      _month.month,
        year:       _month.year,
      );
      await CacheService.save(cacheKey, resp.data);
      if (mounted) setState(() { _salary = SalaryRecord.fromJson(resp.data); _loading = false; });
    } catch (e) {
      if (mounted && _salary == null) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final empAsync = ref.watch(employeesProvider);
    final fmt = NumberFormat('#,##,###.00');

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
          title: const Text('Salary View'),
          backgroundColor: AppTheme.surface),
      body: Column(children: [
        // Controls
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            empAsync.when(
              loading: () =>
                  const ShimmerBox(width: double.infinity, height: 52),
              error: (e, _) => const SizedBox(),
              data: (employees) => employees.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            color: AppTheme.textSecondary, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No employees yet. Add one from the Employees tab.',
                            style: TextStyle(
                                color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ),
                      ]),
                    )
                  : DropdownButtonFormField<Employee>(
                      initialValue: _employee,
                      dropdownColor: AppTheme.cardBg,
                      isExpanded: true,
                      hint: const Text('Select Employee',
                          style: TextStyle(color: AppTheme.textSecondary)),
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person,
                              color: AppTheme.accent)),
                      items: employees
                          .map((e) => DropdownMenuItem(
                                value: e,
                                child: Text(e.name,
                                    style: const TextStyle(
                                        color: AppTheme.textPrimary)),
                              ))
                          .toList(),
                      onChanged: (e) {
                        setState(() => _employee = e);
                        _fetch();
                      },
                    ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _month,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(
                          primary: AppTheme.accent,
                          surface: AppTheme.cardBg),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _month = picked);
                  _fetch();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('MMMM yyyy').format(_month),
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15)),
                      const Icon(Icons.calendar_month,
                          color: AppTheme.accent),
                    ]),
              ),
            ),
          ]),
        ),

        // Salary card
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent))
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _fetch)
                  : _salary == null
                      ? const Center(
                          child: Text('Select employee and month',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            // Header card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.accent, Color(0xFF0A5240)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(children: [
                                Text(_salary!.employeeName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    DateFormat('MMMM yyyy').format(
                                        DateTime(_salary!.year,
                                            _salary!.month)),
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 14)),
                                const SizedBox(height: 20),
                                Text('NET PAY',
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.75),
                                        fontSize: 13,
                                        letterSpacing: 2)),
                                Text('₹${fmt.format(_salary!.netPay)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ),
                            const SizedBox(height: 20),

                            // Breakdown
                            _SalaryRow(
                                label: 'Monthly Salary',
                                value: '₹${fmt.format(_salary!.monthlySalary)}',
                                color: AppTheme.textPrimary),
                            _SalaryRow(
                                label: 'Working Days',
                                value: '${_salary!.workingDays} days',
                                color: AppTheme.textSecondary),
                            const Divider(color: AppTheme.divider),
                            _SalaryRow(
                                label: 'Present Days',
                                value: '${_salary!.presentDays}',
                                color: AppTheme.accent),
                            _SalaryRow(
                                label: 'Late Days',
                                value: '${_salary!.lateDays}',
                                color: AppTheme.warning),
                            _SalaryRow(
                                label: 'Absent Days',
                                value: '${_salary!.absentDays}',
                                color: AppTheme.error),
                            const Divider(color: AppTheme.divider),
                            _SalaryRow(
                                label: 'Per Day Salary',
                                value:
                                    '₹${fmt.format(_salary!.perDaySalary)}',
                                color: AppTheme.textSecondary),
                            _SalaryRow(
                                label: 'Deduction',
                                value:
                                    '-₹${fmt.format(_salary!.deductionAmount)}',
                                color: AppTheme.error),
                            const Divider(color: AppTheme.divider, height: 24),
                            _SalaryRow(
                                label: 'NET PAY',
                                value: '₹${fmt.format(_salary!.netPay)}',
                                color: AppTheme.accent,
                                large: true),
                          ]),
                        ),
        ),
      ]),
    );
  }
}

class _SalaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  final bool   large;

  const _SalaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: large ? 15 : 14,
                    fontWeight:
                        large ? FontWeight.w600 : FontWeight.normal)),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: large ? 18 : 14,
                    fontWeight:
                        large ? FontWeight.bold : FontWeight.w500)),
          ]),
    );
  }
}
