import asyncio
from pathlib import Path
from app.api import game
from app.services.account_store import AccountStore

def _reset():
    game.ROOMS.clear(); game.ROOM_META.clear(); game.SOCKETS.clear()

def _store(tmp_path:Path):
    s=AccountStore(tmp_path/'accounts.json')
    for pid,name in [('p1','Bir'),('p2','Iki')]:
        s.ensure(pid,name,None,None,is_guest=False); s._data['accounts'][pid]['chips']=1_000_000
    s._save(); return s

def _join(store,pid):
    a=store.get(pid); return game.JoinRoomIn(name=a['name'],player_id=pid,account_token=a['session_token'])

def test_private_host_start_requires_filled_seats_and_ready(tmp_path,monkeypatch):
    _reset(); store=_store(tmp_path); monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1'); c=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir')); asyncio.run(game.join_room(c['room_id'],_join(store,'p2')))
    start=game.ActionIn(seat=c['seat'],kind='start_match',reconnect_token=c['reconnect_token'],request_id='a')
    out=asyncio.run(game._execute_action(c['room_id'],start)); assert out['ok'] is False and out['code']=='empty_seats'
    # Host fills the remaining seats with bots; adding bots never starts the match.
    for seat in (2,3):
        added=asyncio.run(game.manage_room(c['room_id'],game.ManageRoomIn(seat=c['seat'],reconnect_token=c['reconnect_token'],action='add_bot',target_seat=seat,bot_level='medium')))
        assert added['ok'] is True and game.ROOMS[c['room_id']].state.phase=='waiting'
    # Hazır sistemi: davetli oyuncu HAZIRIM'a basmadan masa başlamaz.
    start.request_id='b'; out=asyncio.run(game._execute_action(c['room_id'],start)); assert out['ok'] is False and out['code']=='players_not_ready'
    # Masa sahibi onaylayarak hazır olmayanı beklemeden başlatabilir (force).
    forced=game.ActionIn(seat=c['seat'],kind='start_match',reconnect_token=c['reconnect_token'],request_id='f',payload={'force':True})
    import copy
    room_backup=copy.deepcopy(game.ROOMS[c['room_id']]);meta_backup=copy.deepcopy({k:v for k,v in game.ROOM_META[c['room_id']].items() if k not in ('sockets','spectators')})
    out=asyncio.run(game._execute_action(c['room_id'],forced)); assert out['ok'] is True
    game.ROOMS[c['room_id']]=room_backup;game.ROOM_META[c['room_id']].update(meta_backup)
    j=[s for s,pid in game.ROOM_META[c['room_id']]['player_ids'].items() if pid=='p2'][0]
    tok=game.ROOM_META[c['room_id']]['seat_tokens'][j]
    asyncio.run(game.set_ready(c['room_id'],game.ReadyIn(seat=j,reconnect_token=tok,ready=True)))
    st=game._state(c['room_id'],j); assert [p for p in st['players'] if p['seat']==j][0]['ready'] is True
    start.request_id='c'; out=asyncio.run(game._execute_action(c['room_id'],start)); assert out['ok'] is True

def test_direct_gifts_are_free_and_retry_safe(tmp_path,monkeypatch):
    _reset(); store=_store(tmp_path); monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1'); c=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir')); j=asyncio.run(game.join_room(c['room_id'],_join(store,'p2'))); before=store.get('p1')['chips']
    body=game.ChatIn(seat=c['seat'],reconnect_token=c['reconnect_token'],kind='gift',value='dragon',to_seat=j['seat'],request_id='gift-once')
    out=asyncio.run(game.table_chat(c['room_id'],body)); assert out['ok'] is True
    retry=asyncio.run(game.table_chat(c['room_id'],body)); assert retry==out
    assert store.get('p1')['chips']==before
    recipient=store.get('p2')
    assert len(recipient['gifts_received'])==1 and recipient['gifts_received'][0]['cost']==0
    assert len([n for n in recipient['notifications'] if n['kind']=='gift_received'])==1

def test_gift_store_request_id_is_idempotent_and_bound_to_payload(tmp_path):
    store=_store(tmp_path)
    first=store.send_gift('p1','p2','dragon','same-request')
    retry=store.send_gift('p1','p2','dragon','same-request')
    conflict=store.send_gift('p1','p2','coffee','same-request')
    assert first==retry
    assert conflict['ok'] is False and conflict['code']=='idempotency_conflict'
    assert len(store.get('p2')['gifts_received'])==1

def test_reconnect_same_seat_after_takeover(tmp_path,monkeypatch):
    _reset(); store=_store(tmp_path); monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1'); c=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir')); room=c['room_id']; seat=c['seat']; token=c['reconnect_token']; game.ROOMS[room].takeover_by_bot(seat,'afk')
    out=game.reconnect_game(game.ReconnectIn(player_id='p1',account_token=a['session_token'])); assert out['ok'] is True and out['seat']==seat and out['reconnect_token']==token and not game.ROOMS[room].state.player(seat).bot
