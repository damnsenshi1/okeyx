from pathlib import Path
import re
root=Path('.')

# ---------- game.py ----------
p=root/'backend/app/api/game.py'
s=p.read_text()

# Ready body
s=s.replace("class ReconnectIn(BaseModel):\n    player_id:str\n    account_token:str\n\n\nclass ManageRoomIn(BaseModel):",
            "class ReconnectIn(BaseModel):\n    player_id:str\n    account_token:str\n\nclass ReadyIn(BaseModel):\n    seat:int\n    reconnect_token:str\n    ready:bool=True\n\n\nclass ManageRoomIn(BaseModel):",1)
assert 'class ReadyIn' in s

# room meta ready map
s=s.replace("'state_version':1,'quick_match':False", "'state_version':1,'quick_match':False,'ready':{}",1)
assert "'ready':{}" in s

# bind ready default (quick match auto-ready; custom waits for explicit ready)
s=s.replace("m['connected'].setdefault(seat,False);m['afk_strikes'][seat]=0\n    room.set_player_identity",
            "m['connected'].setdefault(seat,False);m['afk_strikes'][seat]=0\n    m.setdefault('ready',{})[seat]=bool(m.get('quick_match',False))\n    room.set_player_identity",1)

# publish per-player ready
s=s.replace("        p['player_id']=pid\n        acc=STORE.get(pid) if pid else None",
            "        p['player_id']=pid\n        p['ready']=bool(m.setdefault('ready',{}).get(seat, bool(p.get('bot'))))\n        acc=STORE.get(pid) if pid else None",1)

# publish aggregate ready state
s=s.replace("    state['quick_match']=bool(m.get('quick_match',False))\n    return state",
            "    state['quick_match']=bool(m.get('quick_match',False))\n    human_seats=[int(seat) for seat,pid in m.get('player_ids',{}).items() if pid and not room.state.players[int(seat)].bot]\n    ready_map=m.setdefault('ready',{})\n    state['ready_by_seat']={str(seat):bool(ready_map.get(seat,False)) for seat in human_seats}\n    state['viewer_ready']=bool(ready_map.get(viewer,False))\n    state['ready_count']=sum(1 for seat in human_seats if bool(ready_map.get(seat,False)))\n    state['all_humans_ready']=bool(human_seats) and all(bool(ready_map.get(seat,False)) for seat in human_seats)\n    return state",1)

# start gate: host + custom room all humans ready
needle="    if body.kind=='start_match':\n        # Quick Match is a real-player queue. Do not let the first player turn\n"
assert needle in s
s=s.replace(needle,
"    if body.kind=='start_match':\n"
"        if int(body.seat)!=int(m.get('owner_seat',0) or 0):\n"
"            response={'ok':False,'code':'only_host_can_start','payload':{},'request_id':body.request_id,'state':_state(room_id,body.seat)}\n"
"            if body.request_id:m['dedupe'][body.request_id]=response\n"
"            return response\n"
"        if not m.get('quick_match'):\n"
"            human_seats=[int(seat) for seat,pid in m.get('player_ids',{}).items() if pid and not r.state.players[int(seat)].bot]\n"
"            not_ready=[seat for seat in human_seats if not bool(m.setdefault('ready',{}).get(seat,False))]\n"
"            if not_ready:\n"
"                response={'ok':False,'code':'players_not_ready','payload':{'not_ready':not_ready},'request_id':body.request_id,'state':_state(room_id,body.seat)}\n"
"                if body.request_id:m['dedupe'][body.request_id]=response\n"
"                return response\n"
"        # Quick Match is a real-player queue. Do not let the first player turn\n",1)

# ready route
needle="@router.post('/game/{room_id}/manage')\nasync def manage_room(room_id:str,body:ManageRoomIn):\n"
assert needle in s
s=s.replace(needle,
"@router.post('/game/{room_id}/ready')\n"
"async def set_ready(room_id:str,body:ReadyIn):\n"
"    r=ROOMS.get(room_id)\n"
"    if not r:raise HTTPException(404,'room_not_found')\n"
"    if r.state.phase!='waiting':raise HTTPException(409,'ready_waiting_only')\n"
"    m=_auth(room_id,body.seat,body.reconnect_token)\n"
"    if body.seat not in m.get('player_ids',{}):raise HTTPException(403,'player_not_in_room')\n"
"    m.setdefault('ready',{})[body.seat]=bool(body.ready)\n"
"    _touch(room_id)\n"
"    await _broadcast(room_id)\n"
"    return {'ok':True,'code':'ready_updated','ready':bool(body.ready),'state':_state(room_id,body.seat)}\n\n"
"@router.post('/game/{room_id}/manage')\n"
"async def manage_room(room_id:str,body:ManageRoomIn):\n",1)

