"""Aşama 1: kalıcı depolama (Supabase), admin/gizli anahtar sertleştirmesi, hız sınırı, JWKS."""
from __future__ import annotations

import asyncio
import json
import time

import httpx
import pytest
from fastapi.testclient import TestClient
from jose import jwt, jwk
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

from app.core import auth as auth_mod
from app.core import ratelimit
from app.core.config import settings
from app.main import app
from app.services.account_store import AccountStore
from app.services.remote_store import SupabaseKV, split_state, merge_state


# --- Sahte PostgREST (bellekte) -------------------------------------------------
class FakePostgrest:
    def __init__(self):
        self.rows: dict[str, dict] = {}
        self.fail_get = False
        self.requests: list[tuple[str, str]] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append((request.method, str(request.url)))
        if request.method == 'GET':
            if self.fail_get:
                return httpx.Response(503, text='paused')
            keys = sorted(self.rows)
            params = request.url.params
            off = int(params.get('offset', 0)); lim = int(params.get('limit', 1000))
            return httpx.Response(200, json=[{'key': k, 'data': self.rows[k]} for k in keys[off:off + lim]])
        if request.method == 'POST':
            for row in json.loads(request.content):
                self.rows[row['key']] = row['data']
            return httpx.Response(201)
        if request.method == 'DELETE':
            raw = request.url.params.get('key', '')
            inner = raw[len('in.('):-1]
            for k in [x.strip('"') for x in inner.split('","')] if inner else []:
                self.rows.pop(k.strip('"'), None)
            return httpx.Response(204)
        return httpx.Response(405)

    def kv(self) -> SupabaseKV:
        return SupabaseKV('https://x.supabase.co', 'service-key', transport=httpx.MockTransport(self.handler))


def _store(tmp_path, fake, name='a.json'):
    s = AccountStore(path=tmp_path / name, remote=fake.kv())
    s._sync.interval = 0.01
    return s


def test_accounts_survive_restart_through_supabase(tmp_path):
    fake = FakePostgrest()
    s1 = _store(tmp_path, fake)
    assert s1.ready
    acc = s1.ensure('player-1', 'Ayşe', None, None, is_guest=False)
    s1.sync_local_wallet('player-1', 123_456, 7)
    s1.flush()
    assert 'account:player-1' in fake.rows
    assert fake.rows['account:player-1']['chips'] == 123_456

    # Disk tamamen kayboldu (Render yeniden başladı): farklı klasör, aynı Supabase.
    s2 = _store(tmp_path / 'yeni', fake)
    got = s2.get('player-1')
    assert got and got['chips'] == 123_456 and got['diamonds'] == 7
    assert got['session_token'] == acc['session_token']
    assert s2.verify('player-1', acc['session_token'])


def test_only_changed_rows_are_uploaded(tmp_path):
    fake = FakePostgrest()
    s = _store(tmp_path, fake)
    s.ensure('p1', 'A'); s.ensure('p2', 'B'); s.flush()
    fake.requests.clear()
    s.sync_local_wallet('p1', 5); s.flush()
    posts = [r for r in fake.requests if r[0] == 'POST']
    assert len(posts) == 1
    assert fake.rows['account:p1']['chips'] == 5


def test_never_overwrites_remote_when_load_failed(tmp_path):
    fake = FakePostgrest()
    good = _store(tmp_path, fake)
    good.ensure('vip-player', 'Eski'); good.sync_local_wallet('vip-player', 9_999_999); good.flush()

    fake.fail_get = True  # Supabase duraklatılmış
    broken = _store(tmp_path / 'b', fake)
    assert not broken.ready
    assert broken._sync.flush() == 0  # yüklenmediyse asla yazmaz
    fake.requests.clear()
    broken._save()
    broken.flush()
    assert not [r for r in fake.requests if r[0] in ('POST', 'DELETE')]
    assert fake.rows['account:vip-player']['chips'] == 9_999_999

    # Supabase geri gelince hesap geri yüklenir.
    fake.fail_get = False
    assert broken._load_remote_quiet()
    assert broken.ready
    assert broken.get('vip-player')['chips'] == 9_999_999


def test_purge_account_removes_row_and_friend_links(tmp_path):
    fake = FakePostgrest()
    s = _store(tmp_path, fake)
    s.ensure('a', 'A'); s.ensure('b', 'B')
    s._data['accounts']['b']['friends'] = ['a']
    s._save(); s.flush()
    assert 'account:a' in fake.rows
    assert s.purge_account('a') is True
    s.flush()
    assert 'account:a' not in fake.rows
    assert fake.rows['account:b']['friends'] == []


def test_split_and_merge_roundtrip():
    data = AccountStore._empty_data()
    data['accounts']['x'] = {'id': 'x', 'chips': 1}
    data['clubs']['c1'] = {'name': 'Kulüp'}
    rows = split_state(data)
    assert set(rows) >= {'account:x', 'global:clubs', 'global:canak'}
    back = merge_state(rows, AccountStore._empty_data())
    assert back['accounts'] == data['accounts'] and back['clubs'] == data['clubs']


# --- Admin / yapılandırma ------------------------------------------------------
client = TestClient(app)


