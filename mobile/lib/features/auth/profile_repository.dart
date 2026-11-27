import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerProfile {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? avatarSeed;
  final bool isGuest;
  final int level;
  final int xp;
  final int rating;
  final int coins;
  final int diamonds;
  final int gamesPlayed;
  final int wins;
  final int vipLevel;

  const PlayerProfile({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.avatarSeed,
    required this.isGuest,
    required this.level,
    required this.xp,
    required this.rating,
    required this.coins,
    required this.diamonds,
    required this.gamesPlayed,
    required this.wins,
    this.vipLevel = 0,
  });

  factory PlayerProfile.fromJson(Map<String, dynamic> json, {int vipLevel = 0}) => PlayerProfile(
        userId: '${json['user_id'] ?? ''}',
        displayName: '${json['display_name'] ?? 'Oyuncu'}',
        avatarUrl: json['avatar_url'] as String?,
        avatarSeed: json['avatar_seed'] as String?,
        isGuest: json['is_guest'] == true,
        level: (json['level'] as num?)?.toInt() ?? 1,
        xp: (json['xp'] as num?)?.toInt() ?? 0,
        rating: (json['rating'] as num?)?.toInt() ?? 1000,
        coins: (json['coins'] as num?)?.toInt() ?? 10000,
        diamonds: (json['diamonds'] as num?)?.toInt() ?? 0,
        gamesPlayed: (json['games_played'] as num?)?.toInt() ?? 0,
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        vipLevel: vipLevel,
      );

  PlayerProfile copyWith({
    String? displayName,
    String? avatarUrl,
    String? avatarSeed,
    bool clearAvatar = false,
    bool? isGuest,
    int? vipLevel,
  }) => PlayerProfile(
        userId: userId,
        displayName: displayName ?? this.displayName,
        avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
        avatarSeed: avatarSeed ?? this.avatarSeed,
        isGuest: isGuest ?? this.isGuest,
        level: level,
        xp: xp,
        rating: rating,
        coins: coins,
        diamonds: diamonds,
        gamesPlayed: gamesPlayed,
        wins: wins,
        vipLevel: vipLevel ?? this.vipLevel,
      );
}

class UserPreferences {
  final String locale;
  final bool musicEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool notificationsEnabled;
  final bool dataSaverEnabled;
  final bool reducedMotionEnabled;
  final bool radioEnabled;
  final String radioStation;
  final double musicVolume;
  final double radioVolume;
  final double ambienceVolume;
  final double sfxVolume;
  final bool opponentMusicKits;
  final bool giftAnimations;
  final bool tableAmbienceEnabled;
  /// Masa çuhası: green | bordo | navy | anthracite
  final String tableTheme;
  /// Istaka: walnut | oak | ebony
  final String rackStyle;
  final bool bigTileNumbers;