# ready cleanup on kick/leave
s=s.replace("m['player_ids'].pop(target,None);m['seat_tokens'].pop(target,None);m['connected'][target]=False;m['disconnect_at'][target]=_now()",
            "m['player_ids'].pop(target,None);m['seat_tokens'].pop(target,None);m.setdefault('ready',{}).pop(target,None);m['connected'][target]=False;m['disconnect_at'][target]=_now()")
s=s.replace("m['player_ids'].pop(body.seat,None);m['seat_tokens'].pop(body.seat,None)\n            if int(m.get('owner_seat',0))==int(body.seat):",
            "m['player_ids'].pop(body.seat,None);m['seat_tokens'].pop(body.seat,None);m.setdefault('ready',{}).pop(body.seat,None)\n            if int(m.get('owner_seat',0))==int(body.seat):")
s=s.replace("m['player_ids'].pop(body.seat,None);m['seat_tokens'].pop(body.seat,None)\n    m['connected'][body.seat]=False",
            "m['player_ids'].pop(body.seat,None);m['seat_tokens'].pop(body.seat,None);m.setdefault('ready',{}).pop(body.seat,None)\n    m['connected'][body.seat]=False")

# changing settings cancels ready flags
s=s.replace("        r.recalculate_turbo()\n        _touch(room_id)",
            "        r.recalculate_turbo()\n        if not m.get('quick_match'):\n            for seat in list(m.setdefault('ready',{})):m['ready'][seat]=False\n        _touch(room_id)",1)

# free gifts: remove debit path for table gift and fallback gift
s=s.replace("""        if table_gift:
            cost=max(0,int(gift.get('cost',0) or 0))
            if from_id and cost and not STORE.debit(from_id,cost,f"Masaya hediye • {gift['name']}",notify=False):
                return {'ok':False,'code':'insufficient_coins','required':cost}
            value=str(gift['name'])
""","""        if table_gift:
            value=str(gift['name'])
""",1)
s=s.replace("""        else:
            cost=max(0,int(gift.get('cost',0) or 0))
            if from_id and cost:
                if not STORE.debit(from_id,cost,f"Masa hediyesi • {gift['name']}",notify=False):return {'ok':False,'code':'insufficient_coins','required':cost}
            value=str(gift['name'])
""","""        else:
            value=str(gift['name'])
""",1)

# full free emoji set
s=s.replace("allowed={'😂','😎','🔥','👏','🤝','😱','🍀','⭐'}",
            "allowed={'😂','😎','🔥','👏','🤝','😱','🍀','⭐','❤️','☕','🌹','🎉','😅','😡','🤯','💯'}",1)
p.write_text(s)

# ---------- account_store.py ----------
p=root/'backend/app/services/account_store.py'
s=p.read_text()
marker='WHEEL_REWARDS='
assert marker in s
insert="""# Social table gifts are free for every player and never spend wallet currency.
for _gift in GIFT_CATALOG.values():
    _gift['cost']=0
    _gift['free']=True

"""
s=s.replace(marker,insert+marker,1)
old="""            gift=GIFT_CATALOG[gift_type];cost=max(0,int(gift.get('cost',0) or 0))
            if int(a.get('chips',0) or 0)<cost:return {'ok':False,'code':'insufficient_coins','required':cost,'balance':int(a.get('chips',0) or 0)}
            if cost:
                a['chips']-=cost;a.setdefault('stats',{});a['stats']['chips_spent']=int(a['stats'].get('chips_spent',0) or 0)+cost
            item={'id':uuid.uuid4().hex[:10],'from_id':from_id,'from_name':a['name'],'gift_type':gift_type,'name':gift['name'],'emoji':gift.get('emoji','🎁'),'cost':cost,'persistent':bool(gift.get('persistent',False)),'created_at':_now()}
"""
assert old in s
s=s.replace(old,"""            gift=GIFT_CATALOG[gift_type];cost=0
            item={'id':uuid.uuid4().hex[:10],'from_id':from_id,'from_name':a['name'],'gift_type':gift_type,'name':gift['name'],'emoji':gift.get('emoji','🎁'),'cost':0,'persistent':bool(gift.get('persistent',False)),'created_at':_now()}
""",1)
p.write_text(s)

