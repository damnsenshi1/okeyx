from pathlib import Path

from app.services.account_store import AccountStore
from app.services.phase4_service import Phase4Service, _effective_price


def _svc(tmp_path: Path):
    s = AccountStore(tmp_path / 'a.json')
    s.ensure('boss', 'Boss', None, None, is_guest=False)
    s.ensure('p1', 'P1', None, None, is_guest=False)
    svc = Phase4Service(s)
    svc._global().setdefault('staff_roles', {})['boss'] = 'owner'
    return s, svc


def test_welcome_chips_default_is_one_million(tmp_path):
    s, _ = _svc(tmp_path)
    assert s.get('p1')['chips'] == 1_000_000


def test_discount_and_price_edit(tmp_path):
    s, svc = _svc(tmp_path)
    r = svc.staff_update_cosmetic('boss', 'rack_walnut', {'price': 40000, 'discount_percent': 25})
    assert r['ok'] and _effective_price(r['item']) == 30000
    before = s.get('p1')['chips']
    out = svc.buy_cosmetic('p1', 'rack_walnut')
    assert out['ok'] and s.get('p1')['chips'] == before - 30000


def test_non_staff_cannot_edit(tmp_path):
    _, svc = _svc(tmp_path)
    try:
        svc.staff_update_cosmetic('p1', 'rack_walnut', {'price': 1})
        assert False
    except PermissionError:
        pass


def test_rtp_bounded_and_economy(tmp_path):
    s, svc = _svc(tmp_path)
    assert svc.staff_set_rtp('boss', 'slot', 50)['rtp_percent'] == 85.0
    assert svc.staff_set_rtp('boss', 'slot', 99)['rtp_percent'] == 97.0
    eco = svc.staff_update_economy('boss', {'commission_percent': 12, 'canak_percent': 5})['economy']
    assert eco['commission_percent'] == 12 and eco['canak_percent'] == 5
    m = svc.staff_market('boss')
    assert m['ok'] and m['audit'] and m['side_games']['slot']['rtp_percent'] == 97.0
