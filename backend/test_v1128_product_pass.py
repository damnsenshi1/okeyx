from pathlib import Path

from app.services.account_store import AccountStore
from app.services.phase4_service import Phase4Service


def _store(tmp_path: Path):
    store = AccountStore(tmp_path / 'accounts.json')
    store.ensure('owner', 'Owner', None, None, is_guest=False)
    store.ensure('player', 'Player', None, None, is_guest=False)
    with store._lock:
        store._data.setdefault('phase4', {}).setdefault('staff_roles', {})['owner'] = 'owner'
        store._data['accounts']['player']['chips'] = 1000
        store._save()
    return store


def test_exact_two_billion_staff_wallet_adjustment(tmp_path):
    store = _store(tmp_path)
    service = Phase4Service(store)
    result = service.staff_adjust_wallet('owner', 'player', 'coins', 2_000_000_000, 'test')
    assert result['ok'] is True
    assert store.get('player')['chips'] == 2_000_001_000
    notes = store.get('player')['notifications']
    assert any('2' in str(n.get('message', '')) for n in notes)


def test_chest_daily_limit_is_server_authoritative(tmp_path):
    store = _store(tmp_path)
    store.update_reward_config({'chest': {'daily_limit': 5, 'rewards': [{'reward': 100, 'weight': 1}]}})
    with store._lock:
        store._data['accounts']['player']['chests']['keys'] = 10
        store._save()
    results = [store.open_chest('player') for _ in range(6)]
    assert all(x['ok'] is True for x in results[:5])
    assert results[5]['ok'] is False
    assert results[5]['code'] == 'daily_chest_limit'


def test_wheel_config_can_be_changed_by_staff(tmp_path):
    store = _store(tmp_path)
    service = Phase4Service(store)
    out = service.staff_reward_config('owner', {'wheel': {'daily_limit': 2, 'segments': [{'reward': 777, 'weight': 1}]}})
    assert out['ok'] is True
    a = store.spin_wheel('player')
    b = store.spin_wheel('player')
    c = store.spin_wheel('player')
    assert a['reward'] == 777 and b['reward'] == 777
    assert c['ok'] is False and c['code'] == 'daily_wheel_limit'


def test_default_cosmetics_are_owned_and_equipped(tmp_path):
    store = _store(tmp_path)
    service = Phase4Service(store)
    hub = service.hub('player')
    defaults = [x for x in hub['cosmetics'] if x.get('default')]
    assert defaults
    assert all(x.get('owned') is True for x in defaults)
    assert all(x.get('equipped') is True for x in defaults)
