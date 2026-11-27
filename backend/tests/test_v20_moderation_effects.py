import random

from app.services import chance_engine as ce


def _acct():
    return {'chips': 10**12, 'diamonds': 0, 'slot_vouchers': {}, 'stats': {}, 'tickets': 0, 'name': 't'}


def _tower_rtp(rtp, floors_to_climb, n=20000):
    cfg = {'rtp_percent': rtp, 'bet_options': [1000]}
    a = _acct(); ch = {}; w = p = 0
    for _ in range(n):
        st = ce.tower_start(a, cfg, 1000, ch); w += 1000; cid = st['challenge_id']
        for f in range(floors_to_climb):
            r = ce.tower_choose(a, cfg, cid, random.randint(0, 2), ch)
            if not r['safe']:
                break
            if r.get('finished'):
                p += r['payout_coins']; break
        else:
            if not ch[cid]['used']:
                p += ce.tower_cashout(a, cfg, cid, ch)['payout_coins']
    return 100 * p / w


def test_tower_payout_matches_rtp_for_every_strategy():
    random.seed(7)
    for floors in (1, 3, 6):
        assert abs(_tower_rtp(90, floors) - 90) < 6, floors


def test_wheel_config_returns_effective_defaults(tmp_path):
    from app.services.account_store import AccountStore
    s = AccountStore(tmp_path / 'a.json')
    cfg = s.reward_config()
    assert cfg['wheel']['segments'] and cfg['chest']['rewards']
