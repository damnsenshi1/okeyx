"""Düz Okey modu: 14/15 dağıtım, bitirme kontrolü, botlu tam oyun, 106 taş korunumu."""
from app.domain.models import Color, Tile
from app.services.game_runtime import Room, duz_hand_complete, duz_finish_options


def _t(c, n, k=0):
    return Tile(f'{c.value}-{n}-{k}', c, n, False)


def test_duz_deal_is_14_and_15():
    r = Room(seed=7, variant='duz')
    counts = sorted(len(p.hand) for p in r.state.players.values())
    assert counts == [14, 14, 14, 15]
    assert r.state.variant == 'duz'
    assert r.audit_state() == []


def test_duz_complete_series_and_pairs():
    r = Room(seed=1, variant='duz')
    rules = r.service.rules
    jn = r.state.joker.joker_number
    # Okey sayısından uzak, okey/sahte okey olmayan taşlarla temiz el kur.
    def safe(n):
        return n != jn
    nums = [n for n in range(1, 14) if safe(n)]
    hand = []
    # 4+4+3+3 = 14 taş: renk serileri
    for color, start, size in ((Color.RED, 0, 4), (Color.BLUE, 0, 4), (Color.BLACK, 0, 3), (Color.YELLOW, 0, 3)):
        run = None
        for i in range(0, 13):
            cand = list(range(i + 1, i + 1 + size))
            if all(1 <= x <= 13 and safe(x) for x in cand):
                run = cand; break
        hand += [_t(color, x) for x in run]
    assert duz_hand_complete(rules, hand) == 'series'
    # Bir taşı boz -> tamamlanmamış
    broken = hand[:-1] + [_t(Color.RED, nums[-1], 1) if nums[-1] not in (1,2,3,4) else _t(Color.RED, 12, 1)]
    assert duz_hand_complete(rules, broken) is None
    # 7 çift
    pairs = []
    for n in nums[:7]:
        pairs += [_t(Color.RED, n, 0), _t(Color.RED, n, 1)]
    assert duz_hand_complete(rules, pairs) == 'pairs'
    opts = duz_finish_options(rules, pairs + [_t(Color.BLUE, nums[0], 0)])
    assert f'blue-{nums[0]}-0' in opts


def test_duz_blocks_101_actions_and_left_tile_not_mandatory():
    r = Room(seed=3, variant='duz')
    seat = r.state.current_seat
    assert r.action(seat, 'open_series', {}).code == 'not_in_duz'
    p = r.state.player(seat)
    first = p.hand[0].id
    assert r.action(seat, 'discard', {'tile_id': first}).ok
    nxt = r.state.current_seat
    assert r.action(nxt, 'take_left', {}).ok
    assert r.state.player(nxt).pending_left_tile_id is None
    # Soldan aldığı taşı hemen geri atabilir (zorunlu kullanım yok).
    assert r.action(nxt, 'discard', {'tile_id': first}).ok


def test_duz_bad_finish_rejected():
    r = Room(seed=11, variant='duz')
    seat = r.state.current_seat
    tid = r.state.player(seat).hand[0].id
    if tid not in r.duz_options(seat):
        res = r.action(seat, 'finish', {'tile_id': tid})
        assert not res.ok and res.code == 'hand_not_complete'
        assert len(r.state.player(seat).hand) == 15


def test_duz_full_bot_games_end_and_score():
    finished_by_player = 0
    for seed in range(40):
        r = Room(seed=seed, variant='duz', max_rounds=1)
        for s in range(4):
            r.state.player(s).bot = True
        guard = 0
        while r.state.phase != 'finished' and guard < 400:
            r.bot_turn(r.state.current_seat); guard += 1
            assert r.audit_state() == []
        assert r.state.phase == 'finished'
        if r.state.round_end_reason == 'finish':
            finished_by_player += 1
            w = r.state.winner_seat
            assert r.state.round_scores[w] == 0
            assert all(v >= 2 for s, v in r.state.round_scores.items() if s != w)
        else:
            assert all(v == 0 for v in r.state.round_scores.values())
        assert r.state.match_finished
    assert finished_by_player > 0


def test_duz_public_state_shape():
    r = Room(seed=5, variant='duz')
    st = r.public_state(r.state.current_seat)
    assert st['game_type'] == 'duz'
    assert 'finish' in st['available_actions']
    assert st['opening_preview_score'] == 0
