from __future__ import annotations
import asyncio, os, secrets, time, uuid, hashlib, re, json
from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from app.services.game_runtime import ROOMS,new_room
from app.services.account_store import STORE,GIFT_CATALOG,GIFT_COOLDOWN_S
from app.services.runtime_persistence import save_runtime, load_runtime, RemoteMirror, restore_from_remote, build_runtime_blob, write_runtime_blob
from app.core.config import settings

router=APIRouter(tags=['game'])

def _now()->float:return time.time()

class ActionIn(BaseModel):
    seat:int=0
    kind:str
    payload:dict=Field(default_factory=dict)
    reconnect_token:str|None=None
    request_id:str|None=None

class CreateRoomIn(BaseModel):
    name:str='OkeyX Masası'
    variant:str='non_fold'
    entry_fee:int=5000
    assisted:bool=True
    turbo:bool=False
    team_mode:str='solo'
    rounds:int=1
    owner_name:str='Sen'
    player_id:str='local-owner'
    account_token:str=''
    turn_seconds:int=35
    password:str|None=None

class JoinRoomIn(BaseModel):
    name:str='Oyuncu'
    player_id:str='local-player'
    account_token:str=''
    turbo:bool|None=None
    variant:str|None=None
    team_mode:str|None=None
    entry_fee:int|None=None
    rounds:int|None=None
    assisted:bool|None=None
    password:str|None=None

class ChatIn(BaseModel):
    seat:int
    reconnect_token:str
    kind:str='quick'  # quick | emoji | text | voice | gift
    value:str
    to_seat:int|None=None

class LeaveIn(BaseModel):
    seat:int
    reconnect_token:str

class ReconnectIn(BaseModel):
    player_id:str
    account_token:str

class SpectatorIn(BaseModel):
    player_id:str
    account_token:str
    action:str='join'  # join | leave | react | predict
    value:str=''
    to_seat:int|None=None


class ManageRoomIn(BaseModel):
    seat:int=0
    reconnect_token:str
    action:str
    target_seat:int|None=None
    room_name:str|None=None
    turn_seconds:int|None=None
    turbo:bool|None=None
    variant:str|None=None
    team_mode:str|None=None
    entry_fee:int|None=None
    rounds:int|None=None
    assisted:bool|None=None
    chat_enabled:bool|None=None
    gifts_enabled:bool|None=None
    auto_rematch:bool|None=None
    bot_level:str|None=None

SOCKETS:dict[str,dict[int,list[WebSocket]]]={}
ROOM_META:dict[str,dict]={}
WATCHDOG_TASK:asyncio.Task|None=None
QUICK_FILL_TASKS:dict[str,asyncio.Task]={}
_RUNTIME_LOADED=False
_LAST_PERSIST_AT=0.0
_RUNTIME_DIRTY=False
_MIRROR:RemoteMirror|None=None

def _mirror()->RemoteMirror|None:
    """Supabase tanımlıysa oda anlık görüntüsünü oraya da yansıtır (Render diski geçicidir)."""
    global _MIRROR
    if _MIRROR is None and settings.remote_store_enabled:
        try:
            from app.services.remote_store import SupabaseKV
            _MIRROR=RemoteMirror(SupabaseKV(settings.supabase_url,settings.supabase_service_role_key))
        except Exception:
            return None
    return _MIRROR

def _token()->str:return secrets.token_urlsafe(24)

# Yük testi: 100+ masada her 0.35 sn'de tüm odaları paketlemek ana döngüyü
# kilitliyordu. 2 sn aralık kurtarma için yeterli, isteklere nefes aldırır.
PERSIST_MIN_INTERVAL=2.0
# Testler kaydın hemen diske düşmesini bekleyebilir.
PERSIST_SYNC=os.environ.get('OKEYX_PERSIST_SYNC','')=='1'

def _persist_runtime(force:bool=False)->None:
    global _LAST_PERSIST_AT,_RUNTIME_DIRTY
    now=time.monotonic()
    if not force and now-_LAST_PERSIST_AT<PERSIST_MIN_INTERVAL:
        _RUNTIME_DIRTY=True
        return
    try:
        raw=build_runtime_blob(ROOMS,ROOM_META)
        _LAST_PERSIST_AT=now;_RUNTIME_DIRTY=False
        path=settings.runtime_snapshot_path;secret=settings.effective_runtime_secret
        def _write():
            try:
                write_runtime_blob(path,secret,raw)
                m=_mirror()
                if m:m.maybe_push(path,force=force)
            except Exception:
                global _RUNTIME_DIRTY
                _RUNTIME_DIRTY=True
        try:
            loop=asyncio.get_running_loop()
        except RuntimeError:
            loop=None
        if loop is not None and not PERSIST_SYNC:
            # Sıkıştırma + fsync olay döngüsünü bekletmez.
            loop.run_in_executor(None,_write)
        else:
            _write()
    except Exception:
        # Persistence must never take a live table down. The watchdog will try
        # again; active in-memory multiplayer remains authoritative meanwhile.
        _RUNTIME_DIRTY=True


def _restore_runtime_once()->None:
    global _RUNTIME_LOADED
    if _RUNTIME_LOADED:return
    _RUNTIME_LOADED=True
    try:
        m=_mirror()
        if m:restore_from_remote(m.kv,settings.runtime_snapshot_path)
        rooms,meta=load_runtime(settings.runtime_snapshot_path,settings.effective_runtime_secret)
        ROOMS.update(rooms);ROOM_META.update(meta)
    except Exception:
        pass


def _touch(room_id:str)->int:
    m=_ensure_meta(room_id,legacy=True)
    m['state_version']=int(m.get('state_version',0) or 0)+1
    _persist_runtime()
    return m['state_version']

def _human_count(room_id:str)->int:
    room=ROOMS.get(room_id)
    meta=ROOM_META.get(room_id) or {}
    if not room:return 0
    return sum(1 for seat,pid in (meta.get('player_ids') or {}).items() if pid and not room.state.players[int(seat)].bot)


def _bot_count(room_id:str)->int:
    room=ROOMS.get(room_id)
    meta=ROOM_META.get(room_id) or {}
    if not room:return 0
    explicit=set(meta.get('bot_seats') or set())
    return sum(1 for seat in range(4) if seat in explicit and room.state.players[seat].bot and seat not in (meta.get('player_ids') or {}))


def _occupied_count(room_id:str)->int:
    # A seat remains occupied when its human temporarily hands control to an AFK bot.
    # Explicit bots are counted separately; union the seat indexes to avoid double counts.
    room=ROOMS.get(room_id)
    meta=ROOM_META.get(room_id) or {}
    if not room:return 0
    human_seats={int(seat) for seat,pid in (meta.get('player_ids') or {}).items() if pid}
    explicit=set(meta.get('bot_seats') or set())
    bot_seats={seat for seat in range(4) if seat in explicit and room.state.players[seat].bot and seat not in human_seats}
    return min(4,len(human_seats|bot_seats))

def _free_human_seat(room_id:str)->int|None:
    room=ROOMS.get(room_id)
    if not room:return None
    meta=_ensure_meta(room_id,legacy=True)
    explicit=set(meta.get('bot_seats') or set())
    # Hostun bilinçli eklediği bot dolu koltuktur. Gerçek oyuncu yalnızca
    # gerçekten boş placeholder koltuğa oturabilir; botu ezmek için host önce kaldırır.
    return next((seat for seat,p in room.state.players.items() if p.bot and seat not in explicit and seat not in meta.get('player_ids',{})),None)

def _account(player_id:str,account_token:str):
    a=STORE.get(player_id)
    if not a:raise HTTPException(404,'account_not_found')
    if not STORE.verify(player_id,account_token):raise HTTPException(401,'invalid_account_token')
    try:
        from app.services.phase4_service import Phase4Service
        if Phase4Service(STORE).active_sanctions(player_id).get('banned'):raise HTTPException(403,'account_banned')
    except HTTPException:raise
    except Exception:pass
    return a

def _ensure_meta(room_id:str,legacy:bool=False)->dict:
    m=ROOM_META.get(room_id)
    if m:return m
    m={
        'owner_seat':0,'seat_tokens':{},'player_ids':{},'connected':{},'disconnect_at':{},
        'afk_strikes':{0:0,1:0,2:0,3:0},'action_times':{},'chat_times':{},'dedupe':{},
        'economy_charged':False,'settled':False,'recorded_rounds':set(),'chat':[],'reactions':[],'legacy':legacy,'created_at':_now(),
        'password_hash':None,'invited_player_ids':set(),'chat_enabled':True,'gifts_enabled':True,'auto_rematch':False,
        'state_version':1,'quick_match':False,'bot_seats':set(),'spectators':{},'spectator_events':[]
    }
    ROOM_META[room_id]=m
    return m

def _bind_human(room_id:str,seat:int,player_id:str,name:str)->str:
    room=ROOMS[room_id];m=_ensure_meta(room_id)
    token=m['seat_tokens'].get(seat) or _token()
    m['seat_tokens'][seat]=token;m['player_ids'][seat]=player_id
    m['connected'].setdefault(seat,False);m['afk_strikes'][seat]=0
    m.setdefault('bot_seats',set()).discard(seat)
    room.set_player_identity(seat,player_id,STORE.get(player_id)['name'],bot=False)
    _touch(room_id)
    return token

def _auth(room_id:str,seat:int,token:str|None)->dict:
    room=ROOMS.get(room_id)
    if not room:raise HTTPException(404,'room_not_found')
    m=_ensure_meta(room_id,legacy=True)
    if m.get('legacy') and not m['seat_tokens']:
        return m
    expected=m['seat_tokens'].get(seat)
    if not expected or not token or not secrets.compare_digest(expected,token):
        raise HTTPException(401,'invalid_reconnect_token')
    return m

def _rate_limit(m:dict,token:str|None):
    if not token:return
    now=_now();arr=m['action_times'].setdefault(token,[])
    arr[:]=[x for x in arr if now-x<2.0]
    if len(arr)>=24:raise HTTPException(429,'too_many_actions')
    arr.append(now)


