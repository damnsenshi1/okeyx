import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';

class AuthService {
  static const mobileAuthCallback = 'okeyx://auth/callback';
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser =>
      AppConfig.hasSupabase ? _client.auth.currentUser : null;

  bool isAnonymous(User? user) {
    if (user == null) return false;
    final json = user.toJson();
    final identities = json['identities'];
    return json['is_anonymous'] == true ||
        (user.email == null && identities is List && identities.isEmpty);
  }

  Future<void> signInAnonymously() async {
    _requireSupabase();
    await _client.auth.signInAnonymously(
      data: {'source': 'android_mobile', 'app_version': AppConfig.versionName},
    );
  }

  Future<void> signInWithEmail(String email, String password) async {
    _requireSupabase();
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUpWithEmail(
    String email,
    String password,
    String name,
  ) async {
    _requireSupabase();
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: mobileAuthCallback,
      data: {'display_name': name.trim(), 'source': 'android_mobile'},
    );
  }

  Future<void> resetPassword(String email) async {
    _requireSupabase();
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: mobileAuthCallback,
    );
  }

  Future<void> signInWithGoogle({bool linkCurrentUser = false}) async {
    _requireSupabase();
    if (linkCurrentUser) {
      await _client.auth.linkIdentity(
        OAuthProvider.google,
        redirectTo: mobileAuthCallback,
        queryParams: const {'prompt': 'select_account'},
      );
      return;
    }
    // Uygulama içi Google penceresi: tarayıcıya çıkmaz, ekran yatay kalır.
    if (AppConfig.googleWebClientId.isNotEmpty) {
      final google = GoogleSignIn(serverClientId: AppConfig.googleWebClientId, scopes: const ['email', 'profile']);
      try {
        await google.signOut();
      } catch (_) {}
      GoogleSignInAccount? account;
      try {
        account = await google.signIn();
      } catch (e) {
        // Yerel giriş yapılandırması bozuksa (SHA-1 / istemci) tarayıcı yoluna düş.
        debugPrint('OKEYX_GOOGLE_NATIVE_FAIL: $e');
        return _googleBrowser();
      }
      if (account == null) throw StateError('google_cancelled');
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return _googleBrowser();
      try {
        await _client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken, accessToken: auth.accessToken);
      } catch (e) {
        debugPrint('OKEYX_GOOGLE_IDTOKEN_FAIL: $e');
        return _googleBrowser();
      }
      return;
    }
    return _googleBrowser();
  }

  Future<void> _googleBrowser() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: mobileAuthCallback,
      queryParams: const {'prompt': 'select_account'},
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!launched) throw StateError('oauth_browser_not_opened');
  }

  Future<void> signInWithFacebook() async {
    _requireSupabase();
    await _client.auth.signInWithOAuth(
      OAuthProvider.facebook,
      redirectTo: mobileAuthCallback,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> signInWithApple() async {
    _requireSupabase();
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: mobileAuthCallback,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  Future<void> attachEmail(String email) async {
    _requireSupabase();
    await _client.auth.updateUser(
      UserAttributes(email: email.trim()),
      emailRedirectTo: mobileAuthCallback,
    );
  }

  Future<void> setPassword(String password) async {
    _requireSupabase();
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  Future<void> signOut() async {
    if (AppConfig.hasSupabase) await _client.auth.signOut();
  }

  Future<void> deleteAccount() async {
    _requireSupabase();
    final response = await _client.functions.invoke('delete-account');
    if (response.status < 200 || response.status >= 300) {
      throw StateError('account_delete_failed_${response.status}');
    }
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  void _requireSupabase() {
    if (!AppConfig.hasSupabase) throw StateError('supabase_not_configured');
  }
}
