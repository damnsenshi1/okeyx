import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api_endpoint.dart';
import '../../core/device_identity.dart';
import '../auth/profile_repository.dart';
import '../lobby/lobby_api.dart';

typedef GameStateListener = void Function(Map<String, dynamic> state);
typedef ConnectionListener = void Function(bool online, String message);

class GameApiException implements Exception {
  final String code;
  const GameApiException(this.code);

  @override
  String toString() => code;
}

class GameApiClient {
  final PlayerProfile profile;
  final GameStateListener onState;
  final ConnectionListener onConnection;
  final GameSession? initialSession;

  HttpClient? _http;
  WebSocket? _socket;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _connectingSocket = false;
  bool _intentionalLeave = false;
  int _reconnectAttempts = 0;
  int _requestSequence = 0;
  int _lastPingMs = 0;
  int _lastStateVersion = 0;
  String _serverBoot = '';
  final Map<String, Completer<Map<String, dynamic>>> _pendingActions = <String, Completer<Map<String, dynamic>>>{};

  String? roomId;
  String? reconnectToken;
  String? accountToken;
  int seat = 0;

  GameApiClient({
    required this.profile,
    required this.onState,
    required this.onConnection,
    this.initialSession,
  });

  Future<Map<String, dynamic>> startOrRestore() async {
    _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    final account = await _bootstrapAccount();
    accountToken = '${account['session_token'] ?? ''}';
    if (accountToken!.isEmpty) {
      throw const GameApiException('account_session_missing');
    }

    Map<String, dynamic> session;
    if (initialSession != null &&
        initialSession!.roomId.isNotEmpty &&
        initialSession!.reconnectToken.isNotEmpty) {
      session = {
        'room_id': initialSession!.roomId,
        'seat': initialSession!.seat,
        'reconnect_token': initialSession!.reconnectToken,
        'state': initialSession!.state,
      };
    } else {
      final restored = await _post('/api/game/reconnect', {
        'player_id': profile.userId,
        'account_token': accountToken,
      });
      if (restored['ok'] == true) {
        session = restored;
      } else {
        session = await _post('/api/lobby/quick', {
          'name': profile.displayName,
          'player_id': profile.userId,
          'account_token': accountToken,
          'turbo': false,
          'variant': 'non_fold',
          'team_mode': 'solo',
          'entry_fee': 5000,
          'rounds': 3,
          'assisted': true,
        });
      }
    }
    _applySession(session);
    await _connectSocket();
    _startPollingFallback();
    return _map(session['state']);
  }

