from __future__ import annotations

import gzip
import hashlib
import hmac
import os
import pickle
import tempfile
from pathlib import Path
from typing import Any
import threading

MAGIC = b'OKEYX8\x00'


def _mac(secret: str, payload: bytes) -> bytes:
    return hmac.new(secret.encode('utf-8'), payload, hashlib.sha256).digest()


MAGIC_V2 = b'OKEYX9\x00'

# Oda başına önbellek: yalnız durumu değişen (state_version artan) odalar
# yeniden pickle edilir. Eskiden her kayıtta bütün odalar olay döngüsünde
# serileştiriliyordu; 100 masada ~20 ms, Render free CPU'da bunun katları
# kadar bütün oyuncuların hamlesi bekliyordu.
_ROOM_BYTES: dict[str, tuple[Any, bytes]] = {}
_WRITE_LOCK = threading.Lock()


def _safe_meta_row(row: dict) -> dict:
    copied = dict(row)
    # Rate-limit/dedupe history is ephemeral and can grow; rebuilding it is
    # safe while seat/reconnect/economy ownership must survive.
    copied['action_times'] = {}
    copied['chat_times'] = {}
    copied['dedupe'] = {}
    copied['connected'] = {int(k): False for k in copied.get('connected', {})}
    copied['disconnect_at'] = {}
    return copied


def build_runtime_blob(rooms: dict[str, Any], meta: dict[str, dict]) -> bytes:
    """Olay döngüsünde çalışan ucuz kısım: değişen odaları pickle eder."""
    packed: dict[str, bytes] = {}
    for room_id, room in list(rooms.items()):
        row = meta.get(room_id, {})
        try:
            st = room.state
            version = (int(row.get('state_version', 0) or 0), st.turn_no, len(st.stock), st.phase,
                       st.event_seq, len(st.log), len(st.melds), st.round_index, len(row.get('chat', []) or []))
        except Exception:
            version = 0
        cached = _ROOM_BYTES.get(room_id)
        if cached and version and cached[0] == version:
            packed[room_id] = cached[1]
            continue
        data = pickle.dumps((room, _safe_meta_row(row)), protocol=pickle.HIGHEST_PROTOCOL)
        if version:
            _ROOM_BYTES[room_id] = (version, data)
        packed[room_id] = data
    for gone in set(_ROOM_BYTES) - set(rooms):
        _ROOM_BYTES.pop(gone, None)
    return pickle.dumps({'v': 2, 'rooms': packed}, protocol=pickle.HIGHEST_PROTOCOL)


def write_runtime_blob(path: str, secret: str, raw: bytes) -> None:
    """Thread'de çalışabilen kısım: sıkıştır, imzala, atomik yaz."""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    compressed = gzip.compress(raw, compresslevel=1)
    blob = MAGIC_V2 + _mac(secret, compressed) + compressed
    with _WRITE_LOCK:
        fd, tmp_name = tempfile.mkstemp(prefix='okeyx-runtime-', dir=str(target.parent))
        try:
            with os.fdopen(fd, 'wb') as handle:
                handle.write(blob)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp_name, target)
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)


def save_runtime(path: str, secret: str, rooms: dict[str, Any], meta: dict[str, dict]) -> None:
    """Atomically persist active authoritative rooms for restart recovery.

    The snapshot is an internal server artifact, never user supplied. An HMAC
    prevents a modified/corrupt file from being unpickled on the next boot.
    WebSocket objects are intentionally not persisted; clients reconnect with
    their existing reconnect token and receive a fresh authoritative state.
    """
    write_runtime_blob(path, secret, build_runtime_blob(rooms, meta))


def load_runtime(path: str, secret: str) -> tuple[dict[str, Any], dict[str, dict]]:
    target = Path(path)
    if not target.exists():
        return {}, {}
    blob = target.read_bytes()
    magic = MAGIC_V2 if blob.startswith(MAGIC_V2) else MAGIC
    if len(blob) < len(magic) + 32 or not blob.startswith(magic):
        return {}, {}
    signature = blob[len(magic):len(magic) + 32]
    compressed = blob[len(magic) + 32:]
    if not hmac.compare_digest(signature, _mac(secret, compressed)):
        return {}, {}
    try:
        payload = pickle.loads(gzip.decompress(compressed))
    except Exception:
        return {}, {}
    if not isinstance(payload, dict):
        return {}, {}
    if payload.get('v') == 2 and isinstance(payload.get('rooms'), dict):
        rooms, meta = {}, {}
        for room_id, data in payload['rooms'].items():
            try:
                room, row = pickle.loads(data)
            except Exception:
                continue
            rooms[room_id] = room
            meta[room_id] = row
    else:
        rooms = payload.get('rooms') if isinstance(payload.get('rooms'), dict) else {}
        meta = payload.get('meta') if isinstance(payload.get('meta'), dict) else {}
    # Old/finished rooms do not need to occupy memory forever.
    clean_rooms = {}
    clean_meta = {}
    for room_id, room in rooms.items():
        try:
            if room.state.match_finished:
                continue
            # Recreate service references/caches defensively after code updates.
            from app.services.game_service import GameService
            room.service = GameService(room.state)
            room._assist_cache_key = None
            room._assist_cache_value = (0, 0, [], [], 0)
            clean_rooms[room_id] = room
            clean_meta[room_id] = meta.get(room_id, {})
        except Exception:
            continue
    return clean_rooms, clean_meta


# --- Uzak (Supabase) yansıtma: Render diski her yeniden başlatmada silinir ---------
import base64
import threading
import time as _time

REMOTE_KEY = 'runtime:rooms'
MAX_REMOTE_BYTES = 3_500_000


class RemoteMirror:
    """Son oda anlık görüntüsünü arka plan iş parçacığıyla Supabase'e yansıtır.

    Blob zaten HMAC imzalıdır; geri yüklenirken load_runtime aynı imzayı doğrular.
    """

    def __init__(self, kv, interval: float = 8.0):
        self.kv = kv
        self.interval = interval
        self._last = 0.0
        self._busy = threading.Lock()

    def maybe_push(self, path: str, force: bool = False) -> bool:
        now = _time.monotonic()
        if not force and now - self._last < self.interval:
            return False
        if not self._busy.acquire(blocking=False):
            return False
        self._last = now
        threading.Thread(target=self._push, args=(path,), daemon=True).start()
        return True

    def _push(self, path: str) -> None:
        try:
            blob = Path(path).read_bytes()
            if len(blob) <= MAX_REMOTE_BYTES:
                self.kv.upsert({REMOTE_KEY: {'b64': base64.b64encode(blob).decode('ascii'), 'at': int(_time.time())}})
        except Exception:
            pass
        finally:
            self._busy.release()

    def push_now(self, path: str) -> bool:
        """Kapanışta eşzamanlı yazım."""
        try:
            blob = Path(path).read_bytes()
            if len(blob) > MAX_REMOTE_BYTES:
                return False
            self.kv.upsert({REMOTE_KEY: {'b64': base64.b64encode(blob).decode('ascii'), 'at': int(_time.time())}})
            return True
        except Exception:
            return False


def restore_from_remote(kv, path: str) -> bool:
    """Yerel dosya yoksa Supabase'teki son anlık görüntüyü diske yazar (imza yüklemede doğrulanır)."""
    target = Path(path)
    if target.exists():
        return False
    try:
        row = kv.get(REMOTE_KEY)
        if not row or not row.get('b64'):
            return False
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(base64.b64decode(row['b64']))
        return True
    except Exception:
        return False
