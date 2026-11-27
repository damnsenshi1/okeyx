import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api_endpoint.dart';
import '../../core/device_identity.dart';
import '../auth/profile_repository.dart';

class LobbyApiException implements Exception {
  final String code;
  const LobbyApiException(this.code);
  @override
  String toString() => code;
}

class GameSession {
  final String roomId;
  final int seat;
  final String reconnectToken;
  final Map<String, dynamic> state;

  const GameSession({
    required this.roomId,
    required this.seat,
    required this.reconnectToken,
    required this.state,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
        roomId: '${json['room_id'] ?? ''}',
        seat: (json['seat'] as num?)?.toInt() ?? 0,
        reconnectToken: '${json['reconnect_token'] ?? ''}',
        state: _mapStatic(json['state']),
      );

  static Map<String, dynamic> _mapStatic(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}

class LobbyApiClient {
  final PlayerProfile profile;
  HttpClient? _http;
  String? accountToken;

  LobbyApiClient(this.profile) {
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  }

  bool get _localGameplay {
    final uri = Uri.tryParse(ApiEndpoint.baseUrl);
    if (uri == null) return false;
    final h = uri.host;
    if (h == '127.0.0.1' || h == 'localhost' || h == '10.0.2.2') return true;
    final parts = h.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((x) => x == null)) return false;
    final a = parts[0]!, b = parts[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  Future<Map<String, dynamic>> bootstrap() async {
    final deviceId = await DeviceIdentity.get();
    final Map<String, dynamic> out;
    if (_localGameplay) {
      // Option 2 is a developer gameplay build. Do not make entering a table
      // depend on an internet JWKS fetch; the local backend is already reached
      // through ADB reverse and validates this launcher-only secret.
      out = await _post(
        '/api/account/bootstrap-local',
        {
          'player_id': profile.userId,
          'name': profile.displayName,
          'avatar_url': profile.avatarUrl,
          'device_id': deviceId,
          'is_guest': profile.isGuest,
          'coins': profile.coins,
          'diamonds': profile.diamonds,
        },
        headers: const {'X-Local-Test-Secret': 'okeyx-local-playable-v1113'},
      );
    } else {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw const LobbyApiException('supabase_session_missing');
      out = await _post(
        '/api/account/bootstrap-supabase',
        {'name': profile.displayName, 'avatar_url': profile.avatarUrl, 'device_id': deviceId, 'is_guest': profile.isGuest},
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
    }
    final token = '${out['session_token'] ?? ''}';
    if (token.isEmpty) throw const LobbyApiException('account_session_missing');
    accountToken = token;
    // Oyun kapalıyken bildirim denetimi (Android arka plan işi) bu bilgileri okur.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('okx_bg_pid', profile.userId);
      await prefs.setString('okx_bg_token', token);
      await prefs.setString('okx_bg_api', ApiEndpoint.baseUrl);
    } catch (_) {}
    return out;
  }

  Future<Map<String, dynamic>> ensureBootstrap() async {
    if ((accountToken ?? '').isEmpty) return bootstrap();
    try {
      return await account();
    } on LobbyApiException catch (error) {
      // FastAPI's shared test runtime is intentionally restartable. A session
      // token cached by the Flutter process becomes stale after a backend
      // restart even though the Supabase login is still valid. Re-bootstrap
      // transparently instead of breaking Store/Friends/Pass with generic
      // service or FormatException-style errors.
      if (error.code.contains('invalid_account_token') || error.code.contains('account_not_found') || error.code == 'account_session_missing') {
        accountToken = null;
        return bootstrap();
      }
      rethrow;
    }
  }

  Map<String, String> get _socialHeaders {
    final headers = Map<String, String>.from(_authHeaders);
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null && session.accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    return headers;
  }

  Map<String, String> get _authHeaders {
    final token = accountToken;
    if (token == null || token.isEmpty) {
      throw const LobbyApiException('account_session_missing');
    }
    return {'X-Account-Token': token};
  }

  Future<Map<String, dynamic>> account() =>
      _get('/api/account/${profile.userId}', headers: _authHeaders);

  /// Uygulama açıkken ~30 sn'de bir çağrılır; arkadaş listesinde
  /// "Çevrimiçi / Lobide" durumunun gerçek olmasını sağlar.
  Future<void> presencePing() async {
    try {
      await _post('/api/account/${profile.userId}/presence', const <String, dynamic>{}, headers: _authHeaders);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> rooms() async {
    final out = await _get('/api/lobby/rooms');
    return _list(out['rooms']).map(_map).toList();
  }

  Future<List<Map<String, dynamic>>> liveTables() async {
    final out = await _get('/api/lobby/live-tables');
    return _list(out['tables']).map(_map).toList();
  }

  Future<Map<String, dynamic>> spectate(
    String roomId, {
    required String action,
    String value = '',
    int? toSeat,
  }) async {
    await ensureBootstrap();
    return _post('/api/game/$roomId/spectate', {
      'player_id': profile.userId,
      'account_token': accountToken,
      'action': action,
      'value': value,
      'to_seat': toSeat,
    });
  }

  Future<GameSession?> reconnect() async {
    await ensureBootstrap();
    final out = await _post('/api/game/reconnect', {
      'player_id': profile.userId,
      'account_token': accountToken,
    });
    if (out['ok'] != true) return null;
    return GameSession.fromJson(out);
  }

  Future<GameSession> quick({
    required bool turbo,
    required String variant,
    required String teamMode,
    required int entryFee,
    required int rounds,
    required bool assisted,
  }) async {
    await ensureBootstrap();
    final out = await _post('/api/lobby/quick', {
      'name': profile.displayName,
      'player_id': profile.userId,
      'account_token': accountToken,
      'turbo': turbo,
      'variant': variant,
      'team_mode': teamMode,
      'entry_fee': entryFee,
      'rounds': rounds,
      'assisted': assisted,
    });
    return GameSession.fromJson(out);
  }

  /// Botlarla antrenman: bahissiz, anında başlar, XP/lig/turnuva puanı vermez.
  Future<GameSession> practice({String variant = 'non_fold', bool assisted = true}) async {
    await ensureBootstrap();
    final out = await _post('/api/lobby/practice', {
      'name': profile.displayName,
      'player_id': profile.userId,
      'account_token': accountToken,
      'variant': variant,
      'assisted': assisted,
    });
    return GameSession.fromJson(out);
  }

  Future<GameSession> createRoom({
    required String name,
    required bool turbo,
    required String variant,
    required String teamMode,
    required int entryFee,
    required int rounds,
    required bool assisted,
    required int turnSeconds,
    String? password,
  }) async {
    await ensureBootstrap();
    final out = await _post('/api/lobby/rooms', {
      'name': name.trim().isEmpty ? 'OkeyX Masası' : name.trim(),
      'variant': variant,
      'entry_fee': entryFee,
      'assisted': assisted,
      'turbo': turbo,
      'team_mode': teamMode,
      'rounds': rounds,
      'owner_name': profile.displayName,
      'player_id': profile.userId,
      'account_token': accountToken,
      'turn_seconds': turnSeconds,
      'password': (password ?? '').trim().isEmpty ? null : password!.trim(),
    });
    return GameSession.fromJson(out);
  }

  Future<GameSession> joinRoom(String roomId, {String? password}) async {
    await ensureBootstrap();
    final out = await _post('/api/game/$roomId/join', {
      'name': profile.displayName,
      'player_id': profile.userId,
      'account_token': accountToken,
      'password': (password ?? '').trim().isEmpty ? null : password!.trim(),
    });
    return GameSession.fromJson(out);
  }

  Future<List<Map<String, dynamic>>> liveActivity() async {
    final out = await _get('/api/live/activity', query: {'limit': '18'});
    return _list(out['activity']).map(_map).toList();
  }

  Future<Map<String, dynamic>> daily() async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/daily', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> missions() async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/missions', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimMission(String id) async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/missions/$id/claim', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimAchievement(String id) async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/achievements/$id/claim', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> rewardConfig() async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/reward-config', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> notifications() async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/notifications', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> markNotificationsRead() async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/notifications/read', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> social() async {
    // Supabase is the canonical friendship store. Read it first so the social
    // page does not silently look empty when the gameplay API is restarting.
    Map<String, dynamic> backend = const {};
    try {
      await ensureBootstrap();
      backend = await _get('/api/social/${profile.userId}', headers: _socialHeaders);
    } catch (_) {}

    try {
      final rows = await Supabase.instance.client.rpc('okeyx_social_connections');
      final backendPeople = <String, Map<String, dynamic>>{};
      for (final bucket in ['friends', 'requests']) {
        for (final raw in _list(backend[bucket])) {
          final row = _map(raw);
          final id = '${row['id'] ?? row['user_id'] ?? ''}'.trim();
          if (id.isNotEmpty) backendPeople[id] = row;
        }
      }
      final friends = <Map<String, dynamic>>[];
      final requests = <Map<String, dynamic>>[];
      final sentIds = <String>[];
      for (final raw in _list(rows)) {
        final row = _map(raw);
        final id = '${row['user_id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final live = backendPeople[id] ?? const <String, dynamic>{};
        final person = <String, dynamic>{
          ...live,
          'id': id,
          'name': '${row['display_name'] ?? live['name'] ?? 'Oyuncu'}',
          'avatar_url': row['avatar_url'] ?? live['avatar_url'],
          'public_id': row['public_id'] ?? live['public_id'],
          'online': live['online'] == true,
          'in_game': live['in_game'] == true,
          'joinable': live['joinable'] == true,
        };
        switch ('${row['relationship'] ?? ''}') {
          case 'friend': friends.add(person); break;
          case 'incoming': requests.add(person); break;
          case 'sent': sentIds.add(id); break;
        }
      }
      return {
        ...backend,
        'friends': friends,
        'requests': requests,
        'sent_requests': sentIds,
        'recent_players': _list(backend['recent_players']).map(_map).toList(),
      };
    } catch (_) {
      if (backend.isNotEmpty) return backend;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchPlayers(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return const <Map<String, dynamic>>[];
    try {
      await ensureBootstrap();
      final headers = _socialHeaders;
      final out = await _get('/api/social/search', query: {'q': clean, 'player_id': profile.userId}, headers: headers);
      return _list(out['players']).map(_map).toList();
    } catch (_) {
      final rows = await Supabase.instance.client.rpc(
        'okeyx_search_players',
        params: {'p_query': clean, 'p_limit': 20},
      );
      return _list(rows).map((raw) {
        final row = _map(raw);
        return {...row, 'id': '${row['user_id'] ?? ''}', 'name': '${row['display_name'] ?? 'Oyuncu'}'};
      }).toList();
    }
  }

  Future<Map<String, dynamic>> _friendRpc(String targetId, [String? action]) async {
    final raw = action == null
        ? await Supabase.instance.client.rpc('okeyx_friend_request', params: {'p_target_user_id': targetId})
        : await Supabase.instance.client.rpc('okeyx_friend_action', params: {'p_target_user_id': targetId, 'p_action': action});
    return _map(raw);
  }

  Future<Map<String, dynamic>> transferCoins(String targetId, int amount) async {
    await ensureBootstrap();
    return _post('/api/social/transfer-coins', {
      'from_id': profile.userId,
      'to_id': targetId,
      'amount': amount,
    }, headers: _socialHeaders);
  }

  Future<Map<String, dynamic>> friendRequest(String targetId) async {
    try {
      final remote = await _friendRpc(targetId);
      if (remote['ok'] == true || remote['code'] != null) return remote;
    } catch (_) {}
    await ensureBootstrap();
    return _post('/api/social/friend-request', {'from_id': profile.userId, 'to_id': targetId}, headers: _socialHeaders);
  }

  Future<Map<String, dynamic>> acceptFriend(String fromId) async {
    try { final remote = await _friendRpc(fromId, 'accept'); if (remote['ok'] == true || remote['code'] != null) return remote; } catch (_) {}
    await ensureBootstrap();
    return _post('/api/social/friend-accept', {'player_id': profile.userId, 'from_id': fromId}, headers: _socialHeaders);
  }

  Future<Map<String, dynamic>> declineFriend(String fromId) async {
    try { final remote = await _friendRpc(fromId, 'decline'); if (remote['ok'] == true || remote['code'] != null) return remote; } catch (_) {}
    await ensureBootstrap();
    return _post('/api/social/friend-decline', {'player_id':profile.userId,'from_id':fromId}, headers:_socialHeaders);
  }
  Future<Map<String, dynamic>> cancelFriendRequest(String id) async {
    try { final remote = await _friendRpc(id, 'cancel'); if (remote['ok'] == true || remote['code'] != null) return remote; } catch (_) {}
    await ensureBootstrap();
    return _post('/api/social/friend-cancel', {'from_id':profile.userId,'to_id':id}, headers:_socialHeaders);
  }
  Future<Map<String, dynamic>> removeFriend(String id) async {
    try { final remote = await _friendRpc(id, 'remove'); if (remote['ok'] == true || remote['code'] != null) return remote; } catch (_) {}
    await ensureBootstrap();
    return _post('/api/social/friend-remove', {'from_id':profile.userId,'to_id':id}, headers:_socialHeaders);
  }

  Future<Map<String, dynamic>> inviteFriend(String targetId, String roomId) async {
    await ensureBootstrap();
    return _post('/api/social/invite', {'from_id': profile.userId, 'to_id': targetId, 'room_id': roomId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> setBlock(String targetId, bool enabled) async {
    await ensureBootstrap();
    return _post('/api/social/block', {'player_id': profile.userId, 'target_id': targetId, 'enabled': enabled}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> setMute(String targetId, bool enabled) async {
    await ensureBootstrap();
    return _post('/api/social/mute', {'player_id': profile.userId, 'target_id': targetId, 'enabled': enabled}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> report(String targetId, String reason, {String? roomId}) async {
    await ensureBootstrap();
    return _post('/api/social/report', {'player_id': profile.userId, 'target_id': targetId, 'reason': reason, 'room_id': roomId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> spinWheel() async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/wheel', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> openChest() async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/chest', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> dailyRewardState() async {
    await ensureBootstrap();
    final accountState = await account();
    final daily = _map(accountState['daily']);
    final wheel = _map(accountState['wheel']);
    final chests = _map(accountState['chests']);
    final now = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    final localToday = '${now.year}-${p(now.month)}-${p(now.day)}';
    final today = '${accountState['reward_day_key'] ?? localToday}';
    return {
      'ok': true,
      'daily_used': '${daily['last_claim_day'] ?? ''}' == today,
      'wheel_used': '${wheel['last_spin_day'] ?? ''}' == today,
      'chest_used': '${chests['last_free_day'] ?? ''}' == today,
      'account': accountState,
    };
  }

  Future<Map<String, dynamic>> history() async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/history', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> referralInfo() async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/referral', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> redeemReferral(String code, {String? deviceId}) async {
    await ensureBootstrap();
    final installId = deviceId ?? await DeviceIdentity.get();
    return _post('/api/account/referral/redeem', {'player_id': profile.userId, 'code': code, 'device_id': installId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> leaderboard(String scope) async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/leaderboard', query: {'scope': scope}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> setCity(String city) async {
    await ensureBootstrap();
    return _post('/api/account/league/city', {'player_id': profile.userId, 'city': city}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> canak() => _get('/api/canak');

  Future<Map<String, dynamic>> season() async {
    await ensureBootstrap();
    return _get('/api/account/${profile.userId}/season', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimSeason(String milestoneId) async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/season/$milestoneId/claim', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> clubs() async {
    await ensureBootstrap();
    return _get('/api/clubs/${profile.userId}', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> createClub(String name) async {
    await ensureBootstrap();
    return _post('/api/clubs/create', {'player_id': profile.userId, 'name': name}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> joinClub(String clubId) async {
    await ensureBootstrap();
    return _post('/api/clubs/join', {'player_id': profile.userId, 'club_id': clubId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> leaveClub() async {
    await ensureBootstrap();
    return _post('/api/clubs/leave', {'player_id': profile.userId, 'club_id': ''}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimClubWeekly() async {
    await ensureBootstrap();
    return _post('/api/clubs/weekly/claim', {'player_id': profile.userId, 'club_id': ''}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> clubChat(String text) async {
    await ensureBootstrap();
    return _post('/api/clubs/chat', {'player_id': profile.userId, 'text': text}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> phase4Hub() async {
    await ensureBootstrap();
    return _get('/api/phase4/${profile.userId}/hub', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> buyCosmetic(String itemId) async {
    await ensureBootstrap();
    return _post('/api/phase4/store/buy', {'player_id': profile.userId, 'item_id': itemId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> equipCosmetic(String itemId) async {
    await ensureBootstrap();
    return _post('/api/phase4/store/equip', {'player_id': profile.userId, 'item_id': itemId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimVipDaily() async {
    await ensureBootstrap();
    return _post('/api/phase4/vip/${profile.userId}/daily', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimLiveEvent(String eventId) async {
    await ensureBootstrap();
    return _post('/api/phase4/event/${profile.userId}/$eventId/claim', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimPassTask(String taskId) async {
    await ensureBootstrap();
    return _post('/api/phase4/pass/task', {'player_id': profile.userId, 'task_id': taskId}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimPassLevel(int level, {bool premium = false}) async {
    await ensureBootstrap();
    return _post('/api/phase4/pass/claim', {'player_id': profile.userId, 'level': level, 'premium': premium}, headers: _authHeaders);
  }

  /// Oyun sunucusundaki hesabı (bakiye, arkadaş, kulüp izi) kalıcı siler.
  Future<Map<String, dynamic>> deleteGameAccount() async {
    await ensureBootstrap().timeout(const Duration(seconds: 4));
    return _post('/api/account/${profile.userId}/delete', <String, dynamic>{}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> tournament() async {
    await ensureBootstrap().timeout(const Duration(seconds: 4));
    return _get('/api/tournament/${profile.userId}', headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimTournament() async {
    await ensureBootstrap().timeout(const Duration(seconds: 4));
    return _post('/api/tournament/${profile.userId}/claim', <String, dynamic>{}, headers: _authHeaders);
  }

  /// Gerçek satın alma: Google'a sunucu sorar, katalogdaki ürün uygulanır.
  Future<Map<String, dynamic>> googleVerifyPurchase(String productId, String purchaseToken) async {
    await ensureBootstrap().timeout(const Duration(seconds: 4));
    return _post('/api/phase4/store/google-verify', {
      'player_id': profile.userId,
      'product_id': productId,
      'purchase_token': purchaseToken,
    }, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimSalonDaily() async {
    await ensureBootstrap().timeout(const Duration(milliseconds: 900));
    return _post('/api/phase4/salon/claim/${profile.userId}', <String, dynamic>{});
  }

  Future<Map<String, dynamic>> playSideGame(String game, {int? choice, int? wager, bool useVoucher=false, String? action, String? challengeId, List<int>? activeLines}) async {
    // Always use the authoritative live backend. The previous slot fast-path
    // probed an optional Supabase RPC for up to two seconds before falling back,
    // which made every spin feel delayed when that RPC was not deployed.
    await ensureBootstrap().timeout(const Duration(milliseconds: 900));
    return _post('/api/phase4/side-games/play', {
      'player_id': profile.userId,
      'game': game,
      'choice': choice,
      'wager': wager,
      'use_voucher': useVoucher,
      'action': action,
      'challenge_id': challengeId,
      'active_lines': activeLines,
    }, headers: _authHeaders);
  }

  Future<Map<String,dynamic>> staffSnapshot() async { await ensureBootstrap(); return _get('/api/phase4/staff/${profile.userId}/snapshot',headers:_authHeaders); }
  Future<List<Map<String,dynamic>>> staffPlayers(String q) async { await ensureBootstrap(); final x=await _get('/api/phase4/staff/${profile.userId}/players',query:{'q':q},headers:_authHeaders); return _list(x['players']).map(_map).toList(); }
  Future<Map<String,dynamic>> staffSanction(String id,String type,{int durationMinutes=0,String reason=''}) async { await ensureBootstrap(); return _post('/api/phase4/staff/sanction',{'actor_id':profile.userId,'player_id':id,'sanction_type':type,'duration_minutes':durationMinutes,'reason':reason},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffWallet(String id,String currency,int amount,String reason) async { await ensureBootstrap(); return _post('/api/phase4/staff/wallet',{'actor_id':profile.userId,'player_id':id,'currency':currency,'amount':amount,'reason':reason},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffRtp(String game,double percent,{String title=''}) async { await ensureBootstrap(); return _post('/api/phase4/staff/rtp',{'actor_id':profile.userId,'game':game,'percent':percent,'event_title':title},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffSelfTestStart({int games=200,bool push=true}) async { await ensureBootstrap(); return _post('/api/phase4/staff/selftest',{'actor_id':profile.userId,'games':games,'push':push},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffSelfTestStatus() async { await ensureBootstrap(); return _get('/api/phase4/staff/${profile.userId}/selftest',headers:_authHeaders); }
  Future<Map<String,dynamic>> staffMarket() async { await ensureBootstrap(); return _get('/api/phase4/staff/${profile.userId}/market',headers:_authHeaders); }
  Future<Map<String,dynamic>> staffPatch(String kind,String target,Map<String,dynamic> patch) async { await ensureBootstrap(); return _post('/api/phase4/staff/$kind',{'actor_id':profile.userId,'target':target,'patch':patch},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffRewardConfig(Map<String,dynamic> config) async { await ensureBootstrap(); return _post('/api/phase4/staff/reward-config',{'actor_id':profile.userId,'config':config},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffUpsertEvent({String? id,required String title,String subtitle='',int? startsAt,int? endsAt,bool enabled=true,String kind='seasonal',Map<String,dynamic>? config}) async { await ensureBootstrap(); return _put('/api/phase4/staff/live-events',{'id':id,'title':title,'subtitle':subtitle,'starts_at':startsAt,'ends_at':endsAt,'enabled':enabled,'kind':kind,'config':config ?? <String,dynamic>{}},query:{'actor_id':profile.userId},headers:_authHeaders); }
  Future<Map<String,dynamic>> staffDeleteEvent(String eventId) async { await ensureBootstrap(); return _delete('/api/phase4/staff/live-events/$eventId',query:{'actor_id':profile.userId},headers:_authHeaders); }

  Future<Map<String, dynamic>> matchTransitionAd() async {
    await ensureBootstrap();
    return _post('/api/phase4/ads/transition/${profile.userId}', const {}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> startAdSession(String rewardKind) async {
    await ensureBootstrap();
    return _post('/api/phase4/ads/start', {'player_id': profile.userId, 'reward_kind': rewardKind}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> claimAdReward(String token) async {
    await ensureBootstrap();
    return _post('/api/phase4/ads/claim', {'player_id': profile.userId, 'token': token}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> registerPush(String token) async {
    await ensureBootstrap();
    return _post('/api/account/push/register', {'player_id': profile.userId, 'token': token}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> setNotificationPrefs(Map<String, bool> prefs) async {
    await ensureBootstrap();
    return _post('/api/account/${profile.userId}/notification-prefs', prefs, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> supportTicket({required String topic, required String message, String orderId = ''}) async {
    await ensureBootstrap();
    return _post('/api/support/ticket', {'player_id': profile.userId, 'topic': topic, 'message': message, 'order_id': orderId}, headers: _authHeaders);
  }

    Future<Map<String, dynamic>> setVoice({bool? enabled, String? mutePlayerId, bool? muted}) async {
    await ensureBootstrap();
    return _post('/api/phase4/voice', {'player_id': profile.userId, 'enabled': enabled, 'mute_player_id': mutePlayerId, 'muted': muted}, headers: _authHeaders);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final request = await (_http ?? HttpClient()).getUrl(base.replace(path: path, queryParameters: query));
    headers?.forEach((name, value) => request.headers.set(name, value));
    return _finish(request);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final request = await (_http ?? HttpClient()).postUrl(base.replace(path: path));
    request.headers.contentType = ContentType.json;
    headers?.forEach((name, value) => request.headers.set(name, value));
    request.write(jsonEncode(body));
    return _finish(request);
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final request = await (_http ?? HttpClient()).putUrl(base.replace(path: path, queryParameters: query));
    request.headers.contentType = ContentType.json;
    headers?.forEach((name, value) => request.headers.set(name, value));
    request.write(jsonEncode(body));
    return _finish(request);
  }

  Future<Map<String, dynamic>> _delete(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final request = await (_http ?? HttpClient()).deleteUrl(base.replace(path: path, queryParameters: query));
    headers?.forEach((name, value) => request.headers.set(name, value));
    return _finish(request);
  }

  Future<Map<String, dynamic>> _finish(HttpClientRequest request) async {
    final response = await request.close().timeout(const Duration(seconds: 10));
    final text = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 10));
    dynamic decoded;
    try {
      decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } catch (_) {
      throw LobbyApiException('invalid_server_response_${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map && decoded['detail'] != null) {
        throw LobbyApiException('${decoded['detail']}');
      }
      throw LobbyApiException('http_${response.statusCode}');
    }
    return _map(decoded);
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<dynamic> _list(dynamic value) => value is List ? value : const [];

  void dispose() {
    _http?.close(force: true);
    _http = null;
  }
}