  Future<Map<String, dynamic>> action(
    String kind, [
    Map<String, dynamic>? payload,
  ]) async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null) {
      throw const GameApiException('game_session_missing');
    }
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
    final body = <String, dynamic>{
      'seat': seat,
      'kind': kind,
      'payload': payload ?? const <String, dynamic>{},
      'reconnect_token': token,
      'request_id': requestId,
    };
    debugPrint('OKEYX_ACTION_REQUEST: room=$id seat=$seat kind=$kind payload=${payload ?? const <String, dynamic>{}}');

    Map<String, dynamic>? response;
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.open) {
      final completer = Completer<Map<String, dynamic>>();
      _pendingActions[requestId] = completer;
      try {
        socket.add(jsonEncode({
          'type': 'action',
          'kind': kind,
          'payload': payload ?? const <String, dynamic>{},
          'request_id': requestId,
        }));
        response = await completer.future.timeout(const Duration(seconds: 5));
      } catch (_) {
        // The exact same request id is retried through HTTP. The authoritative
        // server dedupe cache makes a lost socket ACK safe instead of applying
        // a draw/discard twice.
        _pendingActions.remove(requestId);
      }
    }
    response ??= await _post('/api/game/$id/action', body);
    _pendingActions.remove(requestId);

    final state = _map(response['state']);
    if (state.isNotEmpty) _acceptState(state);
    debugPrint('OKEYX_ACTION_RESULT: room=$id seat=$seat kind=$kind ok=${response['ok']} code=${response['code'] ?? ''} phase=${state['phase'] ?? ''} v=${state['state_version'] ?? '-'}');
    if (response['ok'] != true) {
      final resultBody = _map(response['payload']);
      final penalty = (resultBody['penalty'] as num?)?.toInt() ?? 0;
      throw GameApiException(
        penalty > 0 ? '${response['code']}:+$penalty' : '${response['code']}',
      );
    }
    return response;
  }


  Future<Map<String, dynamic>> setReady(bool ready) async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null) throw const GameApiException('game_session_missing');
    final out = await _post('/api/game/$id/ready', {'seat': seat, 'reconnect_token': token, 'ready': ready});
    final st = _map(out['state']);
    if (st.isNotEmpty) _acceptState(st);
    return out;
  }

  /// Bekleme odasında boş bir koltuğa geç (koltuk ve bağlantı anahtarı değişir).
  Future<Map<String, dynamic>> changeSeat(int toSeat) async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null) throw const GameApiException('game_session_missing');
    final out = await _post('/api/game/$id/sit', {'seat': seat, 'reconnect_token': token, 'to_seat': toSeat});
    if (out['ok'] == true) {
      _lastStateVersion = 0;
      _applySession(out);
      unawaited(_connectSocket());
    }
    return out;
  }

  Future<Map<String, dynamic>> chat(
    String kind,
    String value, {
    int? toSeat,
  }) async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null) {
      throw const GameApiException('game_session_missing');
    }
    debugPrint('OKEYX_CHAT_REQUEST: room=$id seat=$seat kind=$kind to=${toSeat ?? '-'}');
    final out = await _post('/api/game/$id/chat', {
      'seat': seat,
      'reconnect_token': token,
      'kind': kind,
      'value': value,
      'to_seat': toSeat,
    });
    debugPrint('OKEYX_CHAT_RESULT: room=$id kind=$kind ok=${out['ok']} event=${_map(out['event'])['id'] ?? ''}');
    return out;
  }

  Map<String,String> _socialHeaders(String token) {
    final headers=<String,String>{'X-Account-Token':token};
    final session=Supabase.instance.client.auth.currentSession;
    if(session!=null)headers['Authorization']='Bearer ${session.accessToken}';
    return headers;
  }

  Future<Map<String,dynamic>> friendRequest(String targetId) async {
    final token=accountToken;
    if (token != null && token.isNotEmpty) {
      try {
        return await _post('/api/social/friend-request',{'from_id':profile.userId,'to_id':targetId},headers:_socialHeaders(token));
      } catch (_) {}
    }
    final raw = await Supabase.instance.client.rpc('okeyx_friend_request', params:{'p_target_user_id':targetId});
    return _map(raw);
  }

  Future<List<Map<String, dynamic>>> friends() async {
    final token = accountToken;
    if (token == null || token.isEmpty) throw const GameApiException('account_session_missing');
    final out = await _getWithHeaders('/api/social/${profile.userId}', const <String, String>{}, _socialHeaders(token));
    return _list(out['friends']).map(_map).toList();
  }

  Future<Map<String, dynamic>> transferCoins(String targetId, int amount) async {
    final token = accountToken;
    if (token == null || token.isEmpty) throw const GameApiException('account_session_missing');
    return _post('/api/social/transfer-coins', {
      'from_id': profile.userId,
      'to_id': targetId,
      'amount': amount,
    }, headers: _socialHeaders(token));
  }

  Future<Map<String, dynamic>> inviteFriend(String targetId) async {
    final id = roomId;
    final token = accountToken;
    if (id == null || token == null || token.isEmpty) {
      throw const GameApiException('game_session_missing');
    }
    return _post('/api/social/invite', {
      'from_id': profile.userId,
      'to_id': targetId,
      'room_id': id,
    }, headers: _socialHeaders(token));
  }

  Future<Map<String, dynamic>> setMute(String targetId, bool enabled) async {
    final token = accountToken;
    if (token == null || token.isEmpty) throw const GameApiException('account_session_missing');
    return _post('/api/social/mute', {
      'player_id': profile.userId,
      'target_id': targetId,
      'enabled': enabled,
    }, headers: {'X-Account-Token': token});
  }

  Future<Map<String, dynamic>> setBlock(String targetId, bool enabled) async {
    final token = accountToken;
    if (token == null || token.isEmpty) throw const GameApiException('account_session_missing');
    return _post('/api/social/block', {
      'player_id': profile.userId,
      'target_id': targetId,
      'enabled': enabled,
    }, headers: {'X-Account-Token': token});
  }

  Future<Map<String, dynamic>> reportPlayer(String targetId, String reason) async {
    final token = accountToken;
    if (token == null || token.isEmpty) throw const GameApiException('account_session_missing');
    return _post('/api/social/report', {
      'player_id': profile.userId,
      'target_id': targetId,
      'reason': reason,
      'room_id': roomId,
    }, headers: {'X-Account-Token': token});
  }


  Future<Map<String, dynamic>> manageRoom({required String action, int? targetSeat, String? roomName, int? turnSeconds, bool? turbo, String? variant, String? teamMode, int? entryFee, int? rounds, bool? assisted, bool? chatEnabled, bool? giftsEnabled, bool? autoRematch, String? botLevel}) async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null) throw const GameApiException('game_session_missing');
    return _post('/api/game/$id/manage', {
      'seat': seat,
      'reconnect_token': token,
      'action': action,
      'target_seat': targetSeat,
      'room_name': roomName,
      'turn_seconds': turnSeconds,
      'turbo':turbo,'variant':variant,'team_mode':teamMode,'entry_fee':entryFee,'rounds':rounds,'assisted':assisted,
      'chat_enabled':chatEnabled,'gifts_enabled':giftsEnabled,'auto_rematch':autoRematch,'bot_level':botLevel,
    });
  }

  Future<List<Map<String, dynamic>>> searchPlayers(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return const <Map<String, dynamic>>[];
    final token = accountToken;
    final session = Supabase.instance.client.auth.currentSession;
    if (token != null && token.isNotEmpty) {
      final headers = <String,String>{'X-Account-Token': token};
      if (session != null) headers['Authorization'] = 'Bearer ${session.accessToken}';
      try {
        final out = await _getWithHeaders('/api/social/search', {'q':clean,'player_id':profile.userId}, headers);
        return _list(out['players']).map(_map).toList();
      } catch (_) {}
    }
    try {
      final rows = await Supabase.instance.client.rpc(
        'okeyx_search_players',
        params: {'p_query': clean, 'p_limit': 20},
      );
      return _list(rows).map(_map).toList();
    } catch (_) {
      if (token == null || token.isEmpty) throw const GameApiException('account_session_missing');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> leave() async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null) {
      _intentionalLeave = true;
      return const <String, dynamic>{'ok': true};
    }
    final out = await _post('/api/game/$id/leave', {
      'seat': seat,
      'reconnect_token': token,
    });
    if (out['ok'] == true) {
      _intentionalLeave = true;
      _heartbeat?.cancel();
      _reconnectTimer?.cancel();
      _pollTimer?.cancel();
      try { await _socket?.close(1000, 'intentional_leave'); } catch (_) {}
      _socket = null;
      roomId = null;
      reconnectToken = null;
      _reconnectAttempts = 0;
      onConnection(false, 'AYRILDI');
    }
    return out;
  }

  Future<void> refresh() async {
    final id = roomId;
    final token = reconnectToken;
    if (id == null || token == null || _disposed) return;
    try {
      final state = await _get('/api/game/$id', {
        'seat': '$seat',
        'reconnect_token': token,
      });
      onConnection(true, 'CANLI');
      _acceptState(state);
    } catch (_) {
      onConnection(false, 'YENİDEN BAĞLANIYOR');
      _scheduleReconnect();
    }
  }

  Future<Map<String, dynamic>> _bootstrapAccount() async {
    final uri = Uri.tryParse(ApiEndpoint.baseUrl);
    final h = uri?.host ?? '';
    final parts = h.split('.').map(int.tryParse).toList();
    final privateLan = parts.length == 4 && !parts.any((x) => x == null) && (
      parts[0] == 10 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31)
    );
    final local = uri != null && (h == '127.0.0.1' || h == 'localhost' || h == '10.0.2.2' || privateLan);
    final deviceId = await DeviceIdentity.get();
    if (local) {
      return _post(
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
    }
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw const GameApiException('supabase_session_missing');
    return _post(
      '/api/account/bootstrap-supabase',
      {'name': profile.displayName, 'avatar_url': profile.avatarUrl, 'device_id': deviceId, 'is_guest': profile.isGuest},
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
  }

  void _acceptState(Map<String, dynamic> state) {
    if (state.isEmpty || _disposed) return;
    final version = (state['state_version'] as num?)?.toInt() ?? 0;
    // Sunucu yeniden başladıysa (yeni sürüm yüklendi) sayaç sıfırlanmış olabilir.
    final boot = '${state['server_boot'] ?? ''}';
    if (boot.isNotEmpty && boot != _serverBoot) {
      if (_serverBoot.isNotEmpty) _lastStateVersion = 0;
      _serverBoot = boot;
    }
    if (version > 0) {
      if (version <= _lastStateVersion) return;
      _lastStateVersion = version;
    }
    onState(state);
  }

  void _applySession(Map<String, dynamic> json) {
    _intentionalLeave = false;
    roomId = '${json['room_id']}';
    seat = (json['seat'] as num?)?.toInt() ?? 0;
    reconnectToken = '${json['reconnect_token'] ?? ''}';
    final state = _map(json['state']);
    if (state.isNotEmpty) _acceptState(state);
  }

  Future<void> _connectSocket() async {
    if (_disposed ||
        _connectingSocket ||
        roomId == null ||
        reconnectToken == null) {
      return;
    }
    _connectingSocket = true;
    try {
      await _socket?.close();
      final base = Uri.parse(ApiEndpoint.baseUrl);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/game/$roomId/ws',
        queryParameters: {'seat': '$seat', 'reconnect_token': reconnectToken!},
      );
      final socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 6));
      if (_disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _reconnectAttempts = 0;
      onConnection(true, 'CANLI');
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 8), (_) {
        try {
          _lastPingMs = DateTime.now().millisecondsSinceEpoch;
          _socket?.add('ping');
        } catch (_) {
          _scheduleReconnect();
        }
      });
      socket.listen(
        (message) {
          if (message is! String) return;
          if (message == 'pong') {
            final sent = _lastPingMs;
            if (sent > 0) {
              final rtt = (DateTime.now().millisecondsSinceEpoch - sent).clamp(0, 9999);
              final quality = rtt <= 120 ? 'CANLI' : (rtt <= 260 ? 'ORTA' : 'ZAYIF');
              onConnection(true, '$quality • ${rtt}ms');
            }
            return;
          }
          final decoded = jsonDecode(message);
          if (decoded is! Map) return;
          if (decoded['type'] == 'state') {
            _acceptState(_map(decoded['state']));
            return;
          }
          if (decoded['type'] == 'action_result') {
            final result = _map(decoded);
            final requestId = '${result['request_id'] ?? ''}';
            final pending = _pendingActions.remove(requestId);
            if (pending != null && !pending.isCompleted) pending.complete(result);
            return;
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      onConnection(false, 'YENİDEN BAĞLANIYOR');
      _scheduleReconnect();
    } finally {
      _connectingSocket = false;
    }
  }

  void _scheduleReconnect() {
    if (_disposed || _intentionalLeave || roomId == null || reconnectToken == null || _reconnectTimer?.isActive == true) return;
    onConnection(false, 'YENİDEN BAĞLANIYOR');
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 6).toInt();
    final delayMs = (700 * (1 << (_reconnectAttempts - 1))).clamp(700, 6000).toInt();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      await refresh();
      await _connectSocket();
    });
  }

  void _startPollingFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      final socket = _socket;
      if (socket == null || socket.readyState != WebSocket.open) {
        unawaited(refresh());
      }
    });
  }

  Future<Map<String, dynamic>> _getWithHeaders(String path, Map<String,String> query, Map<String,String> headers) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final uri = base.replace(path:path, queryParameters:query);
    final request = await (_http ?? HttpClient()).getUrl(uri);
    headers.forEach((name,value)=>request.headers.set(name,value));
    return _finish(request);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final uri = base.replace(path: path, queryParameters: query);
    final request = await (_http ?? HttpClient()).getUrl(uri);
    return _finish(request);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final base = Uri.parse(ApiEndpoint.baseUrl);
    final request = await (_http ?? HttpClient()).postUrl(
      base.replace(path: path),
    );
    request.headers.contentType = ContentType.json;
    headers?.forEach((name, value) => request.headers.set(name, value));
    request.write(jsonEncode(body));
    return _finish(request);
  }

  Future<Map<String, dynamic>> _finish(HttpClientRequest request) async {
    final response = await request.close().timeout(const Duration(seconds: 8));
    final text = await utf8.decoder.bind(response).join();
    dynamic decoded;
    try {
      decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
    } catch (_) {
      throw GameApiException('invalid_server_response_${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (decoded is Map && decoded['detail'] != null) {
        throw GameApiException('${decoded['detail']}');
      }
      throw GameApiException('http_${response.statusCode}');
    }
    return _map(decoded);
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  List<dynamic> _list(dynamic value) =>
      value is List ? List<dynamic>.from(value) : <dynamic>[];

  Future<void> dispose() async {
    _disposed = true;
    _heartbeat?.cancel();
    _reconnectTimer?.cancel();
    _pollTimer?.cancel();
    for (final pending in _pendingActions.values) {
      if (!pending.isCompleted) pending.completeError(const GameApiException('socket_closed'));
    }
    _pendingActions.clear();
    await _socket?.close();
    _http?.close(force: true);
  }
}
