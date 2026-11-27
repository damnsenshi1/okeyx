import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ApiEndpoint {
  static const _key = 'okeyx_api_base_url';
  static String _baseUrl = AppConfig.apiBaseUrl;

  static String get baseUrl => _baseUrl;
  static bool get isCustom => _baseUrl != AppConfig.apiBaseUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final compiled = _normalize(AppConfig.apiBaseUrl);
    // Multiplayer/release builds inject API_BASE_URL at compile time. A URL
    // saved by an older APK must never silently override that build target;
    // this was sending Store/Social/Game calls to dead Quick-Tunnel addresses.
    if (_isPinnedCompiled(compiled)) {
      _baseUrl = compiled;
      if (prefs.getString(_key) != compiled) await prefs.setString(_key, compiled);
      return;
    }
    final saved = prefs.getString(_key)?.trim() ?? '';
    _baseUrl = saved.isNotEmpty && _valid(saved) ? _normalize(saved) : compiled;
  }

  static bool _isPinnedCompiled(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return false;
    return uri.host != '127.0.0.1' && uri.host != 'localhost' && uri.host != '10.0.2.2';
  }

  static Future<void> set(String value) async {
    final normalized = _normalize(value);
    if (!_valid(normalized)) throw const FormatException('invalid_server_url');
    _baseUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalized);
  }

  static Future<bool> setCustom(String value) async {
    try {
      await set(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Prefer a production endpoint only when it is actually healthy. This lets
  /// release APKs use the pinned production endpoint while local test builds keep their
  /// compile-time endpoint if production is temporarily unavailable.
  static Future<bool> probeAndSet(
    String value, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final normalized = _normalize(value);
    if (!_valid(normalized)) return false;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final health = Uri.parse('$normalized/healthz');
      final request = await client.getUrl(health).timeout(timeout);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      await set(normalized);
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> reset() async {
    _baseUrl = AppConfig.apiBaseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static String _normalize(String value) {
    // Quick-Tunnel URL files written by older Windows PowerShell builds could
    // carry a UTF-8 BOM (or its OEM-console mojibake) into --dart-define.
    // Strip every prefix before the first real http(s) scheme so Store, Social
    // and Game never silently use a malformed/stale endpoint.
    var out = value.replaceAll('\uFEFF', '').trim();
    final httpIndex = out.indexOf('http://');
    final httpsIndex = out.indexOf('https://');
    final indexes = <int>[if (httpIndex >= 0) httpIndex, if (httpsIndex >= 0) httpsIndex];
    if (indexes.isNotEmpty) {
      indexes.sort();
      out = out.substring(indexes.first);
    }
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    if (!out.contains('://')) {
      out = 'https://$out';
    }
    return out;
  }

  static bool _valid(String value) {
    try {
      final uri = Uri.parse(_normalize(value));
      return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
