import base64
import json
import time
import uuid
from urllib.parse import quote

import httpx
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app.api import ops_extra as OX
from app.api import phase4 as P4
from app.api.account import STORE
from app.core.config import settings
from app.main import app
from tests.test_stage5_google_play import _google, _sa

client = TestClient(app)


def _player(pid):
    a = STORE.ensure(pid, 'P', None, None, is_guest=False)
    return {'x-account-token': a['session_token']}


def test_crash_report_grouped_and_rate_limited(monkeypatch):
    OX._crash_hits.clear()
    body = {'app_version': '12.1.0', 'error': 'Null check ' + uuid.uuid4().hex, 'stack': '#0 main', 'fatal': True}
    r = client.post('/api/telemetry/crash', json=body)
    assert r.json()['ok']
    sig = r.json()['sig']
    client.post('/api/telemetry/crash', json=body)
    assert STORE._data['telemetry']['crash_groups'][sig]['count'] == 2
    for _ in range(12):
        last = client.post('/api/telemetry/crash', json=body).json()
    assert last == {'ok': False, 'code': 'rate_limited'}


def _signed_query(priv, token, tx):
    msg = f'ad_network=541&ad_unit=123&custom_data={token}&reward_amount=1&reward_item=coins&timestamp={int(time.time()*1000)}&transaction_id={tx}&user_id=u1'
    sig = priv.sign(msg.encode(), ec.ECDSA(hashes.SHA256()))
    sig_b64 = base64.urlsafe_b64encode(sig).decode().rstrip('=')
    return msg + f'&signature={sig_b64}&key_id=42'


def test_admob_ssv_required_flow(monkeypatch):
    priv = ec.generate_private_key(ec.SECP256R1())
    pem = priv.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    monkeypatch.setattr(OX, '_fetch_admob_keys', lambda: {'42': pem})
    monkeypatch.setattr(settings, 'admob_ssv_required', True)
    pid = 'ssv-' + uuid.uuid4().hex[:6]
    h = _player(pid)
    start = client.post('/api/phase4/ads/start', json={'player_id': pid, 'reward_kind': 'coins'}, headers=h).json()
    assert start['ok'], start
    tok = start['token']
    # İmza gelmeden ödül yok
    r = client.post('/api/phase4/ads/claim', json={'player_id': pid, 'token': tok}, headers=h).json()
    assert r['code'] == 'ad_not_verified_yet'
    # Sahte imza reddedilir
    bad = _signed_query(ec.generate_private_key(ec.SECP256R1()), tok, 'tx1')
    assert client.get('/api/ads/admob-ssv?' + bad).status_code == 400
    good = _signed_query(priv, tok, 'tx-' + uuid.uuid4().hex)
    assert client.get('/api/ads/admob-ssv?' + good).json()['ok']
    r = client.post('/api/phase4/ads/claim', json={'player_id': pid, 'token': tok}, headers=h).json()
    assert r['ok'] and r['reward'] > 0


def test_google_refund_sync_reverses_coins(monkeypatch):
    state = {}
    gp = _google(state)
    order_tok = 'rf-' + uuid.uuid4().hex
    orig_handler = gp._http._transport.handler

    def handler(req):
        if req.url.path.endswith('/voidedpurchases'):
            return httpx.Response(200, json={'voidedPurchases': [{'orderId': 'GPA.' + order_tok, 'voidedReason': 1}]})
        return orig_handler(req)
    gp._http = httpx.Client(transport=httpx.MockTransport(handler))
    monkeypatch.setattr(P4, '_GOOGLE_CLIENT', gp)
    monkeypatch.setattr(settings, 'google_play_service_account_json', 'configured')
    pid = 'rf-' + uuid.uuid4().hex[:6]
    h = _player(pid)
    before = STORE.get(pid)['chips']
    r = client.post('/api/phase4/store/google-verify', json={'player_id': pid, 'product_id': 'okeyx.gold.50000', 'purchase_token': order_tok}, headers=h)
    assert r.json()['ok']
    assert STORE.get(pid)['chips'] > before
    out = OX.sync_google_refunds(7)
    assert out['reversed'] == 1
    assert STORE.get(pid)['chips'] == before
    assert OX.sync_google_refunds(7)['reversed'] == 0  # ikinci kez geri alınmaz


def test_support_ticket_and_prefs(monkeypatch):
    pid = 'sup-' + uuid.uuid4().hex[:6]
    h = _player(pid)
    r = client.post('/api/support/ticket', json={'player_id': pid, 'topic': 'purchase', 'message': 'Yanlışlıkla aldım iade istiyorum'}, headers=h).json()
    assert r['ok'] and r['ticket_id']
    assert client.post('/api/support/ticket', json={'player_id': pid, 'message': 'xxxxxx'}).status_code == 401
    p = client.post(f'/api/account/{pid}/notification-prefs', json={'invite': False}, headers=h).json()
    assert p['prefs']['invite'] is False


def test_push_respects_prefs(monkeypatch):
    sent = []

    class Fake:
        def send(self, token, title, body, data=None):
            sent.append((token, data)); return True
    monkeypatch.setattr(OX, '_FCM', Fake())
    pid = 'push-' + uuid.uuid4().hex[:6]
    _player(pid)
    STORE.register_push(pid, 'device-token-1')
    assert OX.push_to_player(pid, 'T', 'B', {'kind': 'invite'}) == 1
    STORE.set_notification_prefs(pid, {'invite': False})
    assert OX.push_to_player(pid, 'T', 'B', {'kind': 'invite'}) == 0
    assert OX.push_to_player(pid, 'T', 'B', {'kind': 'friend_request'}) == 1


def test_daily_reminder_once_per_day(monkeypatch):
    sent = []

    class Fake:
        def send(self, token, title, body, data=None):
            sent.append(token); return True
    monkeypatch.setattr(OX, '_FCM', Fake())
    pid = 'rem-' + uuid.uuid4().hex[:6]
    _player(pid)
    STORE.register_push(pid, 'tok-' + pid)
    STORE._data.setdefault('telemetry', {}).pop('daily_reminder_day', None)
    noon_tr = (int(time.time()) // 86400) * 86400 + 10 * 3600  # 13:00 TR
    first = OX.send_daily_reminders(noon_tr)
    assert first >= 1 and ('tok-' + pid) in sent
    assert OX.send_daily_reminders(noon_tr + 60) == 0
