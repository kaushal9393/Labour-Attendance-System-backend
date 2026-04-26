import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class _NotificationItem {
  final String title;
  final String body;
  final DateTime time;
  final String type; // late | checkin | checkout | absent

  const _NotificationItem({
    required this.title,
    required this.body,
    required this.time,
    required this.type,
  });
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<_NotificationItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiService().getNotifications();
      final list = (resp.data['notifications'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _items = list.map((n) => _NotificationItem(
          title: n['title'] as String,
          body:  n['body']  as String,
          time:  DateTime.parse(n['time'] as String),
          type:  n['type']  as String,
        )).toList();
        _loading = false;
      });
    } catch (_) {
      setState(() { _loading = false; _error = 'Could not load notifications'; });
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'late':     return Icons.watch_later_outlined;
      case 'checkout': return Icons.logout;
      case 'absent':   return Icons.person_off_outlined;
      default:         return Icons.login;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'late':   return const Color(0xFFE67E22);
      case 'absent': return AppTheme.error;
      default:       return AppTheme.accent;
    }
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)   return DateFormat('hh:mm a').format(t);
    return DateFormat('dd MMM, hh:mm a').format(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accent),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: AppTheme.error, size: 40),
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.notifications_off_outlined,
                            color: AppTheme.textSecondary, size: 48),
                        SizedBox(height: 12),
                        Text('No activity today',
                            style: TextStyle(color: AppTheme.textSecondary)),
                      ]),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppTheme.accent,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final n = _items[i];
                          final color = _colorFor(n.type);
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 5),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_iconFor(n.type), color: color, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(n.title,
                                              style: const TextStyle(
                                                  color: AppTheme.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14)),
                                          Text(
                                            _relativeTime(n.time),
                                            style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 11),
                                          ),
                                        ],
                                      ),
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
                    ),
    );
  }
}
