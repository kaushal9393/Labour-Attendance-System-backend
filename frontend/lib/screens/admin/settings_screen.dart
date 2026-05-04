import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../services/api_service.dart';
import '../../services/cache_service.dart';
import '../../providers/auth_provider.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  TimeOfDay _startTime    = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime      = const TimeOfDay(hour: 18, minute: 0);
  int       _lateThreshold = 15;
  bool      _saving        = false;

  // Monthly working days
  int  _selectedMonth      = DateTime.now().month;
  int  _selectedYear       = DateTime.now().year;
  int? _monthlyWorkingDays;
  final _monthlyDaysCtrl   = TextEditingController();

  TimeOfDay _ciStart = const TimeOfDay(hour: 8, minute: 45);
  TimeOfDay _ciEnd   = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _coStart = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _coEnd   = const TimeOfDay(hour: 19, minute: 0);

  static const _monthNames = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadMonthlyWorkingDays();
  }

  @override
  void dispose() {
    _monthlyDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMonthlyWorkingDays() async {
    try {
      final resp = await ApiService().getMonthlyWorkingDays(
        month: _selectedMonth, year: _selectedYear,
      );
      final data = resp.data;
      int? days;
      if (data is Map<String, dynamic> && data['working_days'] != null) {
        days = int.tryParse(data['working_days'].toString());
      }
      if (mounted) {
        setState(() {
          _monthlyWorkingDays = days;
          _monthlyDaysCtrl.text = days != null ? days.toString() : '';
        });
      }
    } catch (_) {}
  }

  void _applySettings(Map<String, dynamic> d) {
    final start = (d['work_start_time'] as String).split(':');
    final end   = (d['work_end_time']   as String).split(':');
    _startTime     = TimeOfDay(hour: int.parse(start[0]), minute: int.parse(start[1]));
    _endTime       = TimeOfDay(hour: int.parse(end[0]),   minute: int.parse(end[1]));
    _lateThreshold = d['late_threshold_minutes'];
    _ciStart = _parseTod(d['checkin_window_start'])  ?? _ciStart;
    _ciEnd   = _parseTod(d['checkin_window_end'])    ?? _ciEnd;
    _coStart = _parseTod(d['checkout_window_start']) ?? _coStart;
    _coEnd   = _parseTod(d['checkout_window_end'])   ?? _coEnd;
  }

  Future<void> _loadSettings() async {
    final cached = await CacheService.get('settings');
    if (cached != null && mounted) {
      setState(() => _applySettings(cached as Map<String, dynamic>));
    }
    try {
      final resp = await ApiService().getSettings();
      final d = resp.data as Map<String, dynamic>;
      await CacheService.save('settings', d);
      if (mounted) setState(() => _applySettings(d));
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Save main settings
      await CacheService.remove('settings');
      await ApiService().updateSettings({
        'work_start_time':        _todToApi(_startTime),
        'work_end_time':          _todToApi(_endTime),
        'late_threshold_minutes': _lateThreshold,
        'working_days_per_week':  6,
        'checkin_window_start':   _todToApi(_ciStart),
        'checkin_window_end':     _todToApi(_ciEnd),
        'checkout_window_start':  _todToApi(_coStart),
        'checkout_window_end':    _todToApi(_coEnd),
      });

      // Save monthly working days if filled
      final daysText = _monthlyDaysCtrl.text.trim();
      if (daysText.isNotEmpty) {
        final days = int.tryParse(daysText);
        if (days != null && days >= 1 && days <= 31) {
          await ApiService().setMonthlyWorkingDays(
            month: _selectedMonth, year: _selectedYear, workingDays: days,
          );
          if (mounted) setState(() => _monthlyWorkingDays = days);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Settings saved successfully'),
            ]),
            backgroundColor: AppTheme.accent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save settings'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.accent,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  Future<void> _pickWindow(String which) async {
    final initial = {'ciStart': _ciStart, 'ciEnd': _ciEnd, 'coStart': _coStart, 'coEnd': _coEnd}[which]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.accent, onPrimary: Colors.white,
            surface: Colors.white, onSurface: Colors.black87,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      switch (which) {
        case 'ciStart': _ciStart = picked; break;
        case 'ciEnd':   _ciEnd   = picked; break;
        case 'coStart': _coStart = picked; break;
        case 'coEnd':   _coEnd   = picked; break;
      }
    });
  }

  TimeOfDay? _parseTod(dynamic v) {
    if (v == null) return null;
    final parts = v.toString().split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _todToApi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Work Hours ──────────────────────────────────
            _SectionHeader(icon: Icons.schedule_outlined, title: 'Work Hours'),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _TimeCard(label: 'Start Time', time: _fmtTime(_startTime), onTap: () => _pickTime(true))),
              const SizedBox(width: 12),
              Expanded(child: _TimeCard(label: 'End Time', time: _fmtTime(_endTime), onTap: () => _pickTime(false))),
            ]),
            const SizedBox(height: 20),

            // ── Attendance Window ───────────────────────────
            _SectionHeader(icon: Icons.login_outlined, title: 'Attendance Window'),
            const SizedBox(height: 12),
            _WindowRow(
              label: 'Check-in Allowed',
              fromTime: _fmtTime(_ciStart),
              toTime: _fmtTime(_ciEnd),
              onFromTap: () => _pickWindow('ciStart'),
              onToTap:   () => _pickWindow('ciEnd'),
            ),
            const SizedBox(height: 10),
            _WindowRow(
              label: 'Check-out Allowed',
              fromTime: _fmtTime(_coStart),
              toTime: _fmtTime(_coEnd),
              onFromTap: () => _pickWindow('coStart'),
              onToTap:   () => _pickWindow('coEnd'),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: AppTheme.accent, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scans outside these time windows will be rejected.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Late Threshold ──────────────────────────────
            _SectionHeader(icon: Icons.timer_outlined, title: 'Late Arrival Threshold'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('After start time, mark as Late:',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$_lateThreshold min',
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                ]),
                Slider(
                  value: _lateThreshold.toDouble(),
                  min: 5, max: 60, divisions: 11,
                  activeColor: AppTheme.accent,
                  inactiveColor: AppTheme.divider,
                  label: '$_lateThreshold min',
                  onChanged: (v) => setState(() => _lateThreshold = v.round()),
                ),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
                  Text('5 min', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  Text('60 min', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                ]),
                const SizedBox(height: 4),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Monthly Working Days ────────────────────────
            _SectionHeader(icon: Icons.calendar_month_outlined, title: 'Monthly Working Days'),
            const SizedBox(height: 4),
            const Text(
              'Override working days for a specific month. Leave blank to use auto-calculation.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(children: [
                // Month + Year dropdowns
                Row(children: [
                  Expanded(
                    child: _DropdownCard(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedMonth,
                          isExpanded: true,
                          dropdownColor: AppTheme.cardBg,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                          items: List.generate(12, (i) => i + 1).map((m) =>
                            DropdownMenuItem(value: m, child: Text(_monthNames[m]))
                          ).toList(),
                          onChanged: (m) {
                            if (m == null) return;
                            setState(() {
                              _selectedMonth = m;
                              _monthlyDaysCtrl.clear();
                              _monthlyWorkingDays = null;
                            });
                            _loadMonthlyWorkingDays();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DropdownCard(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedYear,
                          isExpanded: true,
                          dropdownColor: AppTheme.cardBg,
                          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                          items: List.generate(5, (i) => DateTime.now().year - 1 + i).map((y) =>
                            DropdownMenuItem(value: y, child: Text(y.toString()))
                          ).toList(),
                          onChanged: (y) {
                            if (y == null) return;
                            setState(() {
                              _selectedYear = y;
                              _monthlyDaysCtrl.clear();
                              _monthlyWorkingDays = null;
                            });
                            _loadMonthlyWorkingDays();
                          },
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                // Days input
                TextField(
                  controller: _monthlyDaysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Working Days — ${_monthNames[_selectedMonth]} $_selectedYear',
                    labelStyle: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    hintText: _monthlyWorkingDays != null
                        ? 'Currently: $_monthlyWorkingDays days'
                        : 'Not set (auto)',
                    prefixIcon: const Icon(Icons.today_outlined, color: AppTheme.accent, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
                    ),
                    filled: true,
                    fillColor: AppTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (_monthlyWorkingDays != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.check_circle_outline, color: AppTheme.accent, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      '${_monthNames[_selectedMonth]} $_selectedYear: $_monthlyWorkingDays days set',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 12),
                    ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 28),

            // ── Save Button ─────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 20),
                label: Text(
                  _saving ? 'Saving…' : 'Save Settings',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Account ─────────────────────────────────────
            _SectionHeader(icon: Icons.manage_accounts_outlined, title: 'Account'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.swap_horiz,
              iconColor: const Color(0xFF1565C0),
              title: 'Switch App Mode',
              subtitle: 'Go back to Employee / Owner selection',
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove(AppConstants.keyMode);
                if (context.mounted) context.go('/mode-select');
              },
            ),
            const SizedBox(height: 10),
            _SettingsTile(
              icon: Icons.logout,
              iconColor: AppTheme.error,
              title: 'Logout',
              subtitle: 'Sign out of the admin account',
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/admin/login');
              },
            ),
            const SizedBox(height: 28),

            // ── About ────────────────────────────────────────
            _SectionHeader(icon: Icons.info_outline, title: 'About'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: const Row(children: [
                Icon(Icons.verified_outlined, color: AppTheme.accent, size: 20),
                SizedBox(width: 12),
                Text('Garage Attendance  •  v1.0.0',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// ── Helper Widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String   title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: AppTheme.accent, size: 16),
    ),
    const SizedBox(width: 10),
    Text(title,
        style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700)),
  ]);
}

class _TimeCard extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimeCard({required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(time, style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const Icon(Icons.access_time_outlined, color: AppTheme.accent, size: 18),
        ]),
      ]),
    ),
  );
}

class _WindowRow extends StatelessWidget {
  final String label;
  final String fromTime;
  final String toTime;
  final VoidCallback onFromTap;
  final VoidCallback onToTap;
  const _WindowRow({
    required this.label,
    required this.fromTime,
    required this.toTime,
    required this.onFromTap,
    required this.onToTap,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _TimeCard(label: 'From', time: fromTime, onTap: onFromTap)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text('→', style: TextStyle(color: AppTheme.textSecondary, fontSize: 18)),
        ),
        Expanded(child: _TimeCard(label: 'To', time: toTime, onTap: onToTap)),
      ]),
    ],
  );
}

class _DropdownCard extends StatelessWidget {
  final Widget child;
  const _DropdownCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.divider),
    ),
    child: child,
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.cardBg,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(
                color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 20),
        ]),
      ),
    ),
  );
}
