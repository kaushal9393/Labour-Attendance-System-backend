import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/shimmer_loader.dart';
import '../../widgets/error_view.dart';

class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  DateTime _selected = DateTime.now();
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiService().getMonthlySummary(
          month: _selected.month, year: _selected.year);
      setState(() { _data = resp.data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
          title: const Text('Monthly Report'),
          backgroundColor: AppTheme.surface),
      body: Column(children: [
        // Month selector
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selected,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.dark(
                        primary: AppTheme.accent, surface: AppTheme.cardBg),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setState(() => _selected = picked);
                _fetch();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat('MMMM yyyy').format(_selected),
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const Icon(Icons.calendar_month,
                        color: AppTheme.accent),
                  ]),
            ),
          ),
        ),

        Expanded(
          child: _loading
              ? const ShimmerList()
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _fetch)
                  : _data == null
                      ? const SizedBox()
                      : _buildTable(),
        ),
      ]),
    );
  }

  Widget _buildTable() {
    final employees =
        (_data!['employees'] as List?) ?? [];
    if (employees.isEmpty) {
      return const Center(
          child: Text('No data for this month',
              style: TextStyle(color: AppTheme.textSecondary)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('EMPLOYEE', style: _hdr)),
            Expanded(child: Text('PRES', style: _hdr)),
            Expanded(child: Text('ABS', style: _hdr)),
            Expanded(child: Text('LATE', style: _hdr)),
            Expanded(flex: 2, child: Text('NET PAY', style: _hdr)),
          ]),
        ),
        const SizedBox(height: 6),
        ...employees.map((e) {
          final net = double.parse(e['net_pay'].toString());
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              Expanded(
                  flex: 3,
                  child: Text(e['employee_name'],
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 13))),
              Expanded(
                  child: Text('${e['present_days']}',
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 13))),
              Expanded(
                  child: Text('${e['absent_days']}',
                      style: const TextStyle(
                          color: AppTheme.error, fontSize: 13))),
              Expanded(
                  child: Text('${e['late_days']}',
                      style: const TextStyle(
                          color: AppTheme.warning, fontSize: 13))),
              Expanded(
                  flex: 2,
                  child: Text(
                    '₹${NumberFormat('#,##,###').format(net)}',
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  )),
            ]),
          );
        }),
      ]),
    );
  }
}

const _hdr = TextStyle(
    color: AppTheme.textSecondary,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5);
