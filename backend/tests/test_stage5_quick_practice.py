"""Hızlı eşleşme 15 sn içinde botla dolar; antrenman bahissiz ve ödülsüzdür."""
import asyncio

from fastapi.testclient import TestClient

from app.api import game as G
from app.main import app
from app.services.account_store import AccountStore

client = TestClient(app)


def _acct(pid='quick-p1'):
    a = G.STORE.ensure(pid, 'Quick', None, None, is_guest=False)
    G.STORE.sync_local_wallet(pid, 1_000_000, 0)
    return pid, a['session_token']


def _quick(pid, tok):
    r = client.post('/api/lobby/quick', json={'player_id': pid, 'account_token': tok, 'entry_fee': 5000})
    assert r.status_code == 200, r.text
    return r.json()


def test_quick_room_fills_with_bots_after_timeout_and_starts():
    pid, tok = _acct('quick-p1')
    out = _quick(pid, tok)
    rid = out['room_id']
    room = G.ROOMS[rid]
    assert room.state.phase == 'waiting' and not room.state.started
    # Erken: 15 sn dolmadan bot doldurma yok.
    assert not room.state.started
    G.ROOM_META[rid]['created_at'] -= G.QUICK_BOT_FILL_SECONDS + 1
    assert G._fill_bots_and_start(rid) is True
    assert room.state.started
    bots = [p for p in room.state.players.values() if p.bot]
    assert len(bots) == 3 and all(p.name == 'Normal Bot' for p in bots)
    assert sum(1 for p in room.state.players.values() if not p.bot) == 1


def test_fill_requires_at_least_one_human():
    r = G.new_room(room_name='x', waiting=True, entry_fee=5000)
    G._ensure_meta(r.state.room_id)
    assert G._fill_bots_and_start(r.state.room_id) is False


def test_practice_is_free_instant_and_gives_no_progress():
    pid, tok = _acct('prac-p1')
    before = dict(G.STORE.get(pid)['stats'])
    chips = G.STORE.get(pid)['chips']
    r = client.post('/api/lobby/practice', json={'player_id': pid, 'account_token': tok})
    assert r.status_code == 200, r.text
    rid = r.json()['room_id']
    room = G.ROOMS[rid]
    assert room.state.started and room.state.entry_fee == 0
    assert G.ROOM_META[rid]['practice'] is True
    # Aynı oyuncu tekrar basarsa aynı masa gelir (çift masa yok).
    assert client.post('/api/lobby/practice', json={'player_id': pid, 'account_token': tok}).json()['room_id'] == rid
    room.state.match_finished = True
    room.state.total_scores = {0: 10, 1: 20, 2: 30, 3: 40}
    G._settle_if_finished(rid)
    assert G.STORE.get(pid)['chips'] == chips
    assert G.STORE.get(pid)['stats']['games'] == before['games']


def test_level_aware_matching_and_relaxation():
    hi, tok_hi = _acct('lvl-hi')
    G.STORE._data['accounts'][hi]['xp'] = 50_000_000; G.STORE._normalize(G.STORE._data['accounts'][hi])
    out = _quick(hi, tok_hi)
    rid = out['room_id']
    low, tok_low = _acct('lvl-low')
    G.STORE._data['accounts'][low]['xp'] = 0; G.STORE._normalize(G.STORE._data['accounts'][low])
    # Yeni oda: seviye farkı büyük -> aynı odaya girmez
    other = _quick(low, tok_low)
    assert other['room_id'] != rid
    hl = G.STORE.get(hi)['level']; ll = G.STORE.get(low)['level']
    assert hl - ll > G.LEVEL_BAND
    assert G._level_compatible(rid, ll) is False and G._level_compatible(rid, hl) is True
    # Oda eskiyince sınır gevşer
    G.ROOM_META[rid]['created_at'] -= G.LEVEL_BAND_RELAX_SECONDS + 1
    assert G._level_compatible(rid, ll) is True
