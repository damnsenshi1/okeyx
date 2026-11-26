import json
import uuid

import httpx
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.api import phase4 as P4
from app.api.account import STORE
from app.core.config import settings
from app.main import app
from app.services.google_play import GooglePlayClient, price_hint_to_minor

client = TestClient(app)


def _sa():
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = priv.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()).decode()
    return json.dumps({'client_email': 'svc@x.iam', 'private_key': pem, 'token_uri': 'https://oauth2.googleapis.com/token'})


def _google(state):
    def handler(req: httpx.Request):
        if req.url.host == 'oauth2.googleapis.com':
            return httpx.Response(200, json={'access_token': 'at', 'expires_in': 3600})
        if req.url.path.endswith(':acknowledge'):
            state['acked'] = state.get('acked', 0) + 1
            return httpx.Response(200, json={})
        tok = req.url.path.rsplit('/', 1)[-1]
        if tok == 'cancelled':
            return httpx.Response(200, json={'purchaseState': 1, 'orderId': 'GPA.1'})
        if tok == 'missing':
            return httpx.Response(404, json={})
        return httpx.Response(200, json={'purchaseState': 0, 'orderId': 'GPA.' + tok})
    return GooglePlayClient(_sa(), 'com.x', transport=httpx.MockTransport(handler))


def _player():
    a = STORE.ensure('gp-player', 'GP', None, None, is_guest=False)
    return {'x-account-token': a['session_token']}


def test_real_purchase_grants_once_from_catalog_not_client(monkeypatch):
    state = {}
    monkeypatch.setattr(P4, '_GOOGLE_CLIENT', _google(state))
    monkeypatch.setattr(settings, 'google_play_service_account_json', 'configured')
    h = _player()
    before = STORE.get('gp-player')['chips']
    body = {'player_id': 'gp-player', 'product_id': 'okeyx.gold.50000', 'purchase_token': 'tok-' + uuid.uuid4().hex}
    r = client.post('/api/phase4/store/google-verify', json=body, headers=h)
    assert r.status_code == 200 and r.json()['ok'], r.text
    assert STORE.get('gp-player')['chips'] == before + 750_000
    # Aynı sipariş ikinci kez: altın verilmez
    r2 = client.post('/api/phase4/store/google-verify', json=body, headers=h)
    assert STORE.get('gp-player')['chips'] == before + 750_000 and r2.json().get('code') == 'already_processed'
    assert state['acked'] >= 1  # yeniden denemede de onay tekrarlanır (zararsız, ilk onay düşmüşse kurtarır)


def test_cancelled_missing_and_unknown_sku_rejected(monkeypatch):
    monkeypatch.setattr(P4, '_GOOGLE_CLIENT', _google({}))
    monkeypatch.setattr(settings, 'google_play_service_account_json', 'configured')
    h = _player()
    before = STORE.get('gp-player')['chips']
    for tok, code in (('cancelled', 'purchase_not_completed'), ('missing', 'purchase_not_found')):
        r = client.post('/api/phase4/store/google-verify', json={'player_id': 'gp-player', 'product_id': 'okeyx.gold.50000', 'purchase_token': tok}, headers=h)
        assert r.status_code == 402 and r.json()['detail'] == code
    r = client.post('/api/phase4/store/google-verify', json={'player_id': 'gp-player', 'product_id': 'nope', 'purchase_token': 'x'}, headers=h)
    assert r.status_code == 404
    assert STORE.get('gp-player')['chips'] == before


def test_not_configured_and_auth_required(monkeypatch):
    monkeypatch.setattr(P4, '_GOOGLE_CLIENT', None)
    monkeypatch.setattr(settings, 'google_play_service_account_json', '')
    h = _player()
    body = {'player_id': 'gp-player', 'product_id': 'okeyx.gold.50000', 'purchase_token': 't'}
    assert client.post('/api/phase4/store/google-verify', json=body, headers=h).status_code == 503
    assert client.post('/api/phase4/store/google-verify', json=body).status_code in (401, 403, 422)


def test_price_hint_parsing():
    assert [price_hint_to_minor(x) for x in ('₺39,90', '₺4,99', '₺349,90', '', '₺10')] == [3990, 499, 34990, 0, 1000]
