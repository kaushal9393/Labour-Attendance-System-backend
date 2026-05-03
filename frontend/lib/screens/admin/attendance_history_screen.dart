import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/employee.dart';
import '../../providers/employee_provider.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';
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
  DateTime  _selectedDate = DateTime.now();
  List<dynamic>? _records;
  bool   _loading = false;
  String? _error;
  bool   _autoSelected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoSelected) return;
    final empAsync = ref.read(employeesProvider);
    empAsync.whenData((employees) {
      if (employees.isNotEmpty) {
        _autoSelected = true;
        _selectedEmployee = employees.first;
        _fetch();
      }
    });
  }

  Future<void> _fetch() async {
    if (_selectedEmployee == null) return;
    setState(() { _loading = true; _error = null; });

    final cacheKey = 'att_hist_${_selectedEmployee!.id}_${_selectedDate.year}_${_selectedDate.month}';
    final cached = await CacheService.get(cacheKey);
    if (cached != null) {
      setState(() { _records = cached as List; _loading = false; });
    }

    try {
      final resp = await ApiService().getMonthlyAttendance(
        employeeId: _selectedEmployee!.id,
        month:      _selectedDate.month,
        year:       _selectedDate.year,
      );
      await CacheService.save(cacheKey, resp.data);
      if (mounted) setState(() { _records = resp.data as List; _loading = false; });
    } catch (e) {
      if (mounted && _records == null) setState(() { _error = e.toString(); _loading = false; });
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Edit bottom sheet ───────────────────────────────────────
  void _openEditSheet(Map<String, dynamic>? existing, String dateStr) {
    if (_selectedEmployee == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttendanceEditSheet(
        employeeId:     _selectedEmployee!.id,
        employeeName:   _selectedEmployee!.name,
        dateStr:        dateStr,
        existing:       existing,
        onSaved: () {
          // Invalidate cache and reload
          final cacheKey = 'att_hist_${_selectedEmployee!.id}_${_selectedDate.year}_${_selectedDate.month}';
          CacheService.remove(cacheKey);
          _fetch();
        },
      ),
    );
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

  // Build list of all days in selected month, merge with records
  List<Map<String, dynamic>> _buildDayList() {
    final year  = _selectedDate.year;
    final month = _selectedDate.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final today = DateTime.now();

    // Map existing records by date string
    final recordMap = <String, Map<String, dynamic>>{};
    for (final r in (_records ?? [])) {
      final d = (r['attendance_date'] as String).substring(0, 10);
      recordMap[d] = Map<String, dynamic>.from(r);
    }

    final days = <Map<String, dynamic>>[];
    for (int d = 1; d <= daysInMonth; d++) {
      final date    = DateTime(year, month, d);
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final isFuture = date.isAfter(today);
      final record  = recordMap[dateStr];
      days.add({
        'date':      date,
        'dateStr':   dateStr,
        'isFuture':  isFuture,
        'record':    record,
      });
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final empAsync = ref.watch(employeesProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Attendance History'),
        backgroundColor: AppTheme.surface,
      ),
      body: Column(children: [
        // ── Controls ──────────────────────────────────────────
        Container(
          color: AppTheme.surface,
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            empAsync.when(
              loading: () => const ShimmerBox(width: double.infinity, height: 52),
              error: (e, _) => Text(e.toString(), style: const TextStyle(color: AppTheme.error)),
              data: (employees) => employees.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 18),
                        SizedBox(width: 10),
                        Expanded(child: Text('No employees yet.',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                      ]),
                    )
                  : DropdownButtonFormField<Employee>(
                      initialValue: _selectedEmployee,
                      dropdownColor: AppTheme.cardBg,
                      isExpanded: true,
                      hint: const Text('Select Employee',
                          style: TextStyle(color: AppTheme.textSecondary)),
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person, color: AppTheme.accent)),
                      items: employees.map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e.name, style: const TextStyle(color: AppTheme.textPrimary)),
                      )).toList(),
                      onChanged: (e) {
                        setState(() => _selectedEmployee = e);
                        _fetch();
                      },
                    ),
            ),
            const SizedBox(height: 12),
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
                          primary: AppTheme.accent, surface: AppTheme.cardBg),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(DateFormat('MMMM yyyy').format(_selectedDate),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
                  const Icon(Icons.calendar_month, color: AppTheme.accent, size: 20),
                ]),
              ),
            ),
          ]),
        ),

        // ── Table ─────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const ShimmerList()
              : _error != null
                  ? ErrorView(message: _error!, onRetry: _fetch)
                  : _selectedEmployee == null
                      ? const Center(child: Text('Select an employee to view history',
                          style: TextStyle(color: AppTheme.textSecondary)))
                      : _buildTable(),
        ),
      ]),
    );
  }

  Widget _buildTable() {
    final days = _buildDayList();

    return Column(children: [
      // Header
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(children: [
          Expanded(flex: 2, child: Text('DATE',   style: _headerStyle)),
          Expanded(child:         Text('IN',      style: _headerStyle)),
          Expanded(child:         Text('OUT',     style: _headerStyle)),
          Expanded(child:         Text('STATUS',  style: _headerStyle)),
          SizedBox(width: 32),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: days.length,
          itemBuilder: (_, i) {
            final day      = days[i];
            final isFuture = day['isFuture'] as bool;
            final dateStr  = day['dateStr'] as String;
            final date     = day['date'] as DateTime;
            final record   = day['record'] as Map<String, dynamic>?;
            final status   = record?['status'] as String? ?? 'absent';
            final color    = isFuture ? AppTheme.textSecondary : _statusColor(status);
            final isWeekend = date.weekday == DateTime.sunday;

            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isWeekend
                    ? AppTheme.surface
                    : AppTheme.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isWeekend ? AppTheme.divider : Colors.transparent,
                ),
              ),
              child: Row(children: [
                // Date
                Expanded(flex: 2, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat('dd MMM').format(date),
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    Text(DateFormat('EEE').format(date),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                )),
                // Check-in
                Expanded(child: Text(
                  isFuture ? '—' : (record != null ? _fmt(record['check_in']) : '--:--'),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                )),
                // Check-out
                Expanded(child: Text(
                  isFuture ? '—' : (record != null ? _fmt(record['check_out']) : '--:--'),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                )),
                // Status badge
                Expanded(child: isFuture
                    ? const Text('—', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12))
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          record != null ? status.toUpperCase() : 'ABSENT',
                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )),
                // Edit button
                if (!isFuture)
                  GestureDetector(
                    onTap: () => _openEditSheet(record, dateStr),
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.edit_outlined,
                          color: AppTheme.accent, size: 15),
                    ),
                  )
                else
                  const SizedBox(width: 28),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

// ── Edit / Add Bottom Sheet ────────────────────────────────────
class _AttendanceEditSheet extends StatefulWidget {
  final int    employeeId;
  final String employeeName;
  final String dateStr;
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;

  const _AttendanceEditSheet({
    required this.employeeId,
    required this.employeeName,
    required this.dateStr,
    required this.existing,
    required this.onSaved,
  });

  @override
  State<_AttendanceEditSheet> createState() => _AttendanceEditSheetState();
}

class _AttendanceEditSheetState extends State<_AttendanceEditSheet> {
  late String _status;
  TimeOfDay?  _checkIn;
  TimeOfDay?  _checkOut;
  bool _saving = false;

  String _fmt24(String? dt) {
    if (dt == null) return '';
    try {
      final t = DateTime.parse(dt).toLocal();
      return '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
    } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _status   = r?['status'] ?? 'present';

    final ciStr = _fmt24(r?['check_in']);
    final coStr = _fmt24(r?['check_out']);

    if (ciStr.isNotEmpty) {
      final p = ciStr.split(':');
      _checkIn = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
    if (coStr.isNotEmpty) {
      final p = coStr.split(':');
      _checkOut = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay? initial) async {
    return showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
              primary: AppTheme.accent, onPrimary: Colors.white,
              surface: Colors.white, onSurface: Colors.black87),
        ),
        child: child!,
      ),
    );
  }

  String _todStr(TimeOfDay? t) {
    if (t == null) return '--:--';
    return '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
  }

  String? _todToApi(TimeOfDay? t) {
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().manualEditAttendance({
        'employee_id':     widget.employeeId,
        'attendance_date': widget.dateStr,
        'action':          'upsert',
        'status':          _status,
        'check_in':        _todToApi(_checkIn),
        'check_out':       _todToApi(_checkOut),
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance updated'), backgroundColor: AppTheme.accent),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _delete() {
    // Close sheet immediately — optimistic delete
    Navigator.pop(context);
    widget.onSaved();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Record deleted'), backgroundColor: AppTheme.error),
    );
    // API call in background — ignore errors (optimistic)
    ApiService().manualEditAttendance({
      'employee_id':     widget.employeeId,
      'attendance_date': widget.dateStr,
      'action':          'delete',
    }).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(widget.dateStr);
    final dateLabel = DateFormat('dd MMMM yyyy (EEEE)').format(date);
    final isExisting = widget.existing != null;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20,
          MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),

        // Title
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isExisting ? 'Attendance Edit Karo' : 'Attendance Add Karo',
                style: const TextStyle(color: AppTheme.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w700)),
            Text('${widget.employeeName}  •  $dateLabel',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ]),
          if (isExisting)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.error),
            ),
        ]),
        const SizedBox(height: 20),

        // Status chips
        const Align(alignment: Alignment.centerLeft,
            child: Text('Status', style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Row(children: [
          _StatusChip(label: 'Present', value: 'present',
              selected: _status == 'present', color: AppTheme.accent,
              onTap: () => setState(() => _status = 'present')),
          const SizedBox(width: 8),
          _StatusChip(label: 'Late', value: 'late',
              selected: _status == 'late', color: AppTheme.warning,
              onTap: () => setState(() => _status = 'late')),
          const SizedBox(width: 8),
          _StatusChip(label: 'Absent', value: 'absent',
              selected: _status == 'absent', color: AppTheme.error,
              onTap: () => setState(() {
                _status = 'absent';
                _checkIn  = null;
                _checkOut = null;
              })),
        ]),
        const SizedBox(height: 20),

        // Check-in / Check-out (only if not absent)
        if (_status != 'absent') ...[
          const Align(alignment: Alignment.centerLeft,
              child: Text('Time', style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _TimeTile(
              label: 'Check-in',
              time: _todStr(_checkIn),
              onTap: () async {
                final t = await _pickTime(_checkIn);
                if (t != null) setState(() => _checkIn = t);
              },
            )),
            const SizedBox(width: 12),
            Expanded(child: _TimeTile(
              label: 'Check-out',
              time: _todStr(_checkOut),
              onTap: () async {
                final t = await _pickTime(_checkOut);
                if (t != null) setState(() => _checkOut = t);
              },
            )),
          ]),
          const SizedBox(height: 20),
        ],

        // Save button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isExisting ? 'Save Changes' : 'Add Record',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label, value;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.value,
      required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : AppTheme.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? color : AppTheme.divider,
                width: selected ? 1.5 : 1),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
              color: selected ? color : AppTheme.textSecondary,
              fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label, time;
  final VoidCallback onTap;
  const _TimeTile({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(time, style: const TextStyle(color: AppTheme.textPrimary,
                fontSize: 16, fontWeight: FontWeight.w600)),
            const Icon(Icons.access_time, color: AppTheme.accent, size: 18),
          ]),
        ]),
      ),
    );
  }
}

const _headerStyle = TextStyle(
    color: AppTheme.textSecondary, fontSize: 11,
    fontWeight: FontWeight.w700, letterSpacing: 0.5);
