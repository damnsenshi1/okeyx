from __future__ import annotations
import json, os, threading, time, uuid, secrets, hashlib, random, re
from copy import deepcopy
from pathlib import Path
from app.services.remote_store import SupabaseKV, RemoteSync, split_state, merge_state

DATA_PATH=Path(os.getenv('OKEYX_DATA_PATH') or (Path(__file__).resolve().parents[2]/'data'/'accounts.json'))

DAILY_REWARDS=[2500,3000,3500,4000,5000,6500,10000]
GIFT_CATALOG={
    # Social gifts are short table moments, not gameplay advantages.
    'tea': {'name':'Çay','cost':0,'emoji':'🫖','reaction':False,'persistent':False},
    'coffee': {'name':'Türk Kahvesi','cost':0,'emoji':'☕','reaction':False,'persistent':False},
    'nazar': {'name':'Nazar Boncuğu','cost':0,'emoji':'🧿','reaction':False,'persistent':False},
    'rose': {'name':'Gül','cost':0,'emoji':'🌹','reaction':False,'persistent':False},
    'simit': {'name':'Simit','cost':0,'emoji':'🥨','reaction':False,'persistent':False},
    'cake': {'name':'Pasta','cost':0,'emoji':'🎂','reaction':False,'persistent':True},
    'trophy': {'name':'Altın Kupa','cost':0,'emoji':'🏆','reaction':False,'persistent':True},
    'fireworks': {'name':'Havai Fişek','cost':0,'emoji':'🎆','reaction':False,'persistent':True},
    # Masada fırlatılan eğlenceli tepkiler (oyunu etkilemez).
    'tomato': {'name':'Domates','cost':0,'emoji':'🍅','reaction':True,'persistent':False,'hidden':False},
    'egg': {'name':'Yumurta','cost':0,'emoji':'🥚','reaction':True,'persistent':False,'hidden':False},
    'heart': {'name':'Kalp','cost':0,'emoji':'❤️','reaction':False,'persistent':False,'hidden':False},
    'fire': {'name':'Ateş','cost':0,'emoji':'🔥','reaction':False,'persistent':False,'hidden':False},
    # Hidden aliases keep sessions from an older APK from failing mid-table.
    'punch': {'name':'Yumruk','cost':0,'emoji':'👊','reaction':True,'persistent':False,'hidden':False},
    'applause': {'name':'Alkış','cost':0,'emoji':'👏','reaction':True,'persistent':False,'hidden':False},
    'slipper': {'name':'Terlik','cost':0,'emoji':'🩴','reaction':False,'persistent':False,'hidden':False},
    'fish': {'name':'Balık Tokadı','cost':0,'emoji':'🐟','reaction':False,'persistent':False,'hidden':False},
    'rubber_chicken': {'name':'Lastik Tavuk','cost':0,'emoji':'🐔','reaction':False,'persistent':False,'hidden':False},
    'plunger': {'name':'Pompa','cost':0,'emoji':'🪠','reaction':False,'persistent':False,'hidden':False},
    'censored_banana': {'name':'Sansürlü Muz','cost':0,'emoji':'🍌','reaction':False,'persistent':False,'hidden':False},
    'money_rain': {'name':'Para Yağmuru','cost':0,'emoji':'💸','reaction':False,'persistent':False,'hidden':False},
    'crown': {'name':'Altın Taç','cost':0,'emoji':'👑','reaction':False,'persistent':False,'hidden':False},
    'rocket': {'name':'Roket','cost':0,'emoji':'🚀','reaction':False,'persistent':False,'hidden':False},
    'sports_car': {'name':'Spor Araba','cost':0,'emoji':'🏎️','reaction':False,'persistent':False,'hidden':False},
    'dragon': {'name':'Ejderha','cost':0,'emoji':'🐉','reaction':False,'persistent':False,'hidden':False},
    # Yeni hediyeler
    'lokum': {'name':'Lokum','cost':0,'emoji':'🍬','reaction':False,'persistent':False,'hidden':False},
    'doner': {'name':'Döner','cost':0,'emoji':'🥙','reaction':False,'persistent':False,'hidden':False},
    'ayran': {'name':'Ayran','cost':0,'emoji':'🥛','reaction':False,'persistent':False,'hidden':False},
    'balloon': {'name':'Balon','cost':0,'emoji':'🎈','reaction':False,'persistent':False,'hidden':False},
    'kiss': {'name':'Öpücük','cost':0,'emoji':'💋','reaction':False,'persistent':False,'hidden':False},
    'ghost': {'name':'Hayalet','cost':0,'emoji':'👻','reaction':False,'persistent':False,'hidden':False},
    'clown': {'name':'Palyaço Burnu','cost':0,'emoji':'🤡','reaction':True,'persistent':False,'hidden':False},
    'water': {'name':'Su Balonu','cost':0,'emoji':'💦','reaction':True,'persistent':False,'hidden':False},
    'pie': {'name':'Yüze Pasta','cost':0,'emoji':'🥧','reaction':True,'persistent':False,'hidden':False},
    'bomb': {'name':'Bomba','cost':0,'emoji':'💣','reaction':True,'persistent':False,'hidden':False},
    'gold_rain': {'name':'Altın Yağmuru','cost':0,'emoji':'🪙','reaction':False,'persistent':False,'hidden':False},
    'confetti': {'name':'Konfeti','cost':0,'emoji':'🎉','reaction':False,'persistent':False,'hidden':False},
    'unicorn': {'name':'Unicorn','cost':0,'emoji':'🦄','reaction':False,'persistent':False,'hidden':False},
    'lightning': {'name':'Şimşek','cost':0,'emoji':'⚡','reaction':False,'persistent':False,'hidden':False},
    'diamond_ring': {'name':'Pırlanta Yüzük','cost':0,'emoji':'💍','reaction':False,'persistent':False,'hidden':False},
}
# Masadaki gösterim biçimi: 'stick' = avatara "tak" diye yapışır,
# 'big' = tüm ekranı kaplayan kısa gösteri, 'float' = avatarın üstünde süzülür.
GIFT_STICK={'tomato','egg','punch','slipper','fish','rubber_chicken','plunger','censored_banana','clown','water','pie','bomb'}
GIFT_BIG={'dragon','sports_car','rocket','money_rain','crown','fireworks','trophy','cake','gold_rain','confetti','unicorn','lightning','diamond_ring'}
GIFT_COOLDOWN_S=10.0
for _gid,_row in GIFT_CATALOG.items():
    _row.setdefault('style','stick' if _gid in GIFT_STICK else ('big' if _gid in GIFT_BIG else 'float'))
    _row.setdefault('cooldown_s',GIFT_COOLDOWN_S)
WHEEL_REWARDS=[500,1000,1500,2500,5000,10000,25000]
CHEST_REWARDS=[750,1250,2000,3500,5000,7500,15000]
SEASON_ID='2026-S1'
SEASON_MILESTONES=[
    {'id':'s1_5','points':5,'chips':1500},
    {'id':'s1_15','points':15,'chips':3500},
    {'id':'s1_30','points':30,'chips':7500},
    {'id':'s1_60','points':60,'chips':15000},
]


def _now()->int:return int(time.time())

# Oyun günü Türkiye saatine göre döner (Render sunucusu UTC çalışır).
# Eskiden gece 00:00-03:00 arası istemci "ödül hazır" derken sunucu hâlâ
# önceki günü sayıyor ve "Bu işlem şu anda tamamlanamadı" hatası çıkıyordu.
GAME_UTC_OFFSET_SECONDS=int(os.environ.get('OKEYX_GAME_UTC_OFFSET_SECONDS','10800'))

# player_id -> son nabız (yalnız bellekte; sunucu yeniden başlarsa herkes çevrimdışı başlar)
PRESENCE:dict[str,float]={}
PRESENCE_WINDOW_SECONDS=60.0

def seen_recently(player_id:str,window:float=PRESENCE_WINDOW_SECONDS)->bool:
    ts=PRESENCE.get(player_id)
    return bool(ts and _now()-ts<window)

# Masada yalnızca sahip olunan kozmetikler gösterilir. Varsayılanlar
# (rack_classic, tiles_classic, cloth_green, frame_none) herkese açıktır.
_DEFAULT_COSMETICS={'rack':'rack_classic','tiles':'tiles_classic','cloth':'cloth_green','frame':'frame_none'}


def _owned_equipped(a:dict)->dict:
    inv=set(a.get('inventory') or [])
    out={}
    for cat,item in dict(a.get('equipped') or {}).items():
        item=str(item or '')
        if not item:continue
        if item in inv or item==_DEFAULT_COSMETICS.get(cat):
            out[cat]=item
        elif cat in _DEFAULT_COSMETICS:
            out[cat]=_DEFAULT_COSMETICS[cat]
    return out


def _game_time(ts:int|float|None=None):
    return time.gmtime((ts or _now())+GAME_UTC_OFFSET_SECONDS)

def _day_key(ts:int|None=None)->str:
    return time.strftime('%Y-%m-%d',_game_time(ts))

def _month_key(ts:int|None=None)->str:
    return time.strftime('%Y-%m',_game_time(ts))


