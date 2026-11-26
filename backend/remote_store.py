"""Supabase (PostgREST) üzerinde kalıcı anahtar-değer deposu.

Render ücretsiz planda disk geçicidir; hesaplar/coinler orada tutulamaz.
Bu modül AccountStore'un tüm verisini `okeyx_server_kv` tablosuna yazar:

  account:<oyuncu_id>   -> tek oyuncunun hesabı
  global:<ad>           -> clubs, reports, canak, activity, phase4 ...

Tablo yalnızca service_role anahtarıyla erişilir (RLS açık, politika yok).
"""
from __future__ import annotations

import hashlib
import json
import threading
import time
from typing import Any, Callable

import httpx

TABLE = 'okeyx_server_kv'
PAGE = 1000
BATCH = 200


class RemoteStoreError(RuntimeError):
    pass


class SupabaseKV:
    def __init__(self, url: str, service_key: str, transport: httpx.BaseTransport | None = None, timeout: float = 12.0):
        self.base = url.rstrip('/') + '/rest/v1/' + TABLE
        self.headers = {
            'apikey': service_key,
            'Authorization': f'Bearer {service_key}',
            'Content-Type': 'application/json',
        }
        self._client = httpx.Client(timeout=timeout, transport=transport)

    def load_all(self) -> dict[str, Any]:
        out: dict[str, Any] = {}
        offset = 0
        while True:
            r = self._client.get(
                self.base,
                params={'select': 'key,data', 'order': 'key.asc', 'limit': PAGE, 'offset': offset},
                headers=self.headers,
            )
            if r.status_code != 200:
                raise RemoteStoreError(f'load_failed:{r.status_code}:{r.text[:200]}')
            rows = r.json()
            for row in rows:
                out[str(row['key'])] = row['data']
            if len(rows) < PAGE:
                return out
            offset += PAGE

    def get(self, key: str) -> Any | None:
        r = self._client.get(
            self.base,
            params={'select': 'data', 'key': 'eq.' + key, 'limit': 1},
            headers=self.headers,
        )
        if r.status_code != 200:
            raise RemoteStoreError(f'get_failed:{r.status_code}:{r.text[:200]}')
        rows = r.json()
        return rows[0]['data'] if rows else None

    def upsert(self, rows: dict[str, Any]) -> None:
        items = list(rows.items())
        for i in range(0, len(items), BATCH):
            chunk = [{'key': k, 'data': v, 'updated_at': 'now()'} for k, v in items[i:i + BATCH]]
            for row in chunk:
                row['updated_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
            r = self._client.post(
                self.base + '?on_conflict=key',
                headers={**self.headers, 'Prefer': 'resolution=merge-duplicates,return=minimal'},
                content=json.dumps(chunk, ensure_ascii=False).encode('utf-8'),
            )
            if r.status_code not in (200, 201, 204):
                raise RemoteStoreError(f'upsert_failed:{r.status_code}:{r.text[:200]}')

    def delete(self, keys: list[str]) -> None:
        for i in range(0, len(keys), BATCH):
            chunk = keys[i:i + BATCH]
            quoted = ','.join('"' + k.replace('"', '') + '"' for k in chunk)
            r = self._client.delete(
                self.base, params={'key': f'in.({quoted})'},
                headers={**self.headers, 'Prefer': 'return=minimal'},
            )
            if r.status_code not in (200, 204):
                raise RemoteStoreError(f'delete_failed:{r.status_code}:{r.text[:200]}')


def split_state(data: dict) -> dict[str, Any]:
    """AccountStore._data -> düz anahtar sözlüğü."""
    rows: dict[str, Any] = {}
    for pid, acc in (data.get('accounts') or {}).items():
        rows[f'account:{pid}'] = acc
    for name, value in data.items():
        if name != 'accounts':
            rows[f'global:{name}'] = value
    return rows


def merge_state(rows: dict[str, Any], base: dict) -> dict:
    """Uzaktan gelen satırlardan AccountStore._data üret (base varsayılanları korur)."""
    data = {k: (dict(v) if isinstance(v, dict) and k == 'accounts' else v) for k, v in base.items()}
    data['accounts'] = {}
    for key, value in rows.items():
        if key.startswith('account:'):
            data['accounts'][key[len('account:'):]] = value
        elif key.startswith('global:'):
            data[key[len('global:'):]] = value
    return data


def digest(value: Any) -> str:
    return hashlib.md5(json.dumps(value, sort_keys=True, ensure_ascii=False, default=str).encode('utf-8')).hexdigest()


class RemoteSync:
    """AccountStore için arka plan yazıcısı: değişen satırları ~2 sn'de bir gönderir."""

    def __init__(self, kv: SupabaseKV, snapshot: Callable[[], dict[str, Any]], interval: float = 2.0):
        self.kv = kv
        self._snapshot = snapshot
        self.interval = interval
        self._hashes: dict[str, str] = {}
        self._dirty = threading.Event()
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None
        self._flush_lock = threading.Lock()
        self.last_error: str | None = None
        self.loaded = False

    def mark_known(self, rows: dict[str, Any]) -> None:
        self._hashes = {k: digest(v) for k, v in rows.items()}

    def mark_dirty(self) -> None:
        self._dirty.set()

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, name='okeyx-remote-sync', daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        self._dirty.set()
        self.flush()

    def _loop(self) -> None:
        backoff = self.interval
        while not self._stop.is_set():
            self._dirty.wait(timeout=30)
            if self._stop.is_set():
                return
            time.sleep(self.interval)
            if not self._dirty.is_set():
                continue
            try:
                self.flush()
                backoff = self.interval
            except Exception as exc:  # noqa: BLE001
                self.last_error = str(exc)[:300]
                print(f'OKEYX_REMOTE_FLUSH_FAIL {self.last_error}', flush=True)
                backoff = min(backoff * 2, 60.0)
                self._dirty.set()
                time.sleep(backoff)

    def flush(self) -> int:
        """Değişenleri gönderir. Yüklenmemişse ASLA yazmaz (boş veriyle ezmeyi önler)."""
        if not self.loaded:
            return 0
        with self._flush_lock:
            self._dirty.clear()
            rows = self._snapshot()
            changed = {k: v for k, v in rows.items() if self._hashes.get(k) != digest(v)}
            removed = [k for k in self._hashes if k not in rows]
            try:
                if changed:
                    self.kv.upsert(changed)
                if removed:
                    self.kv.delete(removed)
            except Exception:
                self._dirty.set()
                raise
            for k, v in changed.items():
                self._hashes[k] = digest(v)
            for k in removed:
                self._hashes.pop(k, None)
            self.last_error = None
            return len(changed) + len(removed)
