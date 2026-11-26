"""Aşama 1: 101 kural motoru için bağımsız doğrulayıcı (oracle) ile rastgele sınama.

Oracle motorun kodunu kullanmaz; taşları kendi tanımıyla yorumlar:
- gerçek okey joker, sahte okey gerçek okeyin yüzüdür (joker DEĞİL)
- seri 1..13 içinde ardışık, 13'ten 1'e dönmez (12-13-1 geçersiz)
- per: aynı sayı, farklı renkler, 3 ya da 4 taş
"""
from __future__ import annotations

import random

import pytest

from app.domain.models import Color, JokerContext, Meld, MeldType, Tile
from app.domain.rules import Rules101
from app.services.game_runtime import Room, build_tiles

COLORS = list(Color)


def okey_face(ind_color: Color, ind_number: int) -> tuple[Color, int]:
    return ind_color, (1 if ind_number == 13 else ind_number + 1)


def classify(t: Tile, face):
    """('joker',) | ('tile', color, number)"""
    if t.fake_joker:
        return ('tile', face[0], face[1])
    if (t.color, t.number) == face:
        return ('joker',)
    return ('tile', t.color, t.number)


def oracle_run(tiles, face):
    n = len(tiles)
    kinds = [classify(t, face) for t in tiles]
    nat = [k for k in kinds if k[0] == 'tile']
    jokers = n - len(nat)
    if n < 3 or not nat:
        return None
    if len({k[1] for k in nat}) != 1:
        return None
    nums = [k[2] for k in nat]
    if len(set(nums)) != len(nums):
        return None
    best = None
    for start in range(1, 13 - n + 2):  # pencere 1..13 içinde kalmalı
        window = list(range(start, start + n))
        if all(x in window for x in nums) and len(window) - len(nums) == jokers:
            s = sum(window)
            best = s if best is None else max(best, s)
    return best


def oracle_set(tiles, face):
    n = len(tiles)
    kinds = [classify(t, face) for t in tiles]
    nat = [k for k in kinds if k[0] == 'tile']
    if n not in (3, 4) or not nat:
        return None
    if len({k[2] for k in nat}) != 1:
        return None
    if len({k[1] for k in nat}) != len(nat):
        return None
    return nat[0][2] * n


def random_tiles(rng, k):
    return rng.sample(build_tiles(), k)


def test_run_and_set_validation_match_independent_oracle():
    rng = random.Random(20260826)
    checked = valid_runs = valid_sets = 0
    for _ in range(40000):
        ind_c, ind_n = rng.choice(COLORS), rng.randint(1, 13)
        face = okey_face(ind_c, ind_n)
        rules = Rules101(JokerContext(ind_c, ind_n))
        # Geçerli grup üretme ihtimalini artır: bazen tek renk ardışık / tek sayı seç.
        pool = build_tiles()
        mode = rng.random()
        if mode < .35:
            c = rng.choice(COLORS); s = rng.randint(1, 10); L = rng.randint(3, min(5, 14 - s))
            tiles = [t for t in pool if t.color == c and t.number in range(s, s + L)]
            rng.shuffle(tiles)
            tiles = list({t.number: t for t in tiles}.values())
            tiles += rng.sample([t for t in pool if t.fake_joker or (t.color, t.number) == face], rng.randint(0, 2))
        elif mode < .6:
            n = rng.randint(1, 13)
            tiles = [t for t in pool if t.number == n]
            tiles = rng.sample(tiles, rng.randint(2, min(5, len(tiles))))
            tiles += rng.sample([t for t in pool if t.fake_joker or (t.color, t.number) == face], rng.randint(0, 1))
        else:
            tiles = rng.sample(pool, rng.randint(3, 5))
        tiles = list({t.id: t for t in tiles}.values())
        if len(tiles) < 3:
            continue
        got_run = rules.validate_run(tiles)
        exp_run = oracle_run(tiles, face)
        assert got_run.valid == (exp_run is not None), (face, [(t.id) for t in tiles], got_run, exp_run)
        if exp_run is not None:
            assert got_run.score == exp_run
            valid_runs += 1
        got_set = rules.validate_set(tiles)
        exp_set = oracle_set(tiles, face)
        assert got_set.valid == (exp_set is not None), (face, [(t.id) for t in tiles], got_set, exp_set)
        if exp_set is not None:
            assert got_set.score == exp_set
            valid_sets += 1
        checked += 1
    # Oracle gerçekten geçerli örnekleri de görmüş olmalı (boş test olmasın).
    assert checked > 20000 and valid_runs > 500 and valid_sets > 500


@pytest.mark.parametrize('ind_number,expected', [(5, 6), (12, 13), (13, 1), (1, 2)])
def test_okey_is_indicator_plus_one_same_color_and_wraps_13_to_1(ind_number, expected):
    j = JokerContext(Color.BLUE, ind_number)
    assert (j.joker_color, j.joker_number) == (Color.BLUE, expected)
    real = Tile('r', Color.BLUE, expected, False)
    other_color = Tile('o', Color.RED, expected, False)
    fake = Tile('f', None, None, True)
    assert j.is_real_joker(real)
    assert not j.is_real_joker(other_color)
    assert not j.is_real_joker(fake)
    n = j.normalized(fake)
    assert (n.color, n.number) == (Color.BLUE, expected) and not n.fake_joker


def test_fake_okey_is_not_a_wildcard():
    rules = Rules101(JokerContext(Color.RED, 5))  # okey = kırmızı 6, sahte = kırmızı 6 yüzü
    fake = Tile('fake-0', None, None, True)
    # Sahte okey yalnızca kırmızı 6 yerine geçer: kırmızı 5-[sahte]-7 geçerli, kırmızı 5-[sahte]-8 geçersiz.
    ok = [Tile('a', Color.RED, 5, False), fake, Tile('b', Color.RED, 7, False)]
    bad = [Tile('a', Color.RED, 5, False), fake, Tile('b', Color.RED, 8, False)]
    assert rules.validate_run(ok).valid
    assert not rules.validate_run(bad).valid


