from __future__ import annotations
import secrets
from fastapi import APIRouter, HTTPException, Header, Depends
from pydantic import BaseModel
from app.services.account_store import STORE,GIFT_CATALOG,_day_key,seen_recently
from app.core.config import settings
import httpx
import asyncio
import time

router=APIRouter(tags=['account'])

class BootstrapIn(BaseModel):
    player_id:str
    name:str='Oyuncu'
    session_token:str|None=None

class GoogleBootstrapIn(BaseModel):
    name:str='Oyuncu'
    avatar_url:str|None=None
    device_id:str|None=None
    is_guest:bool=False

class LocalBootstrapIn(BaseModel):
    player_id:str
    name:str='Oyuncu'
    avatar_url:str|None=None
    device_id:str|None=None
    is_guest:bool=False
    coins:int|None=None
    diamonds:int|None=None

class ProfileUpdateIn(BaseModel):
    name:str|None=None
    avatar_url:str|None=None

class FriendIn(BaseModel):
    from_id:str
    to_id:str

class AcceptFriendIn(BaseModel):
    player_id:str
    from_id:str

class GiftIn(BaseModel):
    from_id:str
    to_id:str
    gift_type:str

class CoinTransferIn(BaseModel):
    from_id:str
    to_id:str
    amount:int

class InviteIn(BaseModel):
    from_id:str
    to_id:str
    room_id:str

class TargetIn(BaseModel):
    player_id:str
    target_id:str
    enabled:bool=True

class ReportIn(BaseModel):
    player_id:str
    target_id:str
    reason:str='other'
    room_id:str|None=None

class PushIn(BaseModel):
    player_id:str
    token:str
    device_id:str|None=None

class ReferralIn(BaseModel):
    player_id:str
    code:str
    device_id:str|None=None

class CityIn(BaseModel):
    player_id:str
    city:str

class ClubCreateIn(BaseModel):
    player_id:str
    name:str

class ClubJoinIn(BaseModel):
    player_id:str
    club_id:str

class ClubChatIn(BaseModel):
    player_id:str
    text:str

async def _google_user(authorization:str|None=Header(None)):
    # Lazy import keeps local guest-only development usable before optional auth deps are installed.
    from app.core.auth import current_user
    return await current_user(authorization)

async def _sync_staff_role(player_id:str, authorization:str|None):
    """Mirror the signed-in user's own Supabase staff role into the local runtime.

    The RPC can only return auth.uid()'s row, so a shared test server never
    auto-promotes whichever friend connects first.
    """
    if not authorization or not settings.supabase_url or not settings.supabase_anon_key:
        return
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            r=await client.post(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/rpc/okeyx_my_staff_role",
                headers={
                    'apikey':settings.supabase_anon_key,
                    'Authorization':authorization,
                    'Content-Type':'application/json',
                },
                json={},
            )
        if r.status_code<200 or r.status_code>=300:return
        body=r.json()
        row=body[0] if isinstance(body,list) and body else (body if isinstance(body,dict) and body.get('role') else None)
        if not row:return
        role=str(row.get('role') or '').strip()
        if role not in {'owner','admin','moderator','event_manager','support'}:return
        with STORE._lock:
            phase4=STORE._data.setdefault('phase4',{})
            phase4.setdefault('staff_roles',{})[player_id]=role
            STORE._save()
    except Exception:
        return

async def _sync_public_id(player_id:str, public_id:str|None, authorization:str|None):
    """Persist the short OX id in Supabase so friends can search it globally."""
    value=str(public_id or '').strip().upper()
    if not authorization or not value or not settings.supabase_url or not settings.supabase_anon_key:
        return
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            await client.post(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/rpc/okeyx_set_my_public_id",
                headers={
                    'apikey':settings.supabase_anon_key,
                    'Authorization':authorization,
                    'Content-Type':'application/json',
                },
                json={'p_public_id':value},
            )
    except Exception:
        return


async def _supabase_social_rpc(function_name:str, payload:dict, authorization:str|None):
    if not authorization or not settings.supabase_url or not settings.supabase_anon_key:
        return None
    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            r=await client.post(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/rpc/{function_name}",
                headers={
                    'apikey':settings.supabase_anon_key,
                    'Authorization':authorization,
                    'Content-Type':'application/json',
                },
                json=payload,
            )
        if r.status_code<200 or r.status_code>=300:
            return {'ok':False,'code':f'social_rpc_{r.status_code}'}
        body=r.json() if r.content else {}
        if isinstance(body,list) and len(body)==1 and isinstance(body[0],dict) and 'ok' in body[0]:
            return body[0]
        return body
    except Exception:
        return {'ok':False,'code':'social_service_unavailable'}


