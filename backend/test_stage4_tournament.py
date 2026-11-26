from app.services import tournament as T
from app.services.account_store import AccountStore, _week_key


def _store(tmp_path):
    st = AccountStore(path=tmp_path / 'a.json')
    for p in ('a', 'b', 'c'):
        st.ensure(p, p.upper())
    return st


def test_settle_match_feeds_tournament_and_rank(tmp_path):
    st = _store(tmp_path)
    for _ in range(3):
        st.settle_match([{'id': 'a', 'name': 'A'}, {'id': 'b', 'name': 'B'}], 'a', 0, 1)
    rows = T.standings(st, _week_key())
    assert rows[0]['id'] == 'a' and rows[0]['points'] == 90 and rows[1]['id'] == 'b' and rows[1]['points'] == 15


def test_claim_once_with_server_side_prize(tmp_path):
    st = _store(tmp_path)
    week = 'W-prev'
    for _ in range(3):
        T.record_result(st, week, 'a', 'A', True)
    T.record_result(st, week, 'b', 'B', False)
    before = st.get('a')['chips']
    r = T.claim_previous(st, week, 'a')
    assert r['ok'] and r['rank'] == 1 and r['coins'] == 250_000
    assert st.get('a')['chips'] == before + 250_000
    assert T.claim_previous(st, week, 'a')['code'] == 'already_claimed'
    assert T.claim_previous(st, week, 'b')['code'] == 'not_enough_games'
    assert T.claim_previous(st, week, 'c')['code'] == 'no_result'


def test_prize_table_and_persistence_row(tmp_path):
    assert [T.prize_for_rank(r) for r in (1, 2, 3, 4, 10, 11, 50, 51)] == [250000, 150000, 100000, 40000, 40000, 15000, 15000, 5000]
    from app.services.remote_store import split_state
    st = _store(tmp_path)
    T.record_result(st, _week_key(), 'a', 'A', True)
    assert 'global:tournaments' in split_state(st._data)
