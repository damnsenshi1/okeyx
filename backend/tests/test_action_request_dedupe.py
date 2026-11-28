from __future__ import annotations

import asyncio
from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore


def _setup(tmp_path: Path, monkeypatch):
    game.ROOMS.clear()
    game.ROOM_META.clear()
    game.SOCKETS.clear()
    store = AccountStore(tmp_path / 'accounts.json')
    host = store.ensure('p1', name='One', is_guest=True)
    guest = store.ensure('p2', name='Two', is_guest=True)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)
    created = game.create_room(game.CreateRoomIn(
        player_id='p1', account_token=host['session_token'],
    ))
    joined = asyncio.run(game.join_room(created['room_id'], game.JoinRoomIn(
        name='Two', player_id='p2', account_token=guest['session_token'],
    )))
    return created, joined


def _action(seat: int, token: str, request_id: str) -> game.ActionIn:
    return game.ActionIn(
        seat=seat,
        reconnect_token=token,
        kind='draw_stock',
        request_id=request_id,
    )


def test_action_request_id_is_scoped_to_seat(tmp_path, monkeypatch):
    created, joined = _setup(tmp_path, monkeypatch)
    room_id = created['room_id']

    seat_zero = asyncio.run(game._execute_action(
        room_id, _action(created['seat'], created['reconnect_token'], 'same-id'),
    ))
    assert seat_zero['code'] == 'match_not_started'
    assert seat_zero['state']['players'][0]['hand']
    assert seat_zero['state']['players'][1]['hand'] == []

    seat_one = asyncio.run(game._execute_action(
        room_id, _action(joined['seat'], joined['reconnect_token'], 'same-id'),
    ))
    assert seat_one['code'] == 'match_not_started'
    assert seat_one['state']['players'][0]['hand'] == []
    assert seat_one['state']['players'][1]['hand']

    game.ROOMS.clear()
    game.ROOM_META.clear()
    game.SOCKETS.clear()


def test_same_seat_action_retry_returns_cached_result(tmp_path, monkeypatch):
    created, _ = _setup(tmp_path, monkeypatch)
    room_id = created['room_id']
    body = _action(created['seat'], created['reconnect_token'], 'retry-id')

    first = asyncio.run(game._execute_action(room_id, body))
    version_after_first = game.ROOM_META[room_id]['state_version']
    retry = asyncio.run(game._execute_action(room_id, body))

    assert retry == first
    assert game.ROOM_META[room_id]['state_version'] == version_after_first
    game.ROOMS.clear()
    game.ROOM_META.clear()
    game.SOCKETS.clear()
