import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime   = const TimeOfDay(hour: 18, minute: 0);
  int       _lateThreshold = 15;
  int       _workDays      = 6;
  bool      _loading = false;
  bool      _saving  = false;

  TimeOfDay _ciStart = const TimeOfDay(hour: 8, minute: 45);
  TimeOfDay _ciEnd   = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _coStart = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _coEnd   = const TimeOfDay(hour: 19, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiService().getSettings();
      final d = resp.data as Map<String, dynamic>;
      final start = (d['work_start_time'] as String).split(':');
      final end   = (d['work_end_time']   as String).split(':');
      setState(() {
        _startTime     = TimeOfDay(hour: int.parse(start[0]), minute: int.parse(start[1]));
        _endTime       = TimeOfDay(hour: int.parse(end[0]),   minute: int.parse(end[1]));
        _lateThreshold = d['late_threshold_minutes'];
        _workDays      = d['working_days_per_week'];
        _ciStart = _parseTod(d['checkin_window_start'])  ?? _ciStart;
        _ciEnd   = _parseTod(d['checkin_window_end'])    ?? _ciEnd;
        _coStart = _parseTod(d['checkout_window_start']) ?? _coStart;
        _coEnd   = _parseTod(d['checkout_window_end'])   ?? _coEnd;
        _loading       = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().updateSettings({
        'work_start_time':         '${_startTime.hour.toString().padLeft(2,'0')}:${_startTime.minute.toString().padLeft(2,'0')}:00',
        'work_end_time':           '${_endTime.hour.toString().padLeft(2,'0')}:${_endTime.minute.toString().padLeft(2,'0')}:00',
        'late_threshold_minutes':  _lateThreshold,
        'working_days_per_week':   _workDays,
        'checkin_window_start':    _todToApi(_ciStart),
        'checkin_window_end':      _todToApi(_ciEnd),
        'checkout_window_start':   _todToApi(_coStart),
        'checkout_window_end':     _todToApi(_coEnd),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Settings saved'),
              backgroundColor: AppTheme.accent),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to save settings'),
              backgroundColor: AppTheme.error),
        );
      }
    }
    setState(() => _saving = false);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppTheme.accent, surface: AppTheme.cardBg),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  TimeOfDay? _parseTod(dynamic v) {
    if (v == null) return null;
    final parts = v.toString().split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _todToApi(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickWindow(String which) async {
    final initial = {
      'ciStart': _ciStart,
      'ciEnd':   _ciEnd,
      'coStart': _coStart,
      'coEnd':   _coEnd,
    }[which]!;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AppTheme.accent, surface: AppTheme.cardBg),
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
          backgroundColor: AppTheme.surface),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Work hours section
                  const _SectionTitle(title: 'Work Hours'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _TimeSelector(
                        label: 'Start Time',
                        time:  _fmtTime(_startTime),
                        onTap: () => _pickTime(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeSelector(
                        label: 'End Time',
                        time:  _fmtTime(_endTime),
                        onTap: () => _pickTime(false),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  // Attendance Window
                  const _SectionTitle(title: 'Attendance Window'),
                  const SizedBox(height: 12),
                  const Text('Check-in Allowed Between',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _TimeSelector(
                        label: 'From',
                        time: _fmtTime(_ciStart),
                        onTap: () => _pickWindow('ciStart'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeSelector(
                        label: 'To',
                        time: _fmtTime(_ciEnd),
                        onTap: () => _pickWindow('ciEnd'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const Text('Check-out Allowed Between',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _TimeSelector(
                        label: 'From',
                        time: _fmtTime(_coStart),
                        onTap: () => _pickWindow('coStart'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeSelector(
                        label: 'To',
                        time: _fmtTime(_coEnd),
                        onTap: () => _pickWindow('coEnd'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.accent.withValues(alpha: 0.4)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.accent, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Employees can only scan within these time windows. Scans outside are rejected.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Late threshold
                  const _SectionTitle(title: 'Late Arrival Threshold'),
                  const SizedBox(height: 8),
                  Text(
                    'Employees arriving more than $_lateThreshold minutes after start time are marked "Late"',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  Slider(
                    value: _lateThreshold.toDouble(),
                    min: 5, max: 60, divisions: 11,
                    activeColor: AppTheme.accent,
                    inactiveColor: AppTheme.divider,
                    label: '$_lateThreshold min',
                    onChanged: (v) =>
                        setState(() => _lateThreshold = v.round()),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('5 min',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    Text('$_lateThreshold min',
                        style: const TextStyle(
                            color: AppTheme.accent,
                            fontWeight: FontWeight.bold)),
                    const Text('60 min',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
                  const SizedBox(height: 24),

                  // Working days
                  const _SectionTitle(title: 'Working Days Per Week'),
                  const SizedBox(height: 12),
                  Row(children: [
                    _DayChip(
                      label: '5 days\nMon–Fri',
                      selected: _workDays == 5,
                      onTap: () => setState(() => _workDays = 5),
                    ),
                    const SizedBox(width: 12),
                    _DayChip(
                      label: '6 days\nMon–Sat',
                      selected: _workDays == 6,
                      onTap: () => setState(() => _workDays = 6),
                    ),
                  ]),
                  const SizedBox(height: 32),

                  // Save button
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Saving…' : 'Save Settings'),
                  ),
                  const SizedBox(height: 28),

                  // Account section
                  const _SectionTitle(title: 'Account'),
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
                  const _SectionTitle(title: 'About'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.accent, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('Garage Attendance  •  v1.0.0',
                            style: TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) => Text(title,
      style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700));
}

class _TimeSelector extends StatelessWidget {
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimeSelector(
      {required this.label, required this.time, required this.onTap});

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
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(time,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Icon(Icons.access_time, color: AppTheme.accent, size: 18),
          ]),
        ]),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
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
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  ]),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool   selected;
  final VoidCallback onTap;
  const _DayChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.15)
                : AppTheme.cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(children: [
            Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? AppTheme.accent : AppTheme.textSecondary,
                size: 22),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    height: 1.4)),
          ]),
        ),
      ),
    );
  }
}
