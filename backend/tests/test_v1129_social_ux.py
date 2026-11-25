from pathlib import Path

from app.services.account_store import AccountStore, _week_key
from app.services.phase4_service import Phase4Service


def _store(tmp_path: Path) -> AccountStore:
    store = AccountStore(tmp_path / 'accounts.json')
    store.ensure('p1', 'Oyuncu', None, None, is_guest=False)
    return store


def test_standard_emoji_packs_are_owned_but_only_one_is_equipped(tmp_path):
    store = _store(tmp_path)
    service = Phase4Service(store)
    hub = service.hub('p1')
    packs = [x for x in hub['cosmetics'] if x.get('category') == 'emoji_pack']
    assert {x['id'] for x in packs} >= {'emoji_cafe', 'emoji_party', 'emoji_troll', 'emoji_neon'}
    assert all(x['owned'] is True for x in packs)
    assert sum(1 for x in packs if x.get('equipped')) == 1


def test_living_schema_upgrade_adds_new_standard_cosmetics_to_old_config(tmp_path):
    store = _store(tmp_path)
    service = Phase4Service(store)
    with store._lock:
        cfg = service._global()['config']
        cfg['living_schema_version'] = 1
        cfg['cosmetics'] = [x for x in cfg['cosmetics'] if x.get('id') not in {'emoji_party', 'emoji_troll', 'emoji_neon'}]
        store._save()
    hub = service.hub('p1')
    ids = {x['id'] for x in hub['cosmetics']}
    assert {'emoji_party', 'emoji_troll', 'emoji_neon'} <= ids
    assert service.config()['living_schema_version'] == 2


def test_club_weekly_event_can_be_claimed_once(tmp_path):
    store = _store(tmp_path)
    store.ensure('p2', 'Dost', None, None, is_guest=False)
    created = store.club_create('p1', 'Test Kulüp')
    assert created['ok'] is True
    club_id = created['club']['id']
    joined = store.club_join('p2', club_id)
    assert joined['ok'] is True
    with store._lock:
        store._data['accounts']['p1']['stats']['games'] = 20
        store._data['accounts']['p1']['stats']['wins'] = 8
        before = int(store._data['accounts']['p1']['chips'])
        store._save()
    view = store.club_view('p1')
    event = view['club']['weekly_event']
    assert event['complete'] is True
    assert event['claimed'] is False
    first = store.club_claim_weekly('p1')
    assert first['ok'] is True
    assert first['reward'] == 15000
    assert store.get('p1')['chips'] == before + 15000
    second = store.club_claim_weekly('p1')
    assert second['ok'] is False and second['code'] == 'club_event_already_claimed'
    assert _week_key() in store.get('p1')['club_rewards']['claimed_weeks']
