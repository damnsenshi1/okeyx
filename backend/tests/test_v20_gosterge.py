from app.services.game_runtime import Room
from app.domain.models import Tile


def test_show_indicator_in_classic():
    r = Room(seed=5, variant='duz', random_starter=False)
    r.start_match(0)
    s = r.state
    seat = s.current_seat
    ind = s.indicator
    p = s.player(seat)
    p.hand[0] = Tile('ind-copy', ind.color, ind.number)
    assert r.available_actions(seat)['show_indicator'] is True
    out = r.action(seat, 'show_indicator', {})
    assert out.ok, out.code
    assert r.available_actions(seat)['show_indicator'] is False
    assert r.action(seat, 'show_indicator', {}).ok is False
