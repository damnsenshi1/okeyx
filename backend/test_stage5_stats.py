from fastapi.testclient import TestClient

from app.main import app
from app.services.account_store import AccountStore


def _st(tmp_path):
    st = AccountStore(path=tmp_path / 'a.json')
    for p in ('a', 'b'):
        st.ensure(p, p.upper())
    return st


def test_monthly_leaderboard_and_mode_stats(tmp_path):
    st = _st(tmp_path)
    meta = {'variant': 'fold', 'turbo': True, 'game_type': 'okey101'}
    st.settle_match([{'id': 'a', 'name': 'A'}, {'id': 'b', 'name': 'B'}], 'a', 0, 1, meta)
    st.settle_match([{'id': 'a', 'name': 'A'}, {'id': 'b', 'name': 'B'}], 'b', 0, 1, {**meta, 'turbo': False, 'variant': 'non_fold'})
    lb = st.leaderboard('a', 'monthly')
    assert [r['points'] for r in lb['rows']] == [38, 38]
    by = st.get('a')['stats_by_mode']
    assert by['okey101:fold:turbo']['wins'] == 1 and by['okey101:non_fold']['games'] == 1 and by['okey101:non_fold']['wins'] == 0
    assert st.public('a')['stats_by_mode']['okey101:fold:turbo']['games'] == 1


def test_monthly_scope_accepted_by_api():
    from app.api.account import STORE
    c = TestClient(app)
    a = STORE.ensure('lb-user', 'LB', None, None, is_guest=False)
    r = c.get('/api/account/lb-user/leaderboard', params={'scope': 'monthly'}, headers={'x-account-token': a['session_token']})
    assert r.status_code == 200 and r.json()['scope'] == 'monthly'