def _force_local_relationship(me:str,target:str,relationship:str):
    """Mirror Supabase friendship state into the restartable game cache."""
    with STORE._lock:
        a=STORE._data.get('accounts',{}).get(me); b=STORE._data.get('accounts',{}).get(target)
        if not a or not b:return
        for x in (a,b):
            x.setdefault('friends',[]); x.setdefault('friend_requests',[]); x.setdefault('sent_friend_requests',[])
        a['friends']=[x for x in a['friends'] if x!=target]; b['friends']=[x for x in b['friends'] if x!=me]
        a['friend_requests']=[x for x in a['friend_requests'] if x!=target]; b['friend_requests']=[x for x in b['friend_requests'] if x!=me]
        a['sent_friend_requests']=[x for x in a['sent_friend_requests'] if x!=target]; b['sent_friend_requests']=[x for x in b['sent_friend_requests'] if x!=me]
        if relationship=='friend':
            a['friends'].append(target); b['friends'].append(me)
        elif relationship=='sent':
            a['sent_friend_requests'].append(target); b['friend_requests'].append(me)
        elif relationship=='incoming':
            a['friend_requests'].append(target); b['sent_friend_requests'].append(me)
        STORE._save()

async def _sync_social_from_supabase(player_id:str, authorization:str|None):
    body=await _supabase_social_rpc('okeyx_social_connections',{},authorization)
    if not isinstance(body,list):return
    # Clear local relationship edges for this player, then restore canonical rows.
    with STORE._lock:
        a=STORE._data.get('accounts',{}).get(player_id)
        if a:
            a['friends']=[];a['friend_requests']=[];a['sent_friend_requests']=[]
    for row in body:
        if not isinstance(row,dict):continue
        target=str(row.get('user_id') or '')
        if not target or target==player_id:continue
        STORE.ensure(target,str(row.get('display_name') or 'Oyuncu'),None,row.get('avatar_url'),is_guest=False)
        rel=str(row.get('relationship') or 'none')
        _force_local_relationship(player_id,target,rel)

def _require(player_id:str,token:str|None):
    if not STORE.ready:raise HTTPException(503,'storage_unavailable')
    if not STORE.get(player_id):raise HTTPException(404,'account_not_found')
    if not STORE.verify(player_id,token):raise HTTPException(401,'invalid_account_token')

def _sanctions(player_id:str)->dict:
    try:
        from app.services.phase4_service import Phase4Service
        return Phase4Service(STORE).active_sanctions(player_id)
    except Exception:
        return {}

def _require_social(player_id:str,token:str|None,lock:str|None=None):
    # Supabase anonymous sessions are real auth identities too. Guests can use
    # friends/invites immediately; linking Google/e-mail only protects recovery.
    _require(player_id,token)
    # Yönetici cezaları: ban her sosyal işlemi, kilitler ilgili işlemi kapatır.
    san=_sanctions(player_id)
    if san.get('banned'):raise HTTPException(403,'account_banned')
    if lock and san.get(lock):raise HTTPException(403,lock)

@router.post('/account/bootstrap')
def bootstrap(body:BootstrapIn):
    if not STORE.ready:raise HTTPException(503,'storage_unavailable')
    a=STORE.bootstrap_guest(body.player_id,body.name,body.session_token)
    if not a:raise HTTPException(401,'invalid_account_token')
    return a

@router.post('/account/bootstrap-google')
async def bootstrap_google(body:GoogleBootstrapIn,user=Depends(_google_user)):
    if not STORE.ready:raise HTTPException(503,'storage_unavailable')
    # Supabase JWT is the identity authority; game/account session token remains our app session secret.
    account=STORE.ensure(user['id'],body.name,user.get('email'),body.avatar_url,is_guest=False)
    if body.device_id:
        STORE.track_device(user['id'],body.device_id)
        account=STORE.apply_welcome_policy(user['id'],body.device_id) or account
    return account