def _chat_rate_limit(m:dict,token:str,kind:str):
    now=_now();last=m.setdefault('chat_times',{}).get(token,0.0)
    wait=1.80 if kind=='voice' else (0.70 if kind=='gift' else (0.80 if kind=='text' else 0.40))
    if now-last<wait:raise HTTPException(429,'chat_cooldown')
    m['chat_times'][token]=now

def _state(room_id:str,viewer:int)->dict:
    room=ROOMS[room_id];m=_ensure_meta(room_id,legacy=True)
    state=room.public_state(viewer)
    for p in state['players']:
        seat=p['seat']
        pid=m['player_ids'].get(seat)
        afk_bot=bool(p['bot'] and pid)
        p['afk_bot']=afk_bot
        p['connected']=bool(m['connected'].get(seat,False)) if pid else bool(p['bot'])
        p['afk_strikes']=int(m['afk_strikes'].get(seat,0))
        p['player_id']=pid
        explicit_bot=seat in m.setdefault('bot_seats',set())
        p['empty']=bool(p.get('bot')) and not pid and not explicit_bot
        p['explicit_bot']=explicit_bot
        if p['empty']:
            p['name']='Boş Koltuk'
        acc=STORE.table_view(pid) if pid else None
        p['avatar_url']=acc.get('avatar_url') if acc else None
        if acc:
            p['level']=int(acc.get('level',1) or 1)
            p['chips']=int(acc.get('chips',0) or 0)
            vip=acc.get('vip') or {}
            p['vip_level']=int(vip.get('level',0) or 0)
            p['vip_badge']=str(vip.get('badge') or (f"VIP {p['vip_level']}" if p['vip_level'] else ''))
            p['name_color']=str(vip.get('name_color') or '')
            p['profile_frame']=str((acc.get('equipped') or {}).get('frame') or '')
            p['loadout']=dict(acc.get('equipped') or {})
            stats=acc.get('stats') or {}
            league=acc.get('league') or {}
            p['public_stats']={
                'games':int(stats.get('games',0) or 0),
                'wins':int(stats.get('wins',0) or 0),
                'losses':int(stats.get('losses',0) or 0),
                'best_streak':int(stats.get('best_streak',0) or 0),
                'current_streak':int(stats.get('current_streak',0) or 0),
                'city':str(league.get('city','Denizli') or 'Denizli'),
                'tier':str(league.get('tier','Bronz') or 'Bronz'),
            }
            p['gifts_received']=list(acc.get('gifts_received',[])[:8])
        elif p['bot']:
            bot_level=p.get('bot_level') or 'medium'
            p['level']={'easy':8,'medium':18,'hard':32,'afk':18}.get(bot_level,18)
            p['chips']={'easy':25_000,'medium':85_000,'hard':250_000,'afk':85_000}.get(bot_level,85_000)
            p['vip_level']=0;p['vip_badge']='';p['name_color']='';p['profile_frame']='';p['loadout']={}
            p['gifts_received']=[]
            p['public_stats']={
                'games':{'easy':38,'medium':146,'hard':412,'afk':0}.get(bot_level,146),
                'wins':{'easy':9,'medium':57,'hard':196,'afk':0}.get(bot_level,57),
                'losses':{'easy':29,'medium':89,'hard':216,'afk':0}.get(bot_level,89),
                'best_streak':{'easy':2,'medium':5,'hard':11,'afk':0}.get(bot_level,5),
                'current_streak':0,
                'city':'OkeyX','tier':{'easy':'Bronz','medium':'Gümüş','hard':'Altın','afk':'—'}.get(bot_level,'Gümüş'),
            }
        else:
            p['level']=1
            p['chips']=0
            p['vip_level']=0;p['vip_badge']='';p['name_color']='';p['profile_frame']='';p['loadout']={}
            p['gifts_received']=[]
            p['public_stats']={'games':0,'wins':0,'losses':0,'best_streak':0,'current_streak':0,'city':'—','tier':'—'}
    state['viewer_seat']=viewer
    # The room owner's selected table cloth is authoritative for every client,
    # so cosmetics render consistently instead of each device choosing locally.
    state['owner_seat']=int(m.get('owner_seat',0) or 0)
    state['chat_enabled']=bool(m.get('chat_enabled',True));state['gifts_enabled']=bool(m.get('gifts_enabled',True));state['auto_rematch']=bool(m.get('auto_rematch',False))
    viewer_pid=m.get('player_ids',{}).get(viewer)
    viewer_account=STORE.get(viewer_pid) if viewer_pid else None
    hidden=set((viewer_account or {}).get('muted',[]))|set((viewer_account or {}).get('blocked',[]))
    state['chat']=[item for item in m['chat'][-20:] if item.get('kind')!='gift' and (not item.get('player_id') or item.get('player_id') not in hidden)]
    state['reactions']=[item for item in m.get('reactions',[])[-12:] if not item.get('player_id') or item.get('player_id') not in hidden]
    state['economy_charged']=bool(m['economy_charged'])
    state['settlement']=m.get('settlement')
    viewer_player=next((x for x in state['players'] if int(x.get('seat',-1))==int(viewer)),{})
    state['viewer_afk_bot']=bool(viewer_player.get('afk_bot'))
    state['viewer_chips']=int(viewer_player.get('chips',0) or 0)
    state['required_balance']=_required_balance(int(state.get('entry_fee',0) or 0),bool(state.get('turbo')))
    state['canak']={'enabled':bool(m.get('canak_enabled',True)) and not m.get('practice'),'pot':int(m.get('canak_pot',0) or 0),'fee':_canak_fee(room),'last':m.get('canak_last')}
    state['state_version']=int(m.get('state_version',1) or 1)
    state['quick_fill_at_ms']=int(float(m.get('quick_fill_at',0) or 0)*1000) if m.get('quick_match') and not room.state.started else 0
    state['quick_fill_seconds']=max(0,int(float(m.get('quick_fill_at',0) or 0)-_now()+.999)) if m.get('quick_match') and not room.state.started and m.get('quick_fill_at') else 0
    state['quick_fill_error']=m.get('quick_fill_error')
    state['server_time_ms']=int(time.time()*1000)
    state['human_count']=_human_count(room_id)
    state['bot_count']=_bot_count(room_id)
    state['occupied_count']=_occupied_count(room_id)
    state['empty_count']=max(0,4-state['occupied_count'])
    state['quick_match']=bool(m.get('quick_match',False))
    state['spectator_count']=len(m.setdefault('spectators',{}))
    return state

def _settle_spectator_predictions(room_id:str)->None:
    room=ROOMS.get(room_id);m=ROOM_META.get(room_id) or {}
    if not room or room.state.phase!='finished':return
    round_index=int(room.state.round_index)
    winner=int(room.state.winner_seat) if room.state.winner_seat is not None else -1
    flags=dict(room.state.round_finish_flags or {})
    changed=False
    for row in m.setdefault('spectators',{}).values():
        prediction=row.get('prediction') or {}
        if int(prediction.get('round',-1))!=round_index or prediction.get('settled'):continue
        value=str(prediction.get('value') or '')
        correct=(value==f'winner:{winner}' or (value=='joker_finish' and flags.get('joker_finish') is True) or (value=='pair_finish' and flags.get('pair_finish') is True))
        reward=150 if correct and value in ('joker_finish','pair_finish') else (100 if correct else 0)
        row['points']=int(row.get('points',0) or 0)+reward
        prediction.update({'settled':True,'correct':correct,'reward':reward})
        row['prediction']=prediction;changed=True
    if changed:_persist_runtime()

def _spectator_state(room_id:str,player_id:str)->dict:
    room=ROOMS.get(room_id)
    if not room:raise HTTPException(404,'room_not_found')
    _settle_spectator_predictions(room_id)
    m=_ensure_meta(room_id,legacy=True)
    now=_now()
    spectators=m.setdefault('spectators',{})
    for pid,row in list(spectators.items()):
        if now-float(row.get('last_seen',now))>150:spectators.pop(pid,None)
    spectator=spectators.get(player_id)
    if not spectator:raise HTTPException(403,'spectator_not_joined')
    spectator['last_seen']=now
    state=_state(room_id,0)
    for p in state.get('players',[]):
        p['hand']=[]
        for key in ('pending_left_tile_id','rack_value','turbo_star_count','can_undo_layoff','can_undo_opening'):
            p.pop(key,None)
    for key in ('available_actions','left_opening_opportunity','left_useful_tile_id','left_useful_reason','penalty_tile_ids','opening_preview_score','opening_preview_used','opening_preview_pairs','assisted_series_score','assisted_series_groups','assisted_series_used_ids','useful_tile_ids','viewer_afk_bot','viewer_chips','required_balance'):
        state.pop(key,None)
    state['viewer_seat']=-1
    state['spectator_points']=int(spectator.get('points',0) or 0)
    state['spectator_prediction']=dict(spectator.get('prediction') or {})
    state['spectator_events']=list(m.setdefault('spectator_events',[])[-12:])
    state['can_predict']=bool(room.state.started and room.state.phase not in ('waiting','finished') and int(room.state.turn_no)<=2)
    return state

async def refresh_player_rooms(player_ids)->None:
    """Cüzdan değişince (altın gönderme, hediye) oyuncunun oturduğu masaları
    yeni sürümle yayınla; aksi halde istemci eski bakiyeyi göstermeye devam eder."""
    ids={str(x) for x in player_ids if x}
    for rid in list(ROOMS):
        m=ROOM_META.get(rid) or {}
        if ids & {str(v) for v in (m.get('player_ids') or {}).values()}:
            _touch(rid)
            try:await _broadcast(rid)
            except Exception:pass

