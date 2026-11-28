import asyncio
from pathlib import Path

import pytest
from fastapi import HTTPException

from app.api import game
from app.services.account_store import AccountStore, GIFT_CATALOG


def _reset():
    game.ROOMS.clear(); game.ROOM_META.clear(); game.SOCKETS.clear()


def _store(tmp_path: Path):
    s = AccountStore(tmp_path / 'accounts.json')
    for pid, name in [('p1', 'Bir'), ('p2', 'Iki')]:
        s.ensure(pid, name, None, None, is_guest=False)
    s._save(); return s


def _join(store, pid):
    a = store.get(pid); return game.JoinRoomIn(name=a['name'], player_id=pid, account_token=a['session_token'])


def test_catalog_has_display_styles():
    assert GIFT_CATALOG['slipper']['style'] == 'stick'
    assert GIFT_CATALOG['tomato']['style'] == 'stick'
    assert GIFT_CATALOG['dragon']['style'] == 'big'
    assert GIFT_CATALOG['tea']['style'] == 'float'
    # Küçük hediyeler 3 sn, tam ekran gösteriler 6 sn bekler.
    assert all(row['cooldown_s'] == (6.0 if row['style'] == 'big' else 3.0) for row in GIFT_CATALOG.values())


def test_same_gift_has_short_cooldown(tmp_path, monkeypatch):
    _reset(); store = _store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)
    clock = [1000.0]
    monkeypatch.setattr(game, '_now', lambda: clock[0])
    a = store.get('p1')
    c = game.create_room(game.CreateRoomIn(player_id='p1', account_token=a['session_token'], owner_name='Bir'))
    j = asyncio.run(game.join_room(c['room_id'], _join(store, 'p2')))

    def send(value):
        return asyncio.run(game.table_chat(c['room_id'], game.ChatIn(seat=c['seat'], reconnect_token=c['reconnect_token'], kind='gift', value=value, to_seat=j['seat'])))

    out = send('slipper')
    assert out['ok'] is True and out['event']['gift_id'] == 'slipper' and out['event']['style'] == 'stick'
    clock[0] += 1.5
    with pytest.raises(HTTPException) as err:
        send('slipper')
    assert err.value.detail == 'gift_cooldown'
    # Başka bir hediye serbest (genel 0.7 sn sınırı geçti).
    assert send('tea')['ok'] is True
    clock[0] += 2
    assert send('slipper')['ok'] is True
    _reset()
