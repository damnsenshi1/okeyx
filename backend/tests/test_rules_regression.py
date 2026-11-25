from app.domain.models import Color, JokerContext, Meld, MeldType, Tile
from app.domain.rules import Rules101
from app.services.game_runtime import Room, build_tiles, find_series_groups, find_pairs
from app.services.game_service import ActionResult


def tile(i: str, color: Color, n: int) -> Tile:
    return Tile(i, color, n, False)


def rules() -> Rules101:
    # red 5 indicator => red 6 is real okey
    return Rules101(JokerContext(Color.RED, 5))


def test_physical_set_is_exactly_106_unique_tiles():
    tiles = build_tiles()
    assert len(tiles) == 106
    assert len({t.id for t in tiles}) == 106


def test_non_wrapping_run_12_13_1_is_invalid():
    r = rules()
    g = [tile('a', Color.BLUE, 12), tile('b', Color.BLUE, 13), tile('c', Color.BLUE, 1)]
    assert not r.validate_run(g).valid


def test_run_9_10_11_12_is_valid_and_canonical():
    r = rules()
    g = [tile('12', Color.BLACK, 12), tile('9', Color.BLACK, 9), tile('11', Color.BLACK, 11), tile('10', Color.BLACK, 10)]
    out = r.validate_run(g)
    assert out.valid and out.score == 42
    ordered = r.canonical_meld_order(g, MeldType.RUN)
    assert [x.number for x in ordered] == [9, 10, 11, 12]


def test_set_requires_same_number_and_unique_colors():
    r = rules()
    ok = [tile('r', Color.RED, 3), tile('b', Color.BLUE, 3), tile('k', Color.BLACK, 3)]
    bad = [tile('r1', Color.RED, 3), tile('r2', Color.RED, 3), tile('b', Color.BLUE, 3)]
    assert r.validate_set(ok).valid
    assert not r.validate_set(bad).valid


def test_pair_is_exact_same_face_or_real_okey_substitution():
    r = rules()
    exact = [tile('a', Color.YELLOW, 8), tile('b', Color.YELLOW, 8)]
    mismatch = [tile('c', Color.YELLOW, 8), tile('d', Color.BLUE, 8)]
    joker = tile('joker', Color.RED, 6)
    assert r.validate_pair(exact).valid
    assert not r.validate_pair(mismatch).valid
    assert r.validate_pair([tile('e', Color.BLUE, 10), joker]).valid


def test_room_starts_with_integrity_and_22_for_starter():
    room = Room(seed=42, random_starter=False)
    assert room.state.current_seat == 0
    assert len(room.state.player(0).hand) == 22
    assert all(len(room.state.player(s).hand) == 21 for s in (1, 2, 3))
    assert room.state.phase == 'discard'
    assert room.audit_state() == []


def test_starter_must_discard_before_drawing():
    room = Room(seed=43, random_starter=False)
    assert not room.draw(0, 'stock').ok
    first = room.state.player(0).hand[0]
    out = room.discard(0, first.id)
    assert out.ok
    assert room.state.current_seat == 1
    assert room.state.phase == 'draw'
    assert room.audit_state() == []


def test_left_take_can_be_returned_without_losing_tile():
    room = Room(seed=44, random_starter=False)
    first = room.state.player(0).hand[0]
    assert room.discard(0, first.id).ok
    before = len(room.state.discard_piles[0])
    assert room.draw(1, 'left').ok
    assert len(room.state.discard_piles[0]) == before - 1
    assert room.state.player(1).pending_left_tile_id == first.id
    assert room.return_left(1).ok
    assert len(room.state.discard_piles[0]) == before
    assert room.state.phase == 'draw'
    assert room.audit_state() == []


def test_assisted_solver_keeps_one_finish_tile():
    r = rules()
    hand = [
        tile('b9', Color.BLUE, 9), tile('b10', Color.BLUE, 10), tile('b11', Color.BLUE, 11),
        tile('k9', Color.BLACK, 9), tile('k10', Color.BLACK, 10), tile('k11', Color.BLACK, 11),
        tile('y10', Color.YELLOW, 10), tile('y11', Color.YELLOW, 11), tile('y12', Color.YELLOW, 12),
        tile('r7', Color.RED, 7),
    ]
    groups = find_series_groups(r, hand, minimum=0, max_used=len(hand)-1)
    assert groups
    assert sum(len(g) for g in groups) <= len(hand) - 1


