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
      final needsResize = decoded.width > 480 || decoded.height > 480;
      final resized = needsResize
          ? img.copyResize(decoded, width: 480, height: 480)
          : decoded;
      return base64Encode(img.encodeJpg(resized, quality: 75));
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
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
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

  /// Ping the backend health endpoint to wake a cold Railway instance.
  Future<void> warmupBackend() async {
    try {
      await _dio.get('/health',
          options: Options(receiveTimeout: const Duration(seconds: 15)));
    } catch (_) {
      // Ignore errors — best-effort warmup
    }
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
      // Compress all photos off the main thread in a single isolate
      body['photos'] = await compute(_compressPhotosIsolate, raw);
    }
    return _dio.post('/employees/register', data: body);
  }

  Future<Response> updateEmployee(int id, Map<String, dynamic> body) =>
      _dio.put('/employees/$id', data: body);

  Future<Response> deleteEmployee(int id) => _dio.delete('/employees/$id');

  // ── Attendance ──────────────────────────────────────────────
  Future<Response> scanFace(String base64Image, String companyCode) =>
      _dio.post('/attendance/scan',
          data: {'image': base64Image, 'company_code': companyCode});

  Future<Response> getTodayAttendance() => _dio.get('/attendance/today');

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
}
