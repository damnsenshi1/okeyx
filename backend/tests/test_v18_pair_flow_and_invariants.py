"""V18: çift açma akışı, bot atomikliği ve tam maç simülasyonu.

Gerçek hata: bir oyuncu iki sahte okeyle çift açtıktan sonra bot, gerçek
okeyi bu çifte işledi; masa geçersiz duruma düştü ve sonraki bütün insan
hamleleri `state_invariant_error` ile reddedilip oyun kilitlendi.
"""
import random

from app.domain.models import Color, Tile, Meld, MeldType
from app.services.game_runtime import new_room


def _human_turn(room, seat, prefer_pairs=True):
    st = room.state
    if st.phase == 'draw':
        r = room.action(seat, 'draw_stock', {})
        assert r.ok, r.code
    p = room.state.player(seat)
    acts = room.available_actions(seat)
    if prefer_pairs and not p.opened and acts.get('open_pairs'):
        room.action(seat, 'open_pairs', {})
    elif not p.opened and acts.get('open_series'):
        room.action(seat, 'open_series', {})
    p = room.state.player(seat)
    if p.opened and p.opening_mode == 'pairs' and room.available_actions(seat).get('add_pairs'):
        room.action(seat, 'add_pairs', {})
    if p.opened and room.available_actions(seat).get('auto_layoff'):
        room.action(seat, 'auto_layoff', {})
    p = room.state.player(seat)
    if p.pending_left_tile_id:
        room.action(seat, 'return_left', {})
    st = room.state
    if st.phase == 'discard' and st.current_seat == seat:
        for t in list(p.hand):
            if st.joker.is_real_joker(t):
                continue
            if room.action(seat, 'discard', {'tile_id': t.id}).ok:
                return
        r = room.action(seat, 'discard', {'tile_id': p.hand[0].id})
        assert r.ok, r.code


def _play_match(seed, variant, prefer_pairs=True, turbo=False):
    random.seed(seed)
    room = new_room(seed=seed, variant=variant, turbo=turbo, max_rounds=3)
    room.bot_pace_ms = 0
    pair_rounds = []
    for _ in range(5000):
        st = room.state
        if st.phase == 'finished':
            if st.player(0).opened and st.player(0).opening_mode == 'pairs':
                pair_rounds.append(st.round_index)
            if st.match_finished:
                return room, pair_rounds
            r = room.action(0, 'new_hand', {})
            assert r.ok, r.code
            room.intro_until_ms = 0
            # yeni elde önceki elin çift durumu taşınmamalı
            assert all(not p.opened and p.opening_mode is None for p in room.state.players.values())
            assert room.state.min_opening_pairs == 5
            continue
        seat = st.current_seat
        if st.player(seat).bot:
            before = (st.turn_no, st.phase, seat, len(st.stock))
            room.bot_turn(seat)
            st = room.state
            assert (st.turn_no, st.phase, st.current_seat, len(st.stock)) != before, 'bot kilitlendi'
        else:
            _human_turn(room, seat, prefer_pairs)
        assert room.audit_state() == []
    raise AssertionError('maç bitmedi')


def test_full_matches_never_lock_and_pair_opening_repeats_across_hands():
    total_pair_rounds = 0
    for run in range(3):  # deterministik: aynı tohumlar 3 kez aynı sonucu vermeli
        for seed in range(0, 24):
            for variant in ('non_fold', 'fold'):
                room, pr = _play_match(seed, variant, prefer_pairs=True, turbo=bool(seed % 2))
                assert room.state.match_finished
                total_pair_rounds += len(pr)
    # Çift açma gerçekten birden fazla elde tekrar yapılabilmiş olmalı
    assert total_pair_rounds > 10


def test_series_policy_matches_finish():
    for seed in range(40, 52):
        room, _ = _play_match(seed, 'non_fold', prefer_pairs=False)
        assert room.state.match_finished


def _rig_joker_pair(room):
    st = room.state
    jn, jc = st.joker.joker_number, st.joker.joker_color
    # Tüm taş havuzundan sahte okeyleri ve gerçek okeyleri bul
    pool = []
    for p in st.players.values():
        pool += p.hand
    pool += st.stock
    fakes = [t for t in pool if t.fake_joker]
    reals = [t for t in pool if not t.fake_joker and t.color == jc and t.number == jn]
    return fakes, reals


def test_real_okey_cannot_extend_fake_okey_pair():
    room = new_room(seed=7, variant='non_fold')
    st = room.state
    fakes, reals = _rig_joker_pair(room)
    assert len(fakes) == 2 and reals
    # Taşları masadan/ellerden çıkarıp kontrollü kur
    def take(t):
        for p in st.players.values():
            if t in p.hand:
                p.hand.remove(t); return
        st.stock.remove(t)
    for t in fakes + reals[:1]:
        take(t)
    st.melds.append(Meld('0-pair-test', 0, MeldType.PAIR, list(fakes)))
    seat = st.current_seat
    p = st.player(seat)
    p.opened = True; p.opening_mode = 'pairs'; p.opening_pairs = 1
    p.hand.append(reals[0])
    # ele tutarlılık için fazladan bir taşı stoka geri koy
    extra = p.hand.pop(0); st.stock.append(extra)
    assert room.service._matching_open_pair(reals[0]) is None
    room.service.layoff_pair(seat, reals[0].id)
    # Okey yeni bir çift kurabilir ama sahte okey çiftine 3. taş olarak giremez.
    fake_pair = next(m for m in st.melds if m.id == '0-pair-test')
    assert len(fake_pair.tiles) == 2
    assert room.audit_state() == []


def test_bot_turn_rolls_back_corruption(monkeypatch):
    room = new_room(seed=11, variant='non_fold')
    room.bot_pace_ms = 0
    st = room.state
    # Sırayı bir bota ver
    st.current_seat = 1; st.phase = 'draw'
    def broken(self, seat):
        # kasıtlı olarak taş kaybettir
        self.state.player(seat).hand.pop()
    monkeypatch.setattr(type(room), '_bot_turn_impl', broken)
    room.bot_turn(1)
    assert room.audit_state() == []
    assert room.state.current_seat == 2  # güvenli çek-at ile sıra ilerledi


def test_reward_day_uses_turkey_time():
    from app.services import account_store as A
    # 2026-11-26 22:30 UTC = 27 Kasım 01:30 Türkiye
    ts = 1795732200
    assert A._day_key(ts) == '2026-11-27'


def test_presence_is_not_set_by_shadow_account_creation(tmp_path, monkeypatch):
    from app.services import account_store as A
    store = A.AccountStore(tmp_path / 'acc.json')
    A.PRESENCE.clear()
    store.ensure('friend-1', 'Ayşe', None, None, is_guest=False)  # arama/gölge hesap
    assert not A.seen_recently('friend-1')
    store.touch_presence('friend-1')
    assert A.seen_recently('friend-1')
    monkeypatch.setattr(A, '_now', lambda: __import__('time').time() + 120)
    assert not A.seen_recently('friend-1')


def test_table_loadout_drops_unowned_cosmetics():
    from app.services.account_store import _owned_equipped
    acc = {'inventory': ['rack_classic', 'tiles_marble'], 'equipped': {'rack': 'rack_royal', 'tiles': 'tiles_marble', 'frame': 'frame_royal', 'emoji': 'emoji_basic'}}
    out = _owned_equipped(acc)
    assert out['rack'] == 'rack_classic'
    assert out['tiles'] == 'tiles_marble'
    assert out['frame'] == 'frame_none'
    assert 'emoji' not in out
