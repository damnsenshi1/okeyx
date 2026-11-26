"""Hata kaydı, yavaş istek takibi ve bellek içi sayaçlar (Render günlüklerine yazılır)."""
from __future__ import annotations

import logging
import time
import uuid
from collections import Counter, deque

from starlette.requests import Request
from starlette.responses import JSONResponse

log = logging.getLogger('okeyx')
if not log.handlers:
    h = logging.StreamHandler()
    h.setFormatter(logging.Formatter('%(asctime)s %(levelname)s okeyx %(message)s'))
    log.addHandler(h)
    log.setLevel(logging.INFO)

SLOW_SECONDS = 1.5
STARTED = time.time()
STATUS = Counter()           # '2xx','4xx','5xx'
SLOW: deque = deque(maxlen=50)   # son yavaş istekler
ERRORS: deque = deque(maxlen=50)  # son 5xx / istisnalar


def snapshot() -> dict:
    return {
        'uptime_seconds': int(time.time() - STARTED),
        'status_counts': dict(STATUS),
        'recent_slow': list(SLOW)[-10:],
        'recent_errors': list(ERRORS)[-10:],
    }


async def observability_middleware(request: Request, call_next):
    rid = uuid.uuid4().hex[:10]
    t0 = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception as exc:  # beklenmeyen hata: kaydet, gövdeyi sızdırma
        ERRORS.append({'rid': rid, 'path': request.url.path, 'error': type(exc).__name__, 'at': int(time.time())})
        STATUS['5xx'] += 1
        log.exception('unhandled rid=%s %s %s', rid, request.method, request.url.path)
        return JSONResponse({'detail': 'internal_error', 'request_id': rid}, status_code=500)
    dt = time.perf_counter() - t0
    STATUS[f'{response.status_code // 100}xx'] += 1
    if response.status_code >= 500:
        ERRORS.append({'rid': rid, 'path': request.url.path, 'status': response.status_code, 'at': int(time.time())})
        log.error('5xx rid=%s %s %s -> %s', rid, request.method, request.url.path, response.status_code)
    if dt >= SLOW_SECONDS:
        SLOW.append({'rid': rid, 'path': request.url.path, 'seconds': round(dt, 2), 'at': int(time.time())})
        log.warning('slow rid=%s %s %s %.2fs', rid, request.method, request.url.path, dt)
    response.headers['X-Request-Id'] = rid
    return response