# ---------- phase4_service.py ----------
p=root/'backend/app/services/phase4_service.py'
s=p.read_text()
s,n=re.subn(r'\n\s*\{"id": "emoji_(?:party|cafe|troll|neon)"[^\n]+\},','',s)
assert n==4, f'emoji rows removed={n}'
s=s.replace('"8": {"item": "emoji_party"}', '"8": {"coins": 5_000}',1)
old="""        if int(cfg.get("living_schema_version", 0)) < 1:
            existing={str(x.get("id")) for x in cfg.get("cosmetics",[]) if isinstance(x,dict)}
            for item in DEFAULT_PHASE4_CONFIG.get("cosmetics",[]):
                if str(item.get("id")) not in existing:cfg.setdefault("cosmetics",[]).append(deepcopy(item))
            cfg.setdefault("chance_controls",deepcopy(DEFAULT_PHASE4_CONFIG.get("chance_controls",{})))
            cfg["living_schema_version"]=1
            cfg["version"]=max(5,int(cfg.get("version",1))+1)
"""
assert old in s
s=s.replace(old,"""        if int(cfg.get("living_schema_version", 0)) < 2:
            cfg["cosmetics"]=[x for x in cfg.get("cosmetics",[]) if isinstance(x,dict) and x.get("category")!="emoji_pack"]
            existing={str(x.get("id")) for x in cfg.get("cosmetics",[]) if isinstance(x,dict)}
            for item in DEFAULT_PHASE4_CONFIG.get("cosmetics",[]):
                if item.get("category")=="emoji_pack":continue
                if str(item.get("id")) not in existing:cfg.setdefault("cosmetics",[]).append(deepcopy(item))
            cfg.setdefault("chance_controls",deepcopy(DEFAULT_PHASE4_CONFIG.get("chance_controls",{})))
            pass_cfg=cfg.setdefault("pass",deepcopy(DEFAULT_PHASE4_CONFIG["pass"]))
            if (pass_cfg.get("free_rewards") or {}).get("8",{}).get("item")=="emoji_party":pass_cfg["free_rewards"]["8"]={"coins":5000}
            cfg["living_schema_version"]=2
            cfg["version"]=max(6,int(cfg.get("version",1))+1)
""",1)
old='cosmetics = [{**deepcopy(item), "owned": item["id"] in inventory, "equipped": a["equipped"].get(item["category"]) == item["id"]} for item in cfg.get("cosmetics", []) if not item.get("store_hidden") or item["id"] in inventory]'
assert old in s
s=s.replace(old,'cosmetics = [{**deepcopy(item), "owned": item["id"] in inventory, "equipped": a["equipped"].get(item["category"]) == item["id"]} for item in cfg.get("cosmetics", []) if item.get("category") != "emoji_pack" and (not item.get("store_hidden") or item["id"] in inventory)]',1)
p.write_text(s)

# ---------- account.py live strip ----------
p=root/'backend/app/api/account.py'
s=p.read_text()
old="""@router.get('/live/activity')
def live_activity(limit:int=18):
    return {'activity':STORE.activity_feed(limit)}
"""
if old in s:
    s=s.replace(old,"""@router.get('/live/activity')
def live_activity(limit:int=18):
    meaningful={'purchase','big_win','match_win','event_reward'}
    rows=[row for row in STORE.activity_feed(max(40,limit*4)) if str(row.get('kind') or '') in meaningful]
    return {'activity':rows[:max(1,min(limit,30))]}
""",1)
p.write_text(s)

# ---------- tests ----------
p=root/'backend/tests/test_v11_social_quality.py'
s=p.read_text()
s=s.replace('def test_v11_table_gift_costs_once_and_targets_whole_table', 'def test_v1127_table_gifts_are_free_and_target_whole_table')
s=s.replace("    assert store.get('p1')['chips'] == before - 250", "    assert store.get('p1')['chips'] == before")
p.write_text(s)

