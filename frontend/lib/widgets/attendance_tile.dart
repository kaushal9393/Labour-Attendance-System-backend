import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';
import '../models/attendance.dart';

class AttendanceTile extends StatelessWidget {
  final AttendanceRecord record;
  const AttendanceTile({super.key, required this.record});

  Color _statusColor(String status) {
    switch (status) {
      case 'present': return AppTheme.accent;
      case 'late':    return AppTheme.warning;
      case 'absent':  return AppTheme.error;
      default:        return AppTheme.textSecondary;
    }
  }

  Color _statusBg(String status) {
    switch (status) {
      case 'present': return AppTheme.accentLight;
      case 'late':    return AppTheme.warningLight;
      case 'absent':  return AppTheme.errorLight;
      default:        return AppTheme.surface;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'present': return Icons.check_circle_outline;
      case 'late':    return Icons.access_time;
      case 'absent':  return Icons.cancel_outlined;
      default:        return Icons.help_outline;
    }
  }

  String _formatTime(String? dt) {
    if (dt == null) return '--:--';
    try {
      final t = DateTime.parse(dt).toLocal();
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '--:--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color  = _statusColor(record.status);
    final bgColor = _statusBg(record.status);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        // Avatar
        CircleAvatar(
          radius: 22,
          backgroundColor: AppTheme.accentLight,
          backgroundImage: record.profilePhotoUrl != null
              ? CachedNetworkImageProvider(record.profilePhotoUrl!)
              : null,
          child: record.profilePhotoUrl == null
              ? Text(record.employeeName[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 17))
              : null,
        ),
        const SizedBox(width: 12),

        // Name & times
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.employeeName,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.login, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 3),
              Text(_formatTime(record.checkIn),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              const SizedBox(width: 10),
              const Icon(Icons.logout, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 3),
              Text(_formatTime(record.checkOut),
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ]),
          ]),
        ),

        // Status badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_statusIcon(record.status), color: color, size: 12),
            const SizedBox(width: 4),
            Text(record.status.toUpperCase(),
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
          ]),
        ),
      ]),
    );
  }
}
