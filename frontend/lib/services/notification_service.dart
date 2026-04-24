import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();

  static const _checkoutNotifId = 1001;
  static const _channelId = 'checkout_reminder';
  static const _channelName = 'Checkout Reminder';

  Future<void> init() async {
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Reminds employees to check out at 5 PM',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await scheduleDailyCheckoutReminder();
  }

  /// Schedules a daily local notification at 17:00 (5 PM) in the device's
  /// local timezone reminding employees to check out before 7 PM.
  Future<void> scheduleDailyCheckoutReminder() async {
    await _plugin.cancel(_checkoutNotifId);

    final localTimezone = tz.local;
    final now = tz.TZDateTime.now(localTimezone);

    var scheduled = tz.TZDateTime(
      localTimezone,
      now.year,
      now.month,
      now.day,
      17,
      0,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Reminds employees to check out at 5 PM',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Checkout Reminder',
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Try exact alarm first; fall back to inexact if permission is denied
    // (Android 12+ requires SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM).
    try {
      await _plugin.zonedSchedule(
        _checkoutNotifId,
        'Time to Check Out!',
        'Checkout window is open: 5:00 PM – 7:00 PM. Scan your face at the kiosk.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        _checkoutNotifId,
        'Time to Check Out!',
        'Checkout window is open: 5:00 PM – 7:00 PM. Scan your face at the kiosk.',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  /// Show an immediate test notification (useful to verify setup).
  Future<void> showTestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      9999,
      'Test Notification',
      'Notifications are working correctly.',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> cancelCheckoutReminder() =>
      _plugin.cancel(_checkoutNotifId);
}
