import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../models/employee.dart';

final employeesProvider = FutureProvider.autoDispose<List<Employee>>((ref) async {
  // Show cached data instantly, then Riverpod will reuse fresh data on next watch
  final cached = await CacheService.get('employees_list');
  if (cached != null) {
    // Kick off background refresh without blocking
    Future(() async {
      try {
        final response = await ApiService().getEmployees();
        await CacheService.save('employees_list', response.data);
        ref.invalidateSelf();
      } catch (_) {}
    });
    return (cached as List).map((e) => Employee.fromJson(e)).toList();
  }

  final response = await ApiService().getEmployees();
  await CacheService.save('employees_list', response.data);
  return (response.data as List).map((e) => Employee.fromJson(e)).toList();
});
