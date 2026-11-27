"""Basit, bellek içi kayan pencere hız sınırı (tek sunucu için yeterli).

Anahtar: hesap token'ı / Authorization özeti; yoksa istemci IP'si. Mobil
operatörlerde çok kişi aynı IP'yi paylaştığı için IP yalnızca son çaredir.
"""
from __future__ import annotations

import hashlib
import time
from collections import deque

from starlette.requests import Request
from starlette.responses import JSONResponse

from .config import settings

# Giriş/hesap açma uçları: kaba kuvvet ve hesap şişirme koruması.
AUTH_PREFIXES = ('/api/account/bootstrap',)
# Coin/ödül üreten ya da para hareketi yapan uçlar.
SENSITIVE_MARKERS = (
    '/wheel', '/chest', '/daily', '/claim', '/transfer-coins', '/gift',
    '/phase4/store/buy', '/phase4/ads/', '/phase4/side-games/play',
    '/phase4/vip/', '/clubs/create', '/clubs/weekly', '/referral/redeem', '/tournament/', '/salon/claim',
)
EXEMPT_PATHS = ('/healthz', '/docs', '/openapi.json')


def _client_ip(request: Request) -> str:
    fwd = request.headers.get('x-forwarded-for')
    if fwd:
        # Render'ın proxy'si gerçek istemci IP'sini zincirin SONUNA ekler.
        # İlk eleman istemci tarafından sahte gönderilebileceği için kullanılmaz.
        return fwd.split(',')[-1].strip()
    return request.client.host if request.client else 'unknown'


def _identity(request: Request) -> str:
    token = request.headers.get('x-account-token') or request.headers.get('authorization')
    if token:
        return 't:' + hashlib.sha256(token.encode('utf-8')).hexdigest()[:20]
    return 'ip:' + _client_ip(request)


class SlidingWindow:
    def __init__(self):
        self._hits: dict[str, deque[float]] = {}
        self._last_prune = time.monotonic()

    def allow(self, key: str, limit: int, window: float = 60.0, now: float | None = None) -> tuple[bool, int]:
        now = time.monotonic() if now is None else now
        q = self._hits.setdefault(key, deque())
        while q and now - q[0] >= window:
            q.popleft()
        if len(q) >= limit:
            return False, max(1, int(window - (now - q[0])) + 1)
        q.append(now)
        if now - self._last_prune > 120:
            self._prune(now, window)
        return True, 0

    def _prune(self, now: float, window: float) -> None:
        self._last_prune = now
        for k in [k for k, q in self._hits.items() if not q or now - q[-1] >= window]:
            self._hits.pop(k, None)


WINDOW = SlidingWindow()


async def rate_limit_middleware(request: Request, call_next):
    path = request.url.path
    if request.method == 'OPTIONS' or path in EXEMPT_PATHS or not path.startswith('/api'):
        return await call_next(request)
    checks: list[tuple[str, int]] = []
    if settings.rate_limit_general_per_min > 0:
        checks.append((f'g:{_identity(request)}', settings.rate_limit_general_per_min))
    if request.method != 'GET':
        if settings.rate_limit_auth_per_min > 0 and path.startswith(AUTH_PREFIXES):
            checks.append((f'a:{_client_ip(request)}', settings.rate_limit_auth_per_min))
        if settings.rate_limit_sensitive_per_min > 0 and any(m in path for m in SENSITIVE_MARKERS):
            checks.append((f's:{_identity(request)}', settings.rate_limit_sensitive_per_min))
    for key, limit in checks:
        ok, retry = WINDOW.allow(key, limit)
        if not ok:
            return JSONResponse({'detail': 'too_many_requests'}, status_code=429, headers={'Retry-After': str(retry)})
    return await call_next(request)
