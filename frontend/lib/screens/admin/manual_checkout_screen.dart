import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/employee_provider.dart'; // employeesProvider
import '../../services/api_service.dart';

class ManualCheckoutScreen extends ConsumerStatefulWidget {
  const ManualCheckoutScreen({super.key});

  @override
  ConsumerState<ManualCheckoutScreen> createState() =>
      _ManualCheckoutScreenState();
}

class _ManualCheckoutScreenState extends ConsumerState<ManualCheckoutScreen> {
  Employee? _selectedEmployee;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _loading = false;
  String? _successMsg;
  String? _errorMsg;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accent,
            surface: AppTheme.cardBg,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accent,
            surface: AppTheme.cardBg,
            onSurface: AppTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _submit() async {
    if (_selectedEmployee == null) {
      setState(() => _errorMsg = 'Please select an employee.');
      return;
    }
    setState(() {
      _loading = true;
      _successMsg = null;
      _errorMsg = null;
    });

    try {
      final checkoutDt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      final resp = await ApiService().manualCheckout(
        employeeId: _selectedEmployee!.id,
        attendanceDate: _selectedDate,
        checkoutTime: checkoutDt,
      );
      final data = resp.data as Map<String, dynamic>;
      setState(() => _successMsg =
          '${data['employee_name']} checked out at ${data['checkout_time']}');
      // Refresh today's attendance so the dashboard reflects the change
      ref.invalidate(todayAttendanceProvider);
    } catch (e) {
      String msg = 'Failed to record checkout.';
      if (e.toString().contains('404')) msg = 'Employee not found.';
      if (e.toString().contains('401')) msg = 'Session expired — please log in again.';
      setState(() => _errorMsg = msg);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(employeesProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Manual Checkout'),
        backgroundColor: AppTheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Info banner explaining the purpose
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Use this to manually record checkout for employees who '
                  'missed the 5 PM – 7 PM window.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Employee dropdown
          const _Label('Employee'),
          const SizedBox(height: 8),
          employeesAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent)),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: AppTheme.error)),
            data: (employees) {
              final active =
                  employees.where((e) => e.status == 'active').toList();
              return DropdownButtonFormField<Employee>(
                value: _selectedEmployee,
                dropdownColor: AppTheme.cardBg,
                decoration: const InputDecoration(
                  hintText: 'Select employee',
                  prefixIcon:
                      Icon(Icons.person_outline, color: AppTheme.textSecondary),
                ),
                items: active
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e.name,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() {
                  _selectedEmployee = v;
                  _errorMsg = null;
                }),
              );
            },
          ),
          const SizedBox(height: 20),

          // Date picker
          const _Label('Attendance Date'),
          const SizedBox(height: 8),
          _PickerTile(
            icon: Icons.calendar_today_outlined,
            label: DateFormat('EEE, dd MMM yyyy').format(_selectedDate),
            onTap: _pickDate,
          ),
          const SizedBox(height: 20),

          // Time picker
          const _Label('Checkout Time'),
          const SizedBox(height: 8),
          _PickerTile(
            icon: Icons.access_time_outlined,
            label: _selectedTime.format(context),
            onTap: _pickTime,
          ),
          const SizedBox(height: 32),

          // Submit button
          ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.logout),
            label: Text(_loading ? 'Recording...' : 'Record Checkout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              minimumSize: const Size(double.infinity, 52),
            ),
          ),

          // Success message
          if (_successMsg != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    color: AppTheme.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_successMsg!,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14)),
                ),
              ]),
            ),
          ],

          // Error message
          if (_errorMsg != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_errorMsg!,
                      style: const TextStyle(
                          color: AppTheme.error, fontSize: 14)),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4));
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            Icon(icon, color: AppTheme.textSecondary, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 15)),
            const Spacer(),
            const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary, size: 20),
          ]),
        ),
      ),
    );
  }
}
