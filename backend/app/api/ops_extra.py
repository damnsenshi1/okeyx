"""Yayın sonrası operasyon uçları.

- /api/telemetry/crash   : uygulama çökme/hata raporları (Crashlytics yerine kendi sunucumuz)
- /api/ads/admob-ssv     : AdMob ödüllü reklam sunucu doğrulaması (Google ECDSA imzası)
- /api/phase4/admin/crashes, /api/phase4/admin/refund-sync : yönetici uçları
- /api/push/test         : yönetici için FCM deneme bildirimi
"""
from __future__ import annotations

import base64
import hashlib
import json
import time
from collections import deque
from typing import Any
from urllib.parse import unquote

import httpx
from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, Field

from app.api.phase4 import _admin, _svc, _google_client
from app.core.config import settings
from app.services.account_store import STORE

router = APIRouter(tags=['ops'])

# ---------------------------------------------------------------- crash reports
CRASH_LIMIT = 300
_crash_hits: dict[str, deque] = {}


class CrashIn(BaseModel):
    player_id: str | None = Field(None, max_length=80)
    app_version: str = Field('', max_length=32)
    platform: str = Field('android', max_length=24)
    device: str = Field('', max_length=80)
    error: str = Field('', max_length=600)
    stack: str = Field('', max_length=6000)
    fatal: bool = False
    context: str = Field('', max_length=120)


def _client_ip(request: Request) -> str:
    fwd = request.headers.get('x-forwarded-for')
    return fwd.split(',')[0].strip() if fwd else (request.client.host if request.client else '?')


@router.post('/telemetry/crash')
def report_crash(body: CrashIn, request: Request):
    ip = _client_ip(request)
    q = _crash_hits.setdefault(ip, deque())
    now = time.monotonic()
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= 10:  # cihaz başına dakikada 10 rapor
        return {'ok': False, 'code': 'rate_limited'}
    q.append(now)
    sig = hashlib.sha1((body.error[:200] + body.stack[:400]).encode('utf-8', 'ignore')).hexdigest()[:12]
    with STORE._lock:
        tel = STORE._data.setdefault('telemetry', {})
        crashes = tel.setdefault('crashes', [])
        groups = tel.setdefault('crash_groups', {})
        g = groups.setdefault(sig, {'count': 0, 'first_at': int(time.time()), 'error': body.error[:200]})
        g['count'] += 1; g['last_at'] = int(time.time()); g['last_version'] = body.app_version
        crashes.append({'sig': sig, 'at': int(time.time()), **body.model_dump()})
        del crashes[:-CRASH_LIMIT]
        if len(groups) > 400:
            for k in sorted(groups, key=lambda k: groups[k].get('last_at', 0))[:100]:
                groups.pop(k, None)
        STORE._save()
    return {'ok': True, 'sig': sig}


