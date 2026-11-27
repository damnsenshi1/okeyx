import pytest
from fastapi import HTTPException

from app.api import account as acc_api
from app.api import phase4 as p4_api
from app.services.account_store import AccountStore
from app.services.phase4_service import Phase4Service


@pytest.fixture()
def env(tmp_path, monkeypatch):
    s = AccountStore(tmp_path / 'a.json')
    for pid in ('staff', 'p1', 'p2'):
        s.ensure(pid, pid, None, None, is_guest=False)
        s._data['accounts'][pid]['chips'] = 1_000_000
    s._save()
    monkeypatch.setattr(acc_api, 'STORE', s)
    monkeypatch.setattr(p4_api, 'STORE', s)
    svc = Phase4Service(s)
    monkeypatch.setattr(Phase4Service, 'require_staff', lambda self, pid, perm: {'enabled': True})
    return s, svc


def test_ban_blocks_social_store_and_salon(env):
    s, svc = env
    assert svc.staff_sanction('staff', 'p1', 'ban', 0, 'test')['ok']
    tok = s.get('p1')['session_token']
    with pytest.raises(HTTPException) as e:
        acc_api._require_social('p1', tok)
    assert e.value.status_code == 403
    with pytest.raises(HTTPException):
        p4_api._require_active('p1', tok)
    svc.staff_sanction('staff', 'p1', 'unban', 0, '')
    acc_api._require_social('p1', tok)
    p4_api._require_active('p1', tok)


def test_invite_and_gift_locks(env):
    s, svc = env
    svc.staff_sanction('staff', 'p2', 'invite_lock', 60, '')
    tok = s.get('p2')['session_token']
    with pytest.raises(HTTPException):
        acc_api._require_social('p2', tok, 'invite_locked')
    acc_api._require_social('p2', tok, 'gift_locked')  # hediye serbest


def test_price_patch_changes_purchase_cost(env):
    s, svc = env
    item = next(x for x in svc._global()['config']['cosmetics'] if x['id'] == 'rack_walnut')
    svc.staff_update_cosmetic('staff', 'rack_walnut', {'price': 1000, 'discount_percent': 50})
    before = s.get('p1')['chips']
    out = svc.buy_cosmetic('p1', 'rack_walnut')
    assert out['ok'] and before - s.get('p1')['chips'] == 500
    assert item['price'] == 1000


def test_wallet_adjust_and_tower_rtp(env):
    s, svc = env
    svc.staff_adjust_wallet('staff', 'p2', 'coins', 250_000, 'test')
    assert s.get('p2')['chips'] == 1_250_000
    assert svc.staff_set_rtp('staff', 'tower', 88)['ok']
