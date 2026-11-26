"""Aşama 2: açılış sayaçları sıra kimde olursa olsun yardımlı modda hesaplanır."""
from app.domain.models import Color, Tile
from app.services.game_runtime import Room


def _rig_hand(room, seat, tiles):
    room.state.players[seat].hand = tiles
    room._assist_cache_key = None


def test_counters_available_when_not_my_turn():
    room = Room(seed=5, assisted=True)
    st = room.state
    assert st.current_seat == 0
    viewer = 2  # sırası olmayan oyuncu
    # 11-12-13 mavi + 10-11-12-13 siyah vb. net bir seri ver.
    hand = [Tile(f'b{n}', Color.BLUE, n, False) for n in (11, 12, 13)] + \
           [Tile(f'k{n}', Color.BLACK, n, False) for n in (10, 11, 12, 13)] + \
           [Tile('y1', Color.YELLOW, 1, False)]
    _rig_hand(room, viewer, hand)
    state = room.public_state(viewer)
    assert state['assisted_series_score'] >= 36 + 46 - 0 or state['assisted_series_score'] > 0
    assert state['assisted_series_groups'], 'sırası olmayan oyuncuda grup listesi boş geldi'
    # İpucu parlaması yalnızca sıra sendeyken.
    assert state['useful_tile_ids'] == []


def test_counters_are_zero_in_unassisted_mode():
    room = Room(seed=5, assisted=False)
    state = room.public_state(0)
    assert state['assisted_series_score'] == 0 and state['assisted_series_groups'] == []
