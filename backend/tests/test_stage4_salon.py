"""Aşama 4: Şans Salonu yalnız kazanılmış bakiyeyle oynanır; satın alınan altın dokunulmaz."""
from app.services.account_store import AccountStore
from app.services.phase4_service import Phase4Service


def _svc(tmp_path):
    st = AccountStore(path=tmp_path / 'a.json')
    st.ensure('p1', 'A')
    return st, Phase4Service(st)


def test_salon_never_touches_real_coins(tmp_path):
    st, svc = _svc(tmp_path)
    st.sync_local_wallet('p1', 5_000_000, 0)
    for _ in range(40):
        out = svc.play_side_game('p1', 'slot', wager=100)
        assert st.get('p1')['chips'] == 5_000_000
        if not out.get('ok'):
            assert out['code'] == 'insufficient_coins'
    assert 'salon_chips' in st.get('p1')


def test_salon_cannot_be_played_with_purchased_coins_only(tmp_path):
    st, svc = _svc(tmp_path)
    st.sync_local_wallet('p1', 9_000_000, 0)
    svc._salon_ensure(st._data['accounts']['p1'])['salon_chips'] = 0
    out = svc.play_side_game('p1', 'slot', wager=100)
    assert out['ok'] is False and out['code'] == 'insufficient_coins'
    assert st.get('p1')['chips'] == 9_000_000


def test_vouchers_disabled_and_not_sold(tmp_path):
    st, svc = _svc(tmp_path)
    assert svc.play_side_game('p1', 'slot', wager=100, use_voucher=True)['code'] == 'vouchers_disabled'
    from app.services.phase4_service import DEFAULT_PHASE4_CONFIG
    assert all(not p.get('slot_vouchers') for p in DEFAULT_PHASE4_CONFIG['billing_products'])


def test_daily_claim_once_and_catalog_marked_earned_only(tmp_path):
    st, svc = _svc(tmp_path)
    first = svc.salon_claim('p1'); second = svc.salon_claim('p1')
    assert first['ok'] and not second['ok']
    assert svc.side_game_catalog()['earned_only'] is True


def test_privacy_and_delete_pages_public():
    from fastapi.testclient import TestClient
    from app.main import app
    c = TestClient(app)
    assert 'Gizlilik' in c.get('/privacy').text
    assert 'Hesabı sil' in c.get('/delete-account').text
