import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_endpoint.dart';
import 'config.dart';

/// Çökme/hata raporlayıcı: Firebase Crashlytics gerektirmeden hataları kendi
/// sunucumuza (/api/telemetry/crash) gönderir. Aynı hata tekrar tekrar
/// gönderilmez; ağ hatası oyunu asla etkilemez.
abstract final class CrashReporter {
  static String? playerId;
  static final Set<String> _sent = <String>{};
  static int _count = 0;

  static void report(Object error, StackTrace? stack, {bool fatal = false, String context = ''}) {
    final text = '$error';
    final key = '${text.length > 160 ? text.substring(0, 160) : text}|$context';
    if (_sent.contains(key) || _count >= 20) return;
    _sent.add(key);
    _count++;
    unawaited(_send(text, '${stack ?? ''}', fatal, context));
  }

  static Future<void> _send(String error, String stack, bool fatal, String context) async {
    HttpClient? http;
    try {
      http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final base = Uri.parse(ApiEndpoint.baseUrl);
      final req = await http.postUrl(base.replace(path: '/api/telemetry/crash'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'player_id': playerId,
        'app_version': '${AppConfig.versionName}+${AppConfig.buildNumber}',
        'platform': Platform.operatingSystem,
        'device': Platform.operatingSystemVersion.length > 78
            ? Platform.operatingSystemVersion.substring(0, 78)
            : Platform.operatingSystemVersion,
        'error': error.length > 590 ? error.substring(0, 590) : error,
        'stack': stack.length > 5900 ? stack.substring(0, 5900) : stack,
        'fatal': fatal,
        'context': context.length > 110 ? context.substring(0, 110) : context,
      }));
      final res = await req.close().timeout(const Duration(seconds: 6));
      await res.drain<void>();
    } catch (_) {
      // Rapor gönderilemezse sessizce geç.
    } finally {
      http?.close(force: true);
    }
  }
}