def test_admin_disabled_without_strong_key(monkeypatch):
    monkeypatch.setattr(settings, 'admin_key', '')
    assert client.get('/api/phase4/admin/snapshot', headers={'x-admin-key': 'x'}).status_code == 503
    monkeypatch.setattr(settings, 'admin_key', 'okeyx-local-admin-change-me')
    assert client.get('/api/phase4/admin/snapshot', headers={'x-admin-key': 'okeyx-local-admin-change-me'}).status_code == 503


def test_admin_requires_exact_key(monkeypatch):
    monkeypatch.setattr(settings, 'admin_key', 'S3cure-Admin-Key-1234567890')
    assert client.get('/api/phase4/admin/snapshot', headers={'x-admin-key': 'yanlis'}).status_code == 401
    assert client.get('/api/phase4/admin/snapshot').status_code == 401
    assert client.get('/api/phase4/admin/snapshot', headers={'x-admin-key': 'S3cure-Admin-Key-1234567890'}).status_code == 200


def test_secure_defaults():
    from app.core.config import Settings
    s = Settings(_env_file=None)
    assert s.admin_key == '' and not s.admin_enabled
    assert s.allow_test_billing is False
    assert s.local_test_secret == ''


def test_game_new_closed_in_production(monkeypatch):
    monkeypatch.setattr(settings, 'env', 'production')
    monkeypatch.setattr(settings, 'local_dev_mode', False)
    assert client.post('/api/game/new').status_code == 404


def test_bootstrap_local_closed_by_default():
    r = client.post('/api/account/bootstrap-local', json={'player_id': 'x', 'name': 'x'},
                    headers={'X-Local-Test-Secret': ''})
    assert r.status_code in (404, 403, 422)


# --- Hız sınırı ----------------------------------------------------------------
def test_sliding_window_blocks_then_recovers():
    w = ratelimit.SlidingWindow()
    assert all(w.allow('k', 3, 60, now=100.0 + i)[0] for i in range(3))
    ok, retry = w.allow('k', 3, 60, now=104.0)
    assert not ok and retry >= 1
    assert w.allow('k', 3, 60, now=161.0)[0]


def test_http_rate_limit_returns_429(monkeypatch):
    ratelimit.WINDOW._hits.clear()
    monkeypatch.setattr(settings, 'rate_limit_general_per_min', 5)
    codes = [client.get('/api/live/activity', headers={'x-account-token': 'tok-A'}).status_code for _ in range(8)]
    assert codes[:5] == [200] * 5 and 429 in codes[5:]
    # Başka bir hesap etkilenmez.
    assert client.get('/api/live/activity', headers={'x-account-token': 'tok-B'}).status_code == 200
    # Sağlık kontrolü hiçbir zaman sınırlanmaz.
    assert all(client.get('/healthz').status_code == 200 for _ in range(20))
    ratelimit.WINDOW._hits.clear()


# --- JWKS anahtar dönüşü -------------------------------------------------------
def _make_key(kid: str):
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = priv.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    pub = priv.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    jwk_dict = jwk.construct(pub, 'RS256').to_dict(); jwk_dict['kid'] = kid
    return pem, jwk_dict


def test_jwks_refetches_on_rotated_key(monkeypatch):
    monkeypatch.setattr(settings, 'supabase_url', 'https://x.supabase.co')
    old_pem, old_jwk = _make_key('old')
    new_pem, new_jwk = _make_key('new')
    served = {'keys': [old_jwk]}
    calls = {'n': 0}

    async def fake_fetch():
        calls['n'] += 1
        auth_mod._jwks_cache = dict(served)
        auth_mod._jwks_fetched_at = time.monotonic()
        return auth_mod._jwks_cache

    monkeypatch.setattr(auth_mod, '_fetch_jwks', fake_fetch)
    monkeypatch.setattr(auth_mod, '_jwks_cache', None)
    monkeypatch.setattr(auth_mod, '_jwks_fetched_at', 0.0)

    def token(pem, kid):
        claims = {'sub': 'u1', 'aud': 'authenticated', 'iss': 'https://x.supabase.co/auth/v1', 'exp': int(time.time()) + 600}
        return jwt.encode(claims, pem.decode(), algorithm='RS256', headers={'kid': kid})

    user = asyncio.run(auth_mod.current_user('Bearer ' + token(old_pem, 'old')))
    assert user['id'] == 'u1' and calls['n'] == 1

    # Supabase anahtarı döndürdü; önbellek hâlâ eski. Yeni kid gelince yenilenmeli.
    served['keys'] = [new_jwk]
    monkeypatch.setattr(auth_mod, 'JWKS_MIN_REFETCH_SECONDS', 0)
    user = asyncio.run(auth_mod.current_user('Bearer ' + token(new_pem, 'new')))
    assert user['id'] == 'u1' and calls['n'] == 2

    # Tanınmayan kid reddedilir.
    from fastapi import HTTPException
    with pytest.raises(HTTPException) as e:
        asyncio.run(auth_mod.current_user('Bearer ' + token(old_pem, 'nope')))
    assert e.value.status_code == 401


def test_healthz_reports_storage_mode_without_secrets():
    body = client.get('/healthz').json()
    assert body['ok'] is True
    assert body['storage']['mode'] in ('local-file', 'supabase')
    dumped = json.dumps(body)
    assert 'service_role' not in dumped.lower()
    assert not settings.supabase_service_role_key or settings.supabase_service_role_key not in dumped
