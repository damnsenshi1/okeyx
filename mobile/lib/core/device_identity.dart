import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  static const _key = 'okeyx_install_id_v1';
  static String? _cached;

  static Future<String> get() async {
    final cached = _cached;
    if (cached != null && cached.isNotEmpty) return cached;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    final id = 'and-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    await prefs.setString(_key, id);
    _cached = id;
    return id;
  }
}
