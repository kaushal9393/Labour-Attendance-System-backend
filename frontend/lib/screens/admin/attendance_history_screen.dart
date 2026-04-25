import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../providers/employee_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  Employee? _selectedEmployee;
  DateTime _selectedDate = DateTime.now();
  List<dynamic>? _records;
  bool _loading = false;
  String? _error;

  Future<void> _fetch() async {
    if (_selectedEmployee == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiService().getMonthlyAttendance(
        employeeId: _selectedEmployee!.id,
        month:      _selectedDate.month,
        year:       _selectedDate.year,
      );
      setState(() { _records = resp.data as List; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'present': return AppTheme.accent;
      case 'late':    return AppTheme.warning;
      default:        return AppTheme.error;
    }
  }

  String _fmt(String? dt) {
    if (dt == null) return '--:--';
    try {
      final t = DateTime.parse(dt).toLocal();
      return DateFormat('hh:mm a').format(t);
    } catch (_) { return '--:--'; }
  }

  @override
  Widget build(BuildContext context) {
    final empAsync = ref.watch(employeesProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
          title: const Text('Attendance History'),
          backgroundColor: AppTheme.surface),
      body: Column(children: [
        // Controls
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            // Employee picker
            empAsync.when(
              loading: () => const ShimmerBox(width: double.infinity, height: 52),
              error: (e, _) => Text(e.toString(),
                  style: const TextStyle(color: AppTheme.error)),
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
                      initialValue: _selectedEmployee,
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
                        setState(() => _selectedEmployee = e);
                        _fetch();
                      },
                    ),
            ),
            const SizedBox(height: 12),
            // Month picker
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
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
                  setState(() => _selectedDate = picked);
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
                      Text(
                        DateFormat('MMMM yyyy').format(_selectedDate),
                        style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 15),
                      ),
                      const Icon(Icons.calendar_month,
                          color: AppTheme.accent, size: 20),
                    ]),
              ),
            ),
          ]),
        ),

        // Table
        Expanded(
          child: _loading
              ? const ShimmerList()
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _fetch)
                  : _records == null
                      ? const Center(
                          child: Text('Select an employee to view history',
                              style: TextStyle(
                                  color: AppTheme.textSecondary)))
                      : _records!.isEmpty
                          ? const Center(
                              child: Text('No records for this month',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary)))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(children: [
                                // Header
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(children: [
                                    Expanded(
                                        flex: 2,
                                        child: Text('DATE',
                                            style: _headerStyle)),
                                    Expanded(
                                        child: Text('IN',
                                            style: _headerStyle)),
                                    Expanded(
                                        child: Text('OUT',
                                            style: _headerStyle)),
                                    Expanded(
                                        child: Text('STATUS',
                                            style: _headerStyle)),
                                  ]),
                                ),
                                const SizedBox(height: 6),
                                ...(_records!.map((r) {
                                  final rawDate = r['attendance_date'] as String? ?? '';
                                  final isFuture = rawDate.isNotEmpty &&
                                      DateTime.tryParse(rawDate)?.isAfter(DateTime.now()) == true;
                                  final status = r['status'] as String;
                                  final color = isFuture ? AppTheme.textSecondary : _statusColor(status);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.cardBg,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Row(children: [
                                      Expanded(
                                          flex: 2,
                                          child: Text(
                                            rawDate,
                                            style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontSize: 13),
                                          )),
                                      Expanded(
                                          child: Text(isFuture ? '—' : _fmt(r['check_in']),
                                              style: const TextStyle(
                                                  color: AppTheme.textPrimary,
                                                  fontSize: 13))),
                                      Expanded(
                                          child: Text(isFuture ? '—' : _fmt(r['check_out']),
                                              style: const TextStyle(
                                                  color: AppTheme.textPrimary,
                                                  fontSize: 13))),
                                      Expanded(
                                          child: isFuture
                                              ? const Text('—',
                                                  style: TextStyle(
                                                      color: AppTheme.textSecondary,
                                                      fontSize: 13))
                                              : Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status.toUpperCase(),
                                              style: TextStyle(
                                                  color: color,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          )),
                                    ]),
                                  );
                                }).toList()),
                              ]),
                            ),
        ),
      ]),
    );
  }
}

const _headerStyle = TextStyle(
    color: AppTheme.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5);