@router.post('/account/bootstrap-local')
def bootstrap_local(body:LocalBootstrapIn,x_local_test_secret:str|None=Header(None)):
    """USB/ADB local gameplay bootstrap. Never enabled in production.

    This deliberately avoids a network JWKS round trip so a developer can
    actually enter a 101 table even if Supabase/JWKS is slow. The endpoint is
    gated by LOCAL_DEV_MODE and a launcher-only shared secret.
    """
    if not settings.local_dev_mode:
        raise HTTPException(404,'local_bootstrap_disabled')
    if not settings.local_test_secret or not secrets.compare_digest(str(x_local_test_secret or ''),settings.local_test_secret):
        raise HTTPException(403,'invalid_local_test_secret')
    account=STORE.ensure(body.player_id,body.name,None,body.avatar_url,is_guest=body.is_guest)
    # Local/LAN developer gameplay must mirror the authenticated Supabase wallet
    # instead of inventing a separate 1M-chip account on the PC.
    if body.coins is not None:
        account=STORE.sync_local_wallet(body.player_id,max(0,int(body.coins)),max(0,int(body.diamonds or 0)))
    if body.device_id:STORE.track_device(body.player_id,body.device_id)
    return account

@router.post('/account/bootstrap-supabase')
async def bootstrap_supabase(body:GoogleBootstrapIn,authorization:str|None=Header(None),user=Depends(_google_user)):
    if not STORE.ready:raise HTTPException(503,'storage_unavailable')
    """Bootstrap both anonymous and permanent Supabase-authenticated players."""
    account=STORE.ensure(user['id'],body.name,user.get('email'),body.avatar_url,is_guest=body.is_guest)
    if body.device_id:
        STORE.track_device(user['id'],body.device_id)
        account=STORE.apply_welcome_policy(user['id'],body.device_id) or account
    # Do not hold lobby bootstrap hostage to secondary Supabase sync calls.
    # Identity is already verified; staff/public-id mirrors can finish in background.
    asyncio.create_task(_sync_staff_role(user['id'],authorization))
    asyncio.create_task(_sync_public_id(user['id'],account.get('public_id'),authorization))
    return account

@router.get('/account/public/{player_id}')
def public_account(player_id:str):
    a=STORE.public(player_id)
    if not a:raise HTTPException(404,'account_not_found')
    return a

@router.get('/live/activity')
def live_activity(limit:int=18):
    return {'activity':STORE.activity_feed(limit)}

