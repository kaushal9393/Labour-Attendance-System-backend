import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../models/attendance.dart';

// No autoDispose — stays alive across tab switches
final todayAttendanceProvider = FutureProvider<TodayAttendance>((ref) async {
  const cacheKey = 'today_attendance';
  final cached = await CacheService.get(cacheKey);
  if (cached != null) {
    // Background refresh without blocking UI
    Future(() async {
      try {
        final response = await ApiService().getTodayAttendance();
        await CacheService.save(cacheKey, response.data);
        ref.invalidateSelf();
      } catch (_) {}
    });
    return TodayAttendance.fromJson(cached);
  }

  final response = await ApiService().getTodayAttendance();
  await CacheService.save(cacheKey, response.data);
  return TodayAttendance.fromJson(response.data);
});

// Monthly attendance — cache per employee+month key
final monthlyAttendanceProvider = FutureProvider
    .family<List<dynamic>, Map<String, int>>((ref, params) async {
  final cacheKey = 'monthly_att_${params['employee_id']}_${params['year']}_${params['month']}';
  final cached = await CacheService.get(cacheKey);
  if (cached != null) {
    // Background refresh
    Future(() async {
      try {
        final response = await ApiService().getMonthlyAttendance(
          employeeId: params['employee_id']!,
          month:      params['month']!,
          year:       params['year']!,
        );
        await CacheService.save(cacheKey, response.data);
        ref.invalidateSelf();
      } catch (_) {}
    });
    return cached as List;
  }

  final response = await ApiService().getMonthlyAttendance(
    employeeId: params['employee_id']!,
    month:      params['month']!,
    year:       params['year']!,
  );
  await CacheService.save(cacheKey, response.data);
  return response.data as List;
});
