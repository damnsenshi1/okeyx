from app.domain.models import Color
from tests.test_rules_regression import Room, tile


def test_left_tile_glows_when_it_raises_an_already_possible_opening():
    room = Room(seed=4903, random_starter=False, assisted=True)
    j = room.state.joker.joker_color
    cs = [c for c in Color if c != j][:3]
    p = room.state.player(0)
    p.opened = False
    p.opening_mode = None
    p.hand = [tile(f'a{n}', cs[0], n) for n in (10, 11, 12, 13)] + \
             [tile(f'b{n}', cs[1], n) for n in (10, 11, 12, 13)] + \
             [tile(f'c{n}', cs[0], n) for n in (3, 4, 5)] + \
             [tile('d11', cs[2], 11), tile('d12', cs[2], 12), tile('junk1', cs[1], 1)]
    room.state.phase = 'draw'
    room.state.current_seat = 0
    room.state.discard_piles[3] = [tile('left13', cs[2], 13)]
    state = room.public_state(0)
    opp = state['left_opening_opportunity']
    assert opp and opp['improves'] is True
    assert opp['series_score'] > opp['current_series_score'] >= 101
    assert state['left_useful_tile_id'] == 'left13'
    assert 'İŞİNE YARAR' in state['left_useful_reason']