def test_1_is_low_only_and_runs_do_not_wrap():
    rules = Rules101(JokerContext(Color.RED, 9))
    def run(*ns):
        return [Tile(f'b{n}', Color.BLUE, n, False) for n in ns]
    assert rules.validate_run(run(1, 2, 3)).valid
    assert rules.validate_run(run(11, 12, 13)).valid
    assert not rules.validate_run(run(12, 13, 1)).valid
    assert not rules.validate_run(run(13, 1, 2)).valid
    # Okey ile de dönülemez: 12-13-[okey] 14 olamaz, ama 11-12-13 olarak yerleşir.
    joker = Tile('rj', Color.RED, 10, False)  # gösterge kırmızı 9 -> okey kırmızı 10
    assert rules.validate_run([Tile('b12', Color.BLUE, 12, False), Tile('b13', Color.BLUE, 13, False), joker]).score == 36


def test_layoff_cannot_wrap_or_duplicate():
    rules = Rules101(JokerContext(Color.RED, 9))
    meld = Meld('m1', 0, MeldType.RUN, [Tile(f'b{n}', Color.BLUE, n, False) for n in (11, 12, 13)])
    assert not rules.can_layoff(meld, Tile('x1', Color.BLUE, 1, False))[0]
    assert rules.can_layoff(meld, Tile('x10', Color.BLUE, 10, False))[0]
    low = Meld('m2', 0, MeldType.RUN, [Tile(f'k{n}', Color.BLACK, n, False) for n in (1, 2, 3)])
    assert rules.can_layoff(low, Tile('k4', Color.BLACK, 4, False))[0]
    assert not rules.can_layoff(low, Tile('k13', Color.BLACK, 13, False))[0]
    group = Meld('m3', 0, MeldType.SET, [Tile('a', Color.RED, 7, False), Tile('b', Color.BLUE, 7, False), Tile('c', Color.BLACK, 7, False)])
    assert rules.can_layoff(group, Tile('d', Color.YELLOW, 7, False))[0]
    assert not rules.can_layoff(group, Tile('e', Color.RED, 7, False))[0]  # aynı renk tekrar olmaz


def test_opening_thresholds_exactly_101_and_five_pairs():
    rules = Rules101(JokerContext(Color.RED, 2))  # okey kırmızı 3
    g1 = [Tile(f'b{n}', Color.BLUE, n, False) for n in (10, 11, 12, 13)]  # 46
    g2 = [Tile(f'k{n}', Color.BLACK, n, False) for n in (9, 10, 11, 12)]   # 42
    g3 = [Tile('y13', Color.YELLOW, 13, False), Tile('b13x', Color.BLUE, 13, False), Tile('k13', Color.BLACK, 13, False)]  # 39
    total = rules.validate_series_opening([g1, g2, g3])
    assert total.score == 127 and total.valid
    assert rules.validate_series_opening([g1, g2]).score == 88 and not rules.validate_series_opening([g1, g2]).valid
    exact = [[Tile(f'b{n}', Color.BLUE, n, False) for n in (10, 11, 12, 13)],
             [Tile(f'k{n}', Color.BLACK, n, False) for n in (9, 10, 11, 12)],
             [Tile('y9', Color.YELLOW, 4, False), Tile('r9', Color.RED, 4, False), Tile('b9', Color.BLUE, 4, False)]]
    assert rules.validate_series_opening(exact).score == 100 and not rules.validate_series_opening(exact).valid
    pair = lambda i, c, n: [Tile(f'{i}a', c, n, False), Tile(f'{i}b', c, n, False)]
    five = [pair(i, Color.BLUE, i + 1) for i in range(5)]
    assert rules.validate_pair_opening(five).valid
    assert not rules.validate_pair_opening(five[:4]).valid
    mismatched = five[:4] + [[Tile('p', Color.BLUE, 9, False), Tile('q', Color.RED, 9, False)]]
    assert not rules.validate_pair_opening(mismatched).valid


def test_deal_integrity_over_many_random_deals():
    for seed in range(300):
        room = Room(seed=seed, random_starter=(seed % 2 == 0))
        st = room.state
        ids = [t.id for p in st.players.values() for t in p.hand] + [t.id for t in st.stock] + [st.indicator.id]
        assert len(ids) == 106 and len(set(ids)) == 106, seed
        sizes = sorted(len(p.hand) for p in st.players.values())
        assert sizes == [21, 21, 21, 22], seed
        assert len(st.stock) == 20, seed
        assert st.indicator is not None and not st.indicator.fake_joker
        assert len(st.players[st.starter_seat].hand) == 22
        j = st.joker
        reals = [t for t in build_tiles() if j.is_real_joker(t)]
        assert len(reals) == 2
        assert sum(1 for t in build_tiles() if t.fake_joker) == 2


def test_production_shuffle_is_not_seeded_and_varies():
    seen = set()
    for _ in range(25):
        room = Room(seed=None)
        seen.add(tuple(t.id for t in room.state.players[0].hand))
    assert len(seen) > 20  # tahmin edilebilir (sabit tohumlu) dağıtım yok


def test_shuffle_is_roughly_uniform_for_first_hand_tile_color():
    counts = {c: 0 for c in COLORS}
    n = 0
    for seed in range(1500):
        room = Room(seed=seed)
        for t in room.state.players[0].hand:
            if t.color:
                counts[t.color] += 1; n += 1
    for c, v in counts.items():
        assert abs(v / n - .25) < .02, (c, v / n)