def test_find_pairs_prefers_natural_pairs_before_joker():
    r = rules()
    joker = tile('joker', Color.RED, 6)
    hand = [tile('a', Color.BLUE, 5), tile('b', Color.BLUE, 5), tile('c', Color.YELLOW, 9), joker]
    pairs = find_pairs(r, hand)
    assert any({x.id for x in p} == {'a', 'b'} for p in pairs)


def test_layoff_inserts_run_tile_in_canonical_position():
    r = rules()
    meld = Meld('m', 0, MeldType.RUN, [tile('9', Color.BLACK, 9), tile('10', Color.BLACK, 10), tile('12', Color.BLACK, 12)])
    # The existing 9-10-12 shape itself is not a legal exposed meld. Build a
    # legal 9-10-11 and prove 12 is inserted at the right edge instead.
    meld.tiles = [tile('9', Color.BLACK, 9), tile('10', Color.BLACK, 10), tile('11', Color.BLACK, 11)]
    ok, out = r.can_layoff(meld, tile('12', Color.BLACK, 12))
    assert ok
    assert [x.number for x in out] == [9, 10, 11, 12]


def test_rejected_action_rolls_back_partial_tile_mutation():
    room = Room(seed=45, random_starter=False)
    before_ids = [t.id for t in room.state.player(0).hand]
    victim = before_ids[0]

    def broken_discard(seat: int, tile_id: str):
        # Simulate a future regression that mutates state before discovering
        # an error. Room.action must never leak the partial mutation.
        room.state.player(seat).hand = [t for t in room.state.player(seat).hand if t.id != tile_id]
        return ActionResult(False, 'synthetic_failure')

    room.discard = broken_discard  # type: ignore[method-assign]
    out = room.action(0, 'discard', {'tile_id': victim})
    assert not out.ok
    assert [t.id for t in room.state.player(0).hand] == before_ids
    assert room.audit_state() == []


def test_contextual_pair_action_only_for_pair_opening_mode():
    room = Room(seed=46, random_starter=False)
    p = room.state.player(0)
    # red 8 natural pair in hand is enough for the post-opening add-pair plan.
    p.hand = [tile('p1', Color.RED, 8), tile('p2', Color.RED, 8), tile('loose', Color.BLUE, 1)]
    p.opened = True
    p.opening_mode = 'pairs'
    room.state.current_seat = 0
    room.state.phase = 'discard'
    assert room.available_actions(0)['open_pairs'] is False
    assert room.available_actions(0)['add_pairs'] is True

    # A series opener must never receive ÇİFT AÇ just because a pair exists on
    # the table. That button would only produce wrong_opening_mode.
    p.opening_mode = 'series'
    room.state.melds = [Meld('pair-other', 1, MeldType.PAIR, [tile('a', Color.YELLOW, 4), tile('b', Color.YELLOW, 4)])]
    assert room.available_actions(0)['open_pairs'] is False
    assert room.available_actions(0)['add_pairs'] is False


def test_left_discard_obligation_blocks_processing_another_tile():
    room = Room(seed=47, random_starter=False)
    p = room.state.player(0)
    safe = next(c for c in Color if c != room.state.joker.joker_color)
    p.opened = True
    p.opening_mode = 'series'
    room.state.phase = 'discard'
    room.state.current_seat = 0
    pending = tile('pending-left', safe, 5)
    useful = tile('useful-12', safe, 12)
    finish = tile('finish', safe, 1)
    p.hand = [pending, useful, finish]
    p.pending_left_tile_id = pending.id
    p.pending_left_from_seat = 3
    meld = Meld(
        'run-safe', 1, MeldType.RUN,
        [tile('m9', safe, 9), tile('m10', safe, 10), tile('m11', safe, 11)],
    )
    room.state.melds = [meld]

    out = room.service.layoff(0, useful.id, meld.id)
    assert not out.ok and out.code == 'must_use_left_tile'
    assert [t.id for t in p.hand] == [pending.id, useful.id, finish.id]
    assert [t.number for t in meld.tiles] == [9, 10, 11]


