import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


import 'core/theme.dart';
import 'core/router.dart';
import 'services/api_service.dart';
import 'services/cache_service.dart';
import 'services/notification_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackground(RemoteMessage message) async {
  // Handle background FCM messages
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait by default (can be landscape on tablet)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Firebase
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackground);
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: true, badge: true, sound: true,
    );
  } catch (_) {
    // Firebase not configured yet — app still works
  }

  // Init cache, API service, and local notifications
  await CacheService.init();
  ApiService().init();
  try {
    await NotificationService().init();
  } catch (_) {
    // Notification setup failed (e.g. exact alarm permission denied) — app still works
  }

  // Prefetch common data in background — don't await
  ApiService.prefetchAll();

  runApp(const ProviderScope(child: GarageAttendanceApp()));
}

class GarageAttendanceApp extends ConsumerWidget {
  const GarageAttendanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Garage Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
