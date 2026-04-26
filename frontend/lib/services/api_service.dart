import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

// Top-level function required by compute() — runs in a separate isolate
List<String> _compressPhotosIsolate(List<String> photos) {
  return photos.map((b64) {
    try {
      final bytes   = base64Decode(b64);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return b64;
      final needsResize = decoded.width > 320 || decoded.height > 320;
      final resized = needsResize
          ? img.copyResize(decoded, width: 320, height: 320)
          : decoded;
      return base64Encode(img.encodeJpg(resized, quality: 60));
    } catch (_) {
      return b64;
    }
  }).toList();
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl:        AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout:    const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString(AppConstants.keyToken);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(AppConstants.keyToken);
        }
        handler.next(error);
      },
    ));

    // Fire-and-forget: wake Railway backend so first real request is fast
    Future.microtask(warmupBackend);
  }

  /// Ping the backend to wake a cold Railway instance.
  Future<void> warmupBackend() async {
    try {
      await _dio.get('/ping',
          options: Options(receiveTimeout: const Duration(seconds: 15)));
    } catch (_) {}
  }

  /// Prefetch common data into device cache at startup.
  static Future<void> prefetchAll() async {
    try {
      final api = ApiService();
      await Future.wait([
        api.getEmployees(),
        api.getTodayAttendance(),
      ]);
    } catch (_) {}
  }

  // ── Auth ────────────────────────────────────────────────────
  Future<Response> login(Map<String, dynamic> body) =>
      _dio.post('/auth/login', data: body);

  // ── Employees ───────────────────────────────────────────────
  Future<Response> getEmployees() => _dio.get('/employees');

  Future<Response> registerEmployee(Map<String, dynamic> body) async {
    if (body['photos'] is List) {
      final raw = (body['photos'] as List).cast<String>();
      body = Map<String, dynamic>.from(body);
      final compressed = await compute(_compressPhotosIsolate, raw);
      // Cast explicitly — compute() returns List<dynamic> across isolate boundary
      body['photos'] = List<String>.from(compressed);
    }
    // Encode as JSON string explicitly so Dio does not re-encode nested lists
    return _dio.post(
      '/employees/register',
      data: jsonEncode(body),
      options: Options(
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 120),
        contentType: 'application/json',
      ),
    );
  }

  Future<Response> updateEmployee(int id, Map<String, dynamic> body) =>
      _dio.put('/employees/$id', data: body);

  Future<Response> deleteEmployee(int id) => _dio.delete('/employees/$id');

  // ── Attendance ──────────────────────────────────────────────
  Future<Response> scanFace(String base64Image, String companyCode) =>
      _dio.post('/attendance/scan',
          data: {'image': base64Image, 'company_code': companyCode});

  Future<Response> getTodayAttendance() => _dio.get('/attendance/today');

  Future<Response> manualCheckout({
    required int employeeId,
    required DateTime attendanceDate,
    DateTime? checkoutTime,
  }) =>
      _dio.post('/attendance/manual-checkout', data: {
        'employee_id': employeeId,
        'attendance_date': attendanceDate.toIso8601String().substring(0, 10),
        if (checkoutTime != null) 'checkout_time': checkoutTime.toIso8601String(),
      });

  Future<Response> getMonthlyAttendance({
    required int employeeId,
    required int month,
    required int year,
  }) =>
      _dio.get('/attendance/monthly', queryParameters: {
        'employee_id': employeeId,
        'month': month,
        'year': year,
      });

  // ── Salary ──────────────────────────────────────────────────
  Future<Response> getMonthlySalary({
    required int employeeId,
    required int month,
    required int year,
  }) =>
      _dio.get('/salary/monthly', queryParameters: {
        'employee_id': employeeId,
        'month': month,
        'year': year,
      });

  // ── Reports ─────────────────────────────────────────────────
  Future<Response> getMonthlySummary({required int month, required int year}) =>
      _dio.get('/reports/monthly-summary', queryParameters: {
        'month': month,
        'year': year,
      });

  // ── Settings ─────────────────────────────────────────────────
  Future<Response> getSettings() => _dio.get('/settings');

  Future<Response> updateSettings(Map<String, dynamic> body) =>
      _dio.put('/settings', data: body);

  // ── Notifications ─────────────────────────────────────────────
  Future<Response> getNotifications() => _dio.get('/notifications');
}