def test_auto_layoff_never_skips_mandatory_left_tile():
    room = Room(seed=48, random_starter=False)
    p = room.state.player(0)
    safe = next(c for c in Color if c != room.state.joker.joker_color)
    p.opened = True
    p.opening_mode = 'series'
    room.state.phase = 'discard'
    room.state.current_seat = 0
    pending = tile('pending-left', safe, 5)  # cannot enter 9-10-11
    useful = tile('useful-12', safe, 12)    # could enter it, but must wait
    finish = tile('finish', safe, 1)
    p.hand = [pending, useful, finish]
    p.pending_left_tile_id = pending.id
    p.pending_left_from_seat = 3
    meld = Meld(
        'run-safe', 1, MeldType.RUN,
        [tile('m9', safe, 9), tile('m10', safe, 10), tile('m11', safe, 11)],
    )
    room.state.melds = [meld]

    out = room.service.auto_layoff(0)
    assert out.ok
    assert out.payload['processed'] == 0
    assert out.payload['left_obligation_cleared'] is False
    assert {t.id for t in p.hand} == {pending.id, useful.id, finish.id}
    assert [t.number for t in meld.tiles] == [9, 10, 11]

def test_pair_open_action_never_turns_into_pair_layoff():
    room = Room(seed=4601, random_starter=False)
    p = room.state.player(0)
    p.opened = True
    p.opening_mode = 'pairs'
    room.state.phase = 'discard'
    room.state.current_seat = 0
    p.hand = [tile('p1', Color.BLUE, 8), tile('p2', Color.BLUE, 8), tile('finish', Color.YELLOW, 2)]
    room.state.melds = [Meld('pair-lane', 0, MeldType.PAIR, [tile('a', Color.RED, 4), tile('b', Color.RED, 4)])]
    before = [x.id for x in p.hand]
    out = room.action(0, 'open_pairs', {})
    assert not out.ok and out.code == 'already_opened_use_add_pairs'
    assert [x.id for x in room.state.player(0).hand] == before


def test_unassisted_still_exposes_rule_penalty_tiles():
    room = Room(seed=4901, random_starter=False, assisted=False)
    p = room.state.player(0)
    safe = next(c for c in Color if c != room.state.joker.joker_color)
    useful = tile('risk-12', safe, 12)
    finish = tile('finish-2', Color.YELLOW, 2)
    p.hand = [useful, finish]
    p.opened = True
    p.opening_mode = 'series'
    room.state.phase = 'discard'
    room.state.current_seat = 0
    room.state.melds = [Meld('open-run', 1, MeldType.RUN, [
        tile('m9x', safe, 9), tile('m10x', safe, 10), tile('m11x', safe, 11),
    ])]
    state = room.public_state(0)
    assert useful.id in state['penalty_tile_ids']
    # Yardımsız does not expose solver hints, only the mandatory +101 warning.
    assert state['useful_tile_ids'] == []
    out = room.service.discard(0, useful.id)
    assert out.ok and out.payload['penalty'] == 101 and out.payload['useful_discard'] is True


def test_left_discard_hint_requires_real_opening_not_tiny_meld():
    room = Room(seed=4902, random_starter=False, assisted=True)
    p = room.state.player(0)
    safe = next(c for c in Color if c != room.state.joker.joker_color)
    p.opened = False
    p.opening_mode = None
    p.hand = [tile('a1x', safe, 1), tile('a2x', safe, 2), tile('junk4x', Color.YELLOW, 4), tile('junk7x', Color.BLUE, 7)]
    room.state.phase = 'draw'
    room.state.current_seat = 0
    room.state.discard_piles[3] = [tile('left3x', safe, 3)]
    state = room.public_state(0)
    # 1-2-3 is a valid little run, but it does not produce a legal 101 opening;
    # therefore the left tile must NOT shout “İŞİNE YARAR”.
    assert state['left_opening_opportunity'] is None
    assert state['left_useful_tile_id'] is None
