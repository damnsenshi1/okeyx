import asyncio

from app.api import game
from tests.test_v1127_ready_free_social import _reset, _store, _join


def _setup(tmp_path, monkeypatch):
    _reset(); store=_store(tmp_path); monkeypatch.setattr(game,'STORE',store); monkeypatch.setattr(game,'_persist_runtime',lambda force=False:None)
    a=store.get('p1'); c=game.create_room(game.CreateRoomIn(player_id='p1',account_token=a['session_token'],owner_name='Bir'))
    asyncio.run(game.join_room(c['room_id'],_join(store,'p2')))
    for seat in (2,3):
        asyncio.run(game.manage_room(c['room_id'],game.ManageRoomIn(seat=c['seat'],reconnect_token=c['reconnect_token'],action='add_bot',target_seat=seat,bot_level='medium')))
    m=game.ROOM_META[c['room_id']]
    j=[s for s,pid in m['player_ids'].items() if pid=='p2'][0]
    asyncio.run(game.set_ready(c['room_id'],game.ReadyIn(seat=j,reconnect_token=m['seat_tokens'][j],ready=True)))
    out=asyncio.run(game._execute_action(c['room_id'],game.ActionIn(seat=c['seat'],kind='start_match',reconnect_token=c['reconnect_token'],request_id='s')))
    assert out['ok'] is True
    r=game.ROOMS[c['room_id']]; r.intro_until_ms=0; r.state.phase='finished'; r.state.match_finished=True
    return c, j


def test_private_rematch_returns_to_waiting_and_clears_ready(tmp_path, monkeypatch):
    c, j = _setup(tmp_path, monkeypatch)
    m=game.ROOM_META[c['room_id']]
    m['connected'][j]=True
    out=asyncio.run(game._execute_action(c['room_id'],game.ActionIn(seat=c['seat'],kind='rematch',reconnect_token=c['reconnect_token'],request_id='r')))
    assert out['ok'] is True
    r=game.ROOMS[c['room_id']]
    assert r.state.phase=='waiting' and not r.state.started
    assert m['ready_seats']==set()
    assert m['player_ids'].get(j)=='p2'
    # Herkes hazır demeden başlamaz.
    st=asyncio.run(game._execute_action(c['room_id'],game.ActionIn(seat=c['seat'],kind='start_match',reconnect_token=c['reconnect_token'],request_id='s2')))
    assert st['ok'] is False and st['code']=='players_not_ready'


def test_long_disconnected_player_loses_seat_on_rematch(tmp_path, monkeypatch):
    c, j = _setup(tmp_path, monkeypatch)
    m=game.ROOM_META[c['room_id']]
    m['connected'][j]=False; m['disconnect_at'][j]=game._now()-60
    out=asyncio.run(game._execute_action(c['room_id'],game.ActionIn(seat=c['seat'],kind='rematch',reconnect_token=c['reconnect_token'],request_id='r')))
    assert out['ok'] is True
    assert j not in m['player_ids']
    st=game._state(c['room_id'],c['seat'])
    assert [p for p in st['players'] if p['seat']==j][0]['empty'] is True
