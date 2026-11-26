import json

import httpx
from fastapi.testclient import TestClient

from app.core import observability as O
from app.main import app
from app.services import backup as B
from app.services.remote_store import SupabaseKV


class Fake:
    def __init__(self):
        self.rows = {}

    def h(self, req):
        if req.method == 'GET':
            keys = sorted(self.rows)
            off = int(req.url.params.get('offset', 0)); lim = int(req.url.params.get('limit', 1000))
            return httpx.Response(200, json=[{'key': k, 'data': self.rows[k]} for k in keys[off:off + lim]])
        for r in json.loads(req.content):
            self.rows[r['key']] = r['data']
        return httpx.Response(201)


def test_backup_and_restore_roundtrip():
    src = Fake(); src.rows = {'account:a': {'chips': 5}, 'global:clubs': {}}
    kv = SupabaseKV('https://x.supabase.co', 'k', transport=httpx.MockTransport(src.h))
    data = B.backup(kv)
    assert data['count'] == 2
    dst = Fake()
    kv2 = SupabaseKV('https://x.supabase.co', 'k', transport=httpx.MockTransport(dst.h))
    assert B.restore(kv2, data) == 2 and dst.rows == src.rows


def test_corrupt_backup_is_rejected():
    kv = SupabaseKV('https://x.supabase.co', 'k', transport=httpx.MockTransport(Fake().h))
    for bad in ({}, {'format': 'okeyx-kv-backup-1', 'rows': {'a': 1}, 'count': 9}):
        try:
            B.restore(kv, bad); assert False
        except ValueError:
            pass


def test_request_id_header_and_error_isolation():
    c = TestClient(app, raise_server_exceptions=False)
    r = c.get('/healthz')
    assert r.headers.get('x-request-id')

    @app.get('/__boom')
    def boom():
        raise RuntimeError('secret internal detail')

    r = c.get('/__boom')
    assert r.status_code == 500 and 'secret' not in r.text and r.json()['detail'] == 'internal_error'
    assert O.snapshot()['status_counts'].get('5xx', 0) >= 1


def test_terms_page_public():
    assert 'Kullanım Şartları' in TestClient(app).get('/terms').text


def test_admin_ops_requires_key_and_reports(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, 'admin_key', 'S3cure-Admin-Key-1234567890')
    c = TestClient(app)
    assert c.get('/api/phase4/admin/ops').status_code == 401
    r = c.get('/api/phase4/admin/ops', headers={'x-admin-key': 'S3cure-Admin-Key-1234567890'})
    assert r.status_code == 200 and {'rooms', 'accounts', 'status_counts', 'storage'} <= set(r.json())