async def _broadcast(room_id:str,skip_seat:int|None=None):
    """Fan state out concurrently so one slow phone cannot stall every seat."""
    room=ROOMS.get(room_id)
    if not room:return
    seats=SOCKETS.get(room_id,{})
    jobs=[]
    refs=[]
    for seat,sockets in list(seats.items()):
        if skip_seat is not None and int(seat)==int(skip_seat):continue
        # Compute viewer state once even if a device briefly has two sockets.
        payload={'type':'state','state':_state(room_id,seat)}
        for ws in list(sockets):
            refs.append((seat,ws))
            jobs.append(asyncio.create_task(asyncio.wait_for(ws.send_json(payload),timeout=1.25)))
    if not jobs:return
    results=await asyncio.gather(*jobs,return_exceptions=True)
    for (seat,ws),result in zip(refs,results):
        if isinstance(result,BaseException):
            if seat in seats and ws in seats[seat]:seats[seat].remove(ws)

def _required_balance(entry_fee:int,turbo:bool)->int:
    stake=max(0,int(entry_fee));return stake*(10 if turbo else 1)

def _preflight_balance(account:dict,entry_fee:int,turbo:bool)->None:
    required=_required_balance(entry_fee,turbo);current=int(account.get('chips',0))
    if current<required:raise HTTPException(402,f'insufficient_balance:{required}:{current}')

def _charge_entries(room_id:str)->tuple[bool,str]:
    room=ROOMS[room_id];m=_ensure_meta(room_id)
    if m['economy_charged']:return True,'already_checked'
    stake=max(0,int(room.state.entry_fee));required=_required_balance(stake,room.state.turbo)
    for seat,pid in m['player_ids'].items():
        if room.state.players[seat].bot:continue
        a=STORE.get(pid)
        if not a:return False,'account_not_found'
        if a['chips']<required:return False,f'not_enough_chips:{seat}'
    m['economy_charged']=True
    return True,'stake_checked'


ALLOWED_ENTRY_FEES=(500,1000,2000,5000,10000,20000,25000,50000,100000)
QUICK_BOT_FILL_SECONDS=15
BOT_NAMES={'easy':'Kolay Bot','medium':'Normal Bot','hard':'Zor Bot'}

LEVEL_BAND=8       # ilk 8 sn: seviye farkı en fazla 8
LEVEL_BAND_RELAX_SECONDS=8

def _level_compatible(room_id:str,my_level:int)->bool:
    """Seviyeye göre eşleştirme: odadaki insanlarla fark LEVEL_BAND içinde olmalı;
    oda 8 sn'den eskiyse sınır kalkar (az oyunculu saatlerde beklememek için)."""
    m=ROOM_META.get(room_id) or {}
    if _now()-float(m.get('created_at',_now()))>=LEVEL_BAND_RELAX_SECONDS:return True
    for pid in (m.get('player_ids') or {}).values():
        acc=STORE.get(pid)
        if acc and abs(int(acc.get('level',1) or 1)-my_level)>LEVEL_BAND:return False
    return True


def _fill_bots_and_start(room_id:str,level:str='medium')->bool:
    """Bekleme odasındaki boş koltukları botla doldurup maçı atomik biçimde başlatır."""
    room=ROOMS.get(room_id);m=_ensure_meta(room_id)
    if not room or room.state.phase!='waiting' or room.state.started:return False
    if _human_count(room_id)<1:return False
    # Önce tüm gerçek oyuncuların bakiyesini doğrula. Başarısız kontrolde
    # koltuklara bot yazıp arayüzü dolu gösterme; bu eski sessiz takılma hatasıydı.
    ok,_code=_charge_entries(room_id)
    if not ok:
        m['quick_fill_error']=_code
        _touch(room_id)
        return False
    level=level if level in BOT_NAMES else 'medium'
    names=['Mert','Ayşe','Kemal','Eylül','Deniz','Zeynep','Emre','Elif']
    # Kullanıcının bekleme ekranında bilinçli olarak seçtiği botları koru.
    # Yalnızca gerçekten boş placeholder koltuklarına otomatik bot ekle.
    explicit=set(m.setdefault('bot_seats',set()))
    auto_added=[]
    for seat in range(4):
        if seat in m.get('player_ids',{}):
            continue
        p=room.state.player(seat)
        if seat in explicit and p.bot:
            continue
        m['bot_seats'].add(seat)
        p.bot=True;p.bot_level=level;p.user_id=f'bot-seat-{seat}';p.name=names[(seat + int(room.state.round_index or 0)) % len(names)]
        auto_added.append(seat)
    # Bot doluluğu ayrı bir ölçüdür; hızlı eşleşmede bir insan + üç bot
    # gerçek dört koltuklu bir masadır ve otomatik başlatılabilir.
    if _occupied_count(room_id) < 4:
        for seat in auto_added:
            m['bot_seats'].discard(seat)
            p=room.state.player(seat);p.bot=True;p.user_id=f'bot-seat-{seat}';p.name='Boş Koltuk'
        m['quick_fill_error']='empty_seats'
        _touch(room_id)
        return False
    started=room.start_match(0)
    if not started.ok:
        # Yalnızca bu çağrıda oluşturduğumuz botları geri al; kullanıcının
        # önceden seçtiği zorluk ve bot koltukları aynen korunur.
        for seat in auto_added:
            m['bot_seats'].discard(seat)
            p=room.state.player(seat);p.bot=True;p.user_id=f'bot-seat-{seat}';p.name='Boş Koltuk'
        m['economy_charged']=False
        m['quick_fill_error']=started.code
        _touch(room_id)
        return False
    m['bot_filled']=True;m['quick_fill_error']=None
    _canak_round_start(room_id)
    _touch(room_id)
    return True

async def _quick_fill_after_delay(room_id:str)->None:
    # If entry preflight fails, keep the queue alive and retry after ten seconds.
    # This avoids a permanently expired countdown after a player tops up their balance.
    try:
        while True:
            m=ROOM_META.get(room_id) or {}
            deadline=float(m.get('quick_fill_at',_now()+QUICK_BOT_FILL_SECONDS) or _now())
            await asyncio.sleep(max(0.0, deadline-_now()))
            room=ROOMS.get(room_id);m=ROOM_META.get(room_id) or {}
            if not room or room.state.phase!='waiting' or room.state.started:return
            if not m.get('quick_match') or _human_count(room_id)<1:return
            if _fill_bots_and_start(room_id,'medium'):
                await _broadcast(room_id)
                return
            if room.state.phase!='waiting' or room.state.started or _human_count(room_id)<1:return
            m['quick_fill_at']=_now()+10
            m['quick_fill_retry_count']=int(m.get('quick_fill_retry_count',0) or 0)+1
            _touch(room_id)
            await _broadcast(room_id)
    finally:
        # A cancelled timer may be replaced immediately (for example after a
        # room is re-queued). Never let the old task remove the new task handle.
        current=asyncio.current_task()
        if QUICK_FILL_TASKS.get(room_id) is current:
            QUICK_FILL_TASKS.pop(room_id,None)

def _schedule_quick_fill(room_id:str)->None:
    task=QUICK_FILL_TASKS.get(room_id)
    if task and not task.done():return
    m=_ensure_meta(room_id)
    m.setdefault('quick_fill_at',_now()+QUICK_BOT_FILL_SECONDS)
    QUICK_FILL_TASKS[room_id]=asyncio.create_task(_quick_fill_after_delay(room_id))


def _record_round_if_finished(room_id:str):
    room=ROOMS.get(room_id);m=ROOM_META.get(room_id)
    if not room or not m or room.state.phase!='finished':return
    idx=int(room.state.round_index);recorded=m.setdefault('recorded_rounds',set())
    if idx in recorded:return
    recorded.add(idx)
    flags=dict(room.state.round_finish_flags or {})
    winner=room.state.winner_seat
    for seat,pid in list(m.get('player_ids',{}).items()):
        if not STORE.get(pid):continue
        player=room.state.players.get(seat)
        STORE.record_round(
            pid,
            opening_mode=getattr(player,'opening_mode',None),
            winner=(winner==seat),
            okey_finish=bool(flags.get('joker_finish')),
            pair_finish=bool(flags.get('pair_finish')),
        )
    _table_canak(room_id,room,m,flags,winner)

