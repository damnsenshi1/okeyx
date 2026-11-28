class AppConfig {
  static const appName = 'OkeyX';
  static const versionName = String.fromEnvironment('OKEYX_VERSION', defaultValue: '20.8.5');
  static const buildNumber = int.fromEnvironment('OKEYX_BUILD', defaultValue: 285);
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  /// Google Cloud'daki "Web application" OAuth istemci kimliği (gizli değil).
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
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
