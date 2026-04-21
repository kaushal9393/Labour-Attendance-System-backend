import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl:        AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 60),
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
          // Token expired — clear and redirect
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(AppConstants.keyToken);
        }
        handler.next(error);
      },
    ));
  }

  // ── Auth ────────────────────────────────────────────────────
  Future<Response> login(Map<String, dynamic> body) =>
      _dio.post('/auth/login', data: body);

  // ── Employees ───────────────────────────────────────────────
  Future<Response> getEmployees() => _dio.get('/employees');

  Future<Response> registerEmployee(Map<String, dynamic> body) {
    // Compress every photo to max 480x480 @ 75% JPEG before upload
    if (body['photos'] is List) {
      final raw = (body['photos'] as List).cast<String>();
      body = Map<String, dynamic>.from(body);
      body['photos'] = raw.map(_compressBase64Photo).toList();
    }
    return _dio.post('/employees/register', data: body);
  }

  static String _compressBase64Photo(String b64) {
    try {
      final bytes = base64Decode(b64);
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return b64;
      // Skip if already smaller than target
      final needsResize = decoded.width > 480 || decoded.height > 480;
      final resized = needsResize
          ? img.copyResize(decoded, width: 480, height: 480)
          : decoded;
      final jpeg = img.encodeJpg(resized, quality: 75);
      return base64Encode(jpeg);
    } catch (_) {
      return b64;
    }
  }

  Future<Response> updateEmployee(int id, Map<String, dynamic> body) =>
      _dio.put('/employees/$id', data: body);

  Future<Response> deleteEmployee(int id) => _dio.delete('/employees/$id');

  // ── Attendance ──────────────────────────────────────────────
  Future<Response> scanFace(String base64Image, String companyCode) =>
      _dio.post('/attendance/scan', data: {'image': base64Image, 'company_code': companyCode});

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