def _canak_fee(room)->int:
    """Masa çanağı: her el başında her gerçek oyuncu giriş bedelinin yönetici
    panelindeki oranı kadar (varsayılan %10) koyar."""
    pct=max(0,min(50,int(STORE.economy().get('canak_percent',10))))
    if pct<=0:return 0
    fee=max(50,int(room.state.entry_fee or 0)*pct//100)
    return fee*(2 if room.state.turbo else 1)

def _canak_round_start(room_id:str)->None:
    """El başında her gerçek oyuncu çanağa payını koyar (el başına bir kez)."""
    room=ROOMS.get(room_id);m=ROOM_META.get(room_id)
    if not room or not m or m.get('practice') or not m.get('canak_enabled',True):return
    if not room.state.started or room.state.phase=='waiting':return
    key=f"{m.get('created_at',0)}:{int(m.get('match_seq',0) or 0)}:{int(room.state.round_index)}"
    if m.get('canak_charged_key')==key:return
    m['canak_charged_key']=key
    fee=_canak_fee(room)
    for seat,pid in list(m.get('player_ids',{}).items()):
        if room.state.players[seat].bot or not STORE.get(pid):continue
        if STORE.debit(pid,fee,'table_canak',notify=False):
            m['canak_pot']=int(m.get('canak_pot',0) or 0)+fee

def _table_canak(room_id:str,room,m:dict,flags:dict,winner)->None:
    """Çanak okey: okeyle ya da çiftten biten oyuncu masadaki çanağı kırar ve alır.
    Kırılmazsa çanak aynı masada bir sonraki ele devreder."""
    if m.get('practice') or not m.get('canak_enabled',True):return
    _canak_round_start(room_id)
    if winner is None or not (flags.get('joker_finish') or flags.get('pair_finish')):return
    pot=int(m.get('canak_pot',0) or 0)
    if pot<=0:return
    pid=m.get('player_ids',{}).get(winner)
    if not pid or room.state.players[winner].bot or not STORE.get(pid):return
    # Etkinlik: "Çanak 2 katı" gibi canlı etkinlikler çanağı büyütür (ev sahibinden).
    try:
        from app.api.phase4 import _svc as _p4
        mult=max([float((ev.get('config') or {}).get('canak_multiplier',1) or 1) for ev in _p4()._active_events()] or [1.0])
        pot=int(pot*max(1.0,min(5.0,mult)))
    except Exception:
        pass
    STORE.credit(pid,pot,'table_canak_win',notify=False)
    kind='okey' if flags.get('joker_finish') else 'cift'
    name=room.state.players[winner].name
    m['canak_pot']=0
    m['canak_last']={'seat':int(winner),'name':name,'amount':pot,'kind':kind,'at':int(_now()*1000)}
    try:
        STORE.add_notification(pid,'Çanağı kırdın!',f'{pot:,} altın masa çanağı senin.'.replace(',','.'),'canak',{'room_id':room_id})
        room._emit_table_event('canak_break',int(winner),f'{name} ÇANAĞI KIRDI • +{pot:,}'.replace(',','.'),{'amount':pot,'kind':kind})
    except Exception:
        pass

def _settle_if_finished(room_id:str):
    room=ROOMS.get(room_id);m=ROOM_META.get(room_id)
    if not room or not m or m.get('settled') or not room.state.match_finished:return
    if m.get('practice'):
        # Antrenman: bahis, XP, lig ve turnuva puanı yok (bot çiftliği olmasın).
        m['settled']=True
        return
    scores=room.state.total_scores
    if not scores:return

    x=max(1,int(room.state.multiplier if room.state.turbo else 1))
    stake=max(0,int(room.state.entry_fee))

    def remaining(seat:int)->int:
        return int(room.state.round_breakdown.get(seat,{}).get('remaining_points',room.state.round_breakdown.get(seat,{}).get('rack',0)))

    # Tek elde direkt elde kalan puana göre; çok elde toplam puan, eşitlikte son elde kalan.
    def rank_key(seat:int):
        if room.state.max_rounds==1:
            return (remaining(seat),seat)
        return (int(scores.get(seat,0)),remaining(seat),seat)

    ordered=sorted(range(4),key=rank_key)
    rank_by_seat={seat:i+1 for i,seat in enumerate(ordered)}

    # TEK ekonomi. Standartta mevcut dengeli 1.75x / 0.25x / -1x / -1x
    # yapısı korunur. Turbo'da kullanıcı beklentisine göre çarpan gerçek ödül
    # tablosuna yansır: ör. x10 => 1. sıra 10.5x, 2. sıra 2.5x; 3/4 bu iki
    # kazancı sıfır-toplam olacak şekilde eşit paylaşır.
    if room.state.turbo:
        first_win=int(round(stake*(x+0.5)))
        second_win=int(round(stake*(x*0.25)))
        loss_pool=first_win+second_win
        third_loss=loss_pool//2
        fourth_loss=loss_pool-third_loss
        solo_deltas={
            ordered[0]: first_win,
            ordered[1]: second_win,
            ordered[2]: -third_loss,
            ordered[3]: -fourth_loss,
        }
    else:
        same_loss=int(stake)
        second_win=int(round(stake*0.25))
        first_win=max(0,(same_loss*2)-second_win)
        solo_deltas={
            ordered[0]: first_win,
            ordered[1]: second_win,
            ordered[2]: -same_loss,
            ordered[3]: -same_loss,
        }

    if room.state.team_mode=='paired':
        team_scores=room.team_score_map(scores)
        winning_team=min(team_scores,key=lambda t:(team_scores[t],t))
        winning_seats=set(room.team_members(winning_team))
        deltas={seat:(stake*x if seat in winning_seats else -stake*x) for seat in range(4)}
        winner_ids=[pid for seat,pid in m['player_ids'].items() if seat in winning_seats]
        result_kind='paired'
    else:
        deltas=solo_deltas
        winning_seats={ordered[0],ordered[1]}
        winner_ids=[pid for seat,pid in m['player_ids'].items() if seat in winning_seats]
        result_kind='solo'

    commission_rate=max(0,min(30,int(STORE.economy().get('commission_percent',15))))/100.0
    gross_deltas={seat:int(v) for seat,v in deltas.items()}
    commissions={seat:(int(round(v*commission_rate)) if v>0 else 0) for seat,v in gross_deltas.items()}
    net_deltas={seat:gross_deltas[seat]-commissions[seat] for seat in gross_deltas}
    house_fee=sum(commissions.values())
    gross_total=sum(gross_deltas.values())
    net_total=sum(net_deltas.values())

    if gross_total!=0 or net_total+house_fee!=0:
        m['settlement']={'status':'blocked','error':'economy_invariant','gross_total':gross_total,'net_total':net_total,'house_fee':house_fee}
        m['settled']=True
        return

    # All-or-nothing preflight before any wallet mutation.
    for seat,pid in m['player_ids'].items():
        delta=int(net_deltas.get(seat,0))
        acc=STORE.get(pid)
        if acc and delta<0 and int(acc.get('chips',0))<(-delta):
            m['settlement']={'status':'blocked','error':'insufficient_balance_at_settlement','seat':seat,'required':-delta,'available':int(acc.get('chips',0)),'house_fee':house_fee}
            m['settled']=True
            return

    participants=[]
    applied=[]
    for seat,pid in m['player_ids'].items():
        participants.append({'id':pid,'name':room.state.players[seat].name,'seat':seat})
        delta=int(net_deltas.get(seat,0))
        if not STORE.get(pid) or delta==0:continue
        if delta>0:
            STORE.credit(pid,delta,f'{room.state.room_name} • {rank_by_seat[seat]}. sıra • %{int(round(commission_rate*100))} masa komisyonu sonrası',notify=False)
            applied.append({'seat':seat,'delta':delta,'gross':gross_deltas[seat],'commission':commissions[seat],'ok':True})
        else:
            ok=STORE.debit(pid,-delta,f'{room.state.room_name} • {rank_by_seat[seat]}. sıra',notify=False)
            applied.append({'seat':seat,'delta':delta,'gross':gross_deltas[seat],'commission':0,'ok':bool(ok)})

    finish_flags=dict(room.state.round_finish_flags or {})
    # Active LiveOps events now affect real match progression, not only a
    # decorative banner. Keep the strongest concurrent XP multiplier.
    now_ms=int(time.time()*1000)
    xp_multiplier=1.0
    try:
        for ev in STORE._data.get('phase4',{}).get('global',{}).get('live_events',[]):
            if not bool(ev.get('enabled',True)):continue
            if int(ev.get('starts_at',0) or 0)<=now_ms<=int(ev.get('ends_at',0) or 0):
                xp_multiplier=max(xp_multiplier,float((ev.get('config') or {}).get('xp_multiplier',1.0) or 1.0))
    except Exception:
        xp_multiplier=1.0
    STORE.settle_match(
        participants,winner_ids[0] if winner_ids else None,0,room.state.max_rounds,
        {'scores':scores,'winner_ids':winner_ids,'paired':room.state.team_mode=='paired','finish_flags':finish_flags,'variant':room.state.variant,'turbo':bool(room.state.turbo),'game_type':('duz' if room.state.variant=='duz' else 'okey101')},
        xp_multiplier=xp_multiplier,
    )
    canak_add=max(0,int(round(house_fee*0.02)))
    canak_balance=STORE.add_canak(canak_add,room_id)
    canak_explosion=None
    if finish_flags.get('joker_finish') or finish_flags.get('pair_finish'):
        canak_explosion=STORE.pop_canak(winner_ids,room_id)
        canak_balance=STORE.canak_state().get('balance',0)

    rankings=[]
    for seat in ordered:
        pid=m['player_ids'].get(seat)
        acc=STORE.get(pid) if pid else None
        rankings.append({
            'rank':rank_by_seat[seat],'seat':seat,'name':room.state.players[seat].name,
            'score':int(scores.get(seat,0)),'remaining':remaining(seat),
            'remaining_points':remaining(seat),
            'remaining_tile_count':int(room.state.round_breakdown.get(seat,{}).get('remaining_tile_count',len(room.state.players[seat].hand))),
            'delta':int(net_deltas.get(seat,0)),'gross_delta':int(gross_deltas.get(seat,0)),
            'commission':int(commissions.get(seat,0)),
            'balance_after':int((acc or {}).get('chips',0) or 0) if acc else None,
            'team':room.team_of(seat) if room.state.team_mode=='paired' else None,
        })

    m['settlement']={
        'stake':stake,'multiplier':x,'mode':'turbo' if room.state.turbo else 'standard',
        'team_mode':room.state.team_mode,'result_kind':result_kind,'rankings':rankings,
        'winner_seat':ordered[0],'winner_seats':sorted(winning_seats),
        'team_scores':room.team_score_map(scores),
        'commission_rate':commission_rate,'house_fee':house_fee,
        'gross_ledger_total':gross_total,'net_ledger_total':net_total,
        'wallet_applied':applied,
        'wallet_ok':all(x.get('ok',False) for x in applied),
        'canak_contribution':canak_add,'canak_balance':canak_balance,'canak_explosion':canak_explosion,'xp_multiplier':xp_multiplier,
    }
    m['settled']=True


_CHAT_BLOCK_PATTERNS=(
    re.compile(r'https?://',re.I),
    re.compile(r'www\.',re.I),
)
_CHAT_MASK_WORDS=('amk','aq','orospu','sik','piç','pic')

def _moderate_chat_text(value:str)->str:
    from app.core.textfilter import mask,is_spam
    text=' '.join((value or '').split())
    if not text:raise HTTPException(400,'empty_message')
    if any(p.search(text) for p in _CHAT_BLOCK_PATTERNS):raise HTTPException(400,'chat_link_not_allowed')
    if is_spam(text):raise HTTPException(400,'chat_spam_detected')
    text,_flag=mask(text)
    return text[:120]

def _append_chat(room_id:str,seat:int,kind:str,value:str,to_seat:int|None=None)->dict:
    room=ROOMS[room_id];m=_ensure_meta(room_id)
    p=room.state.player(seat)
    target=room.state.player(to_seat) if to_seat is not None and to_seat in room.state.players else None
    event={'id':uuid.uuid4().hex[:10],'seat':seat,'player_id':m.get('player_ids',{}).get(seat),'name':p.name,'kind':kind,'value':value[:120],'to_seat':to_seat,'to_name':target.name if target else None,'created_at':int(_now())}
    if kind=='gift':
        reactions=m.setdefault('reactions',[])
        reactions.append(event);m['reactions']=reactions[-20:]
    else:
        m['chat'].append(event);m['chat']=m['chat'][-30:]
    return event

@router.get('/lobby/rooms')
def list_rooms():
    out=[]
    for rid,r in ROOMS.items():
        st=r.state;m=_ensure_meta(rid,legacy=True)
        human=_human_count(rid)
        bot_count=_bot_count(rid)
        occupied=_occupied_count(rid)
        if st.phase!='waiting':continue
        out.append({
            'room_id':rid,'name':st.room_name,'variant':st.variant,'entry_fee':st.entry_fee,
            'assisted':st.assisted,'turbo':st.turbo,'rounds':st.max_rounds,'players':occupied,'human_players':human,'bot_players':bot_count,
            'capacity':4,'multiplier':st.multiplier,'phase':st.phase,'started':st.started,'pot':st.pot,'game_mode':('turbo' if st.turbo else 'standard'),'team_mode':st.team_mode,
            'turn_seconds':st.turn_seconds,'locked':bool(m.get('password_hash')),'required_balance':_required_balance(st.entry_fee,st.turbo)
        })
    return {'rooms':out}

@router.get('/lobby/live-tables')
def list_live_tables():
    out=[]
    for room_id,room in ROOMS.items():
        state=room.state;m=_ensure_meta(room_id,legacy=True)
        if not state.started or state.match_finished:continue
        players=[]
        for seat in range(4):
            player=state.players[seat]
            players.append({'seat':seat,'name':player.name,'bot':bool(player.bot),'opened':bool(player.opened)})
        out.append({
            'room_id':room_id,'name':state.room_name,'variant':state.variant,
            'turbo':bool(state.turbo),'team_mode':state.team_mode,'entry_fee':int(state.entry_fee),
            'round_index':int(state.round_index),'max_rounds':int(state.max_rounds),
            'phase':state.phase,'players':players,'spectators':len(m.setdefault('spectators',{})),
            'pot':int(state.pot),'turn_seconds':int(state.turn_seconds),
        })
    out.sort(key=lambda row:(-int(row['spectators']),-int(row['entry_fee'])))
    return {'tables':out[:30]}

@router.post('/game/{room_id}/spectate')
async def spectate_room(room_id:str,body:SpectatorIn):
    room=ROOMS.get(room_id)
    if not room:raise HTTPException(404,'room_not_found')
    account=_account(body.player_id,body.account_token)
    m=_ensure_meta(room_id,legacy=True);spectators=m.setdefault('spectators',{})
    if body.action=='join':
        if body.player_id in set(m.get('player_ids',{}).values()):raise HTTPException(409,'already_at_table')
        previous=spectators.get(body.player_id) or {}
        spectators[body.player_id]={
            'player_id':body.player_id,'name':str(account.get('name') or 'Yancı')[:24],
            'avatar_url':account.get('avatar_url'),'points':int(previous.get('points',0) or 0),
            'prediction':dict(previous.get('prediction') or {}),'joined_at':float(previous.get('joined_at') or _now()),'last_seen':_now(),
        }
        _touch(room_id)
        return {'ok':True,'state':_spectator_state(room_id,body.player_id)}
    if body.action=='leave':
        spectators.pop(body.player_id,None);_touch(room_id)
        return {'ok':True}
    spectator=spectators.get(body.player_id)
    if not spectator:raise HTTPException(403,'spectator_not_joined')
    spectator['last_seen']=_now()
    if body.action=='state':
        return {'ok':True,'state':_spectator_state(room_id,body.player_id)}
    if body.action=='react':
        allowed={
            'nazar':('Nazar Boncuğu','totem'),'tea':('Çay','gift'),
            'coffee':('Türk Kahvesi','gift'),'applause':('Alkış','reaction'),
        }
        if body.value not in allowed:raise HTTPException(400,'spectator_reaction_not_allowed')
        if body.to_seat not in range(4):raise HTTPException(400,'target_required')
        last=float(spectator.get('last_reaction_at',0) or 0)
        if _now()-last<1.2:raise HTTPException(429,'spectator_reaction_cooldown')
        spectator['last_reaction_at']=_now();label,reaction_kind=allowed[body.value]
        event={
            'id':uuid.uuid4().hex[:10],'seat':-1,'player_id':body.player_id,
            'name':f"Yancı • {spectator['name']}",'kind':'gift','value':label,
            'reaction_kind':reaction_kind,'spectator':True,'to_seat':body.to_seat,
            'to_name':room.state.player(body.to_seat).name,'created_at':int(_now()),
        }
        m.setdefault('reactions',[]).append(event);m['reactions']=m['reactions'][-20:]
        m.setdefault('spectator_events',[]).append(event);m['spectator_events']=m['spectator_events'][-20:]
        _touch(room_id);await _broadcast(room_id)
        return {'ok':True,'event':event,'state':_spectator_state(room_id,body.player_id)}
    if body.action=='predict':
        if not room.state.started or room.state.phase in ('waiting','finished') or int(room.state.turn_no)>2:
            return {'ok':False,'code':'prediction_closed','state':_spectator_state(room_id,body.player_id)}
        allowed={f'winner:{seat}' for seat in range(4)}|{'joker_finish','pair_finish'}
        if body.value not in allowed:raise HTTPException(400,'prediction_not_allowed')
        spectator['prediction']={'round':int(room.state.round_index),'value':body.value,'settled':False,'created_at':int(_now())}
        _touch(room_id)
        return {'ok':True,'state':_spectator_state(room_id,body.player_id)}
    raise HTTPException(400,'bad_spectator_action')

@router.post('/lobby/rooms')
def create_room(body:CreateRoomIn):
    if body.variant not in ('non_fold','fold','duz'):raise HTTPException(400,'bad_variant')
    if body.team_mode not in ('solo','paired'):raise HTTPException(400,'bad_team_mode')
    if body.rounds not in (1,2,3):raise HTTPException(400,'bad_round_count')
    if body.entry_fee not in ALLOWED_ENTRY_FEES:raise HTTPException(400,'bad_entry_fee')
    account=_account(body.player_id,body.account_token)
    _preflight_balance(account,body.entry_fee,body.turbo)
    r=new_room(
        variant=body.variant,entry_fee=body.entry_fee,assisted=body.assisted,turbo=body.turbo,
        max_rounds=body.rounds,room_name=body.name,waiting=True,turn_seconds=body.turn_seconds,team_mode=body.team_mode,
        random_starter=True,intro_seconds=5
    )
    m=_ensure_meta(r.state.room_id);m['legacy']=False
    password=(body.password or '').strip()
    if password:
        if len(password)<3 or len(password)>24:raise HTTPException(400,'bad_room_password')
        m['password_hash']=hashlib.sha256(password.encode('utf-8')).hexdigest()
    token=_bind_human(r.state.room_id,0,body.player_id,account['name'])
    STORE.record_activity('room_created',body.player_id,f'{account["name"]} yeni bir 101 masası açtı',{'room_id':r.state.room_id,'entry_fee':body.entry_fee,'turbo':body.turbo})
    return {'room_id':r.state.room_id,'seat':0,'reconnect_token':token,'state':_state(r.state.room_id,0)}

@router.post('/lobby/quick')
async def quick_room(body:JoinRoomIn):
    """Quick matchmaking: share a real-player queue for up to 15 seconds,
    then fill any remaining seats with server-controlled bots and start.
    Four real players start immediately. The deadline is authoritative and
    is also exposed to clients for an accurate countdown.
    """
    account=_account(body.player_id,body.account_token)
    requested_fee=body.entry_fee if body.entry_fee in ALLOWED_ENTRY_FEES else 5000
    requested_turbo=bool(body.turbo) if body.turbo is not None else False
    _preflight_balance(account,requested_fee,requested_turbo)

    # If the same player already owns a live waiting quick room, restore it
    # instead of creating duplicates on repeated taps/network retries.
    for rid,r in list(ROOMS.items()):
        meta=_ensure_meta(rid,legacy=True)
        seat=next((s for s,pid in meta.get('player_ids',{}).items() if pid==body.player_id),None)
        if seat is not None and r.state.phase=='waiting' and meta.get('quick_match'):
            _schedule_quick_fill(rid)
            token=meta['seat_tokens'].get(seat) or _token();meta['seat_tokens'][seat]=token
            return {'room_id':rid,'seat':seat,'reconnect_token':token,'state':_state(rid,seat)}

    my_level=int(account.get('level',1) or 1)
    for rid,r in list(ROOMS.items()):
        if r.state.phase!='waiting':continue
        m=_ensure_meta(rid)
        if not m.get('quick_match'):continue
        if m.get('password_hash'):continue
        if not _level_compatible(rid,my_level):continue
        if body.turbo is not None and r.state.turbo!=body.turbo:continue
        if body.variant and r.state.variant!=body.variant:continue
        if body.team_mode and r.state.team_mode!=body.team_mode:continue
        if body.entry_fee is not None and r.state.entry_fee!=body.entry_fee:continue
        if body.rounds is not None and r.state.max_rounds!=body.rounds:continue
        if body.assisted is not None and r.state.assisted!=body.assisted:continue
        seat=_free_human_seat(rid)
        if seat is None:continue
        _preflight_balance(account,r.state.entry_fee,r.state.turbo)
        m['legacy']=False
        token=_bind_human(rid,seat,body.player_id,account['name'])
        STORE.record_activity('room_join',body.player_id,f'{account["name"]} hızlı eşleşme masasına katıldı',{'room_id':rid,'entry_fee':r.state.entry_fee,'turbo':r.state.turbo})
        # Four real players -> authoritative server starts the table. No client
        # has to win a race to press START.
        if _human_count(rid)>=4:
            task=QUICK_FILL_TASKS.pop(rid,None)
            if task:task.cancel()
            ok,code=_charge_entries(rid)
            if not ok:raise HTTPException(402,code)
            started=r.start_match(int(m.get('owner_seat',0) or 0))
            if not started.ok:raise HTTPException(409,started.code)
            _canak_round_start(rid)
            _touch(rid)
        else:
            _schedule_quick_fill(rid)
        await _broadcast(rid)
        return {'room_id':rid,'seat':seat,'reconnect_token':token,'state':_state(rid,seat)}

    # Create a WAITING quick-match room, not an instant bot table.
    r=new_room(
        room_name='Hızlı Eşleşme',waiting=True,
        turbo=requested_turbo,
        variant=body.variant if body.variant in ('fold','non_fold','duz') else 'non_fold',
        team_mode=body.team_mode if body.team_mode in ('solo','paired') else 'solo',
        entry_fee=requested_fee,
        # Hızlı maç varsayılan tek el; oyuncu ana ekrandan 2 ya da 3 el seçebilir.
        max_rounds=body.rounds if body.rounds in (1,2,3) else 1,
        assisted=True if body.assisted is None else body.assisted,
        random_starter=True,intro_seconds=5,
    )
    m=_ensure_meta(r.state.room_id);m['legacy']=False;m['quick_match']=True
    token=_bind_human(r.state.room_id,0,body.player_id,account['name'])
    m['quick_fill_at']=_now()+QUICK_BOT_FILL_SECONDS
    _schedule_quick_fill(r.state.room_id)
    STORE.record_activity('quick_play',body.player_id,f'{account["name"]} hızlı eşleşme kuyruğuna katıldı',{'room_id':r.state.room_id,'entry_fee':r.state.entry_fee,'turbo':r.state.turbo})
    return {'room_id':r.state.room_id,'seat':0,'reconnect_token':token,'state':_state(r.state.room_id,0)}

@router.post('/lobby/practice')
async def practice_room(body:JoinRoomIn):
    """Botlarla antrenman: bahissiz, anında başlar, XP/lig/turnuva puanı vermez."""
    account=_account(body.player_id,body.account_token)
    # Zaten açık bir antrenman masası varsa onu geri ver (çift dokunma/yeniden deneme).
    for rid,r in list(ROOMS.items()):
        meta=_ensure_meta(rid,legacy=True)
        seat=next((s for s,pid in meta.get('player_ids',{}).items() if pid==body.player_id),None)
        if seat is not None and meta.get('practice') and not r.state.match_finished:
            token=meta['seat_tokens'].get(seat) or _token();meta['seat_tokens'][seat]=token
            return {'room_id':rid,'seat':seat,'reconnect_token':token,'state':_state(rid,seat)}
    r=new_room(
        room_name='Antrenman Masası',waiting=True,turbo=False,
        variant=body.variant if body.variant in ('fold','non_fold','duz') else 'non_fold',
        team_mode='solo',entry_fee=0,max_rounds=1,
        assisted=True if body.assisted is None else body.assisted,
        random_starter=True,intro_seconds=3,
    )
    rid=r.state.room_id
    m=_ensure_meta(rid);m['legacy']=False;m['practice']=True
    token=_bind_human(rid,0,body.player_id,account['name'])
    if not _fill_bots_and_start(rid,'medium'):raise HTTPException(409,'practice_start_failed')
    await _broadcast(rid)
    return {'room_id':rid,'seat':0,'reconnect_token':token,'state':_state(rid,0)}

@router.post('/game/{room_id}/join')
async def join_room(room_id:str,body:JoinRoomIn):
    r=ROOMS.get(room_id)
    if not r:raise HTTPException(404,'room_not_found')
    if r.state.phase!='waiting':raise HTTPException(409,'room_already_started')
    account=_account(body.player_id,body.account_token)
    _preflight_balance(account,r.state.entry_fee,r.state.turbo)
    m=_ensure_meta(room_id)
    password_hash=m.get('password_hash')
    invited=body.player_id in m.get('invited_player_ids',set())
    if password_hash and not invited:
        given=hashlib.sha256((body.password or '').encode('utf-8')).hexdigest()
        if not secrets.compare_digest(password_hash,given):raise HTTPException(401,'room_password_required')
    if body.player_id in m.get('player_ids',{}).values():
        # Authenticated rejoin of the same waiting room.
        seat=next(s for s,pid in m['player_ids'].items() if pid==body.player_id)
        return {'room_id':room_id,'seat':seat,'reconnect_token':m['seat_tokens'][seat],'state':_state(room_id,seat)}
    seat=_free_human_seat(room_id)
    if seat is None:raise HTTPException(409,'room_full')
    token=_bind_human(room_id,seat,body.player_id,account['name'])
    STORE.record_activity('room_join',body.player_id,f'{account["name"]} bir masaya katıldı',{'room_id':room_id,'entry_fee':r.state.entry_fee,'turbo':r.state.turbo})
    if m.get('quick_match') and _human_count(room_id)>=4:
        task=QUICK_FILL_TASKS.pop(room_id,None)
        if task:task.cancel()
        ok,code=_charge_entries(room_id)
        if not ok:raise HTTPException(402,code)
        started=r.start_match(int(m.get('owner_seat',0) or 0))
        if not started.ok:raise HTTPException(409,started.code)
        _touch(room_id)
    await _broadcast(room_id)
    return {'room_id':room_id,'seat':seat,'reconnect_token':token,'state':_state(room_id,seat)}

@router.post('/game/new')
def game_new(
    variant:str=Query('non_fold',pattern='^(non_fold|fold|duz)$'),
    entry_fee:int=5000,assisted:bool=True,turbo:bool=False,rounds:int=1,name:str='OkeyX Masası'
):
    # Legacy local test route; normal product flow uses lobby. Yayında kapalı.
    if settings.is_production and not settings.local_dev_mode:raise HTTPException(404,'not_found')
    r=new_room(variant=variant,entry_fee=entry_fee,assisted=assisted,turbo=turbo,max_rounds=rounds,room_name=name)
    _ensure_meta(r.state.room_id,legacy=True)
    return _state(r.state.room_id,0)

@router.get('/game/{room_id}')
async def game_state(room_id:str,seat:int=0,reconnect_token:str|None=None):
    if room_id not in ROOMS:raise HTTPException(404,'room_not_found')
    m=_ensure_meta(room_id,legacy=True)
    if not m.get('legacy'):_auth(room_id,seat,reconnect_token)
    return _state(room_id,seat)

@router.post('/game/reconnect')
def reconnect_game(body:ReconnectIn):
    """Restore an authenticated player after socket loss or an app restart."""
    _account(body.player_id,body.account_token)
    candidates=[]
    for room_id,room in ROOMS.items():
        meta=_ensure_meta(room_id,legacy=True)
        seat=next((s for s,pid in meta.get('player_ids',{}).items() if pid==body.player_id),None)
        if seat is None or room.state.match_finished:continue
        candidates.append((meta.get('created_at',0),room_id,seat,meta))
    if not candidates:return {'ok':False,'code':'active_game_not_found'}
    _,room_id,seat,meta=max(candidates,key=lambda x:x[0])
    token=meta['seat_tokens'].get(seat) or _token()
    meta['seat_tokens'][seat]=token
    ROOMS[room_id].restore_human(seat)
    _touch(room_id)
    return {'ok':True,'room_id':room_id,'seat':seat,'reconnect_token':token,'state':_state(room_id,seat)}

async def _execute_action(room_id:str,body:ActionIn):
    """Single authoritative action path used by HTTP and WebSocket clients."""
    r=ROOMS.get(room_id)
    if not r:raise HTTPException(404,'room_not_found')
    m=_auth(room_id,body.seat,body.reconnect_token)
    _rate_limit(m,body.reconnect_token)
    if body.request_id and body.request_id in m['dedupe']:
        return m['dedupe'][body.request_id]

    # A valid reconnect token restores a human seat if a disconnect bot had taken it.
    if body.seat in m['player_ids'] and r.state.player(body.seat).bot:
        r.restore_human(body.seat)

    if body.kind=='start_match':
        owner=int(m.get('owner_seat',0) or 0)
        if not m.get('quick_match') and body.seat!=owner:
            response={'ok':False,'code':'host_only','payload':{},'request_id':body.request_id,'state':_state(room_id,body.seat)}
            if body.request_id:m['dedupe'][body.request_id]=response
            return response
        if not m.get('quick_match'):
            # Özel masada Hazır sistemi yok. Dört koltuk gerçek oyuncu veya
            # hostun bilinçli eklediği botla dolduğunda başlatma tamamen hostta.
            open_seats=[seat for seat in range(4) if seat not in m.get('player_ids',{}) and not (seat in m.setdefault('bot_seats',set()) and r.state.player(seat).bot)]
            if open_seats:
                response={'ok':False,'code':'empty_seats','payload':{'seats':open_seats},'request_id':body.request_id,'state':_state(room_id,body.seat)}
                if body.request_id:m['dedupe'][body.request_id]=response
                return response
        # Hızlı eşleşmede varsayılan akış 15 sn gerçek oyuncu arar. Ancak
        # masa sahibi boş koltuklara BOT EKLE ile bot koyduysa bu botlar da
        # koltuk doldurur; 1 insan + 3 bot gibi masalar başlatılabilmelidir.
        if m.get('quick_match'):
            humans=_human_count(room_id)
            bots=_bot_count(room_id)
            occupied=_occupied_count(room_id)
            if occupied < 4:
                response={
                    'ok':False,'code':'quick_match_waiting_for_players','payload':{
                        'humans':humans,'bots':bots,'occupied':occupied,'empty':4-occupied,'required':4,
                    },'request_id':body.request_id,'state':_state(room_id,body.seat),
                }
                if body.request_id:m['dedupe'][body.request_id]=response
                return response
            if body.seat != int(m.get('owner_seat',0) or 0):
                response={'ok':False,'code':'host_only','payload':{},'request_id':body.request_id,'state':_state(room_id,body.seat)}
                if body.request_id:m['dedupe'][body.request_id]=response
                return response
        ok,code=_charge_entries(room_id)
        if not ok:
            response={'ok':False,'code':code,'payload':{},'request_id':body.request_id,'state':_state(room_id,body.seat)}
            return response

    # API katmanında host kimliği doğrulandıktan sonra motorun legacy seat-0
    # kilidini atla. Böylece oda sahibi ilk koltukta olmak zorunda kalmaz.
    result=r.start_match(0) if body.kind=='start_match' else r.action(body.seat,body.kind,body.payload)
    if result.ok and body.kind=='start_match':
        task=QUICK_FILL_TASKS.pop(room_id,None)
        if task and task is not asyncio.current_task():
            task.cancel()
    if result.ok and body.kind=='rematch':
        # Same room, fresh match: allow a new settlement/stat cycle.
        m['match_seq']=int(m.get('match_seq',0) or 0)+1
        m['settled']=False
        m['recorded_rounds']=set()
        m['economy_charged']=False
    if result.ok:m['afk_strikes'][body.seat]=0
    _record_round_if_finished(room_id)
    _settle_if_finished(room_id)
    _canak_round_start(room_id)
    # Even rejected rule actions can mutate the authoritative penalty/event
    # state, so every processed action advances a monotonic revision.
    _touch(room_id)
    response={'ok':result.ok,'code':result.code,'payload':result.payload or {},'request_id':body.request_id,'state':_state(room_id,body.seat)}
    if body.request_id:
        m['dedupe'][body.request_id]=response
        if len(m['dedupe'])>80:
            for k in list(m['dedupe'])[:-60]:m['dedupe'].pop(k,None)
    # Acting client receives the canonical state in the action result. Peers
    # receive the same revision immediately over their sockets.
    await _broadcast(room_id,skip_seat=body.seat)
    return response

@router.post('/game/{room_id}/action')
async def game_action(room_id:str,body:ActionIn):
    return await _execute_action(room_id,body)


@router.post('/game/{room_id}/manage')
async def manage_room(room_id:str,body:ManageRoomIn):
    r=ROOMS.get(room_id)
    if not r:raise HTTPException(404,'room_not_found')
    m=_auth(room_id,body.seat,body.reconnect_token)
    if int(m.get('owner_seat',0))!=int(body.seat):raise HTTPException(403,'host_only')
    action=(body.action or '').strip().lower()
    if action=='kick':
        if r.state.phase!='waiting':raise HTTPException(409,'kick_waiting_only')
        target=body.target_seat
        if target is None or target not in range(4) or target==body.seat:raise HTTPException(400,'bad_target_seat')
        pid=m.get('player_ids',{}).get(target)
        if not pid:raise HTTPException(404,'player_not_found')
        p=r.state.player(target)
        p.bot=True;p.user_id=f'bot-seat-{target}';p.name=['Sen','Deniz','Mert','Eylül'][target]
        m['player_ids'].pop(target,None);m['seat_tokens'].pop(target,None);m.setdefault('bot_seats',set()).discard(target);m['connected'][target]=False;m['disconnect_at'][target]=_now()
        _touch(room_id)
        await _broadcast(room_id)
        return {'ok':True,'code':'player_kicked','seat':target}
    if action in {'add_bot','remove_bot'}:
        if r.state.phase!='waiting':raise HTTPException(409,'bot_waiting_only')
        target=body.target_seat
        if target is None or target not in range(4) or target==body.seat:raise HTTPException(400,'bad_target_seat')
        if target in m.get('player_ids',{}):return {'ok':False,'code':'seat_has_player'}
        p=r.state.player(target)
        if action=='remove_bot':
            m.setdefault('bot_seats',set()).discard(target);p.bot=True;p.bot_level='medium';p.user_id=f'bot-seat-{target}';p.name='Boş Koltuk'
        else:
            level=(body.bot_level or 'medium').strip().lower()
            if level not in {'easy','medium','hard'}:level='medium'
            m.setdefault('bot_seats',set()).add(target);p.bot=True;p.bot_level=level;p.user_id=f'bot-seat-{target}';p.name=['Mert','Ayşe','Kemal','Eylül'][target]
        _touch(room_id);await _broadcast(room_id)
        return {'ok':True,'code':action,'state':_state(room_id,body.seat)}
    if action=='settings':
        if r.state.phase!='waiting':raise HTTPException(409,'settings_waiting_only')
        if body.room_name is not None:
            name=' '.join(body.room_name.strip().split())[:28]
            if name:r.state.room_name=name
        if body.turn_seconds is not None:r.state.turn_seconds=max(15,min(90,int(body.turn_seconds)))
        if body.turbo is not None:r.state.turbo=bool(body.turbo)
        if body.variant is not None:
            wanted=body.variant if body.variant in ('fold','non_fold','duz') else 'non_fold'
            # Düz Okey 14 taşla dağıtılır; dağıtılmış masada 101<->Düz geçişi yapılamaz.
            if (wanted=='duz')!=(r.state.variant=='duz'):raise HTTPException(409,'variant_change_needs_new_room')
            r.state.variant=wanted
        if body.team_mode is not None:r.state.team_mode='paired' if body.team_mode=='paired' else 'solo'
        if body.assisted is not None:r.state.assisted=bool(body.assisted)
        if body.rounds is not None:r.state.max_rounds=max(1,min(3,int(body.rounds)))
        if body.entry_fee is not None:
            requested=max(1000,min(1_000_000,int(body.entry_fee)))
            liability=requested*(10 if r.state.turbo else 1)
            for pid in m.get('player_ids',{}).values():
                if not pid:continue
                acc=STORE.get(pid)
                if acc and int(acc.get('chips',0) or 0)<liability:
                    return {'ok':False,'code':'room_player_insufficient_balance','required':liability}
            r.state.entry_fee=requested;r.state.pot=requested*4
        if body.chat_enabled is not None:m['chat_enabled']=bool(body.chat_enabled)
        if body.gifts_enabled is not None:m['gifts_enabled']=bool(body.gifts_enabled)
        if body.auto_rematch is not None:m['auto_rematch']=bool(body.auto_rematch)
        r.recalculate_turbo()
        _touch(room_id)
        await _broadcast(room_id)
        return {'ok':True,'code':'settings_updated','state':_state(room_id,body.seat)}
    raise HTTPException(400,'bad_manage_action')

@router.post('/game/{room_id}/leave')
async def leave_room(room_id:str,body:LeaveIn):
    r=ROOMS.get(room_id)
    if not r:raise HTTPException(404,'room_not_found')
    m=_auth(room_id,body.seat,body.reconnect_token)

    # Waiting room / finished match / pre-deal intro: free exit. Countdown
    # is still pre-game, so Turbo lock has not started from the player's POV.
    intro_active=bool(getattr(r,'intro_until_ms',0) and int(time.time()*1000)<int(r.intro_until_ms))
    if r.state.phase in ('waiting','finished') or intro_active:
        if r.state.phase=='waiting' or intro_active:
            p=r.state.player(body.seat)
            p.bot=True;p.user_id=f'bot-seat-{body.seat}';p.name=['Sen','Deniz','Mert','Eylül'][body.seat]
            m['player_ids'].pop(body.seat,None);m['seat_tokens'].pop(body.seat,None);m.setdefault('bot_seats',set()).discard(body.seat)
            if int(m.get('owner_seat',0))==int(body.seat):
                remaining=sorted(int(seat) for seat,pid in m.get('player_ids',{}).items() if pid)
                if remaining:m['owner_seat']=remaining[0]
        m['connected'][body.seat]=False;m['disconnect_at'][body.seat]=_now()
        _touch(room_id)
        await _broadcast(room_id)
        return {'ok':True,'code':'left_intro' if intro_active else 'left_free'}

    # Turbo match cannot be intentionally abandoned from the table.
    # Closing/disconnecting is handled by reconnect grace -> bot takeover while
    # the original player stays financially tied to the match.
    if r.state.turbo:
        return {'ok':False,'code':'turbo_leave_locked'}

    # Standard 101: leaving mid-match forfeits exactly the table stake and a bot
    # takes over the seat. The leaver is removed from final settlement so they
    # are never charged twice.
    pid=m['player_ids'].get(body.seat)
    stake=max(0,int(r.state.entry_fee))
    if pid and STORE.get(pid):
        ok=STORE.debit(pid,stake,f'{r.state.room_name} • maçtan ayrılma cezası',notify=False)
        if not ok:
            return {'ok':False,'code':'leave_forfeit_insufficient_balance'}
    r.takeover_by_bot(body.seat,'medium')
    m['player_ids'].pop(body.seat,None);m['seat_tokens'].pop(body.seat,None);m.setdefault('bot_seats',set()).discard(body.seat)
    m['connected'][body.seat]=False;m['disconnect_at'][body.seat]=_now()
    _touch(room_id)
    await _broadcast(room_id)
    return {'ok':True,'code':'left_forfeit','forfeit':stake}

@router.post('/game/{room_id}/chat')
async def table_chat(room_id:str,body:ChatIn):
    r=ROOMS.get(room_id)
    if not r:raise HTTPException(404,'room_not_found')
    m=_auth(room_id,body.seat,body.reconnect_token)
    sender_id=m.get('player_ids',{}).get(body.seat)
    if sender_id:
        from app.services.phase4_service import Phase4Service
        san=Phase4Service(STORE).active_sanctions(sender_id)
        if san.get('muted') or san.get('chat_locked'):raise HTTPException(403,'account_muted')
        if body.kind=='gift' and san.get('gift_locked'):raise HTTPException(403,'gifts_locked')
    if body.kind not in ('quick','emoji','text','voice','gift'):raise HTTPException(400,'bad_chat_kind')
    if body.kind=='gift' and not bool(m.get('gifts_enabled',True)):raise HTTPException(403,'gifts_disabled')
    if body.kind!='gift' and not bool(m.get('chat_enabled',True)):raise HTTPException(403,'chat_disabled')
    value=body.value.strip()
    if body.kind=='emoji':
        allowed={'😂','😎','🔥','👏','🤝','😱','🍀','⭐','❤️','🥳','😅','🤩','😈','🤔','🙈','💯','👑','🎯','🫶','🤣','🎉','🕺','💃','✨','🏆','☕','🫖','🧿','😄','🪑','🤡','😏','🙃','👀','🫠','🧂','🐔','🩴','💜','💙','🩵','⚡','🌌','🎵'}
        if value not in allowed:raise HTTPException(400,'emoji_not_allowed')
        _chat_rate_limit(m,body.reconnect_token,body.kind)
    elif body.kind=='quick':
        allowed={
            'İyi oyun!','Bol şans!','Güzel el.','Hadi bakalım 😄','Tebrikler!','Biraz hızlı 😅',
            'Okey sende mi?','Çift gidiyorum 😄','Eline sağlık.','Şans bugün benden yana 🍀',
            'Son taş!','Vay be!','Devam devam 🔥','Kusura bakma 😅'
        }
        if value not in allowed:raise HTTPException(400,'quick_message_not_allowed')
        _chat_rate_limit(m,body.reconnect_token,body.kind)
    elif body.kind=='text':
        if len(value)>120:raise HTTPException(400,'message_too_long')
        value=_moderate_chat_text(value)
        _chat_rate_limit(m,body.reconnect_token,body.kind)
    elif body.kind=='voice':
        allowed={
            'Hadi kardeşim, ağaç olduk!','Okey bende!','Taşını at da oynayalım!',
            'Bol şans!','Son taş!','Vay be!','Çift gidiyorum!','Eline sağlık!'
        }
        if value not in allowed:raise HTTPException(400,'voice_line_not_allowed')
        _chat_rate_limit(m,body.reconnect_token,body.kind)
    else:
        table_gift=body.to_seat == -1
        if body.to_seat is None or (not table_gift and body.to_seat not in range(4)) or body.to_seat==body.seat:raise HTTPException(400,'target_required')
        if value not in GIFT_CATALOG:raise HTTPException(400,'gift_not_found')
        # Aynı hediye aynı oyuncudan 10 sn içinde tekrar atılamaz (istemcide
        # geri sayım halkası gösterilir; sunucu da zorlar).
        gift_cd=m.setdefault('gift_cooldowns',{});cd_key=f"{body.seat}:{value}"
        if _now()-float(gift_cd.get(cd_key,0.0))<float(GIFT_CATALOG[value].get('cooldown_s',GIFT_COOLDOWN_S)):
            raise HTTPException(429,'gift_cooldown')
        _chat_rate_limit(m,body.reconnect_token,body.kind)
        gift_id=value
        from_id=m['player_ids'].get(body.seat);to_id=None if table_gift else m['player_ids'].get(body.to_seat)
        gift=GIFT_CATALOG[value]
        # A table gift is paid once and animates around all seats; it is not persisted
        # as three separate profile gifts. Direct gifts keep normal recipient history.
        if table_gift:
            cost=max(0,int(gift.get('cost',0) or 0))
            if from_id and cost and not STORE.debit(from_id,cost,f"Masaya hediye • {gift['name']}",notify=False):
                return {'ok':False,'code':'insufficient_coins','required':cost}
            value=str(gift['name'])
        elif from_id and to_id:
            g=STORE.send_gift(from_id,to_id,value)
            if not g.get('ok'):return g
            value=str(g.get('gift',{}).get('name') or gift['name'])
        else:
            cost=max(0,int(gift.get('cost',0) or 0))
            if from_id and cost:
                if not STORE.debit(from_id,cost,f"Masa hediyesi • {gift['name']}",notify=False):
                    return {'ok':False,'code':'insufficient_coins','required':cost}
            value=str(gift['name'])
    event=_append_chat(room_id,body.seat,body.kind,value,body.to_seat)
    if body.kind=='gift':
        m.setdefault('gift_cooldowns',{})[f"{body.seat}:{gift_id}"]=_now()
        event['gift_id']=gift_id
        event['style']=str(GIFT_CATALOG[gift_id].get('style','float'))
    _touch(room_id)
    await _broadcast(room_id)
    return {'ok':True,'event':event}

@router.websocket('/game/{room_id}/ws')
async def game_ws(ws:WebSocket,room_id:str,seat:int=0,reconnect_token:str|None=None):
    r=ROOMS.get(room_id)
    if not r:
        await ws.close(code=4404);return
    m=_ensure_meta(room_id,legacy=True)
    if not m.get('legacy'):
        expected=m['seat_tokens'].get(seat)
        if not expected or not reconnect_token or not secrets.compare_digest(expected,reconnect_token):
            await ws.close(code=4401);return
    await ws.accept()
    if seat in m['player_ids'] and r.state.player(seat).bot:r.restore_human(seat)
    m['connected'][seat]=True;m['disconnect_at'].pop(seat,None);m['afk_strikes'][seat]=0
    SOCKETS.setdefault(room_id,{}).setdefault(seat,[]).append(ws)
    _touch(room_id)
    await _broadcast(room_id)
    try:
        while True:
            msg=await ws.receive_text()
            if msg=='ping':
                m['connected'][seat]=True
                await ws.send_text('pong')
                continue
            # V8 supports low-latency authoritative actions over the existing
            # authenticated game socket. HTTP remains a fallback for old clients.
            try:
                packet=json.loads(msg)
            except Exception:
                await ws.send_json({'type':'error','code':'bad_socket_payload'})
                continue
            if not isinstance(packet,dict):
                await ws.send_json({'type':'error','code':'bad_socket_payload'})
                continue
            kind=str(packet.get('type') or '')
            if kind=='action':
                try:
                    body=ActionIn(
                        seat=seat,
                        kind=str(packet.get('kind') or ''),
                        payload=packet.get('payload') if isinstance(packet.get('payload'),dict) else {},
                        reconnect_token=reconnect_token,
                        request_id=str(packet.get('request_id') or '') or None,
                    )
                    result=await _execute_action(room_id,body)
                    await ws.send_json({'type':'action_result',**result})
                except HTTPException as exc:
                    await ws.send_json({'type':'action_result','ok':False,'code':str(exc.detail),'request_id':packet.get('request_id'),'payload':{},'state':_state(room_id,seat)})
                except Exception as exc:
                    await ws.send_json({'type':'action_result','ok':False,'code':'socket_action_failed','request_id':packet.get('request_id'),'payload':{'error':type(exc).__name__},'state':_state(room_id,seat)})
            elif kind=='sync':
                await ws.send_json({'type':'state','state':_state(room_id,seat)})
            else:
                await ws.send_json({'type':'error','code':'unknown_socket_message'})
    except WebSocketDisconnect:
        pass
    finally:
        lst=SOCKETS.get(room_id,{}).get(seat,[])
        if ws in lst:lst.remove(ws)
        if not lst:
            m['connected'][seat]=False;m['disconnect_at'][seat]=_now()
            _touch(room_id)
        await _broadcast(room_id)

async def room_watchdog():
    """AFK + reconnect monitor. Never let one broken room kill all auto-turns."""
    while True:
        now=_now()
        for rid,room in list(ROOMS.items()):
            try:
                m=_ensure_meta(rid,legacy=True);changed=False
                if (room.state.phase=='waiting' and m.get('quick_match') and not room.state.started
                        and now-float(m.get('quick_fill_at',float(m.get('created_at',now))+QUICK_BOT_FILL_SECONDS))>=0):
                    try:changed=_fill_bots_and_start(rid) or changed
                    except HTTPException:pass
                if room.state.started and room.intro_until_ms:
                    changed=room.advance_intro_if_ready() or changed
                if room.state.started and not room.intro_until_ms and room.state.phase in ('draw','discard'):
                    seat=room.state.current_seat;p=room.state.player(seat)
                    if not p.bot and seat in m['player_ids'] and not m['connected'].get(seat,False):
                        disc=m['disconnect_at'].get(seat)
                        if disc and now-disc>=20:
                            room.takeover_by_bot(seat,'afk');changed=True
                    if not p.bot and room.state.turn_deadline_ms and int(now*1000)>=room.state.turn_deadline_ms:
                        result=room.timeout_turn(seat)
                        if result.ok:
                            m['afk_strikes'][seat]=m['afk_strikes'].get(seat,0)+1;changed=True
                            if m['afk_strikes'][seat]>=2:room.takeover_by_bot(seat,'afk')
                        else:
                            room.state.log.append(f'WATCHDOG_TIMEOUT_RETRY seat={seat} code={result.code}')
                            room._set_turn_deadline()
                    elif p.bot and room.state.current_seat==seat:
                        changed=room.run_bots_until_human() or changed
                _record_round_if_finished(rid);_settle_if_finished(rid);_canak_round_start(rid)
                if changed:
                    _touch(rid)
                    await _broadcast(rid)
            except Exception as exc:
                try:room.state.log.append(f'WATCHDOG_ERROR {type(exc).__name__}:{exc}')
                except Exception:pass
            # Her odadan sonra olay döngüsüne nefes ver: çok masada HTTP istekleri beklemesin.
            await asyncio.sleep(0)
        if _RUNTIME_DIRTY and time.monotonic()-_LAST_PERSIST_AT>=PERSIST_MIN_INTERVAL:_persist_runtime(force=True)
        await asyncio.sleep(.75)

def start_watchdog():
    global WATCHDOG_TASK
    _restore_runtime_once()
    if WATCHDOG_TASK is None or WATCHDOG_TASK.done():
        WATCHDOG_TASK=asyncio.create_task(room_watchdog())
