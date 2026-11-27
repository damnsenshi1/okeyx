import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'api_endpoint.dart';

class OkeyXRadioStation {
  final String id, title, source;
  final bool remote;
  final String metadataUrl;
  const OkeyXRadioStation(this.id, this.title, this.source, {this.remote = true, this.metadataUrl = ''});
  factory OkeyXRadioStation.from(Map<String, dynamic> json) {
    final url = '${json['url'] ?? ''}'.trim();
    final asset = '${json['asset'] ?? ''}'.trim();
    return OkeyXRadioStation(
      '${json['id'] ?? ''}',
      '${json['title'] ?? 'Radyo'}',
      url.isNotEmpty ? url : asset,
      remote: url.isNotEmpty,
      metadataUrl: '${json['metadata_url'] ?? ''}'.trim(),
    );
  }
}

const _officialTurkishRadioFallback = <OkeyXRadioStation>[
  OkeyXRadioStation('kral_pop', 'Kral Pop', 'https://dygedge.radyotvonline.net/kralpop/playlist.m3u8', metadataUrl: 'https://www.kralmuzik.com.tr/radyo/kral-pop'),
  OkeyXRadioStation('kral_fm', 'Kral FM', 'https://dygedge2.radyotvonline.net/kralfm/playlist.m3u8', metadataUrl: 'https://www.kralmuzik.com.tr/radyo/kral-fm'),
  OkeyXRadioStation('power_fm', 'Power FM', 'https://listen.powerapp.com.tr/powerfm/mpeg/icecast.audio', metadataUrl: 'https://www.powerapp.com.tr/radios/powerfm/'),
  OkeyXRadioStation('power_turk', 'PowerTürk', 'https://listen.powerapp.com.tr/powerturk/abr/powerturk/128/playlist.m3u8', metadataUrl: 'https://www.powerapp.com.tr/radios/powerturk/'),
  OkeyXRadioStation('metro_fm', 'Metro FM', 'https://17773.live.streamtheworld.com/METRO_FM128AAC.aac', metadataUrl: 'https://metrofm.com.tr/frekanslar'),
  OkeyXRadioStation('fenomen', 'Radyo Fenomen', 'https://live.radyofenomen.com/fenomen/abr/playlist.m3u8', metadataUrl: 'https://www.radyofenomen.com/'),
];

class OkeyXLiveFeatures {
  final bool chanceHallEnabled, radioEnabled, musicKitsEnabled, animatedGiftsEnabled;
  final List<OkeyXRadioStation> radioStations;
  const OkeyXLiveFeatures({
    this.chanceHallEnabled = true,
    this.radioEnabled = true,
    this.musicKitsEnabled = true,
    this.animatedGiftsEnabled = true,
    this.radioStations = _officialTurkishRadioFallback,
  });

  OkeyXRadioStation station(String id) => radioStations.firstWhere(
        (e) => e.id == id,
        orElse: () => radioStations.first,
      );
}

class LiveFeatureService {
  Future<OkeyXLiveFeatures> load() async {
    if (!AppConfig.hasSupabase) return const OkeyXLiveFeatures();
    try {
      final client = Supabase.instance.client;
      Future<Map<String, dynamic>?> flag(String key) async {
        final row = await client
            .from('okeyx_feature_flags')
            .select('enabled,store_build_enabled,config')
            .eq('key', key)
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
      }

      final rows = await Future.wait([
        flag('chance_hall'),
        flag('radio'),
        flag('music_kits'),
        flag('animated_gifts'),
      ]);
      bool on(Map<String, dynamic>? row) =>
          row == null ? true : row['enabled'] == true && row['store_build_enabled'] != false;
      final rawConfig = rows[1]?['config'];
      final config = rawConfig is Map ? Map<String, dynamic>.from(rawConfig) : <String, dynamic>{};
      final rawStations = config['stations'];
      final stations = rawStations is List
          ? rawStations
              .whereType<Map>()
              .map((x) => OkeyXRadioStation.from(Map<String, dynamic>.from(x)))
              .where((x) => x.id.isNotEmpty && x.source.isNotEmpty)
              .toList()
          : <OkeyXRadioStation>[];
      return OkeyXLiveFeatures(
        chanceHallEnabled: on(rows[0]),
        radioEnabled: on(rows[1]),
        musicKitsEnabled: on(rows[2]),
        animatedGiftsEnabled: on(rows[3]),
        radioStations: stations.isEmpty ? _officialTurkishRadioFallback : stations,
      );
    } catch (_) {
      return const OkeyXLiveFeatures();
    }
  }
}


class OkeyXNowPlaying {
  final String artist, title;
  const OkeyXNowPlaying(this.artist, this.title);
  bool get available => artist.isNotEmpty || title.isNotEmpty;
  String get label => [artist, title].where((x) => x.trim().isNotEmpty).join(' • ');
}

class RadioNowPlayingService {
  static final Map<String, OkeyXNowPlaying> _cache = {};
  static final Map<String, DateTime> _cacheAt = {};

  static Future<OkeyXNowPlaying> fetch(OkeyXRadioStation station) async {
    final cached = _cache[station.id];
    final at = _cacheAt[station.id];
    if (cached != null && at != null && DateTime.now().difference(at) < const Duration(seconds: 12)) return cached;

    // Prefer our API proxy. Kral pages are server-rendered but Android-side direct
    // requests can get a different/partial response; the proxy normalizes it.
    final proxy = Uri.parse(ApiEndpoint.baseUrl).replace(
      path: '/api/radio/now-playing',
      queryParameters: {'station': station.id},
    );
    final apiClient = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await apiClient.getUrl(proxy).timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 5));
        final json = jsonDecode(body);
        if (json is Map) {
          final value = OkeyXNowPlaying('${json['artist'] ?? ''}'.trim(), '${json['title'] ?? ''}'.trim());
          if (value.available) {
            _cache[station.id] = value;
            _cacheAt[station.id] = DateTime.now();
            return value;
          }
        }
      }
    } catch (_) {
      // Fall through to direct page parsing; radio audio must never be blocked.
    } finally {
      apiClient.close(force: true);
    }

    final url = station.metadataUrl.trim();
    if (url.isEmpty) return cached ?? const OkeyXNowPlaying('', '');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 3));
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 11) OkeyX/15.0.0');
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml');
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode < 200 || res.statusCode >= 300) return cached ?? const OkeyXNowPlaying('', '');
      final html = await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 5));
      String clean(String x) => x
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"')
          .replaceAll(RegExp(r'\s+'), ' ').trim();
      final pair = RegExp(r'<h2[^>]*>(.*?)</h2>\s*<h3[^>]*>(.*?)</h3>', caseSensitive: false, dotAll: true).firstMatch(html);
      final value = OkeyXNowPlaying(clean(pair?.group(1) ?? ''), clean(pair?.group(2) ?? ''));
      if (value.available) {
        _cache[station.id] = value;
        _cacheAt[station.id] = DateTime.now();
      }
      return value.available ? value : (cached ?? value);
    } catch (_) {
      return cached ?? const OkeyXNowPlaying('', '');
    } finally {
      client.close(force: true);
    }
  }
}
