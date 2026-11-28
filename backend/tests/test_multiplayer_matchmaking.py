from __future__ import annotations

import asyncio
from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore


def _isolated_store(tmp_path: Path) -> AccountStore:
    return AccountStore(tmp_path / 'accounts.json')


def _join(store: AccountStore, player_id: str):
    account = store.ensure(player_id, name=player_id, is_guest=True)
    return game.JoinRoomIn(
        name=player_id,
        player_id=player_id,
        account_token=account['session_token'],
        entry_fee=5000,
        rounds=1,
        turbo=False,
        assisted=True,
        variant='non_fold',
        team_mode='solo',
    )


def _reset_runtime():
    game.ROOMS.clear()
    game.ROOM_META.clear()
    game.SOCKETS.clear()


def test_quick_match_waits_for_real_players(tmp_path, monkeypatch):
    _reset_runtime()
    store = _isolated_store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)

    first = asyncio.run(game.quick_room(_join(store, 'p1')))
    room_id = first['room_id']
    state = first['state']

    assert state['quick_match'] is True
    assert state['human_count'] == 1
    assert state['phase'] == 'waiting'
    assert state['started'] is False
    assert sum(not p.bot for p in game.ROOMS[room_id].state.players.values()) == 1

    _reset_runtime()


def test_quick_match_four_humans_autostarts_same_authoritative_room(tmp_path, monkeypatch):
    _reset_runtime()
    store = _isolated_store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)

    results = [asyncio.run(game.quick_room(_join(store, f'p{i}'))) for i in range(1, 5)]
    room_ids = {row['room_id'] for row in results}
    assert len(room_ids) == 1

    room_id = results[-1]['room_id']
    room = game.ROOMS[room_id]
    final = results[-1]['state']
    assert final['human_count'] == 4
    assert final['started'] is True
    assert final['phase'] != 'waiting'
    assert all(not p.bot for p in room.state.players.values())
    assert len(game.ROOM_META[room_id]['player_ids']) == 4
    assert int(final['state_version']) > 1

    # Retried create/join requests must reuse the started match even after
    # entry fees have reduced the player's wallet.
    store._data['accounts']['p1']['chips'] = 0
    store._save()
    retry_quick = asyncio.run(game.quick_room(_join(store, 'p1')))
    retry_join = asyncio.run(game.join_room(room_id, _join(store, 'p1')))
    assert retry_quick['room_id'] == room_id and retry_quick['seat'] == results[0]['seat']
    assert retry_join['room_id'] == room_id and retry_join['seat'] == results[0]['seat']
    assert len(game.ROOMS) == 1

    _reset_runtime()