  const UserPreferences({
    this.locale = 'tr',
    this.musicEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.notificationsEnabled = true,
    this.dataSaverEnabled = false,
    this.reducedMotionEnabled = false,
    this.radioEnabled = false,
    this.radioStation = 'kral_pop',
    this.musicVolume = .30,
    this.radioVolume = .34,
    this.ambienceVolume = .10,
    this.sfxVolume = .78,
    this.opponentMusicKits = true,
    this.giftAnimations = true,
    this.tableAmbienceEnabled = false,
    this.tableTheme = 'green',
    this.rackStyle = 'walnut',
    this.bigTileNumbers = false,
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) => UserPreferences(
        locale: '${json['locale'] ?? 'tr'}',
        musicEnabled: json['music_enabled'] != false,
        soundEnabled: json['sound_enabled'] != false,
        vibrationEnabled: json['vibration_enabled'] != false,
        notificationsEnabled: json['notifications_enabled'] != false,
        dataSaverEnabled: json['data_saver_enabled'] == true,
        reducedMotionEnabled: json['reduced_motion_enabled'] == true,
        radioEnabled: json['radio_enabled'] == true,
        radioStation: '${json['radio_station'] ?? 'kral_pop'}',
        musicVolume: ((json['music_volume'] as num?)?.toDouble() ?? .30).clamp(0.0,1.0).toDouble(),
        radioVolume: ((json['radio_volume'] as num?)?.toDouble() ?? .34).clamp(0.0,1.0).toDouble(),
        ambienceVolume: ((json['ambience_volume'] as num?)?.toDouble() ?? .10).clamp(0.0,1.0).toDouble(),
        sfxVolume: ((json['sfx_volume'] as num?)?.toDouble() ?? .78).clamp(0.0,1.0).toDouble(),
        opponentMusicKits: json['opponent_music_kits'] != false,
        giftAnimations: json['gift_animations'] != false,
        tableAmbienceEnabled: json['table_ambience_enabled'] == true,
        tableTheme: '${json['table_theme'] ?? 'green'}',
        rackStyle: '${json['rack_style'] ?? 'walnut'}',
        bigTileNumbers: json['big_tile_numbers'] == true,
      );

  UserPreferences copyWith({
    String? locale,
    bool? musicEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? notificationsEnabled,
    bool? dataSaverEnabled,
    bool? reducedMotionEnabled,
    bool? radioEnabled,
    String? radioStation,
    double? musicVolume,
    double? radioVolume,
    double? ambienceVolume,
    double? sfxVolume,
    bool? opponentMusicKits,
    bool? giftAnimations,
    bool? tableAmbienceEnabled,
    String? tableTheme,
    String? rackStyle,
    bool? bigTileNumbers,
  }) => UserPreferences(
        locale: locale ?? this.locale,
        musicEnabled: musicEnabled ?? this.musicEnabled,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        dataSaverEnabled: dataSaverEnabled ?? this.dataSaverEnabled,
        reducedMotionEnabled: reducedMotionEnabled ?? this.reducedMotionEnabled,
        radioEnabled: radioEnabled ?? this.radioEnabled,
        radioStation: radioStation ?? this.radioStation,
        musicVolume: musicVolume ?? this.musicVolume,
        radioVolume: radioVolume ?? this.radioVolume,
        ambienceVolume: ambienceVolume ?? this.ambienceVolume,
        sfxVolume: sfxVolume ?? this.sfxVolume,
        opponentMusicKits: opponentMusicKits ?? this.opponentMusicKits,
        giftAnimations: giftAnimations ?? this.giftAnimations,
        tableAmbienceEnabled: tableAmbienceEnabled ?? this.tableAmbienceEnabled,
        tableTheme: tableTheme ?? this.tableTheme,
        rackStyle: rackStyle ?? this.rackStyle,
        bigTileNumbers: bigTileNumbers ?? this.bigTileNumbers,
      );

  Map<String, dynamic> toJson() => {
        'locale': locale,
        'music_enabled': musicEnabled,
        'sound_enabled': soundEnabled,
        'vibration_enabled': vibrationEnabled,
        'notifications_enabled': notificationsEnabled,
        'data_saver_enabled': dataSaverEnabled,
        'reduced_motion_enabled': reducedMotionEnabled,
        'radio_enabled': radioEnabled,
        'radio_station': radioStation,
        'music_volume': musicVolume,
        'radio_volume': radioVolume,
        'ambience_volume': ambienceVolume,
        'sfx_volume': sfxVolume,
        'opponent_music_kits': opponentMusicKits,
        'gift_animations': giftAnimations,
        'table_ambience_enabled': tableAmbienceEnabled,
        'table_theme': tableTheme,
        'rack_style': rackStyle,
        'big_tile_numbers': bigTileNumbers,
      };
}

class PlayerBundle {
  final PlayerProfile profile;
  final UserPreferences preferences;
  const PlayerBundle(this.profile, this.preferences);
}

class ProfileRepository {
  final SupabaseClient _client;
  ProfileRepository(this._client);

  Future<PlayerBundle> ensureCurrentBundle() async {
    final profile = await ensureCurrentProfile();
    final preferences = await loadPreferences();
    return PlayerBundle(profile, preferences);
  }

  Future<PlayerProfile> ensureCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('auth_session_missing');

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final rawName = '${metadata['display_name'] ?? metadata['full_name'] ?? metadata['name'] ?? user.email?.split('@').first ?? 'Oyuncu'}'.trim();
    final safeName = rawName.isEmpty ? 'Oyuncu' : rawName;
    final name = safeName.length <= 40 ? safeName : safeName.substring(0, 40);
    final avatarUrl = metadata['avatar_url'] as String?;
    final raw = await _client.rpc(
      'okeyx_ensure_profile',
      params: {'p_display_name': name, 'p_avatar_url': avatarUrl},
    );
    final json = _asMap(raw);
    return PlayerProfile.fromJson(
      json,
      vipLevel: (json['vip_level'] as num?)?.toInt() ?? 0,
    );
  }

  Future<PlayerProfile> updateProfile({
    required String displayName,
    String? avatarUrl,
    String? avatarSeed,
  }) async {
    final raw = await _client.rpc(
      'okeyx_update_profile',
      params: {
        'p_display_name': displayName.trim(),
        'p_avatar_url': avatarUrl,
        'p_avatar_seed': avatarSeed,
      },
    );
    final json = _asMap(raw);
    return PlayerProfile.fromJson(
      json,
      vipLevel: (json['vip_level'] as num?)?.toInt() ?? 0,
    );
  }

  Future<UserPreferences> loadPreferences() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('auth_session_missing');
    final row = await _client
        .from('okeyx_user_preferences')
        .select()
        .eq('auth_user_id', user.id)
        .maybeSingle();
    return row == null ? const UserPreferences() : UserPreferences.fromJson(row);
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('auth_session_missing');
    await _client.from('okeyx_user_preferences').upsert({
      'auth_user_id': user.id,
      ...preferences.toJson(),
    });
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    throw const FormatException('profile_response_invalid');
  }
}
