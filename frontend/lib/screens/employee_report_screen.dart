import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/theme.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';

class EmployeeReportScreen extends StatefulWidget {
  final Employee employee;
  const EmployeeReportScreen({super.key, required this.employee});

  @override
  State<EmployeeReportScreen> createState() => _EmployeeReportScreenState();
}

class _EmployeeReportScreenState extends State<EmployeeReportScreen> {
  late DateTime _selectedMonth;
  bool _loading = true;
  Map<String, dynamic>? _salary;
  List<dynamic> _attendance = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final salaryKey = 'salary_${widget.employee.id}_${_selectedMonth.year}_${_selectedMonth.month}';
    final attKey    = 'att_hist_${widget.employee.id}_${_selectedMonth.year}_${_selectedMonth.month}';

    // Show cached data instantly
    final cachedSalary = await CacheService.get(salaryKey);
    final cachedAtt    = await CacheService.get(attKey);
    if (cachedSalary != null && cachedAtt != null) {
      setState(() {
        _salary     = Map<String, dynamic>.from(cachedSalary as Map);
        _attendance = cachedAtt as List;
        _loading    = false;
      });
    }

    try {
      final results = await Future.wait([
        ApiService().getMonthlySalary(
          employeeId: widget.employee.id,
          month: _selectedMonth.month,
          year:  _selectedMonth.year,
        ),
        ApiService().getMonthlyAttendance(
          employeeId: widget.employee.id,
          month: _selectedMonth.month,
          year:  _selectedMonth.year,
        ),
      ]);
      await CacheService.save(salaryKey, results[0].data);
      await CacheService.save(attKey,    results[1].data);
      if (mounted) {
        setState(() {
          _salary     = Map<String, dynamic>.from(results[0].data as Map);
          _attendance = results[1].data as List;
          _loading    = false;
        });
      }
    } catch (_) {
      if (mounted && _salary == null) { setState(() => _loading = false); }
    }
  }

  List<DateTime> _lastSixMonths() {
    final now = DateTime.now();
    return List.generate(6, (i) => DateTime(now.year, now.month - i, 1));
  }

  List<Map<String, dynamic>> _buildDailyRows() {
    final daysInMonth =
        DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0).day;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final byDate = <int, dynamic>{};
    for (final r in _attendance) {
      final d = DateTime.parse(r['attendance_date']).day;
      byDate[d] = r;
    }

    final rows = <Map<String, dynamic>>[];
    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, d);
      final rec  = byDate[d];

      final bool isFuture = date.isAfter(todayDate);
      final bool isToday  = date.isAtSameMomentAs(todayDate);

      String status;
      if (isFuture) {
        status = 'NOT MARKED';
      } else if (rec != null) {
        final hasIn  = rec['check_in']  != null;
        final hasOut = rec['check_out'] != null;
        if (hasIn && hasOut) {
          // Keep original status (present / late) from backend
          status = (rec['status'] as String).toUpperCase();
        } else if (hasIn && !hasOut) {
          status = isToday ? 'CHECKED-IN' : 'INCOMPLETE';
        } else {
          status = isToday ? 'NOT MARKED' : 'ABSENT';
        }
      } else {
        status = isToday ? 'NOT MARKED' : 'ABSENT';
      }

      rows.add({
        'date':      date,
        'check_in':  rec?['check_in'],
        'check_out': rec?['check_out'],
        'status':    status,
      });
    }
    return rows;
  }

  String _fmtTime(String? iso) {
    if (iso == null) return '--';
    try {
      return DateFormat('hh:mm a').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '--';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PRESENT':    return const Color(0xFF0F6E56);
      case 'LATE':       return const Color(0xFFF57C00);
      case 'ABSENT':     return const Color(0xFFE74C3C);
      case 'INCOMPLETE': return const Color(0xFFF57C00);
      case 'CHECKED-IN': return const Color(0xFF1565C0);
      default:           return const Color(0xFF9E9E9E); // NOT MARKED
    }
  }

  // ── PDF ────────────────────────────────────────────────────────
  Future<Uint8List> _buildPdf() async {
    final doc = pw.Document();
    final s = _salary!;
    final rows = _buildDailyRows();
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    const navy = PdfColor.fromInt(0xFF0D1B2A);
    const accent = PdfColor.fromInt(0xFF0F6E56);
    const tableHeaderBg = PdfColor.fromInt(0xFF1B4F72);
    const altRow = PdfColor.fromInt(0xFFF2F3F4);
    const bodyText = PdfColor.fromInt(0xFF1A1A1A);
    const green = PdfColor.fromInt(0xFF0F6E56);
    const orange = PdfColor.fromInt(0xFFF57C00);
    const red = PdfColor.fromInt(0xFFE74C3C);

    final presentDays = (s['present_days'] ?? 0).toString();
    final lateDays = (s['late_days'] ?? 0).toString();
    final absentDays = (s['absent_days'] ?? 0).toString();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => [
          // Header bar
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            color: navy,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GARAGE ATTENDANCE REPORT',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                        'Generated on: ${DateFormat('d MMMM yyyy').format(DateTime.now())}',
                        style: const pw.TextStyle(
                            color: PdfColors.white, fontSize: 10)),
                  ],
                ),
                pw.Text('🚗',
                    style: const pw.TextStyle(
                        color: PdfColors.white, fontSize: 22)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Employee info
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _kv('Name', widget.employee.name),
                _kv('Phone', widget.employee.phone ?? '-'),
                _kv(
                    'Joined',
                    DateFormat('d MMM yyyy').format(
                        DateTime.parse(widget.employee.joiningDate))),
                _kv('Month', monthLabel),
              ],
            ),
          ),
          pw.SizedBox(height: 16),

          // Summary row
          pw.Row(
            children: [
              _summaryBox('PRESENT', presentDays, green),
              pw.SizedBox(width: 8),
              _summaryBox('LATE', lateDays, orange),
              pw.SizedBox(width: 8),
              _summaryBox('ABSENT', absentDays, red),
            ],
          ),
          pw.SizedBox(height: 16),

          // Salary breakdown
          pw.Text('SALARY BREAKDOWN',
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: bodyText)),
          pw.SizedBox(height: 8),
          _salaryRow('Monthly Salary',
              'Rs. ${_fmtNum(s['monthly_salary'])}', bodyText),
          _salaryRow('Total Working Days',
              '${s['working_days']} days', bodyText),
          _salaryRow('Per Day Salary',
              'Rs. ${_fmtNum(s['per_day_salary'])}', bodyText),
          pw.Divider(color: accent),
          _salaryRow('Present Days', '$presentDays days', bodyText),
          _salaryRow('Late Days', '$lateDays days', bodyText),
          _salaryRow('Absent Days', '$absentDays days', bodyText),
          _salaryRow('Deduction',
              '-Rs. ${_fmtNum(s['deduction_amount'])}', red),
          pw.Divider(color: accent),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('NET PAY',
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: green)),
              pw.Text('Rs. ${_fmtNum(s['net_pay'])}',
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: green)),
            ],
          ),
          pw.SizedBox(height: 18),

          // Attendance table
          pw.Text('ATTENDANCE DETAIL',
              style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: bodyText)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: tableHeaderBg),
                children: [
                  _th('DATE'),
                  _th('CHECK IN'),
                  _th('CHECK OUT'),
                  _th('STATUS'),
                ],
              ),
              for (int i = 0; i < rows.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: i.isEven ? PdfColors.white : altRow),
                  children: [
                    _td(DateFormat('dd MMM').format(rows[i]['date'])),
                    _td(_fmtTime(rows[i]['check_in'])),
                    _td(_fmtTime(rows[i]['check_out'])),
                    _td(rows[i]['status'],
                        color: _pdfStatusColor(rows[i]['status'] as String, green, orange, red),
                        bold: true),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 20),

          // Footer
          pw.Divider(color: PdfColors.grey400),
          pw.Center(
            child: pw.Column(children: [
              pw.Text('Garage Attendance System  •  v1.0',
                  style: const pw.TextStyle(
                      color: PdfColors.grey600, fontSize: 9)),
              pw.Text('This is a system generated report.',
                  style: const pw.TextStyle(
                      color: PdfColors.grey600, fontSize: 9)),
            ]),
          ),
        ],
      ),
    );
    return doc.save();
  }

  PdfColor _pdfStatusColor(String status, PdfColor green, PdfColor orange, PdfColor red) {
    switch (status) {
      case 'PRESENT':    return green;
      case 'LATE':       return orange;
      case 'INCOMPLETE': return orange;
      case 'ABSENT':     return red;
      default:           return PdfColors.grey600; // CHECKED-IN / NOT MARKED
    }
  }

  pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 80,
              child: pw.Text('$k:',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 11))),
          pw.Expanded(child: pw.Text(v, style: const pw.TextStyle(fontSize: 11))),
        ]),
      );

  pw.Widget _summaryBox(String label, String value, PdfColor color) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: color, width: 1.2),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(children: [
            pw.Text(label,
                style: pw.TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );

  pw.Widget _salaryRow(String k, String v, PdfColor color) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(k, style: pw.TextStyle(color: color, fontSize: 11)),
            pw.Text(v,
                style: pw.TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  pw.Widget _th(String t) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(t,
            style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget _td(String t, {PdfColor? color, bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(t,
            style: pw.TextStyle(
                color: color ?? PdfColors.black,
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );

  String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final d = double.tryParse(v.toString()) ?? 0;
    return NumberFormat('#,##,###').format(d.round());
  }

  String _pdfFileName() {
    final parts = widget.employee.name.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : 'Employee';
    final last = parts.length > 1 ? parts.last : '';
    final monthName = DateFormat('MMMM').format(_selectedMonth);
    final year = _selectedMonth.year;
    return last.isEmpty
        ? 'Attendance_${first}_${monthName}_$year.pdf'
        : 'Attendance_${first}_${last}_${monthName}_$year.pdf';
  }

  Future<void> _onShareTap() async {
    if (_salary == null) return;

    // Show building indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Building PDF…'),
          duration: Duration(seconds: 2),
          backgroundColor: AppTheme.accent,
        ),
      );
    }

    Uint8List bytes;
    try {
      bytes = await _buildPdf();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to build PDF: $e'), backgroundColor: AppTheme.error),
      );
      return;
    }

    if (!mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: _pdfFileName());
  }

  Future<void> _onDownloadTap() async {
    if (_salary == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Building PDF…'),
          duration: Duration(seconds: 3),
          backgroundColor: AppTheme.accent,
        ),
      );
    }

    Uint8List bytes;
    try {
      bytes = await _buildPdf();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to build PDF: $e'), backgroundColor: AppTheme.error),
      );
      return;
    }

    try {
      const channel = MethodChannel('com.example.garage_attendance/download');
      await channel.invokeMethod('saveToDownloads', {
        'bytes':    bytes,
        'fileName': _pdfFileName(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved to Downloads: ${_pdfFileName()}'),
          backgroundColor: AppTheme.accent,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.employee.name),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final s = _salary ?? {};
    final dailyRows = _buildDailyRows();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile header
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.surface,
                backgroundImage: widget.employee.profilePhotoUrl != null
                    ? CachedNetworkImageProvider(
                        widget.employee.profilePhotoUrl!)
                    : null,
                child: widget.employee.profilePhotoUrl == null
                    ? Text(widget.employee.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 22,
                            fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.employee.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.employee.phone ?? "-"}  |  Joined: ${DateFormat('MMM yyyy').format(DateTime.parse(widget.employee.joiningDate))}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monthly Salary: Rs. ${_fmtNum(widget.employee.monthlyScalary)}',
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // Month dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<DateTime>(
                value: _lastSixMonths().firstWhere(
                    (m) =>
                        m.year == _selectedMonth.year &&
                        m.month == _selectedMonth.month,
                    orElse: () => _selectedMonth),
                dropdownColor: AppTheme.cardBg,
                isExpanded: true,
                iconEnabledColor: AppTheme.accent,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 15),
                items: _lastSixMonths()
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text(DateFormat('MMMM yyyy').format(m)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedMonth = v);
                  _load();
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Summary row
          Row(children: [
            _statBox('PRESENT', '${s['present_days'] ?? 0}',
                const Color(0xFF0F6E56)),
            const SizedBox(width: 8),
            _statBox('LATE', '${s['late_days'] ?? 0}',
                const Color(0xFFF57C00)),
            const SizedBox(width: 8),
            _statBox('ABSENT', '${s['absent_days'] ?? 0}',
                const Color(0xFFE74C3C)),
          ]),
          const SizedBox(height: 18),

          // Salary breakdown
          const Text('SALARY BREAKDOWN',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(children: [
              _breakdownRow('Monthly Salary',
                  'Rs. ${_fmtNum(s['monthly_salary'])}'),
              _breakdownRow('Working Days', '${s['working_days'] ?? 0} days'),
              _breakdownRow('Per Day Salary',
                  'Rs. ${_fmtNum(s['per_day_salary'])}'),
              const Divider(color: AppTheme.divider),
              _breakdownRow('Present Days', '${s['present_days'] ?? 0} days'),
              _breakdownRow('Late Days', '${s['late_days'] ?? 0} days'),
              _breakdownRow('Absent Days', '${s['absent_days'] ?? 0} days'),
              _breakdownRow('Deduction',
                  '-Rs. ${_fmtNum(s['deduction_amount'])}',
                  valueColor: const Color(0xFFE74C3C)),
              const Divider(color: AppTheme.divider),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('NET PAY',
                      style: TextStyle(
                          color: AppTheme.accent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  Text('Rs. ${_fmtNum(s['net_pay'])}',
                      style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ]),
          ),
          const SizedBox(height: 18),

          // Daily table
          const Text('ATTENDANCE DETAIL',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Column(children: [
              _tableHeader(),
              ...dailyRows.map((r) => _tableRow(r)),
            ]),
          ),

          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _onDownloadTap,
            icon: const Icon(Icons.download),
            label: const Text('Download PDF'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _onShareTap,
            icon: const Icon(Icons.share),
            label: const Text('Share Report'),
            style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accent,
                side: const BorderSide(color: AppTheme.accent),
                minimumSize: const Size(double.infinity, 50)),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(children: [
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Widget _breakdownRow(String k, String v, {Color? valueColor}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            Text(v,
                style: TextStyle(
                    color: valueColor ?? AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _tableHeader() => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: const BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: const Row(children: [
          Expanded(
              flex: 2,
              child: Text('Date',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text('In',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text('Out',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))),
          Expanded(
              flex: 2,
              child: Text('Status',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12))),
        ]),
      );

  Widget _tableRow(Map<String, dynamic> r) {
    final status = r['status'] as String;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Row(children: [
        Expanded(
            flex: 2,
            child: Text(DateFormat('dd MMM').format(r['date']),
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 12))),
        Expanded(
            flex: 2,
            child: Text(_fmtTime(r['check_in']),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12))),
        Expanded(
            flex: 2,
            child: Text(_fmtTime(r['check_out']),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12))),
        Expanded(
            flex: 2,
            child: Text(status,
                style: TextStyle(
                    color: _statusColor(status),
                    fontSize: 12,
                    fontWeight: FontWeight.w700))),
      ]),
    );
  }
}
