from pathlib import Path

from app.services.account_store import AccountStore


def test_welcome_once_per_device(tmp_path: Path):
    s = AccountStore(tmp_path / 'a.json')
    s.ensure('u1', 'A', None, None, is_guest=True)
    s.apply_welcome_policy('u1', 'aid-phone1')
    assert s.get('u1')['chips'] == 1_000_000
    # Aynı telefonda yeni (silip yeniden kurulmuş) misafir hesap
    s.ensure('u2', 'B', None, None, is_guest=True)
    s.apply_welcome_policy('u2', 'aid-phone1')
    assert s.get('u2')['chips'] == 50_000
    # Tekrar giriş bakiyeye dokunmaz
    s.credit('u2', 1000, 'test', notify=False)
    s.apply_welcome_policy('u2', 'aid-phone1')
    assert s.get('u2')['chips'] == 51_000
    # Başka telefon tam hediye alır
    s.ensure('u3', 'C', None, None, is_guest=True)
    s.apply_welcome_policy('u3', 'aid-phone2')
    assert s.get('u3')['chips'] == 1_000_000
