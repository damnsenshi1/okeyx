import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/app_updater.dart';
import '../../core/game_audio.dart';
import '../../core/live_features.dart';
import '../../core/remote_config.dart';
import '../../widgets/okx_kit.dart';
import '../../widgets/tile_widget.dart';
import '../auth/auth_service.dart';
import '../auth/avatar_service.dart';
import '../auth/profile_repository.dart';

class SettingsScreen extends StatefulWidget {
  final PlayerProfile profile;
  final UserPreferences preferences;
  final ProfileRepository repository;
  final AuthService auth;
  final MobileRemoteConfig remoteConfig;
  final String? publicId;
  final ValueChanged<PlayerProfile> onProfileChanged;
  final Future<void> Function()? onDeleteGameData;
  final Future<void> Function(Map<String, bool> prefs)? onNotificationPrefs;
  final Future<Map<String, dynamic>> Function(String topic, String message, String orderId)? onSupportTicket;
  final ValueChanged<UserPreferences> onPreferencesChanged;
  // Sunucu hesabındaki gerçek ilerleme (verilmezse yerel profil kullanılır).
  final int? level;
  final int? xp;
  final int? levelXpStart;
  final int? nextLevelXp;
  final int? gamesPlayed;
  final int? wins;

  const SettingsScreen({
    this.level,
    this.xp,
    this.levelXpStart,
    this.nextLevelXp,
    this.gamesPlayed,
    this.wins,
    super.key,
    this.onDeleteGameData,
    this.onNotificationPrefs,
    this.onSupportTicket,
    required this.profile,
    required this.preferences,
    required this.repository,
    required this.auth,
    required this.remoteConfig,
    this.publicId,
    required this.onProfileChanged,
    required this.onPreferencesChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late PlayerProfile _profile = widget.profile;
  late UserPreferences _preferences = widget.preferences;
  late final TextEditingController _nameController;
  late String _selectedSeed;
  int _section = 0;
  bool _busy = false;
  OkeyXLiveFeatures _liveFeatures = const OkeyXLiveFeatures();
  final ScrollController _sectionScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _profile.displayName);
    _selectedSeed = _profile.avatarSeed ?? 'teal';
    unawaited(_loadLiveFeatures());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sectionScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLiveFeatures() async { final f=await LiveFeatureService().load(); if(mounted)setState(()=>_liveFeatures=f); }

  Future<void> _pickAvatar() async {
    if (_busy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: OkxLeather(
            stitch: true,
            radius: 22,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.account_circle_rounded, color: OkeyXColors.gold),
                SizedBox(width: 9),
                OkxTitle('Profil fotoğrafı', size: 18),
              ]),
              const SizedBox(height: 4),
              const Text('JPEG, PNG veya WEBP seç; ardından kare kırpma ekranı açılır.', style: TextStyle(fontSize: 12, color: OkeyXColors.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OkxButton(label: 'GALERİ', icon: Icons.photo_library_rounded, expand: true, onTap: () => Navigator.pop(sheetContext, ImageSource.gallery))),
                const SizedBox(width: 10),
                Expanded(child: OkxButton.ghost(label: 'KAMERA', icon: Icons.photo_camera_rounded, expand: true, onTap: () => Navigator.pop(sheetContext, ImageSource.camera))),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    final old = _profile.avatarUrl;
    try {
      final url = await AvatarService(Supabase.instance.client).pickAndUpload(source: source);
      if (url == null) return;
      final updated = await widget.repository.updateProfile(displayName: _nameController.text.trim(), avatarUrl: url, avatarSeed: _selectedSeed);
      if (old != null && old != url) unawaited(AvatarService(Supabase.instance.client).deleteOwned(old));
      if (!mounted) return;
      setState(() => _profile = updated.copyWith(vipLevel: _profile.vipLevel));
      widget.onProfileChanged(_profile);
      _snack('Profil fotoğrafın uygulandı.');
    } catch (e) {
      _snack('$e'.contains('too_large') ? 'Fotoğraf en fazla 3 MB olabilir.' : 'Fotoğraf yüklenemedi.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _removeAvatar() async {if(_busy||_profile.avatarUrl==null)return;setState(()=>_busy=true);final old=_profile.avatarUrl;try{final u=await widget.repository.updateProfile(displayName:_nameController.text.trim(),avatarUrl:null,avatarSeed:_selectedSeed);await AvatarService(Supabase.instance.client).deleteOwned(old);if(!mounted)return;setState(()=>_profile=u.copyWith(clearAvatar:true,vipLevel:_profile.vipLevel));widget.onProfileChanged(_profile);_snack('Profil fotoğrafın kaldırıldı.');}catch(_){_snack('Fotoğraf kaldırılamadı.',error:true);}finally{if(mounted)setState(()=>_busy=false);}}
  Future<void> _applyAudio(UserPreferences v) async {
    await GameAudio.setVolumes(
      music: v.musicVolume,
      radio: v.radioVolume,
      ambience: v.ambienceVolume,
      sfx: v.sfxVolume,
    );
    if (v.radioEnabled && _liveFeatures.radioEnabled) {
      final st = _liveFeatures.station(v.radioStation);
      try {
        await GameAudio.startRadio(source: st.source, remote: st.remote);
      } catch (_) {
        await GameAudio.startLobby(enabled: v.musicEnabled);
      }
    } else {
      await GameAudio.stopRadio();
      if (v.musicEnabled) {
        await GameAudio.startLobby();
      } else {
        await GameAudio.stopLobby();
      }
    }
  }

  Future<void> _saveProfile(String name, String seed) async {
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.updateProfile(
        displayName: name,
        avatarUrl: _profile.avatarUrl,
        avatarSeed: seed,
      );
      if (!mounted) return;
      setState(() => _profile = updated.copyWith(vipLevel: _profile.vipLevel));
      widget.onProfileChanged(_profile);
      _snack('Profilin kaydedildi.');
    } catch (_) {
      _snack('Profil kaydedilemedi.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreferences(UserPreferences value) async {
    final before = _preferences;
    setState(() => _preferences = value);
    try {
      await widget.repository.savePreferences(value);
      widget.onPreferencesChanged(value);
      unawaited(_applyAudio(value));
    } catch (_) {
      if (mounted) setState(() => _preferences = before);
      _snack('Ayar kaydedilemedi.', error: true);
    }
  }

  static const _tabs = <(IconData, String)>[
    (Icons.person_rounded, 'Profil'),
    (Icons.sports_esports_rounded, 'Oyun ve görünüm'),
    (Icons.volume_up_rounded, 'Ses ve titreşim'),
    (Icons.notifications_rounded, 'Bildirimler'),
    (Icons.verified_user_rounded, 'Hesap ve güvenlik'),
    (Icons.support_agent_rounded, 'Destek ve yasal'),
  ];

  // Sunucudaki gerçek değerler (ana ekran üst barıyla aynı kaynak).
  int get _level => widget.level ?? _profile.level;
  int get _xp => widget.xp ?? _profile.xp;
  int get _games => widget.gamesPlayed ?? _profile.gamesPlayed;
  int get _wins => widget.wins ?? _profile.wins;
  double get _levelProgress {
    final start = widget.levelXpStart ?? 0;
    final next = widget.nextLevelXp ?? 0;
    if (next > start) return ((_xp - start) / (next - start)).clamp(0.0, 1.0).toDouble();
    return ((_xp % 1000) / 1000).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: OkeyXColors.ink,
        body: OkxRoom(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 780 || constraints.maxHeight < 380;
                final sections = [
                  _profileSection,
                  _gameSection,
                  _soundSection,
                  _notificationSection,
                  _accountSection,
                  _legalSection,
                ];
                return Padding(
                  padding: EdgeInsets.fromLTRB(compact ? 8 : 16, compact ? 8 : 12, compact ? 10 : 16, compact ? 8 : 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: compact ? 60 : 236,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              _roundButton(Icons.arrow_back_rounded, () => Navigator.pop(context)),
                              if (!compact) ...[
                                const SizedBox(width: 12),
                                const Expanded(child: OkxTitle('Ayarlar', size: 24)),
                              ],
                            ]),
                            SizedBox(height: compact ? 10 : 16),
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  for (var i = 0; i < _tabs.length; i++) _sectionButton(i, _tabs[i].$1, _tabs[i].$2, compact),
                                ],
                              ),
                            ),
                            if (!compact) _meCard(),
                          ],
                        ),
                      ),
                      SizedBox(width: compact ? 8 : 16),
                      Expanded(
                        child: OkxLeather(
                          radius: compact ? 18 : 24,
                          padding: EdgeInsets.zero,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(compact ? 18 : 24),
                            child: SingleChildScrollView(
                              controller: _sectionScrollController,
                              padding: EdgeInsets.fromLTRB(compact ? 14 : 24, compact ? 12 : 18, compact ? 14 : 24, compact ? 16 : 24),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 860),
                                  child: sections[_section](),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );

  Widget _roundButton(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: OkxLeather(
          radius: 999,
          width: 44,
          height: 44,
          padding: EdgeInsets.zero,
          child: Center(child: Icon(icon, size: 21, color: const Color(0xFFFFE9B0))),
        ),
      );

  Widget _meCard() => OkxLeather(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(children: [
          OkxAvatar(name: _profile.displayName, imageUrl: _profile.avatarUrl, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
              const SizedBox(height: 2),
              Text('$_publicIdValue • LV $_level', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: OkeyXColors.muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );

  Widget _sectionButton(int index, IconData icon, String label, bool compact) {
    final selected = _section == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_section == index) return;
          setState(() => _section = index);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_sectionScrollController.hasClients) _sectionScrollController.jumpTo(0);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: compact ? 50 : 48,
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(colors: [Color(0x33FFD278), Color(0x0AFFD278)])
                : null,
            border: Border.all(color: selected ? OkeyXColors.line2 : Colors.transparent, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: selected ? OkeyXColors.gold : OkeyXColors.muted),
              if (!compact) ...[
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? const Color(0xFFFFE3A0) : OkeyXColors.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── PROFİL ─────────────────────────

  Widget _profileSection() {
    final winRate = _games <= 0 ? 0 : ((_wins * 100) / _games).round();
    return _panel(
      title: 'Oyuncu vitrini',
      subtitle: 'Masada görünen kimliğin, seviyen ve oyuncu numaran.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0x40FFD278), Color(0x10000000)]),
              border: Border.all(color: OkeyXColors.line2),
            ),
            child: Wrap(
              spacing: 18,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  OkxAvatar(name: _profile.displayName, imageUrl: _profile.avatarUrl, size: 88, highlight: true),
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    OkxButton.ghost(
                      label: _profile.avatarUrl == null ? 'FOTO EKLE' : 'DEĞİŞTİR',
                      icon: Icons.photo_camera_rounded,
                      height: 32,
                      fontSize: 11,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      onTap: _busy ? null : _pickAvatar,
                    ),
                    if (_profile.avatarUrl != null) ...[
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _busy ? null : _removeAvatar,
                        child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, size: 20, color: OkeyXColors.danger)),
                      ),
                    ],
                  ]),
                ]),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(_profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: OkeyXFonts.serif, fontSize: 24, fontWeight: FontWeight.w700, color: OkeyXColors.cream))),
                        if (_profile.vipLevel > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(gradient: brassGradient, borderRadius: BorderRadius.circular(9)),
                            child: Text('VIP ${_profile.vipLevel}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: okxTextDark)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.badge_rounded, size: 16, color: OkeyXColors.cyan),
                        const SizedBox(width: 6),
                        SelectableText(_publicIdValue, style: const TextStyle(fontSize: 13, color: OkeyXColors.cyan, fontWeight: FontWeight.w800, letterSpacing: .8)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: _publicIdValue));
                            _snack('Oyuncu ID kopyalandı.');
                          },
                          child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.copy_rounded, size: 16, color: OkeyXColors.muted)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('LV $_level', style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 13, color: OkeyXColors.gold)),
                        const SizedBox(width: 9),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: SizedBox(
                              height: 7,
                              child: Stack(fit: StackFit.expand, children: [
                                const ColoredBox(color: Color(0x80000000)),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _levelProgress,
                                  child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3CCF8E), Color(0xFF9FF0C6)]))),
                                ),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text('${okxFormat(_xp)} XP', style: const TextStyle(fontSize: 11.5, color: OkeyXColors.muted, fontWeight: FontWeight.w700)),
                      ]),
                      if (_profile.isGuest) ...[
                        const SizedBox(height: 8),
                        const Text('Misafir hesaptasın. Google veya e-posta bağlarsan ilerlemen cihazdan bağımsız korunur.', style: TextStyle(fontSize: 11.5, color: OkeyXColors.gold, fontWeight: FontWeight.w700, height: 1.3)),
                      ],
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _profileMiniStat('RATING', '${_profile.rating}', Icons.military_tech_rounded),
                    _profileMiniStat('OYUN', okxFormat(_games), Icons.casino_rounded),
                    _profileMiniStat('GALİBİYET', okxFormat(_wins), Icons.emoji_events_rounded),
                    _profileMiniStat('ORAN', '%$winRate', Icons.trending_up_rounded),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const OkxLabel('OYUNCU ADI'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                maxLength: 32,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(hintText: 'Masada görünecek adın', counterText: '', prefixIcon: Icon(Icons.edit_rounded)),
              ),
            ),
            const SizedBox(width: 10),
            OkxButton(
              label: 'KAYDET',
              icon: Icons.save_rounded,
              height: 48,
              onTap: _busy
                  ? null
                  : () {
                      final value = _nameController.text.trim();
                      if (value.length < 2) {
                        _snack('Oyuncu adı en az 2 karakter olmalı.', error: true);
                        return;
                      }
                      _saveProfile(value, _selectedSeed);
                    },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _profileMiniStat(String label, String value, IconData icon) => Container(
        width: 128,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: const Color(0x52000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: OkeyXColors.line)),
        child: Row(children: [
          Icon(icon, size: 18, color: OkeyXColors.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: OkeyXColors.muted, fontWeight: FontWeight.w800, letterSpacing: .6)),
              const SizedBox(height: 1),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
            ]),
          ),
        ]),
      );

  // ───────────────────────── OYUN VE GÖRÜNÜM ─────────────────────────

  bool get _isVip => _profile.vipLevel > 0;

  Widget _gameSection() {
    const vipFelts = {'anthracite'};
    const vipRacks = {'ebony'};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _panel(
          title: 'Masa çuhası',
          subtitle: 'Oyun masasının kumaş rengi. Hemen uygulanır.',
          child: _grid(
            minItemWidth: 150,
            children: [
              for (final t in okxFeltThemes)
                _themeCard(
                  label: t.$2,
                  vip: vipFelts.contains(t.$1),
                  selected: _preferences.tableTheme == t.$1,
                  preview: Stack(fit: StackFit.expand, children: [
                    OkxFelt(theme: t.$1, borderRadius: BorderRadius.circular(10)),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 7,
                      height: 15,
                      child: DecoratedBox(decoration: walnutDecoration(radius: BorderRadius.circular(4), deep: false, rack: _preferences.rackStyle)),
                    ),
                  ]),
                  onTap: () => _pickVisual(vip: vipFelts.contains(t.$1), apply: () => _savePreferences(_preferences.copyWith(tableTheme: t.$1))),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _panel(
          title: 'Istaka ve taş',
          subtitle: 'Istakanın ağacı ve taş rakamlarının boyu.',
          child: _grid(
            minItemWidth: 150,
            children: [
              for (final r in okxRackStyles)
                _themeCard(
                  label: '${r.$2} ıstaka',
                  vip: vipRacks.contains(r.$1),
                  selected: _preferences.rackStyle == r.$1,
                  preview: DecoratedBox(
                    decoration: walnutDecoration(radius: BorderRadius.circular(10), deep: false, rack: r.$1),
                    child: _tilePreview(),
                  ),
                  onTap: () => _pickVisual(vip: vipRacks.contains(r.$1), apply: () => _savePreferences(_preferences.copyWith(rackStyle: r.$1))),
                ),
              _themeCard(
                label: 'Büyük rakam',
                selected: _preferences.bigTileNumbers,
                preview: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3A3F46), Color(0xFF1C1F24)]),
                  ),
                  child: _tilePreview(big: true),
                ),
                onTap: () => _savePreferences(_preferences.copyWith(bigTileNumbers: !_preferences.bigTileNumbers)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _panel(
          title: 'Oynanış ve performans',
          child: _grid(
            minItemWidth: 300,
            children: [
              _segmentRow(
                'Animasyonlar',
                'Taş uçuşu, açılış duyurusu ve hediye efektleri',
                Icons.motion_photos_on_rounded,
                const ['TAM', 'SADE'],
                _preferences.reducedMotionEnabled ? 1 : 0,
                (i) => _savePreferences(_preferences.copyWith(reducedMotionEnabled: i == 1)),
              ),
              _switch('Hediye animasyonları', 'Terlik, çay, gül ve büyük hediyeler hareketli', Icons.auto_awesome_rounded, _preferences.giftAnimations, (v) => _savePreferences(_preferences.copyWith(giftAnimations: v))),
              _switch('Düşük cihaz modu', 'Yoğun efektleri kapatır, pili korur', Icons.data_saver_on_rounded, _preferences.dataSaverEnabled, (v) => _savePreferences(_preferences.copyWith(dataSaverEnabled: v))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tilePreview({bool big = false}) => Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final t in const [
            GameTile(id: 'p7', number: 7, colorIndex: 0),
            GameTile(id: 'p8', number: 8, colorIndex: 1),
            GameTile(id: 'p9', number: 9, colorIndex: 2),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: SizedBox(width: 24, height: 34, child: TileWidget(tile: t, bigNumber: big || _preferences.bigTileNumbers)),
            ),
        ]),
      );

  void _pickVisual({required bool vip, required VoidCallback apply}) {
    if (vip && !_isVip) {
      _snack('Bu görünüm VIP üyelere özel. Mağazadan VIP olabilirsin.');
      return;
    }
    apply();
  }

  Widget _themeCard({
    required String label,
    required bool selected,
    required Widget preview,
    required VoidCallback onTap,
    bool vip = false,
  }) {
    final locked = vip && !_isVip;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0x40000000),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: selected ? OkeyXColors.gold : OkeyXColors.line, width: selected ? 2 : 1.4),
          boxShadow: selected ? const [BoxShadow(color: Color(0x33FFC864), blurRadius: 16)] : const [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 60,
            width: double.infinity,
            child: Stack(fit: StackFit.expand, children: [
              preview,
              if (locked)
                const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x73000000), borderRadius: BorderRadius.all(Radius.circular(10))),
                  child: Center(child: Icon(Icons.lock_rounded, color: OkeyXColors.gold, size: 22)),
                ),
              if (selected)
                const Positioned(
                  top: 5,
                  right: 5,
                  child: CircleAvatar(radius: 10, backgroundColor: OkeyXColors.gold, child: Icon(Icons.check_rounded, size: 14, color: okxTextDark)),
                ),
            ]),
          ),
          const SizedBox(height: 7),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: selected ? const Color(0xFFFFE3A0) : OkeyXColors.muted),
              ),
            ),
            if (vip) ...[
              const SizedBox(width: 5),
              const Text('VIP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: OkeyXColors.gold)),
            ],
          ]),
        ]),
      ),
    );
  }

  // ───────────────────────── SES VE TİTREŞİM ─────────────────────────

  Widget _soundSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(
            title: 'Ses',
            subtitle: 'Müzik yalnızca ana ekranda çalar; masada sadece taş ve oyun sesleri olur.',
            child: _grid(
              minItemWidth: 320,
              children: [
                _switch('Ana ekran müziği', 'Lobide canlı OkeyX müziği', Icons.music_note_rounded, _preferences.musicEnabled, (v) => _savePreferences(_preferences.copyWith(musicEnabled: v))),
                _volumeControl('Müzik seviyesi', Icons.music_note_rounded, _preferences.musicVolume, (v) {
                  setState(() => _preferences = _preferences.copyWith(musicVolume: v));
                  unawaited(GameAudio.setVolumes(music: v));
                }, (v) => _savePreferences(_preferences.copyWith(musicVolume: v))),
                _switch('Oyun sesleri', 'Taş çekme, atma, açılış, hediye ve sonuç', Icons.volume_up_rounded, _preferences.soundEnabled, (v) => _savePreferences(_preferences.copyWith(soundEnabled: v))),
                _volumeControl('Efekt seviyesi', Icons.graphic_eq_rounded, _preferences.sfxVolume, (v) {
                  setState(() => _preferences = _preferences.copyWith(sfxVolume: v));
                  unawaited(GameAudio.setVolumes(sfx: v));
                }, (v) => _savePreferences(_preferences.copyWith(sfxVolume: v))),
                _switch('Masa ambiyansı', 'Hafif kahvehane uğultusu (müzik değil)', Icons.nights_stay_rounded, _preferences.tableAmbienceEnabled, (v) => _savePreferences(_preferences.copyWith(tableAmbienceEnabled: v))),
                _volumeControl('Ambiyans seviyesi', Icons.surround_sound_rounded, _preferences.ambienceVolume, (v) {
                  setState(() => _preferences = _preferences.copyWith(ambienceVolume: v));
                  unawaited(GameAudio.setVolumes(ambience: v));
                }, (v) => _savePreferences(_preferences.copyWith(ambienceVolume: v))),
                _switch('Kazanan müziği', 'Kazananın kısa zafer teması', Icons.library_music_rounded, _preferences.opponentMusicKits, (v) => _savePreferences(_preferences.copyWith(opponentMusicKits: v))),
                _switch('Titreşim', 'Sıra sende, okey ve bitişte hafif titreşim', Icons.vibration_rounded, _preferences.vibrationEnabled, (v) => _savePreferences(_preferences.copyWith(vibrationEnabled: v))),
              ],
            ),
          ),
          if (_liveFeatures.radioEnabled) ...[
            const SizedBox(height: 18),
            _panel(
              title: 'OkeyX Radyo',
              subtitle: 'Masada müzik isteyenler için. Ana ekrandaki radyo düğmesinden de açılır.',
              child: _grid(
                minItemWidth: 320,
                children: [
                  _switch('Radyo', 'Açıkken lobi müziği yerine radyo çalar', Icons.radio_rounded, _preferences.radioEnabled, (v) => _savePreferences(_preferences.copyWith(radioEnabled: v))),
                  _volumeControl('Radyo seviyesi', Icons.radio_rounded, _preferences.radioVolume, (v) {
                    setState(() => _preferences = _preferences.copyWith(radioVolume: v));
                    unawaited(GameAudio.setVolumes(radio: v));
                  }, (v) => _savePreferences(_preferences.copyWith(radioVolume: v))),
                  if (_preferences.radioEnabled && _liveFeatures.radioStations.isNotEmpty)
                    _row(
                      icon: Icons.queue_music_rounded,
                      title: 'Kanal',
                      trailing: SizedBox(
                        width: 190,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: const Color(0xFA120B33),
                            borderRadius: BorderRadius.circular(14),
                            value: _liveFeatures.radioStations.any((x) => x.id == _preferences.radioStation) ? _preferences.radioStation : _liveFeatures.radioStations.first.id,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: OkeyXColors.cream, fontFamily: OkeyXFonts.sans),
                            items: [for (final x in _liveFeatures.radioStations) DropdownMenuItem(value: x.id, child: Text(x.title, overflow: TextOverflow.ellipsis))],
                            onChanged: (v) {
                              if (v != null) _savePreferences(_preferences.copyWith(radioStation: v));
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );

  // ───────────────────────── BİLDİRİMLER ─────────────────────────

  Widget _notificationSection() => _panel(
        title: 'Bildirimler',
        subtitle: 'Telefonuna gelecek hatırlatmalar. İstediğin zaman kapatabilirsin.',
        child: _grid(
          minItemWidth: 320,
          children: [
            _switch('Tüm bildirimler', 'Kapalıyken hiçbir bildirim gelmez', Icons.notifications_active_rounded, _preferences.notificationsEnabled, (v) {
              _savePreferences(_preferences.copyWith(notificationsEnabled: v));
              _pushPrefs({'push': v});
            }),
            if (_preferences.notificationsEnabled) ...[
              _switch('Arkadaşlık', 'Yeni istek ve kabul', Icons.person_add_alt_1_rounded, _pushPref['friend'] ?? true, (v) => _pushPrefs({'friend': v})),
              _switch('Masa davetleri', 'Arkadaşın seni masaya çağırınca', Icons.table_bar_rounded, _pushPref['invite'] ?? true, (v) => _pushPrefs({'invite': v})),
              _switch('Etkinlik ve turnuva', 'Yeni etkinlik, çanak ve turnuvalar', Icons.emoji_events_rounded, _pushPref['event'] ?? true, (v) => _pushPrefs({'event': v})),
              _switch('Günlük ödül', 'Ödülün hazır olunca hatırlat', Icons.card_giftcard_rounded, _pushPref['daily'] ?? true, (v) => _pushPrefs({'daily': v})),
            ],
          ],
        ),
      );

  // ───────────────────────── HESAP ─────────────────────────

  Widget _accountSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(
            title: _profile.isGuest ? 'Misafir hesabını güvenceye al' : 'Bağlı hesap',
            subtitle: _profile.isGuest ? 'Google veya e-posta bağladığında bu profil ve ilerleme kaybolmaz.' : 'Oturumun güvenli biçimde saklanıyor.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_profile.isGuest && widget.remoteConfig.googleEnabled) ...[
                  OkxButton(label: 'GOOGLE HESABINI BAĞLA', icon: Icons.account_circle_rounded, height: 50, expand: true, onTap: _busy ? null : _linkGoogle),
                  const SizedBox(height: 10),
                ],
                if (_profile.isGuest) ...[
                  OkxButton.ghost(label: 'E-POSTA BAĞLA', icon: Icons.mail_rounded, height: 50, expand: true, onTap: _busy ? null : _linkEmail),
                  const SizedBox(height: 10),
                ],
                if (!_profile.isGuest) ...[
                  _row(icon: Icons.verified_user_rounded, iconColor: OkeyXColors.cyan, title: 'Hesap doğrulandı', detail: 'Profilin bu cihazdan bağımsız olarak korunuyor.'),
                  const SizedBox(height: 10),
                ],
                OkxButton.ghost(label: _profile.isGuest ? 'MİSAFİR OTURUMUNDAN ÇIK' : 'OTURUMU KAPAT', icon: Icons.logout_rounded, height: 48, expand: true, onTap: _busy ? null : _signOut),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _panel(
            title: 'Hesap yönetimi',
            subtitle: 'Silme işlemi geri alınamaz. Oyun geçmişi anonim istatistik olarak kalabilir.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: OkxButton(label: 'HESABI KALICI OLARAK SİL', icon: Icons.delete_forever_rounded, style: OkxButtonStyle.red, height: 46, onTap: _busy ? null : _deleteAccount),
            ),
          ),
        ],
      );

  // ───────────────────────── DESTEK VE YASAL ─────────────────────────

  Widget _legalSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.onSupportTicket != null) ...[
            _panel(
              title: 'Destek',
              subtitle: 'Satın alma, iade, hesap ya da hata bildirimi için bize yaz.',
              child: Align(
                alignment: Alignment.centerLeft,
                child: OkxButton(label: 'DESTEK / İADE TALEBİ', icon: Icons.support_agent_rounded, height: 46, onTap: _openSupport),
              ),
            ),
            const SizedBox(height: 18),
          ],
          _panel(
            title: 'Uygulama güncellemesi',
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Yüklü sürüm: v${AppConfig.versionName} (derleme ${AppUpdater.currentBuild})', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Yeni sürüm çıktığında oyun açılışta sorar. İstersen buradan hemen denetleyebilirsin.', style: TextStyle(fontSize: 12, color: OkeyXColors.muted)),
                ]),
              ),
              const SizedBox(width: 12),
              OkxButton(label: 'GÜNCELLEMELERİ DENETLE', icon: Icons.system_update_rounded, height: 44, onTap: () => AppUpdater.checkAndPrompt(context, force: true)),
            ]),
          ),
          const SizedBox(height: 18),
          _panel(
            title: 'Yasal ve gizlilik',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _legalBlock('KULLANIM KOŞULLARI', 'OkeyX eğlence amaçlı bir 101 Okey oyunudur. Hile, taciz, hesap satışı ve oyun ekonomisini kötüye kullanmak yasaktır. Sanal varlıkların gerçek para değeri yoktur ve nakde çevrilemez.'),
                _legalBlock('GİZLİLİK', 'Oturum, profil, oyun istatistiği ve cihaz tercihleri hizmeti çalıştırmak için işlenir. Parola uygulama veritabanında tutulmaz; kimlik doğrulama Supabase Auth tarafından yönetilir. Hesabını Ayarlar > Hesap ve güvenlik bölümünden silebilirsin.'),
                _legalBlock('SÜRÜM', 'OkeyX v${AppConfig.versionName}'),
              ],
            ),
          ),
        ],
      );

  Widget _legalBlock(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OkxLabel(title, color: OkeyXColors.gold),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 13, color: Color(0xFFD9CBAE), height: 1.5, fontWeight: FontWeight.w500)),
        ]),
      );

  // ───────────────────────── ORTAK PARÇALAR ─────────────────────────

  Widget _panel({required String title, String? subtitle, required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OkxTitle(title, size: 19, color: const Color(0xFFFFE9B0)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: OkeyXColors.muted, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      );

  /// Genişliğe göre 1–4 sütunlu düzen.
  Widget _grid({required double minItemWidth, required List<Widget> children}) => LayoutBuilder(
        builder: (context, c) {
          const gap = 10.0;
          final cols = (c.maxWidth / minItemWidth).floor().clamp(1, 4);
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final child in children) SizedBox(width: w, child: child)],
          );
        },
      );

  Widget _row({required IconData icon, required String title, String? detail, Widget? trailing, Color? iconColor, VoidCallback? onTap}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 62),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: const Color(0x40000000),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1FE8C478)),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0x1AFFD278),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0x4DE8C478)),
              ),
              child: Icon(icon, size: 19, color: iconColor ?? const Color(0xFFFFD98A)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: OkeyXColors.cream)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: OkeyXColors.muted, fontWeight: FontWeight.w600, height: 1.25)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ]),
        ),
      );

  Widget _switch(String title, String detail, IconData icon, bool value, ValueChanged<bool> onChanged) => _row(
        icon: icon,
        title: title,
        detail: detail,
        onTap: () => onChanged(!value),
        trailing: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: value ? const LinearGradient(colors: [Color(0xFF1F8F5D), Color(0xFF3CCF8E)]) : null,
            color: value ? null : const Color(0x1FFFFFFF),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : const Color(0xFFACA7DB),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
          ),
        ),
      );

  Widget _segmentRow(String title, String detail, IconData icon, List<String> options, int selected, ValueChanged<int> onChanged) => _row(
        icon: icon,
        title: title,
        detail: detail,
        trailing: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(11)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < options.length; i++)
              GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: i == selected ? brassGradient : null,
                  ),
                  child: Text(options[i], style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: i == selected ? okxTextDark : OkeyXColors.muted)),
                ),
              ),
          ]),
        ),
      );

  Widget _volumeControl(String title, IconData icon, double value, ValueChanged<double> onChanged, ValueChanged<double> onChangeEnd) => _row(
        icon: icon,
        title: title,
        trailing: SizedBox(
          width: 170,
          child: Row(children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 6, overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
                child: Slider(value: value.clamp(0.0, 1.0).toDouble(), min: 0, max: 1, onChanged: onChanged, onChangeEnd: onChangeEnd),
              ),
            ),
            SizedBox(
              width: 34,
              child: Text('${(value * 100).round()}', textAlign: TextAlign.right, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 12.5, color: OkeyXColors.gold)),
            ),
          ]),
        ),
      );

  Future<void> _linkGoogle() async {
    setState(() => _busy = true);
    try {
      await widget.auth.signInWithGoogle(linkCurrentUser: true);
    } catch (error) {
      _snack(
        '$error'.contains('manual')
            ? 'Supabase panelinde manuel hesap bağlama açılmalı.'
            : 'Google hesabı bağlanamadı.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkEmail() async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('E-posta bağla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'E-postana doğrulama bağlantısı göndereceğiz. Doğrulama tamamlanınca parola oluşturabilirsin.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-posta'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || !email.contains('@')) return;
    setState(() => _busy = true);
    try {
      await widget.auth.attachEmail(email);
      _snack('Doğrulama bağlantısı gönderildi.');
    } catch (_) {
      _snack(
        'E-posta bağlanamadı. Adres başka hesaba ait olabilir.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final accepted = await _confirm(
      'Oturumu kapat?',
      _profile.isGuest
          ? 'Misafir hesaptan çıkarsan bu ilerlemeye tekrar ulaşamayabilirsin.'
          : 'Bu cihazdaki oturum kapanacak.',
    );
    if (!accepted) return;
    setState(() => _busy = true);
    await widget.auth.signOut();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hesabı kalıcı sil'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Bu işlem geri alınamaz. Onaylamak için SİL yaz.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'SİL'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: OkeyXColors.danger,
                ),
                onPressed: () => Navigator.pop(
                  context,
                  controller.text.trim().toUpperCase() == 'SİL',
                ),
                child: const Text('HESABI SİL'),
              ),
            ],
          ),
        ) ??
        false;
    controller.dispose();
    if (!accepted) return;
    setState(() => _busy = true);
    try {
      try {
        await widget.onDeleteGameData?.call();
      } catch (_) {}
      await widget.auth.deleteAccount();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _snack('Hesap silinemedi. Oturumu yenileyip tekrar dene.', error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Onayla'),
            ),
          ],
        ),
      ) ??
      false;

  String get _publicIdValue {
    final supplied = (widget.publicId ?? '').trim();
    if (supplied.isNotEmpty) return supplied;
    final digits = _profile.userId.codeUnits.fold<int>(17, (a, b) => ((a * 31) + b) & 0x7fffffff) % 900000 + 100000;
    return 'OX-${digits.toString().padLeft(6, '0')}';
  }


  final Map<String, bool> _pushPref = <String, bool>{};

  void _pushPrefs(Map<String, bool> prefs) {
    setState(() => _pushPref.addAll(prefs));
    final fn = widget.onNotificationPrefs;
    if (fn != null) {
      fn(prefs).catchError((Object _) {});
    }
  }

  Future<void> _openSupport() async {
    final message = TextEditingController();
    final order = TextEditingController();
    var topic = 'purchase';
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Destek / İade talebi'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButton<String>(
                value: topic,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'purchase', child: Text('Yanlışlıkla satın alma / iade')),
                  DropdownMenuItem(value: 'missing', child: Text('Satın aldım, ürün gelmedi')),
                  DropdownMenuItem(value: 'account', child: Text('Hesap sorunu')),
                  DropdownMenuItem(value: 'bug', child: Text('Hata bildirimi')),
                ],
                onChanged: (v) => setLocal(() => topic = v ?? 'purchase'),
              ),
              TextField(controller: order, maxLength: 64, decoration: const InputDecoration(labelText: 'Sipariş no (GPA.... varsa)')),
              TextField(controller: message, maxLength: 800, maxLines: 4, decoration: const InputDecoration(labelText: 'Ne oldu?')),
              const Text('Google Play iadeleri için play.google.com > Siparişler bölümünü de kullanabilirsin. İade edilen satın alımların ürünleri hesaptan otomatik geri alınır.', style: TextStyle(fontSize: 10, color: Colors.white54)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('GÖNDER')),
          ],
        ),
      ),
    );
    final text = message.text.trim();
    final orderId = order.text.trim();
    message.dispose();
    order.dispose();
    if (sent != true) return;
    if (text.length < 5) {
      _snack('Lütfen sorunu birkaç kelimeyle yaz.', error: true);
      return;
    }
    final fn = widget.onSupportTicket;
    if (fn == null) return;
    try {
      final out = await fn(topic, text, orderId);
      if (out['ok'] == true) {
        _snack('Talebin alındı. Talep no: ${out['ticket_id']}');
      } else {
        _snack(out['code'] == 'ticket_limit' ? 'Bugün çok fazla talep gönderdin.' : 'Talep gönderilemedi.', error: true);
      }
    } catch (_) {
      _snack('Talep gönderilemedi. İnternetini kontrol et.', error: true);
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? const Color(0xFF8A2733) : null,
      ),
    );
  }
}
