import asyncio

from app.api import game as G
from app.services.account_store import AccountStore


def _reset():
    G.ROOMS.clear()
    G.ROOM_META.clear()
    G.SOCKETS.clear()
    G.QUICK_FILL_TASKS.clear()


def _new_account(store, player_id):
    account = store.ensure(player_id, 'Senshi', None, None, is_guest=True)
    return account['session_token']


def _add_bot(room_id, seat, token, level='hard', host_seat=0):
    return asyncio.run(G.manage_room(
        room_id,
        G.ManageRoomIn(
            seat=host_seat,
            reconnect_token=token,
            action='add_bot',
            target_seat=seat,
            bot_level=level,
        ),
    ))


def test_quick_match_host_can_start_with_explicit_bot_seats(tmp_path, monkeypatch):
    _reset()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    monkeypatch.setattr(G, '_broadcast', lambda _room_id, **_kwargs: asyncio.sleep(0))

    _new_account(store, 'v15-quick-host')
    room = G.new_room(room_name='Hızlı bot masası', waiting=True, entry_fee=0)
    room_id = room.state.room_id
    meta = G._ensure_meta(room_id)
    meta['quick_match'] = True
    token = G._bind_human(room_id, 0, 'v15-quick-host', 'Senshi')

    for seat, level in ((1, 'easy'), (2, 'medium'), (3, 'hard')):
        _add_bot(room_id, seat, token, level)

    state = G._state(room_id, 0)
    assert state['human_count'] == 1
    assert state['bot_count'] == 3
    assert state['occupied_count'] == 4

    result = asyncio.run(G._execute_action(
        room_id,
        G.ActionIn(seat=0, kind='start_match', reconnect_token=token, request_id='start-v15'),
    ))

    assert result['ok'] is True
    assert room.state.started is True
    assert room.state.phase != 'waiting'
    assert room.state.players[1].bot_level == 'easy'
    assert room.state.players[2].bot_level == 'medium'
    assert room.state.players[3].bot_level == 'hard'
    _reset()


def test_quick_match_does_not_start_until_all_human_or_explicit_bot_seats_are_full(tmp_path, monkeypatch):
    _reset()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    monkeypatch.setattr(G, '_broadcast', lambda _room_id, **_kwargs: asyncio.sleep(0))

    _new_account(store, 'v15-quick-partial')
    room = G.new_room(room_name='Eksik hızlı masa', waiting=True, entry_fee=0)
    room_id = room.state.room_id
    G._ensure_meta(room_id)['quick_match'] = True
    token = G._bind_human(room_id, 0, 'v15-quick-partial', 'Senshi')
    _add_bot(room_id, 1, token, 'hard')

    result = asyncio.run(G._execute_action(
        room_id,
        G.ActionIn(seat=0, kind='start_match', reconnect_token=token, request_id='start-partial-v15'),
    ))

    assert result['ok'] is False
    assert result['code'] == 'quick_match_waiting_for_players'
    assert result['payload']['occupied'] == 2
    assert result['state']['phase'] == 'waiting'
    _reset()


def test_nonzero_owner_can_start_private_room_with_full_bot_table(tmp_path, monkeypatch):
    _reset()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    monkeypatch.setattr(G, '_broadcast', lambda _room_id, **_kwargs: asyncio.sleep(0))

    _new_account(store, 'v15-owner-seat-one')
    room = G.new_room(room_name='Host koltuk 2', waiting=True, entry_fee=0)
    room_id = room.state.room_id
    meta = G._ensure_meta(room_id)
    meta['owner_seat'] = 1
    token = G._bind_human(room_id, 1, 'v15-owner-seat-one', 'Senshi')
    for seat in (0, 2, 3):
        _add_bot(room_id, seat, token, 'medium', host_seat=1)

    result = asyncio.run(G._execute_action(
        room_id,
        G.ActionIn(seat=1, kind='start_match', reconnect_token=token, request_id='start-host-one-v15'),
    ))

    assert result['ok'] is True
    assert room.state.started is True
    _reset()


def test_occupied_count_keeps_afk_human_seat_occupied(tmp_path, monkeypatch):
    _reset()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    _new_account(store, 'v15-afk-seat')
    room = G.new_room(room_name='AFK koltuk', waiting=True, entry_fee=0)
    room_id = room.state.room_id
    token = G._bind_human(room_id, 0, 'v15-afk-seat', 'Senshi')
    # Disconnect takeover changes the runtime player to a bot, but this is
    # still the same occupied human seat and must not free a fifth place.
    room.state.player(0).bot = True
    room.state.player(0).user_id = 'bot-seat-0'
    assert G._human_count(room_id) == 0
    assert G._occupied_count(room_id) == 1
    _reset()


def test_quick_match_non_host_cannot_start_bot_filled_room(tmp_path, monkeypatch):
    _reset()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    monkeypatch.setattr(G, '_broadcast', lambda _room_id, **_kwargs: asyncio.sleep(0))
    _new_account(store, 'v15-owner')
    _new_account(store, 'v15-guest')
    room = G.new_room(room_name='Host kontrolü', waiting=True, entry_fee=0)
    room_id = room.state.room_id
    G._ensure_meta(room_id)['quick_match'] = True
    owner_token = G._bind_human(room_id, 0, 'v15-owner', 'Owner')
    guest_token = G._bind_human(room_id, 1, 'v15-guest', 'Guest')
    _add_bot(room_id, 2, owner_token, 'easy')
    _add_bot(room_id, 3, owner_token, 'hard')
    result = asyncio.run(G._execute_action(
        room_id,
        G.ActionIn(seat=1, kind='start_match', reconnect_token=guest_token, request_id='guest-start-v15'),
    ))
    assert result['ok'] is False
    assert result['code'] == 'host_only'
    assert room.state.started is False
    _reset()


def test_quick_fill_preserves_manual_bot_levels_and_fills_only_empty_seats(tmp_path, monkeypatch):
    _reset()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    _new_account(store, 'v15-mixed-fill')
    room = G.new_room(room_name='Karışık bot', waiting=True, entry_fee=0)
    room_id = room.state.room_id
    G._ensure_meta(room_id)['quick_match'] = True
    token = G._bind_human(room_id, 0, 'v15-mixed-fill', 'Senshi')
    _add_bot(room_id, 1, token, 'hard')
    assert G._fill_bots_and_start(room_id, 'easy') is True
    assert room.state.started is True
    assert room.state.player(1).bot_level == 'hard'
    assert room.state.player(2).bot_level == 'easy'
    assert room.state.player(3).bot_level == 'easy'
    assert G._occupied_count(room_id) == 4
    _reset()
