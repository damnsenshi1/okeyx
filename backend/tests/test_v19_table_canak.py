from pathlib import Path

from app.api import game
from app.services.account_store import AccountStore


def _setup(tmp_path: Path, monkeypatch):
    game.ROOMS.clear(); game.ROOM_META.clear(); game.SOCKETS.clear()
    s = AccountStore(tmp_path / 'accounts.json')
    for pid in ('p1', 'p2'):
        s.ensure(pid, pid.upper(), None, None, is_guest=False)
    monkeypatch.setattr(game, 'STORE', s)
    r = game.new_room(variant='non_fold', entry_fee=5000, assisted=True, turbo=False, max_rounds=1, room_name='t', waiting=True)
    m = game._ensure_meta(r.state.room_id)
    for seat, pid in ((0, 'p1'), (1, 'p2')):
        m['player_ids'][seat] = pid
        r.state.players[seat].bot = False
    return s, r, m


def test_canak_grows_when_not_broken(tmp_path, monkeypatch):
    s, r, m = _setup(tmp_path, monkeypatch)
    before = s.get('p1')['chips']
    game._table_canak(r.state.room_id, r, m, {'joker_finish': False, 'pair_finish': False}, 0)
    assert m['canak_pot'] == 1000
    assert s.get('p1')['chips'] == before - 500


def test_okey_finish_breaks_canak(tmp_path, monkeypatch):
    s, r, m = _setup(tmp_path, monkeypatch)
    m['canak_pot'] = 4000
    before = s.get('p2')['chips']
    game._table_canak(r.state.room_id, r, m, {'joker_finish': True}, 1)
    assert m['canak_pot'] == 0
    assert m['canak_last']['amount'] == 5000 and m['canak_last']['seat'] == 1
    assert s.get('p2')['chips'] == before - 500 + 5000
    st = game._state(r.state.room_id, 0)
    assert st['canak']['pot'] == 0 and st['canak']['last']['kind'] == 'okey'
