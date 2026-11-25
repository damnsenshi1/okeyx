from __future__ import annotations

import asyncio
from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore, GIFT_CATALOG


def _store(tmp_path: Path) -> AccountStore:
    return AccountStore(tmp_path / 'accounts.json')


def _reset_runtime() -> None:
    game.ROOMS.clear()
    game.ROOM_META.clear()
    game.SOCKETS.clear()


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


def test_v11_social_gift_catalog_is_clean_and_table_safe():
    visible = {key: row for key, row in GIFT_CATALOG.items() if not row.get('hidden')}
    assert {'tea','coffee','nazar','rose','simit','cake','trophy','fireworks','censored_banana','money_rain','rocket','dragon'} <= set(visible)
    assert visible['tea']['cost'] == 0
    assert all(row['cost'] >= 0 for row in visible.values())
    assert all(row['cost'] == 0 for row in visible.values())


def test_v1127_table_gifts_are_free_and_target_whole_table(tmp_path, monkeypatch):
    _reset_runtime()
    store = _store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)

    joined = asyncio.run(game.quick_room(_join(store, 'p1')))
    room_id = joined['room_id']
    seat = joined['seat']
    token = joined['reconnect_token']
    before = store.get('p1')['chips']

    result = asyncio.run(
        game.table_chat(
            room_id,
            game.ChatIn(seat=seat, reconnect_token=token, kind='gift', value='tea', to_seat=-1),
        )
    )

    assert result['ok'] is True
    assert result['event']['to_seat'] == -1
    assert result['event']['value'] == 'Çay'
    assert store.get('p1')['chips'] == before
    assert store.get('p1').get('gifts_received', []) == []
    _reset_runtime()