def _week_key(ts:int|None=None)->str:
    return time.strftime('%Y-W%W',_game_time(ts))


def _sanitize_social_text(value:str,max_len:int=160)->str:
    from ..core.textfilter import mask,is_spam
    text=' '.join((value or '').split())
    if not text:return ''
    if is_spam(text):return ''
    text,_flag=mask(text)
    return text[:max_len]

def _referral_code(player_id:str)->str:
    digest=hashlib.sha256(player_id.encode('utf-8')).hexdigest()[:8].upper()
    return f'OKX{digest}'

def _public_id(player_id:str)->str:
    """Stable, human-shareable public id.

    UUID fragments were too long and looked like database keys in the UI.
    A six digit number is short enough to read over voice/chat while the full
    auth UUID remains the private primary identity. Collisions are resolved by
    AccountStore._ensure_unique_public_id when accounts are loaded/created.
    """
    digest=hashlib.sha256((player_id or 'okeyx').encode('utf-8')).digest()
    number=100000+(int.from_bytes(digest[:8],'big')%900000)
    return f'OX-{number:06d}'

def _league_tier(points:int)->str:
    if points>=1800:return 'Şampiyonlar'
    if points>=900:return 'Elmas'
    if points>=450:return 'Altın'
    if points>=180:return 'Gümüş'
    return 'Bronz'

def _level_for_xp(xp:int)->int:
    # Fast early progression, gradually slower.
    level=1
    need=600
    left=max(0,int(xp))
    while left>=need and level<100:
        left-=need;level+=1;need=int(need*1.14+80)
    return level

def _base_account(player_id:str,name:str='Oyuncu',email:str|None=None,avatar_url:str|None=None,is_guest:bool=False)->dict:
    return {
        'id':player_id,'public_id':_public_id(player_id),'is_guest':bool(is_guest),'name':(name or 'Oyuncu')[:24],'email':email,'avatar_url':avatar_url,'session_token':secrets.token_urlsafe(32),
        'chips':1_000_000,'economy_schema_version':2,'xp':0,'level':1,'created_at':_now(),'last_seen':_now(),
        'stats':{
            'games':0,'wins':0,'losses':0,'rounds':0,'okey_finishes':0,'pair_finishes':0,
            'series_opens':0,'pair_opens':0,'best_streak':0,'current_streak':0,
            'total_xp_earned':0,'chips_won':0,'chips_spent':0,
        },
        'daily':{'last_claim_day':None,'streak':0,'last_claim_at':None},
        'mission_state':{'day':_day_key(),'week':_week_key(),'daily':{},'weekly':{}},
        'achievements':[],
        'friends':[],
        'friend_requests':[],
        'sent_friend_requests':[],
        'recent_players':[],
        'notifications':[],
        'gifts_received':[],
        'wheel':{'last_spin_day':None,'last_reward':0,'spins':0},
        'chests':{'keys':1,'last_free_day':None,'opened':0},
        'blocked':[],
        'muted':[],
        'reports_made':0,
        'referral':{'code':_referral_code(player_id),'redeemed_code':None,'referrals':[]},
        'league':{'week':_week_key(),'points':0,'city':'Denizli','tier':'Bronz'},
        'club_id':None,
        'club_rewards':{'claimed_weeks':[]},
        'season':{'id':SEASON_ID,'points':0,'claimed':[]},
        'push_tokens':[],
        'device_ids':[],
        'security':{'risk_flags':[],'device_account_count':1},
        'match_history':[],
        'settings':{'notifications':True,'friend_requests':True,'invites':True,'gifts':True,'chat':True},
        'coin_transfers':{'day':_day_key(),'sent_today':0,'received_today':0,'history':[]},
    }

DAILY_MISSIONS=[
    {'id':'daily_play_1','title':'1 oyun oyna','target':1,'metric':'games','reward_chips':1200,'reward_xp':80},
    {'id':'daily_win_1','title':'1 oyun kazan','target':1,'metric':'wins','reward_chips':2200,'reward_xp':150},
    {'id':'daily_rounds_3','title':'3 el tamamla','target':3,'metric':'rounds','reward_chips':1600,'reward_xp':110},
]
WEEKLY_MISSIONS=[
    {'id':'weekly_play_10','title':'10 oyun oyna','target':10,'metric':'games','reward_chips':9000,'reward_xp':700},
    {'id':'weekly_win_4','title':'4 oyun kazan','target':4,'metric':'wins','reward_chips':12000,'reward_xp':1000},
    {'id':'weekly_rounds_20','title':'20 el tamamla','target':20,'metric':'rounds','reward_chips':10000,'reward_xp':850},
]

PUSH_KINDS={'friend_request','friend','invite','canak','vip','support','season','referral','tournament','daily_ready','event'}

