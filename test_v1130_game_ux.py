import asyncio
from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore


def _reset():
    game.ROOMS.clear(); game.ROOM_META.clear(); game.SOCKETS.clear()


def _store(tmp_path: Path):
    store = AccountStore(tmp_path / 'accounts.json')
    for pid, name in [('host', 'Senshi'), ('yanci', 'Yancı')]:
        store.ensure(pid, name, None, None, is_guest=False)
        store._data['accounts'][pid]['chips'] = 1_000_000
    store._save()
    return store


def _live_room(tmp_path, monkeypatch):
    _reset(); store = _store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)
    host = store.get('host')
    created = game.create_room(game.CreateRoomIn(player_id='host', account_token=host['session_token'], owner_name='Senshi'))
    for seat, level in [(1, 'easy'), (2, 'medium'), (3, 'hard')]:
        asyncio.run(game.manage_room(created['room_id'], game.ManageRoomIn(seat=0, reconnect_token=created['reconnect_token'], action='add_bot', target_seat=seat, bot_level=level)))
    out = asyncio.run(game._execute_action(created['room_id'], game.ActionIn(seat=0, reconnect_token=created['reconnect_token'], kind='start_match', request_id='start-yanci')))
    assert out['ok'] is True
    return store, created


def test_yanci_state_never_exposes_any_rack(tmp_path, monkeypatch):
    store, created = _live_room(tmp_path, monkeypatch)
    yanci = store.get('yanci')
    out = asyncio.run(game.spectate_room(created['room_id'], game.SpectatorIn(player_id='yanci', account_token=yanci['session_token'], action='join')))
    state = out['state']
    assert state['viewer_seat'] == -1
    assert 'available_actions' not in state
    assert all(player['hand'] == [] for player in state['players'])
    assert game.list_live_tables()['tables'][0]['room_id'] == created['room_id']


def test_yanci_totem_and_prediction_are_non_wager_social_actions(tmp_path, monkeypatch):
    store, created = _live_room(tmp_path, monkeypatch)
    yanci = store.get('yanci'); before = yanci['chips']
    asyncio.run(game.spectate_room(created['room_id'], game.SpectatorIn(player_id='yanci', account_token=yanci['session_token'], action='join')))
    tea = asyncio.run(game.spectate_room(created['room_id'], game.SpectatorIn(player_id='yanci', account_token=yanci['session_token'], action='react', value='tea', to_seat=0)))
    assert tea['ok'] is True and tea['event']['value'] == 'Çay'
    # Totem/reaction is social UX, not a wager. It must not mutate match odds or
    # silently siphon the spectator wallet.
    assert store.get('yanci')['chips'] == before
    pred = asyncio.run(game.spectate_room(created['room_id'], game.SpectatorIn(player_id='yanci', account_token=yanci['session_token'], action='predict', value='winner:0')))
    assert pred['ok'] is True
    assert pred['state']['spectator_prediction']['value'] == 'winner:0'