@router.get('/account/{player_id}')
def account(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    STORE.touch_presence(player_id)
    out=STORE.get(player_id)
    if out is None:return out
    out=dict(out);out['reward_day_key']=_day_key()
    return out

@router.post('/account/{player_id}/presence')
def presence_ping(player_id:str,x_account_token:str|None=Header(None)):
    """Hafif çevrimiçi nabzı (ana ekran ~30 sn'de bir çağırır)."""
    _require(player_id,x_account_token)
    STORE.touch_presence(player_id)
    return {'ok':True}

@router.patch('/account/{player_id}')
def update_account(player_id:str,body:ProfileUpdateIn,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.update_profile(player_id,name=body.name,avatar_url=body.avatar_url)

@router.post('/account/{player_id}/daily')
def daily(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    out=STORE.claim_daily(player_id)
    out=dict(out);out['server_day_key']=_day_key()
    if isinstance(out.get('account'),dict):
        out['account']=dict(out['account']);out['account']['reward_day_key']=out['server_day_key']
    return out

@router.get('/account/{player_id}/missions')
def missions(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.missions(player_id)

@router.post('/account/{player_id}/missions/{mission_id}/claim')
def claim_mission(player_id:str,mission_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.claim_mission(player_id,mission_id)

@router.get('/account/{player_id}/notifications')
def notifications(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    a=STORE.get(player_id)
    # The bell is for social/actionable information. Economy movements and
    # rewards already have their own result/reward UI and would otherwise fill
    # the inbox after a few games. Keep legacy rows hidden too.
    hidden_kinds={'economy','win','reward','mission','wheel','chest'}
    visible=[n for n in a['notifications'] if n.get('kind') not in hidden_kinds]
    return {'notifications':visible[:50],'unread':sum(1 for n in visible if not n.get('read'))}

@router.post('/account/{player_id}/notifications/read')
def read_notifications(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return {'ok':True,'read':STORE.mark_notifications_read(player_id)}

def _presence_map():
    out={}
    try:
        from app.api.game import ROOM_META,ROOMS
        for room_id,m in ROOM_META.items():
            room=ROOMS.get(room_id);humans=sum(1 for pid in m.get('player_ids',{}).values() if pid);locked=bool(m.get('password_hash'))
            for seat,pid in m.get('player_ids',{}).items():
                if not pid:continue
                connected=bool(m.get('connected',{}).get(seat,False))
                if not connected:continue  # bağlantısı kopan oyuncu "oyunda" görünmez
                if room is not None and getattr(room.state,'match_finished',False):continue
                if pid:out[pid]={'online':True,'status':'in_game','in_game':True,'room_id':room_id,'room_name':getattr(getattr(room,'state',None),'room_name','OkeyX Masası'),'locked':locked,'joinable':bool(room and humans<4 and not locked)}
    except Exception:pass
    return out


async def _supabase_search_players(query:str, authorization:str|None, viewer_id:str)->list[dict]:
    """Public-profile fallback for shared multiplayer.

    Local AccountStore remains the real-time game/social cache, but a player
    may search a friend before that friend's phone has bootstrapped into this
    FastAPI process. Supabase Auth profile identity is global, so mirror only
    the minimal public row into the shared runtime when search finds it.
    """
    if not authorization or not settings.supabase_url or not settings.supabase_anon_key:
        return []
    q=(query or '').strip()
    if not q:return []
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            r=await client.post(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/rpc/okeyx_search_players",
                headers={
                    'apikey':settings.supabase_anon_key,
                    'Authorization':authorization,
                    'Content-Type':'application/json',
                },
                json={'p_query':q,'p_limit':20},
            )
        if r.status_code<200 or r.status_code>=300:return []
        body=r.json()
        rows=body if isinstance(body,list) else []
        out=[]
        for row in rows:
            if not isinstance(row,dict):continue
            pid=str(row.get('user_id') or '')
            if not pid or pid==viewer_id:continue
            name=str(row.get('display_name') or 'Oyuncu')[:24]
            avatar=row.get('avatar_url')
            # Creating a shadow account is safe: when that user later connects,
            # STORE.ensure reuses the same auth UUID and upgrades last_seen/token.
            STORE.ensure(pid,name,None,avatar,is_guest=False)
            pub=STORE.public(pid)
            if pub:out.append(pub)
        return out
    except Exception:
        return []

def _presence(row,pres):
    out=dict(row)
    state=pres.get(out.get('id'))
    if state is None:
        recent=seen_recently(str(out.get('id') or ''))
        state={'online':recent,'status':'lobby' if recent else 'offline','in_game':False,'joinable':False}
    out.update(state);return out

@router.get('/social/{player_id}')
async def social(player_id:str,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require(player_id,x_account_token)
    STORE.touch_presence(player_id)
    await _sync_social_from_supabase(player_id,authorization)
    view=STORE.friends_view(player_id);pres=_presence_map();view['friends']=[_presence(x,pres) for x in view.get('friends',[])];view['requests']=[_presence(x,pres) for x in view.get('requests',[])];recent=[]
    for item in view.get('recent_players',[]):
        pub=STORE.public(str(item.get('id') or '')) or dict(item);pub['played_at']=item.get('played_at');recent.append(_presence(pub,pres))
    view['recent_players']=recent;return view

@router.post('/social/friend-request')
async def friend_request(body:FriendIn,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require_social(body.from_id,x_account_token)
    remote=await _supabase_social_rpc('okeyx_friend_request',{'p_target_user_id':body.to_id},authorization)
    if isinstance(remote,dict) and remote.get('ok') is True:
        code=str(remote.get('code') or '')
        _force_local_relationship(body.from_id,body.to_id,'friend' if code in {'accepted','already_friends'} else 'sent')
        return remote

    # Supabase is the global/canonical social graph, but a temporary RPC/network
    # failure must not make the live table feel broken.  The signed game-session
    # token already authenticates this request, so mirror the action into the
    # shared FastAPI cache and let the next healthy Supabase call reconcile it.
    local=STORE.request_friend(body.from_id,body.to_id)
    if local.get('ok') is True:
        local['sync_pending']=bool(authorization and remote is not None)
        local['remote_code']=remote.get('code') if isinstance(remote,dict) else None
        return local
    return remote if isinstance(remote,dict) else local

async def _friend_action(player_id:str,target_id:str,action:str,authorization:str|None):
    remote=await _supabase_social_rpc('okeyx_friend_action',{'p_target_user_id':target_id,'p_action':action},authorization)
    if isinstance(remote,dict) and remote.get('ok') is True:
        rel='friend' if action=='accept' else 'none'
        _force_local_relationship(player_id,target_id,rel)
        return remote

    local = {
        'accept': lambda: STORE.accept_friend(player_id,target_id),
        'decline': lambda: STORE.decline_friend(player_id,target_id),
        'cancel': lambda: STORE.cancel_friend_request(player_id,target_id),
        'remove': lambda: STORE.remove_friend(player_id,target_id),
    }.get(action)
    if local is None:return remote if isinstance(remote,dict) else None
    out=local()
    if isinstance(out,dict) and out.get('ok') is True:
        out['sync_pending']=bool(authorization and remote is not None)
        out['remote_code']=remote.get('code') if isinstance(remote,dict) else None
        return out
    return remote if isinstance(remote,dict) else out

@router.post('/social/friend-accept')
async def friend_accept(body:AcceptFriendIn,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require_social(body.player_id,x_account_token)
    out=await _friend_action(body.player_id,body.from_id,'accept',authorization)
    return out if out is not None else STORE.accept_friend(body.player_id,body.from_id)

@router.post('/social/friend-decline')
async def friend_decline(body:AcceptFriendIn,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require_social(body.player_id,x_account_token)
    out=await _friend_action(body.player_id,body.from_id,'decline',authorization)
    return out if out is not None else STORE.decline_friend(body.player_id,body.from_id)

@router.post('/social/friend-cancel')
async def friend_cancel(body:FriendIn,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require_social(body.from_id,x_account_token)
    out=await _friend_action(body.from_id,body.to_id,'cancel',authorization)
    return out if out is not None else STORE.cancel_friend_request(body.from_id,body.to_id)

@router.post('/social/friend-remove')
async def friend_remove(body:FriendIn,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require_social(body.from_id,x_account_token)
    out=await _friend_action(body.from_id,body.to_id,'remove',authorization)
    return out if out is not None else STORE.remove_friend(body.from_id,body.to_id)

@router.get('/social/gifts/catalog')
def gifts_catalog():
    return {'gifts':GIFT_CATALOG}

@router.post('/social/gift')
async def gift(body:GiftIn,x_account_token:str|None=Header(None)):
    _require_social(body.from_id,x_account_token,'gift_locked')
    out=STORE.send_gift(body.from_id,body.to_id,body.gift_type)
    await _refresh_tables(body.from_id,body.to_id)
    return out

async def _refresh_tables(*ids:str)->None:
    try:
        from app.api.game import refresh_player_rooms
        await refresh_player_rooms(ids)
    except Exception:
        pass

@router.post('/social/transfer-coins')
async def transfer_coins(body:CoinTransferIn,x_account_token:str|None=Header(None)):
    _require_social(body.from_id,x_account_token)
    out=STORE.transfer_coins(body.from_id,body.to_id,body.amount)
    if out.get('ok'):await _refresh_tables(body.from_id,body.to_id)
    return out

@router.post('/social/invite')
def invite(body:InviteIn,x_account_token:str|None=Header(None)):
    _require_social(body.from_id,x_account_token,'invite_locked')
    a=STORE.get(body.from_id);b=STORE.get(body.to_id)
    if not a or not b:return {'ok':False,'code':'user_not_found'}
    room_info={}
    try:
        from app.api.game import ROOM_META,ROOMS
        if body.room_id not in ROOMS:return {'ok':False,'code':'room_not_found'}
        meta=ROOM_META.get(body.room_id)
        if meta is not None:meta.setdefault('invited_player_ids',set()).add(body.to_id)
        st=ROOMS[body.room_id].state
        room_info={'room_name':st.room_name,'variant':st.variant,'entry_fee':st.entry_fee,'turbo':st.turbo,'assisted':st.assisted}
    except Exception:
        pass
    STORE.add_notification(body.to_id,'Masa daveti',f'{a["name"]} seni masaya çağırıyor.','invite',{'room_id':body.room_id,'from_id':body.from_id,'from_name':a['name'],'from_avatar':a.get('avatar_url'),**room_info})
    return {'ok':True}


@router.post('/account/{player_id}/achievements/{achievement_id}/claim')
def claim_achievement(player_id:str,achievement_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.claim_achievement(player_id,achievement_id)

@router.get('/account/{player_id}/reward-config')
def reward_config(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.reward_config()

@router.post('/account/{player_id}/wheel')
def wheel(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.spin_wheel(player_id)

@router.post('/account/{player_id}/chest')
def chest(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.open_chest(player_id)

@router.get('/account/{player_id}/history')
def history(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    a=STORE.get(player_id)
    return {'history':a.get('match_history',[])[:50]}

@router.get('/social/search')
async def social_search(q:str,player_id:str,x_account_token:str|None=Header(None),authorization:str|None=Header(None)):
    _require_social(player_id,x_account_token)
    await _sync_social_from_supabase(player_id,authorization)
    viewer=STORE.get(player_id) or {};pres=_presence_map()
    local=STORE.search_players(q,viewer_id=player_id)
    if len(local)<20:
        remote=await _supabase_search_players(q,authorization,player_id)
        seen={str(x.get('id') or '') for x in local}
        local.extend(x for x in remote if str(x.get('id') or '') not in seen)
    rows=[]
    for row in local[:20]:
        x=_presence(row,pres);pid=str(x.get('id') or '');x['relationship']='friend' if pid in viewer.get('friends',[]) else ('sent' if pid in viewer.get('sent_friend_requests',[]) else ('incoming' if pid in viewer.get('friend_requests',[]) else 'none'));rows.append(x)
    return {'players':rows}

@router.post('/social/block')
def social_block(body:TargetIn,x_account_token:str|None=Header(None)):
    _require_social(body.player_id,x_account_token)
    return STORE.set_social_safety(body.player_id,body.target_id,'block',body.enabled)

@router.post('/social/mute')
def social_mute(body:TargetIn,x_account_token:str|None=Header(None)):
    _require_social(body.player_id,x_account_token)
    return STORE.set_social_safety(body.player_id,body.target_id,'mute',body.enabled)

@router.post('/social/report')
def social_report(body:ReportIn,x_account_token:str|None=Header(None)):
    _require_social(body.player_id,x_account_token)
    return STORE.report_player(body.player_id,body.target_id,body.reason,body.room_id)

@router.post('/account/push/register')
def register_push(body:PushIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return STORE.register_push(body.player_id,body.token,body.device_id)

@router.get('/account/{player_id}/referral')
def referral_info(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.referral_info(player_id)

@router.post('/account/referral/redeem')
def referral_redeem(body:ReferralIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return STORE.redeem_referral(body.player_id,body.code,body.device_id)

@router.post('/account/league/city')
def league_city(body:CityIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return {'ok':True,'league':STORE.set_city(body.player_id,body.city)}

@router.get('/account/{player_id}/leaderboard')
def leaderboard(player_id:str,scope:str='global',x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    if scope not in ('global','friends','city','monthly'):scope='global'
    return STORE.leaderboard(player_id,scope)

@router.get('/canak')
def canak():
    return STORE.canak_state()

@router.get('/account/{player_id}/season')
def season(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.season_state(player_id)

@router.post('/account/{player_id}/season/{milestone_id}/claim')
def season_claim(player_id:str,milestone_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.claim_season(player_id,milestone_id)

@router.get('/clubs/{player_id}')
def clubs(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    return STORE.club_view(player_id)

@router.post('/clubs/create')
def club_create(body:ClubCreateIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return STORE.club_create(body.player_id,body.name)

@router.post('/clubs/join')
def club_join(body:ClubJoinIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return STORE.club_join(body.player_id,body.club_id)

@router.post('/clubs/leave')
def club_leave(body:ClubJoinIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return STORE.club_leave(body.player_id)

@router.post('/clubs/weekly/claim')
def club_weekly_claim(body:ClubJoinIn,x_account_token:str|None=Header(None)):
    _account_guard(body.player_id,x_account_token)
    return STORE.club_claim_weekly(body.player_id)

@router.post('/clubs/chat')
def club_chat(body:ClubChatIn,x_account_token:str|None=Header(None)):
    _require(body.player_id,x_account_token)
    return STORE.club_chat(body.player_id,body.text)


def _prev_week_key()->str:
    import time as _t
    from app.services.account_store import _week_key as _wk
    return _wk(int(_t.time())-7*86400)


@router.get('/tournament/{player_id}')
def tournament_view(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    from app.services import tournament as T
    from app.services.account_store import _week_key as _wk
    return T.view(STORE,_wk(),_prev_week_key(),player_id)


@router.post('/tournament/{player_id}/claim')
def tournament_claim(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    from app.services import tournament as T
    return T.claim_previous(STORE,_prev_week_key(),player_id)


@router.post('/account/{player_id}/delete')
def delete_my_account(player_id:str,x_account_token:str|None=Header(None)):
    """Oyun sunucusundaki hesabı kalıcı siler (Supabase girişi ayrıca silinir)."""
    _require(player_id,x_account_token)
    return {'ok':STORE.purge_account(player_id)}
