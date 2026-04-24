import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../models/attendance.dart';

final todayAttendanceProvider = FutureProvider.autoDispose<TodayAttendance>((ref) async {
  const cacheKey = 'today_attendance';
  final cached = await CacheService.get(cacheKey);
  if (cached != null) {
    // Background refresh
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

final monthlyAttendanceProvider = FutureProvider.autoDispose
    .family<List<dynamic>, Map<String, int>>((ref, params) async {
  final response = await ApiService().getMonthlyAttendance(
    employeeId: params['employee_id']!,
    month:      params['month']!,
    year:       params['year']!,
  );
  return response.data as List;
});
