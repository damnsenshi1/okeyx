import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config.dart';
import '../lobby/lobby_api.dart';

class AdService {
  static Future<void>? _init;

  static Future<void> initialize() => _init ??= MobileAds.instance.initialize().then((_) {});

  Future<Map<String, dynamic>> showRewarded(
    LobbyApiClient api, {
    String rewardKind = 'coins',
  }) async {
    await initialize();
    final session = await api.startAdSession(rewardKind);
    if (session['ok'] != true) return session;
    final token = '${session['token'] ?? ''}';
    if (token.isEmpty) return {'ok': false, 'code': 'ad_session_missing'};

    final completer = Completer<Map<String, dynamic>>();
    RewardedAd.load(
      adUnitId: AppConfig.admobRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          var earned = false;
          // AdMob sunucu doğrulaması: Google, ödülü bu token ile sunucumuza imzalı bildirir.
          ad.setServerSideOptions(ServerSideVerificationOptions(userId: api.profile.userId, customData: token));
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!earned && !completer.isCompleted) {
                completer.complete({'ok': false, 'code': 'ad_not_completed'});
              }
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete({'ok': false, 'code': 'ad_show_failed', 'detail': '$error'});
            },
          );
          ad.show(onUserEarnedReward: (_, __) async {
            earned = true;
            try {
              var out = await api.claimAdReward(token);
              // SSV açıksa Google'ın geri çağrısı birkaç saniye gecikebilir.
              for (var i = 0; i < 5 && out['code'] == 'ad_not_verified_yet'; i++) {
                await Future<void>.delayed(const Duration(seconds: 3));
                out = await api.claimAdReward(token);
              }
              if (!completer.isCompleted) completer.complete(out);
            } catch (error) {
              if (!completer.isCompleted) completer.complete({'ok': false, 'code': 'ad_claim_failed', 'detail': '$error'});
            }
          });
        },
        onAdFailedToLoad: (error) {
          if (!completer.isCompleted) completer.complete({'ok': false, 'code': 'ad_load_failed', 'detail': '$error'});
        },
      ),
    );
    return completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => {'ok': false, 'code': 'ad_timeout'},
    );
  }

  Future<bool> showInterstitial() async {
    await initialize();
    final completer = Completer<bool>();
    InterstitialAd.load(
      adUnitId: AppConfig.admobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(true);
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete(false);
            },
          );
          ad.show();
        },
        onAdFailedToLoad: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(const Duration(seconds: 30), onTimeout: () => false);
  }
}
