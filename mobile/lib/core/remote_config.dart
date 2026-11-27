import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

class MobileRemoteConfig {
  final bool maintenance;
  final int minimumBuild;
  final bool googleEnabled;
  final bool facebookEnabled;
  final bool appleEnabled;
  final int vipMaxLevel;
  final String apiBaseUrl;
  final List<String> loadingTips;

  const MobileRemoteConfig({
    this.maintenance = false,
    this.minimumBuild = 17,
    this.googleEnabled = true,
    this.facebookEnabled = false,
    this.appleEnabled = false,
    this.vipMaxLevel = 200,
    this.apiBaseUrl = '',
    this.loadingTips = const [
      'Günün ipucu: Çifte giderken ıstakandaki taş çeşidine dikkat et.',
      'Göstergeyi ve son atılan taşları takip etmek oyunun yarısıdır.',
      'Misafir hesabını bağlayarak ilerlemeni güvenceye al.',
    ],
  });

  bool get updateRequired => AppConfig.buildNumber < minimumBuild;

  factory MobileRemoteConfig.fromJson(Map<String, dynamic> json) {
    final rawTips = json['loading_tips'];
    final tips = rawTips is List
        ? rawTips.map((item) => '$item'.trim()).where((item) => item.isNotEmpty).toList()
        : const <String>[];
    return MobileRemoteConfig(
      maintenance: json['maintenance'] == true,
      minimumBuild: (json['minimum_build'] as num?)?.toInt() ?? 17,
      googleEnabled: json['google_enabled'] != false,
      facebookEnabled: json['facebook_enabled'] == true,
      appleEnabled: json['apple_enabled'] == true,
      vipMaxLevel: (json['vip_max_level'] as num?)?.toInt() ?? 200,
      apiBaseUrl: '${json['api_base_url'] ?? ''}'.trim(),
      loadingTips: tips.isEmpty ? const MobileRemoteConfig().loadingTips : tips,
    );
  }
}

class RemoteConfigService {
  Future<MobileRemoteConfig> load() async {
    if (!AppConfig.hasSupabase) return const MobileRemoteConfig();
    try {
      final row = await Supabase.instance.client
          .from('okeyx_feature_flags')
          .select('enabled, config')
          .eq('key', 'mobile_foundation')
          .maybeSingle();
      if (row == null || row['enabled'] != true) return const MobileRemoteConfig();
      final config = row['config'];
      return MobileRemoteConfig.fromJson(
        config is Map<String, dynamic> ? config : Map<String, dynamic>.from(config as Map),
      );
    } catch (_) {
      return const MobileRemoteConfig();
    }
  }
}
