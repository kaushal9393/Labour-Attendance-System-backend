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

  const AuthState({
    this.isLoading = false,
    this.isLoggedIn = false,
    this.error,
    this.token,
    this.adminName,
  });

  AuthState copyWith({
    bool? isLoading, bool? isLoggedIn,
    Object? error = _keep,
    String? token, String? adminName,
  }) => AuthState(
    isLoading:  isLoading  ?? this.isLoading,
    isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    error:      error == _keep ? this.error : error as String?,
    token:      token      ?? this.token,
    adminName:  adminName  ?? this.adminName,
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
    final name  = prefs.getString(AppConstants.keyAdminName);
    if (token != null) {
      state = state.copyWith(isLoggedIn: true, token: token, adminName: name);
    }
  }

  Future<bool> login({
    required String companyCode,
    required String email,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await ApiService().login({
        'company_code': companyCode,
        'email': email,
        'password': password,
      });
      final data = response.data as Map<String, dynamic>;
      final token = data['token'] as String;
      final name  = data['admin_name'] as String;
      final companyId = data['company_id'] as int;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyToken,     token);
      await prefs.setString(AppConstants.keyAdminName, name);
      await prefs.setInt(AppConstants.keyCompanyId,    companyId);
      await prefs.setString(AppConstants.keyMode,      AppConstants.modeAdmin);

      state = state.copyWith(isLoading: false, isLoggedIn: true, token: token, adminName: name);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _parseError(e));
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyToken);
    await prefs.remove(AppConstants.keyAdminName);
    state = const AuthState();
  }

  String _parseError(dynamic e) {
    final response = (e as dynamic).response;
    if (response != null) {
      final detail = response.data;
      if (detail is Map) return detail['detail']?.toString() ?? 'Login failed';
      return detail?.toString() ?? 'Login failed';
    }
    final msg = e?.message?.toString() ?? '';
    if (msg.contains('SocketException') || msg.contains('connection') || msg.contains('Connect')) {
      return 'Cannot reach server. Check your network and server URL.';
    }
    return 'Network error. Please try again.';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (_) => AuthNotifier(),
);