@router.get('/phase4/admin/crashes')
def admin_crashes(limit: int = 50, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    tel = STORE._data.get('telemetry', {})
    groups = sorted(({'sig': k, **v} for k, v in tel.get('crash_groups', {}).items()), key=lambda g: -g['count'])
    return {'groups': groups[:limit], 'recent': list(reversed(tel.get('crashes', [])[-limit:]))}


# ---------------------------------------------------------------- AdMob SSV
ADMOB_KEYS_URL = 'https://www.gstatic.com/admob/reward/verifier-keys.json'
_admob_keys: tuple[float, dict[str, str]] | None = None


def _fetch_admob_keys() -> dict[str, str]:
    global _admob_keys
    if _admob_keys and time.time() - _admob_keys[0] < 6 * 3600:
        return _admob_keys[1]
    r = httpx.get(ADMOB_KEYS_URL, timeout=8.0)
    r.raise_for_status()
    keys = {str(k['keyId']): k['pem'] for k in r.json().get('keys', [])}
    _admob_keys = (time.time(), keys)
    return keys


def verify_admob_signature(raw_query: str, keys: dict[str, str]) -> dict[str, str]:
    """Google'ın belgelediği yöntem: 'signature' parametresinden önceki ham sorgu
    metni, key_id ile seçilen ECDSA (P-256/SHA256) açık anahtarıyla doğrulanır."""
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    idx = raw_query.find('&signature=')
    if idx < 0:
        raise ValueError('signature_missing')
    message = raw_query[:idx].encode('utf-8')
    tail = raw_query[idx + 1:]
    params_tail = dict(p.split('=', 1) for p in tail.split('&') if '=' in p)
    sig_b64 = unquote(params_tail.get('signature', ''))
    key_id = unquote(params_tail.get('key_id', ''))
    pem = keys.get(key_id)
    if not pem:
        raise ValueError('unknown_key_id')
    sig = base64.urlsafe_b64decode(sig_b64 + '=' * (-len(sig_b64) % 4))
    pub = serialization.load_pem_public_key(pem.encode('utf-8'))
    try:
        pub.verify(sig, message, ec.ECDSA(hashes.SHA256()))  # type: ignore[union-attr]
    except InvalidSignature as exc:
        raise ValueError('bad_signature') from exc
    return {k: unquote(v) for k, v in (p.split('=', 1) for p in raw_query[:idx].split('&') if '=' in p)}


@router.get('/ads/admob-ssv')
def admob_ssv(request: Request):
    raw = request.url.query
    if not raw:
        return {'ok': True, 'probe': True}  # AdMob konsolu URL doğrulaması
    try:
        params = verify_admob_signature(raw, _fetch_admob_keys())
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    except httpx.HTTPError:
        raise HTTPException(503, 'admob_keys_unavailable')
    token = params.get('custom_data', '')
    out = _svc().mark_ad_ssv(token, params.get('transaction_id', ''), params.get('reward_item', ''))
    if not out.get('ok'):
        raise HTTPException(404, out.get('code', 'ad_session_invalid'))
    return out


# ---------------------------------------------------------------- refunds
def sync_google_refunds(days: int = 30) -> dict[str, Any]:
    client = _google_client()
    start = int((time.time() - days * 86400) * 1000)
    voided = client.voided_purchases(start)
    reversed_n = 0; unknown = 0
    for v in voided:
        order = str(v.get('orderId') or '')
        if not order:
            continue
        reason = 'chargeback' if int(v.get('voidedReason', 0) or 0) == 7 else 'refund'
        out = _svc().refund_purchase('google_play', order, reason)
        if out.get('ok') and not out.get('already_reversed'):
            reversed_n += 1
        elif not out.get('ok'):
            unknown += 1
    with STORE._lock:
        STORE._data.setdefault('telemetry', {})['last_refund_sync'] = {'at': int(time.time()), 'voided': len(voided), 'reversed': reversed_n}
    return {'ok': True, 'voided': len(voided), 'reversed': reversed_n, 'unknown': unknown}


@router.post('/phase4/admin/refund-sync')
def admin_refund_sync(days: int = 30, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return sync_google_refunds(max(1, min(60, days)))


class SupportIn(BaseModel):
    player_id: str = Field(..., max_length=80)
    topic: str = Field('purchase', max_length=24)
    order_id: str = Field('', max_length=64)
    message: str = Field(..., min_length=5, max_length=800)


@router.post('/support/ticket')
def support_ticket(body: SupportIn, x_account_token: str | None = Header(None)):
    """Yanlış satın alma / iade / hesap sorunu için destek talebi."""
    if not STORE.verify(body.player_id, x_account_token):
        raise HTTPException(401, 'invalid_account_token')
    from app.core.textfilter import mask
    with STORE._lock:
        tickets = STORE._data.setdefault('support_tickets', [])
        mine_today = [t for t in tickets if t['player_id'] == body.player_id and time.time() - t['at'] < 86400]
        if len(mine_today) >= 5:
            return {'ok': False, 'code': 'ticket_limit'}
        tid = hashlib.sha1(f'{body.player_id}{time.time()}'.encode()).hexdigest()[:10].upper()
        tickets.append({'id': tid, 'player_id': body.player_id, 'topic': body.topic, 'order_id': body.order_id, 'message': mask(body.message), 'at': int(time.time()), 'status': 'open'})
        del tickets[:-1000]
        STORE._save()
    STORE.add_notification(body.player_id, 'Destek talebin alındı', f'Talep no: {tid}. En kısa sürede dönüş yapılacak.', 'support')
    return {'ok': True, 'ticket_id': tid}


@router.get('/phase4/admin/support')
def admin_support(x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return {'tickets': list(reversed(STORE._data.get('support_tickets', [])[-200:]))}


class TicketUpdateIn(BaseModel):
    ticket_id: str
    status: str = Field(..., pattern='^(open|resolved|refunded|rejected)$')
    note: str = Field('', max_length=400)


@router.post('/phase4/admin/support/update')
def admin_support_update(body: TicketUpdateIn, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    with STORE._lock:
        t = next((t for t in STORE._data.get('support_tickets', []) if t['id'] == body.ticket_id), None)
        if not t:
            raise HTTPException(404, 'ticket_not_found')
        t['status'] = body.status; t['note'] = body.note; t['updated_at'] = int(time.time())
        STORE._save()
    STORE.add_notification(t['player_id'], 'Destek talebin güncellendi', f'{t["id"]}: {body.status}. {body.note}'.strip(), 'support')
    return {'ok': True}


# ---------------------------------------------------------------- push (FCM v1)
class FcmSender:
    SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

    def __init__(self, sa_json: str, project_id: str = '', transport: httpx.BaseTransport | None = None):
        self.sa = json.loads(sa_json)
        self.project = project_id or self.sa.get('project_id', '')
        self._http = httpx.Client(timeout=10.0, transport=transport)
        self._token: tuple[str, float] | None = None

    def _access(self) -> str:
        from jose import jwt
        now = time.time()
        if self._token and self._token[1] > now + 60:
            return self._token[0]
        aud = self.sa.get('token_uri', 'https://oauth2.googleapis.com/token')
        assertion = jwt.encode({'iss': self.sa['client_email'], 'scope': self.SCOPE, 'aud': aud, 'iat': int(now), 'exp': int(now) + 3300}, self.sa['private_key'], algorithm='RS256')
        r = self._http.post(aud, data={'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': assertion})
        r.raise_for_status()
        self._token = (r.json()['access_token'], now + 3300)
        return self._token[0]

    def send(self, token: str, title: str, body: str, data: dict[str, str] | None = None) -> bool:
        msg = {'message': {'token': token, 'notification': {'title': title[:80], 'body': body[:200]},
                           'data': {k: str(v) for k, v in (data or {}).items()},
                           'android': {'priority': 'high'}}}
        r = self._http.post(f'https://fcm.googleapis.com/v1/projects/{self.project}/messages:send', json=msg,
                            headers={'Authorization': f'Bearer {self._access()}'})
        return r.status_code == 200


_FCM: FcmSender | None = None


def fcm() -> FcmSender | None:
    global _FCM
    if _FCM is None and settings.fcm_service_account_json:
        try:
            _FCM = FcmSender(settings.fcm_service_account_json, settings.fcm_project_id)
        except Exception:
            return None
    return _FCM


def push_to_player(player_id: str, title: str, body: str, data: dict[str, str] | None = None) -> int:
    """Oyuncunun kayıtlı cihazlarına push gönderir; push kapalıysa 0 döner."""
    sender = fcm()
    if not sender:
        return 0
    acc = STORE.get(player_id) or {}
    prefs = acc.get('notification_prefs') or {}
    kind = (data or {}).get('kind', '')
    pref_key = 'friend' if kind.startswith('friend') else 'invite' if kind == 'invite' else 'event' if kind in ('event', 'tournament', 'canak') else 'daily' if kind == 'daily_ready' else None
    if prefs.get('push') is False or (pref_key and prefs.get(pref_key) is False):
        return 0
    sent = 0
    for tok in list(acc.get('push_tokens') or [])[-3:]:
        try:
            sent += 1 if sender.send(tok, title, body, data) else 0
        except Exception:
            pass
    return sent


class PushTestIn(BaseModel):
    player_id: str
    title: str = 'OKEYX'
    body: str = 'Deneme bildirimi'


@router.post('/phase4/admin/push-test')
def admin_push_test(body: PushTestIn, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    if not fcm():
        raise HTTPException(503, 'push_not_configured')
    return {'sent': push_to_player(body.player_id, body.title, body.body)}


class PrefsIn(BaseModel):
    push: bool | None = None
    friend: bool | None = None
    invite: bool | None = None
    daily: bool | None = None
    event: bool | None = None


@router.post('/account/{player_id}/notification-prefs')
def notification_prefs(player_id: str, body: PrefsIn, x_account_token: str | None = Header(None)):
    if not STORE.verify(player_id, x_account_token):
        raise HTTPException(401, 'invalid_account_token')
    return {'ok': True, 'prefs': STORE.set_notification_prefs(player_id, {k: v for k, v in body.model_dump().items() if v is not None}), 'push_available': fcm() is not None}


def send_daily_reminders(now: float | None = None) -> int:
    """Türkiye saatiyle 12:00'den sonra, günün ödülünü almamış ve push açık
    oyunculara günde bir kez hatırlatma gönderir."""
    from app.services.account_store import _day_key
    now = time.time() if now is None else now
    tr_hour = int(((now + 3 * 3600) % 86400) // 3600)
    if tr_hour < 12 or not fcm():
        return 0
    today = _day_key(int(now))
    tel = STORE._data.setdefault('telemetry', {})
    if tel.get('daily_reminder_day') == today:
        return 0
    tel['daily_reminder_day'] = today
    targets = [pid for pid, a in list(STORE._data.get('accounts', {}).items())
               if a.get('push_tokens') and (a.get('daily') or {}).get('last_claim_day') != today]
    sent = 0
    for pid in targets[:5000]:
        sent += push_to_player(pid, 'Günlük ödülün hazır!', 'OKEYX\'e gir, bugünün altınını al.', {'kind': 'daily_ready'})
    return sent


def notify_started_events(now: float | None = None) -> int:
    """Başlamış ama henüz duyurulmamış canlı etkinlikleri push ile duyurur (bir kez)."""
    if not fcm():
        return 0
    now_ms = int((time.time() if now is None else now) * 1000)
    events = (STORE._data.get('phase4', {}).get('global', {}) or {}).get('live_events', []) or []
    tel = STORE._data.setdefault('telemetry', {})
    done = set(tel.get('announced_events', []))
    sent = 0
    for ev in events:
        eid = str(ev.get('id', ''))
        if not eid or eid in done or not ev.get('enabled', True):
            continue
        if int(ev.get('starts_at', 0) or 0) <= now_ms <= int(ev.get('ends_at', 0) or 0):
            done.add(eid)
            for pid, a in list(STORE._data.get('accounts', {}).items())[:5000]:
                if a.get('push_tokens'):
                    sent += push_to_player(pid, 'Etkinlik başladı: ' + str(ev.get('title', ''))[:40], str(ev.get('subtitle', '') or 'Hemen katıl!')[:120], {'kind': 'event', 'event_id': eid})
    tel['announced_events'] = sorted(done)[-200:]
    return sent


async def background_ops_loop():
    """Saatlik bakım: günlük ödül hatırlatması; 6 saatte bir Google iade senkronu."""
    import asyncio
    await asyncio.sleep(120)
    tick = 0
    while True:
        for job in (send_daily_reminders, notify_started_events):
            try:
                await asyncio.to_thread(job)
            except Exception:
                pass
        if settings.google_play_service_account_json and tick % 6 == 0:
            try:
                await asyncio.to_thread(sync_google_refunds, 7)
            except Exception:
                pass
        tick += 1
        await asyncio.sleep(3600)


# ---------------------------------------------------------------- performance diagnostics
@router.get('/ops/performance')
def ops_performance(x_admin_key: str | None = Header(None)):
    """Admin-only live diagnostics for slow API requests and game runtime load."""
    _admin(x_admin_key)
    from app.core.observability import snapshot as observability_snapshot
    from app.api import game as game_api
    room_count = len(game_api.ROOMS)
    waiting_count = sum(1 for room in game_api.ROOMS.values() if room.state.phase == 'waiting')
    active_count = sum(1 for room in game_api.ROOMS.values() if room.state.started and room.state.phase != 'finished')
    socket_count = sum(len(sockets) for seats in game_api.SOCKETS.values() for sockets in seats.values())
    remote = STORE.remote_status()
    return {
        'ok': True,
        'process': observability_snapshot(),
        'game': {
            'rooms': room_count,
            'waiting_rooms': waiting_count,
            'active_rooms': active_count,
            'websocket_connections': socket_count,
            'quick_fill_tasks': sum(1 for task in game_api.QUICK_FILL_TASKS.values() if not task.done()),
            'runtime_dirty': bool(game_api._RUNTIME_DIRTY),
            'last_runtime_persist_age_seconds': round(max(0.0, time.monotonic() - game_api._LAST_PERSIST_AT), 2) if game_api._LAST_PERSIST_AT else None,
        },
        'storage': remote,
    }
