import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../models/employee.dart';

class EmployeesNotifier extends StateNotifier<AsyncValue<List<Employee>>> {
  EmployeesNotifier() : super(const AsyncValue.loading()) {
    load();
  }

  // Track locally deleted IDs so API refresh never brings them back
  final Set<int> _deletedIds = {};

  Future<void> load() async {
    final cached = await CacheService.get('employees_list');
    if (cached != null) {
      final list = (cached as List)
          .map((e) => Employee.fromJson(e))
          .where((e) => e.status == 'active' && !_deletedIds.contains(e.id))
          .toList();
      state = AsyncValue.data(list);
    }

    try {
      final response = await ApiService().getEmployees();
      final activeOnly = (response.data as List)
          .where((e) => e['status'] == 'active' && !_deletedIds.contains(e['id']))
          .toList();
      await CacheService.save('employees_list', activeOnly);
      state = AsyncValue.data(
          activeOnly.map((e) => Employee.fromJson(e)).toList());
    } catch (e, st) {
      if (state is! AsyncData) state = AsyncValue.error(e, st);
    }
  }

  Future<void> deleteOptimistic(int employeeId) async {
    // Mark as deleted — survives any future load() calls
    _deletedIds.add(employeeId);

    // Remove from state immediately
    final current = state.valueOrNull ?? [];
    final updated = current.where((e) => e.id != employeeId).toList();
    state = AsyncValue.data(updated);

    // Update cache immediately
    await CacheService.save('employees_list',
      updated.map((e) => {
        'id':                e.id,
        'company_id':        e.companyId,
        'name':              e.name,
        'phone':             e.phone,
        'monthly_salary':    e.monthlyScalary,
        'joining_date':      e.joiningDate,
        'profile_photo_url': e.profilePhotoUrl,
        'status':            e.status,
      }).toList(),
    );

    // Call API in background — no restore on failure, _deletedIds keeps it gone
    ApiService().deleteEmployee(employeeId).catchError((e) => throw e);
  }
}

// No autoDispose — keeps data alive across tab switches, no redundant API calls
final employeesProvider =
    StateNotifierProvider<EmployeesNotifier, AsyncValue<List<Employee>>>(
  (_) => EmployeesNotifier(),
);
