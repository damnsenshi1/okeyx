import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter/foundation.dart';

class GameAudio {
  GameAudio._();
  static final AudioContext _ctx = AudioContext(android: AudioContextAndroid(contentType: AndroidContentType.sonification, usageType: AndroidUsageType.game, audioFocus: AndroidAudioFocus.none));
  static final AudioContext _musicCtx = AudioContext(android: AudioContextAndroid(contentType: AndroidContentType.music, usageType: AndroidUsageType.game, audioFocus: AndroidAudioFocus.none));
  static final Map<String, AudioPool> _pools = {};
  static final AudioPlayer _music = AudioPlayer(playerId:'okeyx_music');
  static final ja.AudioPlayer _radio = ja.AudioPlayer();
  static final AudioPlayer _ambience = AudioPlayer(playerId:'okeyx_ambience');
  static final AudioPlayer _victory = AudioPlayer(playerId:'okeyx_victory');
  static final AudioPlayer _voicePrompt = AudioPlayer(playerId:'okeyx_voice_prompt');
  static bool _musicPrepared=false,_musicPlaying=false,_radioPlaying=false,_ambiencePlaying=false;
  static String _radioKey='',_ambienceKey='',_soundPack='sound_classic';
  static String _tileMaterial='tiles_ivory',_rackMaterial='rack_classic';
  static double _musicVolume=.30,_sfxVolume=.78,_radioVolume=.34,_ambienceVolume=.10;
  static bool _voiceDucked=false;

  static String _assetFor(String name) {
    const swappable={'tile_pick','tile_drop','discard','take_left','rack_slide','turn'};
    // Klasik pakette her zaman gerçek melamin taş sesleri çalar (kaplamadan bağımsız).
    if(!swappable.contains(name)||_soundPack=='sound_classic')return '$name.wav';
    final suffix=switch(_soundPack){'sound_wood'=>'wood','sound_retro'=>'retro','sound_soft'=>'soft',_=>''};
    return suffix.isEmpty?'$name.wav':'${name}_$suffix.wav';
  }
  static void setSoundPack(String id){
    final next={'sound_classic','sound_wood','sound_retro','sound_soft'}.contains(id)?id:'sound_classic';
    _soundPack=next;
  }
  static void setMaterialProfile({required String tiles,required String rack}){
    _tileMaterial=tiles.isEmpty?'tiles_ivory':tiles;
    _rackMaterial=rack.isEmpty?'rack_classic':rack;
  }
  static Future<void> voiceLine(String value,{bool enabled=true})=>voice(switch(value){
    'Hadi kardeşim, ağaç olduk!'=>'voice_hadi',
    'Okey bende!'=>'voice_okey',
    'Taşını at da oynayalım!'=>'voice_fast',
    'Bol şans!'=>'voice_luck',
    'Son taş!'=>'voice_son',
    'Vay be!'=>'voice_wow',
    'Çift gidiyorum!'=>'voice_cift',
    'Eline sağlık!'=>'voice_eline',
    _=>'chat',
  },enabled:enabled,volume:.98);

  static Future<AudioPool?> _pool(String name) async {
    final asset=_assetFor(name);final key='$_soundPack:$name:$asset';
    if (_pools[key]!=null) return _pools[key];
    try {
      final p=await AudioPool.create(source:AssetSource('sfx/$asset'),maxPlayers: name.contains('tile')||name=='discard'?4:2,minPlayers:1,audioContext:_ctx);
      _pools[key]=p; return p;
    } catch(e){ debugPrint('OKEYX_AUDIO_POOL[$name/$asset] $e'); return null; }
  }
  static Future<void> prewarm({bool all=false}) async {
    for(final n in const ['ui_tap','tile_pick','tile_drop','discard','take_left','turn','countdown','warning','game_start','pair_open','series_open','reward','win','lose','slap','glass_break','shockwave','coin_shower']) { await _pool(n); }
  }
  static Future<void> setVolumes({double? music,double? sfx,double? radio,double? ambience}) async {
    if(music!=null)_musicVolume=music.clamp(0,1).toDouble(); if(sfx!=null)_sfxVolume=sfx.clamp(0,1).toDouble();
    if(radio!=null)_radioVolume=radio.clamp(0,1).toDouble(); if(ambience!=null)_ambienceVolume=ambience.clamp(0,1).toDouble();
    final factor=_voiceDucked ? .24 : 1.0; if(_musicPlaying) await _music.setVolume(_musicVolume*factor); if(_radioPlaying) await _radio.setVolume(_radioVolume*factor); if(_ambiencePlaying) await _ambience.setVolume(_ambienceVolume*(_voiceDucked ? .35 : 1));
  }

  static Future<void> setVoiceDucked(bool active) async {
    if (_voiceDucked == active) return;
    _voiceDucked = active;
    final factor = active ? .24 : 1.0;
    try {
      if (_radioPlaying) await _radio.setVolume((_radioVolume * factor).clamp(0, 1).toDouble());
      if (_musicPlaying) await _music.setVolume((_musicVolume * factor).clamp(0, 1).toDouble());
      if (_ambiencePlaying) await _ambience.setVolume((_ambienceVolume * (active ? .35 : 1)).clamp(0, 1).toDouble());
    } catch (e) {
      debugPrint('OKEYX_VOICE_DUCK $e');
    }
  }