class AccountStore:
    def __init__(self,path:Path=DATA_PATH,remote:'SupabaseKV|None'=None):
        self.path=path
        self.path.parent.mkdir(parents=True,exist_ok=True)
        self._lock=threading.RLock()
        self._data=self._empty_data()
        self._sync:RemoteSync|None=None
        self._remote_error:str|None=None
        # remote verilmezse ve ortamda Supabase service anahtarı varsa otomatik bağlanır.
        if remote is None:
            from app.core.config import settings
            if settings.remote_store_enabled:
                remote=SupabaseKV(settings.supabase_url,settings.supabase_service_role_key)
        self._load()
        if remote is not None:
            self._sync=RemoteSync(remote,self._snapshot_rows)
            self._remote_error='not_loaded'
            self._load_remote()
            self._sync.start()

    @staticmethod
    def _empty_data()->dict:
        return {'accounts':{},'clubs':{},'reports':[],'referral_devices':{},'device_accounts':{},'canak':{'balance':0,'history':[]},'activity':[]}

    @property
    def ready(self)->bool:
        """Uzak depo tanımlıysa yalnızca başarıyla yüklendikten sonra hazırdır.

        Hazır değilken hesap açmak/okumak, oyuncuya sıfırdan (taze coinli) hesap
        vermek ve sonra gerçek hesabı ezmek demek olurdu; bu yüzden 503 döneriz."""
        return self._sync is None or self._sync.loaded

    def _snapshot_rows(self)->dict:
        with self._lock:
            return split_state(deepcopy(self._data))

    def _load_remote(self)->bool:
        """Supabase'den tüm veriyi çeker. Başarısızsa False; arka planda yeniden denenir."""
        sync=self._sync
        if sync is None:return True
        try:
            rows=sync.kv.load_all()
        except Exception as exc:
            self._remote_error=str(exc)[:300]
            print(f'OKEYX_REMOTE_LOAD_FAIL {self._remote_error}',flush=True)
            threading.Thread(target=self._retry_remote_load,name='okeyx-remote-load-retry',daemon=True).start()
            return False
        with self._lock:
            if rows:
                self._data=merge_state(rows,self._empty_data())
                for key,default in self._empty_data().items():
                    self._data.setdefault(key,default)
            # rows boşsa: ilk kurulum; yerel (varsa) veri ilk flush'ta yüklenir.
            sync.mark_known(rows)
            sync.loaded=True
            self._remote_error=None
        sync.mark_dirty()
        print(f'OKEYX_REMOTE_LOADED rows={len(rows)}',flush=True)
        return True

    def _retry_remote_load(self):
        delay=3.0
        while self._sync is not None and not self._sync.loaded:
            time.sleep(delay)
            try:
                if self._load_remote_quiet():return
            except Exception:
                pass
            delay=min(delay*2,60.0)

    def _load_remote_quiet(self)->bool:
        sync=self._sync
        try:
            rows=sync.kv.load_all()
        except Exception as exc:
            self._remote_error=str(exc)[:300];return False
        with self._lock:
            if rows:
                local_only={k:v for k,v in self._data.get('accounts',{}).items() if f'account:{k}' not in rows}
                self._data=merge_state(rows,self._empty_data())
                for key,default in self._empty_data().items():
                    self._data.setdefault(key,default)
                self._data['accounts'].update(local_only)
            sync.mark_known(rows);sync.loaded=True;self._remote_error=None
        sync.mark_dirty();print(f'OKEYX_REMOTE_LOADED rows={len(rows)}',flush=True)
        return True

    def flush(self)->int:
        """Bekleyen değişiklikleri hemen Supabase'e yazar (kapanışta çağrılır)."""
        if self._sync is None:return 0
        try:return self._sync.flush()
        except Exception as exc:
            self._remote_error=str(exc)[:300];return 0

    def remote_status(self)->dict:
        return {'enabled':self._sync is not None,'loaded':self.ready,'error':self._remote_error,'accounts':len(self._data.get('accounts',{}))}

    def purge_account(self,player_id:str)->bool:
        """Hesabı ve diğer oyuncuların listelerindeki izini siler (KVKK / hesap silme)."""
        with self._lock:
            existed=self._data['accounts'].pop(player_id,None) is not None
            for a in self._data['accounts'].values():
                for key in ('friends','friend_requests','sent_friend_requests','recent_players','blocked','muted'):
                    if isinstance(a.get(key),list):a[key]=[x for x in a[key] if x!=player_id and (not isinstance(x,dict) or x.get('id')!=player_id)]
            for club in self._data.get('clubs',{}).values():
                if isinstance(club.get('members'),list):
                    club['members']=[m for m in club['members'] if (m if isinstance(m,str) else (m or {}).get('id'))!=player_id]
            self._save()
            return existed

    def _load(self):
        with self._lock:
            try:
                if self.path.exists():
                    raw=json.loads(self.path.read_text(encoding='utf-8'))
                    if isinstance(raw,dict) and isinstance(raw.get('accounts'),dict):
                        self._data=raw
                        self._data.setdefault('clubs',{})
                        self._data.setdefault('reports',[])
                        self._data.setdefault('referral_devices',{})
                        self._data.setdefault('device_accounts',{})
                        self._data.setdefault('canak',{'balance':0,'history':[]})
                        self._data.setdefault('activity',[])
            except Exception:
                self._data={'accounts':{},'clubs':{},'reports':[],'referral_devices':{},'device_accounts':{},'canak':{'balance':0,'history':[]},'activity':[]}

    def _save(self):
        with self._lock:
            if self._sync is not None:
                # Kalıcılık Supabase'de; yerel disk geçici olduğu için yazılmaz.
                self._sync.mark_dirty()
                return
            tmp=self.path.with_suffix('.tmp')
            tmp.write_text(json.dumps(self._data,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
            tmp.replace(self.path)

    def verify(self,player_id:str,token:str|None)->bool:
        if not player_id or not token:return False
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return False
            expected=str(a.get('session_token') or '')
            return bool(expected) and secrets.compare_digest(expected,str(token))

    def bootstrap_guest(self,player_id:str,name:str='Oyuncu',session_token:str|None=None)->dict|None:
        if not player_id:raise ValueError('player_id_required')
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if a:
                if not self.verify(player_id,session_token):return None
                if name:a['name']=(name or a['name'])[:24]
                a['last_seen']=_now();self._normalize(a);self._save();return deepcopy(a)
            a=_base_account(player_id,name,is_guest=True);a['chips']=int(self.economy()['welcome_chips'])
            a['public_id']=self._ensure_unique_public_id(player_id,a.get('public_id'))
            self._data['accounts'][player_id]=a;self._save();return deepcopy(a)

    def ensure(self,player_id:str,name:str='Oyuncu',email:str|None=None,avatar_url:str|None=None,is_guest:bool=False)->dict:
        if not player_id:raise ValueError('player_id_required')
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:
                a=_base_account(player_id,name,email,avatar_url,is_guest=is_guest);a['chips']=int(self.economy()['welcome_chips'])
                a['public_id']=self._ensure_unique_public_id(player_id,a.get('public_id'))
                self._data['accounts'][player_id]=a
            else:
                if name and name!='Oyuncu':a['name']=name[:24]
                if email:a['email']=email
                if avatar_url:a['avatar_url']=avatar_url
                a['is_guest']=bool(is_guest)
                # One-time DEVELOPMENT economy migration. Old test accounts
                # created before the million-coin economy kept tiny balances
                # even after a clean APK install because accounts.json lives on
                # the PC backend. Never run this refill in production.
                if int(a.get('economy_schema_version',1) or 1)<2 and os.getenv('ENV','development').lower()!='production':
                    a['chips']=max(1_000_000,int(a.get('chips',0) or 0))
                    a['economy_schema_version']=2
                a['public_id']=self._ensure_unique_public_id(player_id,a.get('public_id'))
                a['last_seen']=_now()
                self._normalize(a)
            self._save()
            return deepcopy(a)

    def sync_local_wallet(self,player_id:str,coins:int,diamonds:int=0)->dict:
        """Developer-only wallet hydration for LAN/USB gameplay builds.

        The phone has already loaded the authenticated Supabase profile. Keeping
        the local game engine on that exact balance prevents false
        insufficient-funds errors and makes table entry testable.
        """
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a: raise ValueError('account_not_found')
            a['chips']=max(0,int(coins))
            a['diamonds']=max(0,int(diamonds))
            a['economy_schema_version']=3
            a['last_seen']=_now()
            self._save()
            return deepcopy(a)

    def _ensure_unique_public_id(self,player_id:str,current:str|None=None)->str:
        candidate=(current or '').strip().upper()
        if not re.fullmatch(r'OX-\d{6}',candidate):
            candidate=_public_id(player_id)
        # O(1) dizin: eskiden her get() çağrısında tüm hesaplar taranıyordu
        # (10 bin hesapta her durum sorgusu 40 bin döngü demekti).
        accounts=self._data.get('accounts',{})
        idx=self.__dict__.get('_public_index')
        if idx is None or self.__dict__.get('_public_index_src') is not accounts:
            idx={}
            for pid,x in accounts.items():
                p_=str(x.get('public_id') or '').upper()
                if p_ and p_ not in idx:idx[p_]=pid
            self._public_index=idx;self._public_index_src=accounts
        owner=idx.get(candidate)
        if owner is None or owner==player_id or owner not in accounts or str(accounts[owner].get('public_id') or '').upper()!=candidate:
            idx[candidate]=player_id
            return candidate
        value=int(candidate.split('-')[-1])
        for step in range(1,900000):
            nxt=100000+((value-100000+step)%900000)
            probe=f'OX-{nxt:06d}'
            o=idx.get(probe)
            if o is None or o not in accounts or str(accounts[o].get('public_id') or '').upper()!=probe:
                idx[probe]=player_id
                return probe
        raise RuntimeError('public_id_space_exhausted')

    def _normalize(self,a:dict):
        base=_base_account(a.get('id','unknown'),a.get('name','Oyuncu'),a.get('email'),a.get('avatar_url'),bool(a.get('is_guest',False)))
        for k,v in base.items():
            if k not in a:a[k]=deepcopy(v)
        for k,v in base['stats'].items():a['stats'].setdefault(k,v)
        a['public_id']=self._ensure_unique_public_id(str(a.get('id') or ''),a.get('public_id'))
        self._reset_missions_if_needed(a)
        league=a.setdefault('league',deepcopy(base['league']))
        if league.get('week')!=_week_key():
            league.update({'week':_week_key(),'points':0,'tier':'Bronz'})
        league['tier']=_league_tier(int(league.get('points',0)))
        season=a.setdefault('season',deepcopy(base['season']))
        if season.get('id')!=SEASON_ID:season.update({'id':SEASON_ID,'points':0,'claimed':[]})
        a['level']=_level_for_xp(a.get('xp',0))

    def get(self,player_id:str)->dict|None:
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return None
            self._normalize(a)
            # Performans: her durum sorgusunda tüm hesap veritabanını yazma.
            # Bir hesap bu süreçte ilk kez normalize edildiğinde bir kez kaydet;
            # sonraki değişiklikler zaten kendi işlemleriyle kaydedilir.
            seen=self.__dict__.setdefault('_normalized_ids',set())
            if player_id not in seen:
                seen.add(player_id);self._save()
            return deepcopy(a)

    def table_view(self,player_id:str)->dict|None:
        """Masa durumu için hafif, kopyasız okuma (normalize/deepcopy yok).
        Her durum sorgusunda 4 oyuncu için tam hesap kopyalamak kilidi tıkıyordu."""
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return None
            vip=a.get('vip') or {};stats=a.get('stats') or {};league=a.get('league') or {}
            return {
                'avatar_url':a.get('avatar_url'),'level':a.get('level',1),'chips':a.get('chips',0),
                'vip':{'level':vip.get('level',0),'badge':vip.get('badge'),'name_color':vip.get('name_color')},
                'equipped':_owned_equipped(a),
                'stats':{k:stats.get(k,0) for k in ('games','wins','losses','best_streak','current_streak')},
                'league':{'city':league.get('city','Denizli'),'tier':league.get('tier','Bronz')},
                'gifts_received':list((a.get('gifts_received') or [])[:8]),
            }

    def public(self,player_id:str)->dict|None:
        a=self.get(player_id)
        if not a:return None
        return {
            'id':a['id'],'public_id':a.get('public_id') or _public_id(a['id']),'is_guest':bool(a.get('is_guest',False)),'name':a['name'],'avatar_url':a.get('avatar_url'),'level':a['level'],'xp':a['xp'],
            'stats':a['stats'],'stats_by_mode':deepcopy(a.get('stats_by_mode',{})),'achievements':a['achievements'][-8:],
            'league':deepcopy(a.get('league',{})),'club_id':a.get('club_id'),'last_seen':float(a.get('last_seen',0) or 0),
            'gifts_received':deepcopy([x for x in a.get('gifts_received',[]) if bool(x.get('persistent',False))][:12]),
        }

    def touch_presence(self,player_id:str)->None:
        # Gerçek çevrimiçi bilgisi yalnızca oyuncunun kendi istemcisinden gelen
        # nabızla güncellenir. `ensure()` arkadaş aramasında gölge hesap
        # açarken de last_seen yazdığı için eskiden herkes "aktif" görünüyordu.
        PRESENCE[player_id]=_now()
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return
            a['last_seen']=_now()
            # Presence heartbeats are intentionally not fsynced every second;
            # the in-memory value is enough for live friend cards and the next
            # normal account mutation persists it.

    def update_profile(self,player_id:str,*,name:str|None=None,avatar_url:str|None=None)->dict:
        with self._lock:
            a=self._data['accounts'][player_id]
            if name:a['name']=name.strip()[:24] or a['name']
            if avatar_url is not None:a['avatar_url']=avatar_url
            self._save();return deepcopy(a)

    def record_activity(self,kind:str,player_id:str|None,message:str,meta:dict|None=None)->dict:
        with self._lock:
            name='OkeyX'
            public_id=None
            if player_id and player_id in self._data.get('accounts',{}):
                a=self._data['accounts'][player_id];name=str(a.get('name') or 'Oyuncu')[:24];public_id=a.get('public_id') or _public_id(player_id)
            row={'id':uuid.uuid4().hex[:12],'kind':(kind or 'info')[:24],'player_id':player_id,'public_id':public_id,'name':name,'message':(message or '')[:120],'meta':deepcopy(meta or {}),'created_at':_now()}
            feed=self._data.setdefault('activity',[]);feed.insert(0,row);self._data['activity']=feed[:80]
            self._save();return deepcopy(row)

    def activity_feed(self,limit:int=20)->list[dict]:
        with self._lock:
            return deepcopy(self._data.setdefault('activity',[])[:max(1,min(int(limit),40))])

    def add_notification(self,player_id:str,title:str,message:str,kind:str='info',data:dict|None=None)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return {}
            n={'id':uuid.uuid4().hex[:12],'title':title,'message':message,'kind':kind,'data':data or {},'read':False,'created_at':_now()}
            a['notifications'].insert(0,n);a['notifications']=a['notifications'][:80]
            self._save();out=deepcopy(n)
        hook=getattr(self,'push_hook',None)
        if hook and kind in PUSH_KINDS:
            # Ağ çağrısı kilit dışında ve arka planda: oyun akışı push yüzünden yavaşlamaz.
            threading.Thread(target=self._safe_push,args=(hook,player_id,title,message,kind,data or {}),daemon=True).start()
        return out

    @staticmethod
    def _safe_push(hook,player_id,title,message,kind,data):
        try:hook(player_id,title,message,{'kind':kind,**{k:str(v) for k,v in data.items()}})
        except Exception:pass

    def set_notification_prefs(self,player_id:str,prefs:dict)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];cur=a.setdefault('notification_prefs',{})
            for k in ('push','friend','invite','daily','event'):
                if k in prefs:cur[k]=bool(prefs[k])
            self._save();return dict(cur)

    def mark_notifications_read(self,player_id:str)->int:
        with self._lock:
            a=self._data['accounts'][player_id];count=0
            for n in a['notifications']:
                if not n.get('read'):n['read']=True;count+=1
            self._save();return count

    def debit(self,player_id:str,amount:int,reason:str='',*,notify:bool=True)->bool:
        amount=max(0,int(amount))
        with self._lock:
            a=self._data['accounts'][player_id]
            if a['chips']<amount:return False
            a['chips']-=amount;a['stats']['chips_spent']+=amount
            self._save();return True

    def credit(self,player_id:str,amount:int,reason:str='',*,notify:bool=True):
        amount=max(0,int(amount))
        with self._lock:
            a=self._data['accounts'][player_id]
            a['chips']+=amount;a['stats']['chips_won']+=amount
            self._save()

    def transfer_coins(self,from_id:str,to_id:str,amount:int)->dict:
        """Server-authoritative friend-to-friend chip transfer.

        Chips are social currency only; diamonds are deliberately non-transferable.
        The relationship, sender balance and daily anti-abuse ceiling are checked
        under one lock so two simultaneous taps cannot duplicate money.
        """
        amount=int(amount or 0)
        if from_id==to_id:return {'ok':False,'code':'cannot_transfer_self'}
        if amount<1_000:return {'ok':False,'code':'transfer_minimum','minimum':1_000}
        if amount>2_000_000:return {'ok':False,'code':'transfer_too_large','maximum':2_000_000}
        with self._lock:
            sender=self._data.get('accounts',{}).get(from_id)
            receiver=self._data.get('accounts',{}).get(to_id)
            if not sender or not receiver:return {'ok':False,'code':'user_not_found'}
            self._normalize(sender);self._normalize(receiver)
            if to_id not in sender.get('friends',[]) or from_id not in receiver.get('friends',[]):
                return {'ok':False,'code':'friends_only'}
            today=_day_key()
            st=sender.setdefault('coin_transfers',{'day':today,'sent_today':0,'received_today':0,'history':[]})
            rt=receiver.setdefault('coin_transfers',{'day':today,'sent_today':0,'received_today':0,'history':[]})
            if st.get('day')!=today:st.update({'day':today,'sent_today':0,'received_today':0})
            if rt.get('day')!=today:rt.update({'day':today,'sent_today':0,'received_today':0})
            daily_limit=5_000_000
            already=int(st.get('sent_today',0) or 0)
            if already+amount>daily_limit:
                return {'ok':False,'code':'transfer_daily_limit','daily_limit':daily_limit,'remaining_today':max(0,daily_limit-already)}
            if int(sender.get('chips',0) or 0)<amount:return {'ok':False,'code':'insufficient_balance'}
            sender['chips']=int(sender.get('chips',0))-amount
            receiver['chips']=int(receiver.get('chips',0))+amount
            sender.setdefault('stats',{})['chips_spent']=int(sender.get('stats',{}).get('chips_spent',0))+amount
            receiver.setdefault('stats',{})['chips_won']=int(receiver.get('stats',{}).get('chips_won',0))+amount
            st['sent_today']=already+amount
            rt['received_today']=int(rt.get('received_today',0) or 0)+amount
            transfer_id=uuid.uuid4().hex[:12]
            created=_now()
            sent_row={'id':transfer_id,'direction':'sent','other_id':to_id,'other_name':receiver.get('name','Oyuncu'),'amount':amount,'created_at':created}
            recv_row={'id':transfer_id,'direction':'received','other_id':from_id,'other_name':sender.get('name','Oyuncu'),'amount':amount,'created_at':created}
            st.setdefault('history',[]).insert(0,sent_row);st['history']=st['history'][:40]
            rt.setdefault('history',[]).insert(0,recv_row);rt['history']=rt['history'][:40]
            receiver.setdefault('notifications',[]).insert(0,{
                'id':uuid.uuid4().hex[:12],
                'title':'Altın geldi 🪙',
                'message':f'{sender.get("name","Arkadaşın")} sana {amount:,} altın gönderdi.'.replace(',', '.'),
                'kind':'social_transfer',
                'data':{'from_id':from_id,'amount':amount,'transfer_id':transfer_id},
                'read':False,'created_at':created,
            })
            receiver['notifications']=receiver['notifications'][:80]
            self._save()
            return {
                'ok':True,'transfer_id':transfer_id,'amount':amount,
                'sender_chips':sender['chips'],'receiver_chips':receiver['chips'],
                'sent_today':st['sent_today'],'daily_limit':daily_limit,
                'remaining_today':max(0,daily_limit-int(st['sent_today'])),
            }

    def add_xp(self,player_id:str,amount:int,reason:str='')->dict:
        amount=max(0,int(amount))
        with self._lock:
            a=self._data['accounts'][player_id]
            old=a['level'];a['xp']+=amount;a['stats']['total_xp_earned']+=amount;a['level']=_level_for_xp(a['xp'])
            leveled=a['level']>old
            if leveled:self.add_notification(player_id,'Seviye atladın!',f'Seviye {a["level"]} oldun.','level')
            self._save()
            return {'xp':a['xp'],'level':a['level'],'leveled_up':leveled}

    def claim_daily(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id]
            today=_day_key()
            if a['daily'].get('last_claim_day')==today:
                return {'ok':False,'code':'already_claimed','account':deepcopy(a)}
            # consecutive if claimed yesterday
            yesterday=_day_key(_now()-86400)
            if a['daily'].get('last_claim_day')==yesterday:
                streak=(int(a['daily'].get('streak',0))%7)+1
            else:
                streak=1
            reward=DAILY_REWARDS[streak-1]
            a['daily']={'last_claim_day':today,'streak':streak,'last_claim_at':_now()}
            a['chips']+=reward;a['stats']['chips_won']+=reward
            self._save()
            return {'ok':True,'reward':reward,'streak':streak,'account':deepcopy(a)}

    def _reset_missions_if_needed(self,a:dict):
        ms=a.setdefault('mission_state',{})
        day=_day_key();week=_week_key()
        if ms.get('day')!=day:
            ms['day']=day;ms['daily']={}
        if ms.get('week')!=week:
            ms['week']=week;ms['weekly']={}
        ms.setdefault('daily',{});ms.setdefault('weekly',{})

    def _mission_view(self,a:dict,defs:list[dict],bucket:str)->list[dict]:
        self._reset_missions_if_needed(a)
        state=a['mission_state'][bucket]
        out=[]
        for d in defs:
            st=state.setdefault(d['id'],{'progress':0,'claimed':False})
            out.append({**d,'progress':min(int(st['progress']),d['target']),'claimed':bool(st['claimed']),'complete':int(st['progress'])>=d['target']})
        return out

    def missions(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id]
            out={'daily':self._mission_view(a,DAILY_MISSIONS,'daily'),'weekly':self._mission_view(a,WEEKLY_MISSIONS,'weekly')}
            self._save();return deepcopy(out)

    def _advance_metric(self,a:dict,metric:str,amount:int):
        self._reset_missions_if_needed(a)
        for defs,bucket in ((DAILY_MISSIONS,'daily'),(WEEKLY_MISSIONS,'weekly')):
            for d in defs:
                if d['metric']!=metric:continue
                st=a['mission_state'][bucket].setdefault(d['id'],{'progress':0,'claimed':False})
                st['progress']=int(st.get('progress',0))+amount

    def advance(self,player_id:str,metric:str,amount:int=1):
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return
            self._advance_metric(a,metric,amount);self._save()

    def claim_mission(self,player_id:str,mission_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];self._reset_missions_if_needed(a)
            pair=None
            for defs,bucket in ((DAILY_MISSIONS,'daily'),(WEEKLY_MISSIONS,'weekly')):
                d=next((x for x in defs if x['id']==mission_id),None)
                if d:pair=(d,bucket);break
            if not pair:return {'ok':False,'code':'mission_not_found'}
            d,bucket=pair;st=a['mission_state'][bucket].setdefault(mission_id,{'progress':0,'claimed':False})
            if st.get('claimed'):return {'ok':False,'code':'already_claimed'}
            if int(st.get('progress',0))<d['target']:return {'ok':False,'code':'not_complete'}
            st['claimed']=True
            a['chips']+=d['reward_chips'];a['stats']['chips_won']+=d['reward_chips']
            a['xp']+=d['reward_xp'];a['stats']['total_xp_earned']+=d['reward_xp'];a['level']=_level_for_xp(a['xp'])
            self._save()
            return {'ok':True,'reward_chips':d['reward_chips'],'reward_xp':d['reward_xp'],'account':deepcopy(a)}

    def add_recent_players(self,player_id:str,others:list[dict]):
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return
            current=[x for x in a['recent_players'] if x.get('id') not in {o.get('id') for o in others}]
            stamp=_now()
            a['recent_players']=[{'id':o['id'],'name':o['name'],'played_at':stamp} for o in others if o.get('id') and o['id']!=player_id]+current
            a['recent_players']=a['recent_players'][:30]
            self._save()

    def request_friend(self,from_id:str,to_id:str)->dict:
        if from_id==to_id:return {'ok':False,'code':'cannot_friend_self'}
        with self._lock:
            a=self._data['accounts'].get(from_id);b=self._data['accounts'].get(to_id)
            if not a or not b:return {'ok':False,'code':'user_not_found'}
            if to_id in a.get('blocked',[]) or from_id in b.get('blocked',[]):return {'ok':False,'code':'relationship_blocked'}
            if to_id in a['friends']:return {'ok':False,'code':'already_friends'}
            if to_id in a.get('friend_requests',[]):return self.accept_friend(from_id,to_id)
            if from_id not in b['friend_requests']:b['friend_requests'].append(from_id)
            if to_id not in a['sent_friend_requests']:a['sent_friend_requests'].append(to_id)
            self.add_notification(to_id,'Arkadaşlık isteği',f'{a["name"]} seni arkadaş olarak eklemek istiyor.','friend_request',{'from_id':from_id})
            self._save();return {'ok':True}

    def accept_friend(self,player_id:str,from_id:str)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id);b=self._data['accounts'].get(from_id)
            if not a or not b:return {'ok':False,'code':'user_not_found'}
            if from_id not in a['friend_requests']:return {'ok':False,'code':'request_not_found'}
            a['friend_requests']=[x for x in a['friend_requests'] if x!=from_id]
            b['sent_friend_requests']=[x for x in b['sent_friend_requests'] if x!=player_id]
            if from_id not in a['friends']:a['friends'].append(from_id)
            if player_id not in b['friends']:b['friends'].append(player_id)
            self.add_notification(from_id,'Arkadaşlık kabul edildi',f'{a["name"]} artık arkadaşın.','friend')
            self._save();return {'ok':True}

    def decline_friend(self,player_id:str,from_id:str)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id);b=self._data['accounts'].get(from_id)
            if not a or not b:return {'ok':False,'code':'user_not_found'}
            a['friend_requests']=[x for x in a.get('friend_requests',[]) if x!=from_id];b['sent_friend_requests']=[x for x in b.get('sent_friend_requests',[]) if x!=player_id];self._save();return {'ok':True}
    def cancel_friend_request(self,player_id:str,to_id:str)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id);b=self._data['accounts'].get(to_id)
            if not a or not b:return {'ok':False,'code':'user_not_found'}
            a['sent_friend_requests']=[x for x in a.get('sent_friend_requests',[]) if x!=to_id];b['friend_requests']=[x for x in b.get('friend_requests',[]) if x!=player_id];self._save();return {'ok':True}
    def remove_friend(self,player_id:str,target_id:str)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id);b=self._data['accounts'].get(target_id)
            if not a or not b:return {'ok':False,'code':'user_not_found'}
            a['friends']=[x for x in a.get('friends',[]) if x!=target_id];b['friends']=[x for x in b.get('friends',[]) if x!=player_id];self._save();return {'ok':True}

    def friends_view(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id]
            friends=[self.public(fid) for fid in a['friends']]
            req=[self.public(fid) for fid in a['friend_requests']]
            return {'friends':[x for x in friends if x],'requests':[x for x in req if x],'sent_requests':list(a.get('sent_friend_requests',[])),'recent_players':deepcopy(a['recent_players'])}

    def send_gift(self,from_id:str,to_id:str,gift_type:str)->dict:
        if gift_type not in GIFT_CATALOG:return {'ok':False,'code':'gift_not_found'}
        if from_id==to_id:return {'ok':False,'code':'cannot_gift_self'}
        with self._lock:
            a=self._data['accounts'].get(from_id);b=self._data['accounts'].get(to_id)
            if not a or not b:return {'ok':False,'code':'user_not_found'}
            gift=GIFT_CATALOG[gift_type]
            item={'id':uuid.uuid4().hex[:10],'from_id':from_id,'from_name':a['name'],'gift_type':gift_type,'name':gift['name'],'emoji':gift.get('emoji','🎁'),'cost':0,'persistent':bool(gift.get('persistent',False)),'created_at':_now()}
            b.setdefault('gifts_received',[]).insert(0,item);b['gifts_received']=b['gifts_received'][:80]
            self._save();return {'ok':True,'gift':item,'cost':0,'wallet':{'coins':int(a.get('chips',0) or 0)}}

    def record_round(self,player_id:str,*,opening_mode:str|None=None,winner:bool=False,okey_finish:bool=False,pair_finish:bool=False):
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return
            a['stats']['rounds']+=1
            self._advance_metric(a,'rounds',1)
            if opening_mode=='series':a['stats']['series_opens']+=1
            elif opening_mode=='pairs':a['stats']['pair_opens']+=1
            if winner and okey_finish:a['stats']['okey_finishes']+=1
            if winner and pair_finish:a['stats']['pair_finishes']+=1
            self._save()

    def settle_match(self,participants:list[dict],winner_id:str|None,pot:int,rounds:int,finish_meta:dict|None=None,xp_multiplier:float=1.0):
        """participants: [{'id','name'}]. Bot ids can be omitted by caller."""
        with self._lock:
            human_ids=[p['id'] for p in participants if p.get('id') in self._data['accounts']]
            for pid in human_ids:
                a=self._data['accounts'][pid]
                a['stats']['games']+=1
                self._advance_metric(a,'games',1)
                won=pid==winner_id or pid in set((finish_meta or {}).get('winner_ids',[]))
                if won:
                    a['stats']['wins']+=1;a['stats']['current_streak']+=1;a['stats']['best_streak']=max(a['stats']['best_streak'],a['stats']['current_streak'])
                    self._advance_metric(a,'wins',1)
                    a['salon_chips']=int(a.get('salon_chips',20000))+10000
                else:
                    a['stats']['losses']+=1;a['stats']['current_streak']=0
                    a['salon_chips']=int(a.get('salon_chips',20000))+2000
                try:
                    from .tournament import record_result
                    record_result(self,_week_key(),pid,a.get('name','Oyuncu'),won)
                except Exception:
                    pass
                xp_base=350 if won else 120
                xp=max(1,int(round(xp_base*max(1.0,min(5.0,float(xp_multiplier or 1.0))))))
                a['xp']+=xp;a['stats']['total_xp_earned']+=xp;a['level']=_level_for_xp(a['xp'])
                league=a.setdefault('league',{'week':_week_key(),'points':0,'city':'Denizli','tier':'Bronz'})
                if league.get('week')!=_week_key():league.update({'week':_week_key(),'points':0,'tier':'Bronz'})
                league['points']=int(league.get('points',0))+(30 if won else 8);league['tier']=_league_tier(league['points'])
                monthly=a.setdefault('monthly',{'month':_month_key(),'points':0})
                if monthly.get('month')!=_month_key():monthly.update({'month':_month_key(),'points':0})
                monthly['points']=int(monthly.get('points',0))+(30 if won else 8)
                mode_key=f"{(finish_meta or {}).get('game_type','okey101')}:{(finish_meta or {}).get('variant','non_fold')}"+(':turbo' if (finish_meta or {}).get('turbo') else '')
                ms=a.setdefault('stats_by_mode',{}).setdefault(mode_key,{'games':0,'wins':0,'best_streak':0,'streak':0})
                ms['games']+=1
                if won:ms['wins']+=1;ms['streak']+=1;ms['best_streak']=max(ms['best_streak'],ms['streak'])
                else:ms['streak']=0
                season=a.setdefault('season',{'id':SEASON_ID,'points':0,'claimed':[]})
                if season.get('id')!=SEASON_ID:season.update({'id':SEASON_ID,'points':0,'claimed':[]})
                season_delta=3 if won else 1
                season['points']=int(season.get('points',0))+season_delta
                club_id=a.get('club_id')
                if club_id and club_id in self._data.setdefault('clubs',{}):
                    club=self._data['clubs'][club_id]
                    club['season_points']=int(club.get('season_points',0))+season_delta
                if won:a.setdefault('chests',{'keys':1,'last_free_day':None,'opened':0})['keys']=min(9,int(a['chests'].get('keys',0))+1)
                hist={'id':uuid.uuid4().hex[:10],'created_at':_now(),'won':won,'rounds':rounds,'finish_meta':deepcopy(finish_meta or {}),'players':[{'id':p.get('id'),'name':p.get('name'),'seat':p.get('seat')} for p in participants]}
                a.setdefault('match_history',[]).insert(0,hist);a['match_history']=a['match_history'][:50]
                self._unlock_achievements(a)
            if winner_id in self._data['accounts'] and pot>0:
                w=self._data['accounts'][winner_id];w['chips']+=pot;w['stats']['chips_won']+=pot
                if pot>=50000:self.record_activity('match_win',winner_id,f'{w["name"]} masada {pot:,} altın kazandı'.replace(',', '.'),{'coins':pot})
            # Recent-player network.
            for pid in human_ids:
                self.add_recent_players(pid,[p for p in participants if p.get('id')!=pid and p.get('id') in self._data['accounts']])
            self._save()

    def _achievement_defs(self,a:dict):
        st=a.get('stats',{})
        return [
            ('first_game','İlk Masa','İlk oyununu tamamla',int(st.get('games',0)),1,1500),
            ('first_win','İlk Zafer','İlk oyununu kazan',int(st.get('wins',0)),1,2500),
            ('ten_games','Müdavim','10 oyun tamamla',int(st.get('games',0)),10,7500),
            ('five_wins','Kazanan','5 oyun kazan',int(st.get('wins',0)),5,9000),
            ('streak3','Seri 3','3 maçlık galibiyet serisi yap',int(st.get('best_streak',0)),3,12000),
            ('twenty_games','20 Masa','20 oyun tamamla',int(st.get('games',0)),20,15000),
            ('ten_wins','10 Zafer','10 oyun kazan',int(st.get('wins',0)),10,20000),
            ('okey_finish','Okeyle Bitir','Okey atarak bir el bitir',int(st.get('okey_finishes',0)),1,18000),
            ('pair_finish','Çift Ustası','Çiftten bitir',int(st.get('pair_finishes',0)),1,18000),
            ('series_10','Seri Ustası','10 kez seri aç',int(st.get('series_opens',0)),10,12500),
            ('pairs_10','Çiftçi','10 kez çift aç',int(st.get('pair_opens',0)),10,12500),
            ('fifty_games','Masa Veteranı','50 oyun tamamla',int(st.get('games',0)),50,50000),
        ]

    def _unlock_achievements(self,a:dict):
        existing={x['id'] for x in a.setdefault('achievements',[])}
        for aid,title,detail,progress,target,reward in self._achievement_defs(a):
            if progress>=target and aid not in existing:
                a['achievements'].append({'id':aid,'title':title,'detail':detail,'reward_chips':reward,'unlocked_at':_now()})
                existing.add(aid)
                self.add_notification(a['id'],'Başarım açıldı',f'{title} • {reward:,} altın ödülü hazır'.replace(',','.'),'achievement')

    def achievements_view(self,player_id:str)->list[dict]:
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return []
            self._unlock_achievements(a)
            unlocked={x.get('id'):x for x in a.setdefault('achievements',[])}
            claims=set(a.setdefault('achievement_claims',[]))
            out=[]
            for aid,title,detail,progress,target,reward in self._achievement_defs(a):
                out.append({'id':aid,'title':title,'detail':detail,'progress':min(progress,target),'target':target,'reward_chips':reward,'unlocked':aid in unlocked,'claimed':aid in claims,'claimable':aid in unlocked and aid not in claims})
            return out

    def claim_achievement(self,player_id:str,achievement_id:str)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return {'ok':False,'code':'account_not_found'}
            self._unlock_achievements(a)
            item=next((x for x in self.achievements_view(player_id) if x['id']==achievement_id),None)
            if not item:return {'ok':False,'code':'achievement_not_found'}
            if not item['unlocked']:return {'ok':False,'code':'achievement_locked'}
            claims=a.setdefault('achievement_claims',[])
            if achievement_id in claims:return {'ok':False,'code':'achievement_claimed'}
            reward=int(item['reward_chips']);a['chips']+=reward;a['stats']['chips_won']+=reward;claims.append(achievement_id)
            self._save();return {'ok':True,'reward':reward,'chips':a['chips'],'achievement':item}

    def reward_config(self)->dict:
        """Panelde ve oyunda kullanılan GERÇEK içerik: hiç düzenlenmediyse
        varsayılan çark/sandık ödülleri döner (boş liste gösterilmez)."""
        with self._lock:
            cfg=deepcopy(self._data.setdefault('reward_config',{}))
        w=cfg.setdefault('wheel',{});w.setdefault('daily_limit',1)
        if not w.get('segments'):w['segments']=[{'reward':x,'weight':1} for x in WHEEL_REWARDS]
        c=cfg.setdefault('chest',{});c.setdefault('daily_limit',5)
        if not c.get('rewards'):c['rewards']=[{'reward':x,'weight':1} for x in CHEST_REWARDS]
        return cfg

    _ECONOMY_DEFAULTS={'commission_percent':15,'canak_percent':10,'welcome_chips':1_000_000}
    def economy(self)->dict:
        cfg=self._data.setdefault('economy',{})
        return {k:cfg.get(k,v) for k,v in self._ECONOMY_DEFAULTS.items()}
    def update_economy(self,patch:dict)->dict:
        with self._lock:
            cfg=self._data.setdefault('economy',{})
            if 'commission_percent' in patch:cfg['commission_percent']=max(0,min(30,int(patch['commission_percent'])))
            if 'canak_percent' in patch:cfg['canak_percent']=max(0,min(50,int(patch['canak_percent'])))
            if 'welcome_chips' in patch:cfg['welcome_chips']=max(0,min(100_000_000,int(patch['welcome_chips'])))
            self._save();return self.economy()

    def update_reward_config(self,patch:dict)->dict:
        with self._lock:
            cfg=self._data.setdefault('reward_config',{})
            if 'wheel' in patch and isinstance(patch['wheel'],dict):
                w=cfg.setdefault('wheel',{}); w['daily_limit']=max(1,min(10,int(patch['wheel'].get('daily_limit',w.get('daily_limit',1)))))
                seg=patch['wheel'].get('segments')
                if isinstance(seg,list) and seg:
                    rows=[]
                    for x in seg[:12]:
                        if isinstance(x,dict):rows.append({'reward':max(0,min(2_000_000_000,int(x.get('reward',0)))),'weight':max(1,min(10000,int(x.get('weight',1))))})
                    if rows:w['segments']=rows
            if 'chest' in patch and isinstance(patch['chest'],dict):
                c=cfg.setdefault('chest',{}); c['daily_limit']=max(1,min(10,int(patch['chest'].get('daily_limit',c.get('daily_limit',5)))))
                rewards=patch['chest'].get('rewards')
                if isinstance(rewards,list) and rewards:
                    rows=[]
                    for x in rewards[:12]:
                        if isinstance(x,dict):rows.append({'reward':max(0,min(2_000_000_000,int(x.get('reward',0)))),'weight':max(1,min(10000,int(x.get('weight',1))))})
                    if rows:c['rewards']=rows
            self._save();return deepcopy(cfg)

    def spin_wheel(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];today=_day_key();w=a.setdefault('wheel',{'last_spin_day':None,'last_reward':0,'spins':0,'day':None,'spins_today':0})
            if w.get('day')!=today:w['day']=today;w['spins_today']=0
            cfg=self._data.setdefault('reward_config',{}).setdefault('wheel',{'daily_limit':1,'segments':[]});limit=max(1,int(cfg.get('daily_limit',1)))
            if int(w.get('spins_today',0))>=limit:return {'ok':False,'code':'daily_wheel_limit','wheel':deepcopy(w),'daily_limit':limit}
            seg=cfg.get('segments') or [{'reward':x,'weight':1} for x in WHEEL_REWARDS]
            reward=random.choices([int(x['reward']) for x in seg],weights=[max(1,int(x.get('weight',1))) for x in seg],k=1)[0]
            w.update({'last_spin_day':today,'last_reward':reward,'spins':int(w.get('spins',0))+1,'spins_today':int(w.get('spins_today',0))+1})
            a['chips']+=reward;a['stats']['chips_won']+=reward
            self._save();return {'ok':True,'reward':reward,'wheel':deepcopy(w),'chips':a['chips'],'segments':deepcopy(seg),'daily_limit':limit}

    def open_chest(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];today=_day_key();c=a.setdefault('chests',{'keys':1,'last_free_day':None,'opened':0,'day':None,'opened_today':0})
            if c.get('day')!=today:c['day']=today;c['opened_today']=0
            cfg=self._data.setdefault('reward_config',{}).setdefault('chest',{'daily_limit':5,'rewards':[]});limit=max(1,int(cfg.get('daily_limit',5)))
            if int(c.get('opened_today',0))>=limit:return {'ok':False,'code':'daily_chest_limit','chests':deepcopy(c),'daily_limit':limit}
            free=c.get('last_free_day')!=today
            if not free and int(c.get('keys',0))<=0:return {'ok':False,'code':'no_chest_key','chests':deepcopy(c),'daily_limit':limit}
            if free:c['last_free_day']=today
            else:c['keys']=int(c.get('keys',0))-1
            rows=cfg.get('rewards') or [{'reward':x,'weight':1} for x in CHEST_REWARDS]
            reward=random.choices([int(x['reward']) for x in rows],weights=[max(1,int(x.get('weight',1))) for x in rows],k=1)[0]
            c['opened']=int(c.get('opened',0))+1;c['opened_today']=int(c.get('opened_today',0))+1
            a['chips']+=reward;a['stats']['chips_won']+=reward
            self._save();return {'ok':True,'reward':reward,'free':free,'chests':deepcopy(c),'chips':a['chips'],'daily_limit':limit}

    def search_players(self,query:str,viewer_id:str|None=None,limit:int=20)->list[dict]:
        q=(query or '').strip().lower()
        if not q:return []
        with self._lock:
            rows=[]
            for pid,a in self._data['accounts'].items():
                if viewer_id and pid==viewer_id:continue
                public_id=str(a.get('public_id') or _public_id(pid)).lower()
                if q not in pid.lower() and q not in public_id and q not in str(a.get('name','')).lower():continue
                rows.append(self.public(pid))
                if len(rows)>=limit:break
            return [x for x in rows if x]

    def set_social_safety(self,player_id:str,target_id:str,kind:str,enabled:bool=True)->dict:
        if player_id==target_id:return {'ok':False,'code':'cannot_target_self'}
        if target_id not in self._data['accounts']:return {'ok':False,'code':'user_not_found'}
        with self._lock:
            a=self._data['accounts'][player_id]
            key='blocked' if kind=='block' else 'muted'
            arr=a.setdefault(key,[])
            if enabled and target_id not in arr:arr.append(target_id)
            if not enabled:a[key]=[x for x in arr if x!=target_id]
            self._save();return {'ok':True,key:deepcopy(a[key])}

    def report_player(self,player_id:str,target_id:str,reason:str,room_id:str|None=None)->dict:
        if player_id==target_id:return {'ok':False,'code':'cannot_report_self'}
        with self._lock:
            if target_id not in self._data['accounts']:return {'ok':False,'code':'user_not_found'}
            item={'id':uuid.uuid4().hex[:12],'from_id':player_id,'target_id':target_id,'reason':(reason or 'other')[:80],'room_id':room_id,'created_at':_now()}
            self._data.setdefault('reports',[]).append(item);self._data['reports']=self._data['reports'][-500:]
            self._data['accounts'][player_id]['reports_made']=int(self._data['accounts'][player_id].get('reports_made',0))+1
            self._save();return {'ok':True,'report_id':item['id']}

    def register_push(self,player_id:str,token:str,device_id:str|None=None)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];token=(token or '').strip()
            if token and token not in a.setdefault('push_tokens',[]):a['push_tokens'].append(token)
            if device_id and device_id not in a.setdefault('device_ids',[]):a['device_ids'].append(device_id)
            a['push_tokens']=a['push_tokens'][-5:];a['device_ids']=a['device_ids'][-5:]
            self._save();return {'ok':True}

    REPEAT_DEVICE_START_CHIPS=50_000
    def apply_welcome_policy(self,player_id:str,device_id:str|None)->dict|None:
        """Hoş geldin altını cihaz başına bir kez: aynı telefonda silip yeniden
        kurarak ya da yeni misafir hesap açarak tekrar tekrar 1.000.000 alınamaz.
        Yalnızca hiç oynamamış, yeni açılmış hesaba uygulanır."""
        device_id=(device_id or '').strip()[:128]
        if not device_id:return None
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a or a.get('welcome_policy_done'):return None
            a['welcome_policy_done']=True
            granted=self._data.setdefault('welcome_devices',{})
            fresh=int((a.get('stats') or {}).get('games',0) or 0)==0 and _now()-int(a.get('created_at',0) or 0)<600
            owner=granted.get(device_id)
            if owner and owner!=player_id and fresh:
                welcome=int(self.economy()['welcome_chips'])
                if int(a.get('chips',0) or 0)>=welcome:
                    a['chips']=min(int(a['chips']),self.REPEAT_DEVICE_START_CHIPS)
                    a.setdefault('security',{}).setdefault('risk_flags',[])
                    self.add_notification(player_id,'Hoş geldin!','Bu cihazda hoş geldin hediyesi daha önce alındı; hesabın başlangıç altınıyla açıldı.','system')
            elif not owner:
                granted[device_id]=player_id
            self._save()
            return deepcopy(a)

    def track_device(self,player_id:str,device_id:str)->dict:
        device_id=(device_id or '').strip()[:128]
        if not device_id:return {'ok':False,'code':'device_id_required'}
        with self._lock:
            a=self._data['accounts'][player_id]
            ids=a.setdefault('device_ids',[])
            if device_id not in ids:ids.append(device_id)
            a['device_ids']=ids[-5:]
            registry=self._data.setdefault('device_accounts',{})
            linked=registry.setdefault(device_id,[])
            if player_id not in linked:linked.append(player_id)
            registry[device_id]=linked[-12:]
            security=a.setdefault('security',{'risk_flags':[],'device_account_count':1})
            security['device_account_count']=len(registry[device_id])
            flags=set(security.get('risk_flags',[]))
            if len(registry[device_id])>=4:flags.add('multi_account_device')
            security['risk_flags']=sorted(flags)
            self._save();return {'ok':True,'device_account_count':len(registry[device_id]),'risk_flags':security['risk_flags']}

    def referral_info(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];r=a.setdefault('referral',{'code':_referral_code(player_id),'redeemed_code':None,'referrals':[]})
            return {'code':r['code'],'redeemed_code':r.get('redeemed_code'),'referrals':len(r.get('referrals',[])),'reward_each':5000}

    def redeem_referral(self,player_id:str,code:str,device_id:str|None=None)->dict:
        code=(code or '').strip().upper()
        with self._lock:
            a=self._data['accounts'][player_id];r=a.setdefault('referral',{'code':_referral_code(player_id),'redeemed_code':None,'referrals':[]})
            if r.get('redeemed_code'):return {'ok':False,'code':'referral_already_redeemed'}
            owner=None
            for pid,b in self._data['accounts'].items():
                br=b.setdefault('referral',{'code':_referral_code(pid),'redeemed_code':None,'referrals':[]})
                if br.get('code')==code:owner=pid;break
            if not owner:return {'ok':False,'code':'referral_not_found'}
            if owner==player_id:return {'ok':False,'code':'cannot_refer_self'}
            if device_id:
                used=self._data.setdefault('referral_devices',{})
                prior=used.get(device_id)
                if prior and prior!=player_id:return {'ok':False,'code':'device_referral_limit'}
                used[device_id]=player_id
            r['redeemed_code']=code
            owner_r=self._data['accounts'][owner].setdefault('referral',{'code':_referral_code(owner),'redeemed_code':None,'referrals':[]})
            if player_id not in owner_r['referrals']:owner_r['referrals'].append(player_id)
            for pid in (player_id,owner):
                self._data['accounts'][pid]['chips']+=5000;self._data['accounts'][pid]['stats']['chips_won']+=5000
                self.add_notification(pid,'Davet ödülü','5.000 chip davet ödülü hesabına eklendi.','referral')
            self._save();return {'ok':True,'reward':5000}

    def set_city(self,player_id:str,city:str)->dict:
        city=' '.join((city or 'Denizli').strip().split())[:40] or 'Denizli'
        with self._lock:
            a=self._data['accounts'][player_id];league=a.setdefault('league',{'week':_week_key(),'points':0,'city':city,'tier':'Bronz'})
            league['city']=city;self._save();return deepcopy(league)

    def leaderboard(self,viewer_id:str,scope:str='global',limit:int=50)->dict:
        with self._lock:
            viewer=self._data['accounts'][viewer_id];self._normalize(viewer)
            friend_ids=set(viewer.get('friends',[]));city=viewer.get('league',{}).get('city','Denizli')
            rows=[]
            for pid,a in self._data['accounts'].items():
                self._normalize(a)
                if scope=='friends' and pid!=viewer_id and pid not in friend_ids:continue
                if scope=='city' and a.get('league',{}).get('city')!=city:continue
                pts=int(a['league'].get('points',0))
                if scope=='monthly':
                    mo=a.get('monthly') or {}
                    pts=int(mo.get('points',0)) if mo.get('month')==_month_key() else 0
                    if pts<=0 and pid!=viewer_id:continue
                rows.append({'id':pid,'name':a['name'],'avatar_url':a.get('avatar_url'),'level':a['level'],'points':pts,'tier':a['league'].get('tier','Bronz'),'city':a['league'].get('city','Denizli')})
            rows.sort(key=lambda x:(-x['points'],-x['level'],x['name'].lower()))
            for i,row in enumerate(rows,1):row['rank']=i
            return {'scope':scope,'week':_week_key(),'month':_month_key(),'rows':deepcopy(rows[:limit]),'viewer':next((x for x in rows if x['id']==viewer_id),None)}

    def canak_state(self)->dict:
        with self._lock:return deepcopy(self._data.setdefault('canak',{'balance':0,'history':[]}))

    def add_canak(self,amount:int,room_id:str='')->int:
        amount=max(0,int(amount))
        with self._lock:
            c=self._data.setdefault('canak',{'balance':0,'history':[]});c['balance']=int(c.get('balance',0))+amount
            if amount:c['history'].append({'type':'add','amount':amount,'room_id':room_id,'created_at':_now()});c['history']=c['history'][-100:]
            self._save();return c['balance']

    def pop_canak(self,winner_ids:list[str],room_id:str='')->dict:
        with self._lock:
            c=self._data.setdefault('canak',{'balance':0,'history':[]});amount=int(c.get('balance',0))
            valid=[pid for pid in winner_ids if pid in self._data['accounts']]
            if amount<=0 or not valid:return {'ok':False,'amount':0}
            each=amount//len(valid);remainder=amount-(each*len(valid))
            for i,pid in enumerate(valid):
                reward=each+(remainder if i==0 else 0);self._data['accounts'][pid]['chips']+=reward;self._data['accounts'][pid]['stats']['chips_won']+=reward
                self.add_notification(pid,'Çanak patladı!',f'{reward:,} chip çanak ödülü kazandın.','canak',{'room_id':room_id})
            c['balance']=0;c['history'].append({'type':'explode','amount':amount,'room_id':room_id,'winners':valid,'created_at':_now()});c['history']=c['history'][-100:]
            self._save();return {'ok':True,'amount':amount,'each':each,'winners':valid}

    def club_create(self,player_id:str,name:str)->dict:
        name=' '.join((name or '').strip().split())[:28]
        if len(name)<3:return {'ok':False,'code':'club_name_too_short'}
        with self._lock:
            a=self._data['accounts'][player_id]
            if a.get('club_id'):return {'ok':False,'code':'already_in_club'}
            if any(c.get('name','').lower()==name.lower() for c in self._data.setdefault('clubs',{}).values()):return {'ok':False,'code':'club_name_taken'}
            cid=uuid.uuid4().hex[:10];club={'id':cid,'name':name,'owner_id':player_id,'members':[player_id],'chat':[],'created_at':_now(),'season_points':0}
            self._data['clubs'][cid]=club;a['club_id']=cid;self._save();return {'ok':True,'club':deepcopy(club)}

    def club_join(self,player_id:str,club_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id]
            if a.get('club_id'):return {'ok':False,'code':'already_in_club'}
            club=self._data.setdefault('clubs',{}).get(club_id)
            if not club:return {'ok':False,'code':'club_not_found'}
            if len(club['members'])>=50:return {'ok':False,'code':'club_full'}
            club['members'].append(player_id);a['club_id']=club_id;self._save();return {'ok':True,'club':deepcopy(club)}

    def club_leave(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];cid=a.get('club_id')
            if not cid:return {'ok':False,'code':'not_in_club'}
            club=self._data.setdefault('clubs',{}).get(cid)
            if club:
                club['members']=[x for x in club['members'] if x!=player_id]
                if club.get('owner_id')==player_id:
                    if club['members']:club['owner_id']=club['members'][0]
                    else:self._data['clubs'].pop(cid,None)
            a['club_id']=None;self._save();return {'ok':True}

    def club_view(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];cid=a.get('club_id');clubs=self._data.setdefault('clubs',{})
            mine=deepcopy(clubs.get(cid)) if cid else None
            if mine:
                mine['member_profiles']=[self.public(pid) for pid in mine.get('members',[]) if self.public(pid)]
                games=sum(self._data['accounts'][pid]['stats']['games'] for pid in mine.get('members',[]) if pid in self._data['accounts'])
                wins=sum(self._data['accounts'][pid]['stats']['wins'] for pid in mine.get('members',[]) if pid in self._data['accounts'])
                mine['tasks']=[{'id':'club_games_20','title':'Kulüpçe 20 oyun oyna','progress':min(games,20),'target':20,'complete':games>=20},{'id':'club_wins_8','title':'Kulüpçe 8 galibiyet al','progress':min(wins,8),'target':8,'complete':wins>=8}]
                claimed_weeks=a.setdefault('club_rewards',{}).setdefault('claimed_weeks',[])
                mine['weekly_event']={'id':f'{_week_key()}-club-rally','title':'Kulüp Rallisi','week':_week_key(),'reward_chips':15000,'complete':games>=20 and wins>=8,'claimed':_week_key() in claimed_weeks}
            listing=[{'id':c['id'],'name':c['name'],'members':len(c.get('members',[])),'season_points':int(c.get('season_points',0))} for c in clubs.values()]
            listing.sort(key=lambda x:(-x['season_points'],-x['members'],x['name'].lower()))
            for rank,row in enumerate(listing,1):row['rank']=rank
            mine_rank=next((row['rank'] for row in listing if row['id']==cid),None) if cid else None
            tournament={
                'id':f'{SEASON_ID}-CLUBS',
                'title':'Sezon Kulüpler Kupası',
                'season_id':SEASON_ID,
                'rows':deepcopy(listing[:20]),
                'my_rank':mine_rank,
            }
            return {'club':mine,'clubs':deepcopy(listing[:50]),'tournament':tournament}


    def club_claim_weekly(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'].get(player_id)
            if not a:return {'ok':False,'code':'account_not_found'}
            cid=a.get('club_id');club=self._data.setdefault('clubs',{}).get(cid) if cid else None
            if not club:return {'ok':False,'code':'not_in_club'}
            games=sum(self._data['accounts'][pid]['stats']['games'] for pid in club.get('members',[]) if pid in self._data['accounts'])
            wins=sum(self._data['accounts'][pid]['stats']['wins'] for pid in club.get('members',[]) if pid in self._data['accounts'])
            if games<20 or wins<8:return {'ok':False,'code':'club_event_not_complete'}
            week=_week_key();state=a.setdefault('club_rewards',{});claimed=state.setdefault('claimed_weeks',[])
            if week in claimed:return {'ok':False,'code':'club_event_already_claimed'}
            reward=15000;claimed.append(week);state['claimed_weeks']=claimed[-12:];a['chips']=int(a.get('chips',0))+reward;a['stats']['chips_won']=int(a['stats'].get('chips_won',0))+reward
            self.add_notification(player_id,'Kulüp Rallisi tamamlandı!',f'{reward:,} altın kulüp ödülünü aldın.'.replace(',','.'),'club_reward',{'club_id':cid,'week':week})
            self._save();return {'ok':True,'reward':reward,'chips':a['chips'],'week':week}

    def club_chat(self,player_id:str,text:str)->dict:
        text=_sanitize_social_text(text,160)
        if not text:return {'ok':False,'code':'message_rejected'}
        with self._lock:
            a=self._data['accounts'][player_id];cid=a.get('club_id');club=self._data.setdefault('clubs',{}).get(cid) if cid else None
            if not club:return {'ok':False,'code':'not_in_club'}
            item={'id':uuid.uuid4().hex[:10],'player_id':player_id,'name':a['name'],'text':text,'created_at':_now()};club['chat'].append(item);club['chat']=club['chat'][-80:]
            self._save();return {'ok':True,'message':deepcopy(item)}

    def season_state(self,player_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];self._normalize(a);season=a['season']
            return {'id':SEASON_ID,'points':int(season.get('points',0)),'claimed':list(season.get('claimed',[])),'milestones':deepcopy(SEASON_MILESTONES)}

    def claim_season(self,player_id:str,milestone_id:str)->dict:
        with self._lock:
            a=self._data['accounts'][player_id];self._normalize(a);s=a['season'];m=next((x for x in SEASON_MILESTONES if x['id']==milestone_id),None)
            if not m:return {'ok':False,'code':'milestone_not_found'}
            if milestone_id in s['claimed']:return {'ok':False,'code':'already_claimed'}
            if int(s.get('points',0))<m['points']:return {'ok':False,'code':'not_complete'}
            s['claimed'].append(milestone_id);a['chips']+=m['chips'];a['stats']['chips_won']+=m['chips'];self.add_notification(player_id,'Sezon ödülü',f'{m["chips"]:,} chip sezon ödülü alındı.','season')
            self._save();return {'ok':True,'reward':m['chips']}

STORE=AccountStore()
