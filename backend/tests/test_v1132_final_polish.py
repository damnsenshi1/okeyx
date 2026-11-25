import asyncio
from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore


def _reset():
    game.ROOMS.clear(); game.ROOM_META.clear(); game.SOCKETS.clear()


def _store(tmp_path: Path):
    store = AccountStore(tmp_path / 'accounts.json')
    for pid in ('host', 'p2'):
        store.ensure(pid, pid, None, None, is_guest=False)
        store._data['accounts'][pid]['chips'] = 1_000_000
    store._save()
    return store


def test_adding_three_bots_never_starts_private_room(tmp_path, monkeypatch):
    _reset(); store = _store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)
    host = store.get('host')
    created = game.create_room(game.CreateRoomIn(player_id='host', account_token=host['session_token'], owner_name='host'))
    for seat, level in ((1, 'easy'), (2, 'medium'), (3, 'hard')):
        out = asyncio.run(game.manage_room(created['room_id'], game.ManageRoomIn(seat=0, reconnect_token=created['reconnect_token'], action='add_bot', target_seat=seat, bot_level=level)))
        assert out['ok'] is True
        assert game.ROOMS[created['room_id']].state.phase == 'waiting'
        assert game.ROOMS[created['room_id']].state.started is False
    # Host explicitly starts only after deciding to do so.
    out = asyncio.run(game._execute_action(created['room_id'], game.ActionIn(seat=0, reconnect_token=created['reconnect_token'], kind='start_match', request_id='manual-start')))
    assert out['ok'] is True


def test_every_client_emoji_pack_value_is_accepted(tmp_path, monkeypatch):
    _reset(); store = _store(tmp_path)
    monkeypatch.setattr(game, 'STORE', store)
    monkeypatch.setattr(game, '_persist_runtime', lambda force=False: None)
    host = store.get('host')
    created = game.create_room(game.CreateRoomIn(player_id='host', account_token=host['session_token'], owner_name='host'))
    values = ['🎉','🕺','💃','✨','🏆','☕','🫖','🧿','😄','🪑','🤡','😏','🙃','👀','🫠','🧂','🐔','🩴','💜','💙','🩵','⚡','🌌','🎵']
    for value in values:
        # avoid chat cooldown in unit test by resetting the per-token clock
        game.ROOM_META[created['room_id']]['chat_times'] = {}
        out = asyncio.run(game.table_chat(created['room_id'], game.ChatIn(seat=0, reconnect_token=created['reconnect_token'], kind='emoji', value=value)))
        assert out['ok'] is True, value
