import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

abstract final class Telemetry {
  static void track(String eventName, {Map<String, dynamic> properties = const {}}) {
    if (!AppConfig.hasSupabase) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    unawaited(_send(client, user.id, eventName, properties));
  }

  static Future<void> _send(
    SupabaseClient client,
    String userId,
    String eventName,
    Map<String, dynamic> properties,
  ) async {
    try {
      await client.from('okeyx_client_events').insert({
        'auth_user_id': userId,
        'event_name': eventName,
        'app_version': AppConfig.versionName,
        'build_number': AppConfig.buildNumber,
        'platform': 'android',
        'properties': properties,
      });
    } catch (_) {
      // Telemetry oyun akışını hiçbir zaman durdurmaz.
    }
  }
}
