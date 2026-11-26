"""Render diski geçici: aktif masalar Supabase'e yansıtılır ve disk silinince geri gelir."""
import json

import httpx

from app.services.game_runtime import Room
from app.services.remote_store import SupabaseKV
from app.services.runtime_persistence import RemoteMirror, load_runtime, restore_from_remote, save_runtime


class Fake:
    def __init__(self):
        self.rows = {}

    def handler(self, req: httpx.Request):
        if req.method == 'GET':
            key = req.url.params.get('key', '')[3:]
            return httpx.Response(200, json=[{'data': self.rows[key]}] if key in self.rows else [])
        if req.method == 'POST':
            for r in json.loads(req.content):
                self.rows[r['key']] = r['data']
            return httpx.Response(201)
        return httpx.Response(405)

    def kv(self):
        return SupabaseKV('https://x.supabase.co', 'k', transport=httpx.MockTransport(self.handler))


def _snapshot(path, secret):
    room = Room(seed=5, random_starter=False)
    rid = room.state.room_id
    save_runtime(str(path), secret, {rid: room}, {rid: {'state_version': 1, 'seat_tokens': {0: 't'}, 'player_ids': {0: 'p'}, 'connected': {0: True}}})
    return rid


def test_rooms_survive_disk_loss_via_supabase(tmp_path):
    fake = Fake()
    kv = fake.kv()
    path = tmp_path / 'a' / 'rooms.bin'
    rid = _snapshot(path, 'sec')
    assert RemoteMirror(kv).push_now(str(path))
    path.unlink()  # Render yeniden başladı, disk boş
    assert restore_from_remote(kv, str(path))
    rooms, _ = load_runtime(str(path), 'sec')
    assert rid in rooms


def test_restored_blob_is_rejected_with_wrong_secret(tmp_path):
    fake = Fake()
    kv = fake.kv()
    path = tmp_path / 'rooms.bin'
    _snapshot(path, 'right')
    RemoteMirror(kv).push_now(str(path))
    path.unlink()
    restore_from_remote(kv, str(path))
    assert load_runtime(str(path), 'wrong') == ({}, {})


def test_restore_does_not_overwrite_existing_local_file(tmp_path):
    fake = Fake()
    kv = fake.kv()
    path = tmp_path / 'rooms.bin'
    _snapshot(path, 's')
    assert restore_from_remote(kv, str(path)) is False


def test_runtime_secret_is_never_the_old_insecure_default(monkeypatch):
    from app.core.config import settings
    monkeypatch.setattr(settings, 'runtime_secret', '')
    monkeypatch.setattr(settings, 'supabase_service_role_key', 'srv-key-123')
    a = settings.effective_runtime_secret
    assert 'change-me' not in a and len(a) == 64
    monkeypatch.setattr(settings, 'supabase_service_role_key', 'other')
    assert settings.effective_runtime_secret != a
