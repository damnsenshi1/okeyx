from app.domain.models import Meld, MeldType, Tile, Color
from app.services.game_runtime import Room


def T(i, n, c):
    return Tile(f't{i}', c, n)


def test_series_opening_allowed_when_left_tile_goes_to_pairs_same_turn():
    r = Room(1, 'non_fold', waiting=False)
    r.audit_state = lambda: []  # test elini elle kuruyoruz; 106 taş sayımı dışı
    s = r.state
    s.current_seat = 0; s.phase = 'discard'; s.started = True
    s.melds = [Meld('3-pair-0', 3, MeldType.PAIR, [T(900, 11, Color.YELLOW), T(901, 11, Color.YELLOW)])]
    s.player(3).opened = True; s.player(3).opening_mode = 'pairs'
    R, Y, B, K = Color.RED, Color.YELLOW, Color.BLUE, Color.BLACK
    hand = [T(1, 10, R), T(2, 11, R), T(3, 12, R), T(4, 13, R),
            T(5, 8, Y), T(6, 9, Y), T(7, 10, Y),
            T(8, 7, B), T(9, 8, B), T(10, 9, B),
            T(11, 4, R), T(12, 4, Y), T(13, 4, K),
            T(14, 9, K), T(15, 9, K), T(16, 1, R), T(17, 3, R)]
    p = s.player(0); p.hand = hand; p.opened = False
    p.pending_left_tile_id = 't15'; p.pending_left_from_seat = 3
    acts = r.available_actions(0)
    assert acts['open_series'] is True
    out = r.action(0, 'open_series', {})
    assert out.ok, out.code
    assert p.pending_left_tile_id == 't15'
    # Siyah 9 çifti çift alanına eklenir, ardından taş atılabilir.
    out2 = r.action(0, 'add_pairs', {})
    assert out2.ok, out2.code
    assert p.pending_left_tile_id is None
