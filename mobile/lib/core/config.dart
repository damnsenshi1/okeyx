class AppConfig {
  static const appName = 'OkeyX';
  static const versionName = '18.0.0';
  static const buildNumber = 170;
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const admobRewardedId = String.fromEnvironment('ADMOB_REWARDED_ID', defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  static const admobInterstitialId = String.fromEnvironment('ADMOB_INTERSTITIAL_ID', defaultValue: 'ca-app-pub-3940256099942544/1033173712');
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://okeyx-mp-eu.onrender.com',
  );

  static bool get hasSupabase =>
      supabaseUrl.startsWith('https://') &&
      supabaseUrl.contains('.supabase.co') &&
      supabaseAnonKey.isNotEmpty;
}
