import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../core/constants.dart';

class AuthState {
  final bool   isLoading;
  final bool   isLoggedIn;
  final String? error;
  final String? token;
  final String? adminName;
  final String? companyCode;
  final String? companyName;
  final String? plan;

  const AuthState({
    this.isLoading = false,
    this.isLoggedIn = false,
    this.error,
    this.token,
    this.adminName,
    this.companyCode,
    this.companyName,
    this.plan,
  });

  AuthState copyWith({
    bool? isLoading, bool? isLoggedIn,
    Object? error = _keep,
    String? token, String? adminName,
    String? companyCode, String? companyName, String? plan,
  }) => AuthState(
    isLoading:   isLoading   ?? this.isLoading,
    isLoggedIn:  isLoggedIn  ?? this.isLoggedIn,
    error:       error == _keep ? this.error : error as String?,
    token:       token       ?? this.token,
    adminName:   adminName   ?? this.adminName,
    companyCode: companyCode ?? this.companyCode,
    companyName: companyName ?? this.companyName,
    plan:        plan        ?? this.plan,
  );
}

const Object _keep = Object();

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(AppConstants.keyToken);
    if (token == null) return;
    state = state.copyWith(
      isLoggedIn:  true,
      token:       token,
      adminName:   prefs.getString(AppConstants.keyAdminName),
      companyCode: prefs.getString(AppConstants.keyCompanyCode),
      companyName: prefs.getString(AppConstants.keyCompanyName),
      plan:        prefs.getString(AppConstants.keyPlan),
    );
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiService().login({
        'email': email,
        'password': password,
      });
      await _persistAuth(response.data as Map<String, dynamic>);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<bool> signup({
    required String businessName,
    required String companyCode,
    required String ownerName,
    required String email,
    required String phone,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiService().signup({
        'business_name': businessName,
        'company_code':  companyCode,
        'owner_name':    ownerName,
        'email':         email,
        'phone':         phone,
        'password':      password,
      });
      await _persistAuth(response.data as Map<String, dynamic>);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> _persistAuth(Map<String, dynamic> data) async {
    final token       = data['token']        as String;
    final name        = data['admin_name']   as String;
    final companyId   = data['company_id']   as int;
    final companyCode = data['company_code'] as String;
    final companyName = data['company_name'] as String;
    final plan        = (data['plan'] ?? 'free').toString();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyToken,       token);
    await prefs.setString(AppConstants.keyAdminName,   name);
    await prefs.setInt(   AppConstants.keyCompanyId,   companyId);
    await prefs.setString(AppConstants.keyCompanyCode, companyCode);
    await prefs.setString(AppConstants.keyCompanyName, companyName);
    await prefs.setString(AppConstants.keyPlan,        plan);
    await prefs.setString(AppConstants.keyMode,        AppConstants.modeAdmin);

    state = state.copyWith(
      isLoading:   false,
      isLoggedIn:  true,
      token:       token,
      adminName:   name,
      companyCode: companyCode,
      companyName: companyName,
      plan:        plan,
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyToken);
    await prefs.remove(AppConstants.keyAdminName);
    await prefs.remove(AppConstants.keyCompanyCode);
    await prefs.remove(AppConstants.keyCompanyName);
    await prefs.remove(AppConstants.keyPlan);
    state = const AuthState();
  }

  String _parseError(dynamic e) {
    final response = (e as dynamic).response;
    if (response != null) {
      final detail = response.data;
      if (detail is Map) return detail['detail']?.toString() ?? 'Request failed';
      return detail?.toString() ?? 'Request failed';
    }
    final msg = e?.message?.toString() ?? '';
    if (msg.contains('SocketException') || msg.contains('connection') || msg.contains('Connect')) {
      return 'Cannot reach server. Check your network.';
    }
    return 'Network error. Please try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
