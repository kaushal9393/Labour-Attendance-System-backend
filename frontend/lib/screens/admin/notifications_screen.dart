import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';

class _NotificationItem {
  final String title;
  final String body;
  final DateTime time;
  final bool isRead;

  const _NotificationItem({
    required this.title,
    required this.body,
    required this.time,
    this.isRead = false,
  });
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // In a real app these come from Firebase / local storage
  final _items = [
    _NotificationItem(
      title: 'Late Arrival',
      body: 'Rahul Kumar checked in at 09:47 AM (17 min late)',
      time: DateTime.now().subtract(const Duration(minutes: 20)),
    ),
    _NotificationItem(
      title: 'Check-In',
      body: 'Amit Singh checked in at 09:05 AM',
      time: DateTime.now().subtract(const Duration(hours: 1)),
      isRead: true,
    ),
    _NotificationItem(
      title: 'Absent Alert',
      body: '3 employees have not checked in yet today',
      time: DateTime.now().subtract(const Duration(hours: 2)),
      isRead: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.surface,
        actions: [
          TextButton(
            onPressed: () => setState(() {}),
            child: const Text('Mark all read',
                style: TextStyle(color: AppTheme.accent, fontSize: 13)),
          ),
        ],
      ),
      body: _items.isEmpty
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_off_outlined,
                    color: AppTheme.textSecondary, size: 48),
                SizedBox(height: 12),
                Text('No notifications',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ]),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final n = _items[i];
                return Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 5),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: n.isRead
                        ? AppTheme.cardBg
                        : AppTheme.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: n.isRead
                          ? AppTheme.divider
                          : AppTheme.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          n.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: AppTheme.accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(n.title,
                                      style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14)),
                                  Text(
                                    DateFormat('hh:mm a').format(n.time),
                                    style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11),
                                  ),
                                ]),
                            const SizedBox(height: 4),
                            Text(n.body,
                                style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
