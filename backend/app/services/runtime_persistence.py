from __future__ import annotations

import gzip
import hashlib
import hmac
import os
import pickle
import tempfile
from pathlib import Path
from typing import Any

MAGIC = b'OKEYX8\x00'


def _mac(secret: str, payload: bytes) -> bytes:
    return hmac.new(secret.encode('utf-8'), payload, hashlib.sha256).digest()


def save_runtime(path: str, secret: str, rooms: dict[str, Any], meta: dict[str, dict]) -> None:
    """Atomically persist active authoritative rooms for restart recovery.

    The snapshot is an internal server artifact, never user supplied. An HMAC
    prevents a modified/corrupt file from being unpickled on the next boot.
    WebSocket objects are intentionally not persisted; clients reconnect with
    their existing reconnect token and receive a fresh authoritative state.
    """
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    safe_meta: dict[str, dict] = {}
    for room_id, row in meta.items():
        copied = dict(row)
        # Rate-limit/dedupe history is ephemeral and can grow; rebuilding it is
        # safe while seat/reconnect/economy ownership must survive.
        copied['action_times'] = {}
        copied['chat_times'] = {}
        copied['dedupe'] = {}
        copied['connected'] = {int(k): False for k in copied.get('connected', {})}
        copied['disconnect_at'] = {}
        safe_meta[room_id] = copied
    raw = pickle.dumps({'rooms': rooms, 'meta': safe_meta}, protocol=pickle.HIGHEST_PROTOCOL)
    compressed = gzip.compress(raw, compresslevel=6)
    blob = MAGIC + _mac(secret, compressed) + compressed
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


def load_runtime(path: str, secret: str) -> tuple[dict[str, Any], dict[str, dict]]:
    target = Path(path)
    if not target.exists():
        return {}, {}
    blob = target.read_bytes()
    if len(blob) < len(MAGIC) + 32 or not blob.startswith(MAGIC):
        return {}, {}
    signature = blob[len(MAGIC):len(MAGIC) + 32]
    compressed = blob[len(MAGIC) + 32:]
    if not hmac.compare_digest(signature, _mac(secret, compressed)):
        return {}, {}
    try:
        payload = pickle.loads(gzip.decompress(compressed))
    except Exception:
        return {}, {}
    if not isinstance(payload, dict):
        return {}, {}
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