  static Future<void> sfx(String name,{bool enabled=true,double volume=1}) async {
    if(!enabled)return; try { final p=await _pool(name); if(p!=null) await p.start(volume:(volume*_sfxVolume).clamp(.08,1).toDouble()); } catch(e){ debugPrint('OKEYX_AUDIO_SFX[$name] $e'); }
  }
  static Future<void> voice(String name,{bool enabled=true,double volume=1}) async {
    if(!enabled||name.trim().isEmpty)return;
    try{
      await setVoiceDucked(true);
      await _voicePrompt.stop();
      await _voicePrompt.setAudioContext(_musicCtx);
      await _voicePrompt.setReleaseMode(ReleaseMode.stop);
      await _voicePrompt.setVolume((volume*_sfxVolume).clamp(.16,1).toDouble());
      await _voicePrompt.play(AssetSource('sfx/${name.trim()}.wav'));
      await Future.any([_voicePrompt.onPlayerComplete.first,Future.delayed(const Duration(seconds:5))]);
    }catch(e){debugPrint('OKEYX_AUDIO_VOICE[$name] $e');}
    finally{await setVoiceDucked(false);}
  }

  static Future<void> startLobby({bool enabled=true}) async {
    if(!enabled||_musicPlaying||_radioPlaying)return; try { if(!_musicPrepared){await _music.setAudioContext(_musicCtx);await _music.setReleaseMode(ReleaseMode.loop);try{await _music.setSource(AssetSource('music/lobby_theme.mp3'));}catch(_){await _music.setSource(AssetSource('sfx/lobby_loop_v2.wav'));}_musicPrepared=true;} await _music.setVolume(_musicVolume);await _music.resume();_musicPlaying=true;}catch(e){debugPrint('OKEYX_MUSIC $e');}
  }
  static Future<void> stopLobby() async { if(_musicPlaying){try{await _music.pause();}catch(_){}} _musicPlaying=false; }
  static Future<void> startRadio({required String source,bool remote=false,bool enabled=true}) async {
    if(!enabled||source.trim().isEmpty)return;
    final clean=source.trim();
    final key='${remote?'u':'a'}:$clean';
    if(_radioPlaying&&key==_radioKey&&_radio.playing)return;
    await stopLobby();
    try{
      await _radio.stop();
      await _radio.setLoopMode(remote?ja.LoopMode.off:ja.LoopMode.one);
      if(remote){
        await _radio.setUrl(clean).timeout(const Duration(seconds:15));
      }else{
        await _radio.setAsset('assets/sfx/$clean').timeout(const Duration(seconds:8));
      }
      await _radio.setVolume(_radioVolume * (_voiceDucked ? .24 : 1.0));
      unawaited(_radio.play());
      await _radio.playingStream.firstWhere((v)=>v).timeout(const Duration(seconds:5));
      _radioPlaying=true;_radioKey=key;
      debugPrint('OKEYX_RADIO_PLAYING $clean');
    }catch(e){
      _radioPlaying=false;_radioKey='';
      try{await _radio.stop();}catch(_){}
      debugPrint('OKEYX_RADIO_ERROR $e');
      rethrow;
    }
  }
  static Future<void> stopRadio({bool resumeLobby=false}) async { try{await _radio.pause();}catch(_){} _radioPlaying=false;if(resumeLobby)await startLobby(); }
  static Future<void> startAmbience({String asset='table_ambience.wav',bool enabled=true}) async { if(!enabled)return;if(_ambiencePlaying&&_ambienceKey==asset)return;try{await _ambience.stop();await _ambience.setAudioContext(_musicCtx);await _ambience.setReleaseMode(ReleaseMode.loop);await _ambience.setSource(AssetSource('sfx/$asset'));await _ambience.setVolume(_ambienceVolume);await _ambience.resume();_ambiencePlaying=true;_ambienceKey=asset;}catch(e){debugPrint('OKEYX_AMBIENCE $e');}}
  static Future<void> stopAmbience() async {if(_ambiencePlaying){try{await _ambience.pause();}catch(_){}}_ambiencePlaying=false;}
  static Future<void> playMusicKit(String asset,{bool enabled=true,Duration maxDuration=const Duration(seconds:8)}) async {
    if(!enabled||asset.isEmpty)return;final r=_radioPlaying,m=_musicPlaying;try{if(r)await _radio.setVolume(_radioVolume*.12);if(m)await _music.setVolume(_musicVolume*.10);await _victory.stop();await _victory.setAudioContext(_musicCtx);await _victory.setReleaseMode(ReleaseMode.stop);await _victory.setVolume((_musicVolume*1.5).clamp(.25,.9).toDouble());await _victory.play(AssetSource('sfx/$asset'));await Future.any([_victory.onPlayerComplete.first,Future.delayed(maxDuration)]);}catch(e){debugPrint('OKEYX_KIT $e');}finally{final f=_voiceDucked ? .24 : 1.0;if(r&&_radioPlaying)await _radio.setVolume(_radioVolume*f);if(m&&_musicPlaying)await _music.setVolume(_musicVolume*f);}}
}
