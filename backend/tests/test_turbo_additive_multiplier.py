from app.domain.models import Color, Meld, MeldType, Tile
from app.services.game_runtime import Room


def test_turbo_multiplier_is_additive_and_counts_all_indicator_plus_one_colours_once():
    room = Room(seed=741, turbo=True)
    number = room.state.joker.joker_number
    stars = [Tile(f'star-{i}', color, number) for i, color in enumerate((Color.RED, Color.BLUE, Color.BLACK, Color.YELLOW))]
    fake = Tile('fake-okey-star', None, None, True)
    room.state.melds = [
        Meld('series', 0, MeldType.RUN, stars[:3]),
        Meld('pairs', 1, MeldType.PAIR, [stars[3], fake]),
    ]
    room.recalculate_turbo()
    assert room.state.turbo_stars_on_table == 5
    assert room.state.multiplier == 6  # x1 base + 5 unique star tiles

    room.state.melds.append(Meld('duplicate', 2, MeldType.PAIR, [stars[0]]))
    room.recalculate_turbo()
    assert room.state.turbo_stars_on_table == 5
    assert room.state.multiplier == 6


def test_non_turbo_table_keeps_multiplier_at_one():
    room = Room(seed=742, turbo=False)
    room.state.multiplier = 16
    room.recalculate_turbo()
    assert room.state.turbo_stars_on_table == 0
    assert room.state.multiplier == 1
