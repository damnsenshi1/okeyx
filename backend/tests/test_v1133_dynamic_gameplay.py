from pathlib import Path

from app.domain.models import Color, JokerContext, Tile
from app.services.account_store import AccountStore
from app.services.game_runtime import Room
from app.services.game_service import GameService


def _tile(i: str, color: Color, n: int) -> Tile:
    return Tile(i, color, n, False)


def test_remaining_tile_count_and_points_are_distinct_and_round_totals_accumulate():
    room = Room(seed=1133, random_starter=False, max_rounds=3)
    room.state.joker = JokerContext(Color.RED, 13); room.service = GameService(room.state)

    # A player who opened and ends the hand with one 9 must score exactly 9;
    # the UI must never confuse that with a tile count or an unrelated sum.
    p = room.state.player(0)
    p.opened = True
    p.opening_mode = 'series'
    p.hand = [_tile('remain-9', Color.BLUE, 9)]
    room._finish_stock()
    b1 = room.state.round_breakdown[0]
    assert b1['remaining_tile_count'] == 1
    assert b1['remaining_points'] == 9
    assert room.state.round_scores[0] == 9
    assert room.state.total_scores[0] == 9

    assert room.new_hand().ok
    room.state.joker = JokerContext(Color.RED, 13); room.service = GameService(room.state)
    p = room.state.player(0)
    p.opened = True
    p.opening_mode = 'series'
    p.hand = [_tile('remain-7', Color.BLACK, 7)]
    room._finish_stock()
    assert room.state.round_breakdown[0]['remaining_tile_count'] == 1
    assert room.state.round_breakdown[0]['remaining_points'] == 7
    assert room.state.total_scores[0] == 16

    assert room.new_hand().ok
    room.state.joker = JokerContext(Color.RED, 13); room.service = GameService(room.state)
    p = room.state.player(0)
    p.opened = True
    p.opening_mode = 'series'
    p.hand = [_tile('remain-5', Color.YELLOW, 5)]
    room._finish_stock()
    assert room.state.round_breakdown[0]['remaining_tile_count'] == 1
    assert room.state.round_breakdown[0]['remaining_points'] == 5
    assert room.state.total_scores[0] == 21
    assert room.state.match_finished is True


def test_pending_left_preview_explains_before_and_after_score_and_requires_left_tile():
    room = Room(seed=31337, random_starter=False)
    room.state.started = True
    room.state.phase = 'discard'
    room.state.current_seat = 0
    # Pin joker context away from this hand so the preview is deterministic.
    room.state.joker = JokerContext(Color.RED, 5)
    room.service = GameService(room.state)

    p = room.state.player(0)
    p.opened = False
    p.hand = [
        _tile('b9', Color.BLUE, 9), _tile('b10', Color.BLUE, 10), _tile('b11', Color.BLUE, 11),
        _tile('k9', Color.BLACK, 9), _tile('k10', Color.BLACK, 10), _tile('k11', Color.BLACK, 11),
        _tile('y10', Color.YELLOW, 10), _tile('y11', Color.YELLOW, 11), _tile('y12', Color.YELLOW, 12),
        _tile('left-y13', Color.YELLOW, 13),
        _tile('finish', Color.RED, 1),
    ]
    p.pending_left_tile_id = 'left-y13'
    p.pending_left_from_seat = 3

    preview = room.pending_left_opening_preview(0)
    assert preview is not None
    assert preview['must_use'] is True
    assert preview['tile_id'] == 'left-y13'
    assert preview['before_series_score'] < room.state.min_opening_score
    assert preview['with_left_series_score'] >= room.state.min_opening_score
    assert preview['can_open'] is True
    assert preview['with_left_series_score'] > preview['before_series_score']


def test_friend_coin_transfer_is_atomic_and_notifies_receiver(tmp_path: Path):
    store = AccountStore(tmp_path / 'accounts.json')
    store.ensure('alice', 'Alice', None, None, is_guest=False)
    store.ensure('bob', 'Bob', None, None, is_guest=False)
    store._data['accounts']['alice']['chips'] = 3_000_000
    store._data['accounts']['bob']['chips'] = 100_000
    store._data['accounts']['alice']['friends'] = ['bob']
    store._data['accounts']['bob']['friends'] = ['alice']
    store._save()

    out = store.transfer_coins('alice', 'bob', 500_000)
    assert out['ok'] is True
    assert out['sender_chips'] == 2_500_000
    assert out['receiver_chips'] == 600_000
    assert out['remaining_today'] == 4_500_000
    bob = store.get('bob')
    assert bob is not None
    assert bob['notifications'][0]['kind'] == 'social_transfer'
    assert bob['notifications'][0]['data']['amount'] == 500_000

    # Non-friends cannot use the transfer endpoint as a generic economy faucet.
    store.ensure('charlie', 'Charlie', None, None, is_guest=False)
    rejected = store.transfer_coins('alice', 'charlie', 10_000)
    assert rejected['ok'] is False
    assert rejected['code'] == 'friends_only'