p=root/'backend/tests/test_v1127_ready_and_free_social.py'
p.write_text('''import asyncio
from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore


def _reset_runtime():
    game.ROOMS.clear(); game.ROOM_META.clear(); game.SOCKETS.clear()


def _store(tmp_path: Path):
    store=AccountStore(tmp_path/'accounts.json')
    for pid,name in [('p1','Bir'),('p2','Iki')]:
        store.ensure(pid,name,None,None,is_guest=False)
        store._data['accounts'][pid]['chips']=1_000_000
    store._save(); return store


def _join(store,pid):
    a=store.get(pid)
    return game.JoinRoomIn(name=a['name'],player_id=pid,account_token=a['session_token'],turbo=False,variant='non_fold',team_mode='solo',entry_fee=5000,rounds=1,assisted=True)


def test_ready_gate_requires_every_human(tmp_path,monkeypatch):
    _reset_runtime(); store=_store(tmp_path)
    monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1')
    created=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir',name='Masa'))
    room=created['room_id']
    joined=asyncio.run(game.join_room(room,_join(store,'p2')))
    host=game.ActionIn(seat=created['seat'],kind='start_match',reconnect_token=created['reconnect_token'],request_id='start-1')
    out=asyncio.run(game._execute_action(room,host))
    assert out['ok'] is False and out['code']=='players_not_ready'
    asyncio.run(game.set_ready(room,game.ReadyIn(seat=created['seat'],reconnect_token=created['reconnect_token'],ready=True)))
    asyncio.run(game.set_ready(room,game.ReadyIn(seat=joined['seat'],reconnect_token=joined['reconnect_token'],ready=True)))
    host.request_id='start-2'
    out=asyncio.run(game._execute_action(room,host))
    assert out['ok'] is True


def test_direct_gift_does_not_spend_coins(tmp_path,monkeypatch):
    _reset_runtime(); store=_store(tmp_path)
    monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1'); created=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir',name='Masa'))
    joined=asyncio.run(game.join_room(created['room_id'],_join(store,'p2')))
    before=store.get('p1')['chips']
    result=asyncio.run(game.table_chat(created['room_id'],game.ChatIn(seat=created['seat'],reconnect_token=created['reconnect_token'],kind='gift',value='rose',to_seat=joined['seat'])))
    assert result['ok'] is True
    assert store.get('p1')['chips']==before
    assert store.get('p2')['gifts_received'][0]['cost']==0


def test_reconnect_restores_same_authoritative_seat(tmp_path,monkeypatch):
    _reset_runtime(); store=_store(tmp_path)
    monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1')
    created=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir',name='Masa'))
    room=created['room_id']; seat=created['seat']; token=created['reconnect_token']
    game.ROOM_META[room]['connected'][seat]=False
    game.ROOM_META[room]['disconnect_at'][seat]=game._now()-25
    game.ROOMS[room].takeover_by_bot(seat,'afk')
    out=game.reconnect_game(game.ReconnectIn(player_id='p1',account_token=a['session_token']))
    assert out['ok'] is True
    assert out['room_id']==room and out['seat']==seat and out['reconnect_token']==token
    assert game.ROOMS[room].state.player(seat).bot is False
    assert out['state']['viewer_seat']==seat


def test_friend_invite_allows_joining_locked_room(tmp_path,monkeypatch):
    from app.api import account as account_api
    _reset_runtime(); store=_store(tmp_path)
    monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    monkeypatch.setattr(account_api,'STORE',store)
    a=store.get('p1'); b=store.get('p2')
    created=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir',name='Davet Masası',password='1234'))
    invite=account_api.invite(account_api.InviteIn(from_id='p1',to_id='p2',room_id=created['room_id']),x_account_token=a['session_token'])
    assert invite['ok'] is True
    joined=asyncio.run(game.join_room(created['room_id'],game.JoinRoomIn(name='Iki',player_id='p2',account_token=b['session_token'])))
    assert joined['room_id']==created['room_id']
    assert joined['seat'] != created['seat']
''')
print('V11.0.27 backend patch applied')
