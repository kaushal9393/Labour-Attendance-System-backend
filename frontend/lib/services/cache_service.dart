import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<void> save(String key, dynamic data) async {
    await init();
    await _prefs!.setString(key, jsonEncode(data));
  }

  static Future<dynamic> get(String key) async {
    await init();
    final raw = _prefs!.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    await init();
    await _prefs!.remove(key);
  }

  static Future<void> clear() async {
    await init();
    await _prefs!.clear();
  }
}
