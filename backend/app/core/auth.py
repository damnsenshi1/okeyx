from __future__ import annotations
import time
from fastapi import Header, HTTPException
from jose import jwt, JWTError
import httpx
from .config import settings

# JWKS önbelleği: 1 saat geçerli. Bilinmeyen bir kid gelirse (Supabase anahtar
# döndürdüyse) en fazla 60 saniyede bir yeniden çekilir.
JWKS_TTL_SECONDS = 3600
JWKS_MIN_REFETCH_SECONDS = 60

_jwks_cache: dict | None = None
_jwks_fetched_at: float = 0.0


async def _fetch_jwks() -> dict:
    global _jwks_cache, _jwks_fetched_at
    if not settings.supabase_url:
        raise HTTPException(503, 'SUPABASE_URL is not configured')
    async with httpx.AsyncClient(timeout=10) as c:
        r = await c.get(f'{settings.supabase_url.rstrip("/")}/auth/v1/.well-known/jwks.json')
        r.raise_for_status()
        _jwks_cache = r.json()
        _jwks_fetched_at = time.monotonic()
        return _jwks_cache


async def _jwks(force: bool = False) -> dict:
    now = time.monotonic()
    if _jwks_cache and not force and now - _jwks_fetched_at < JWKS_TTL_SECONDS:
        return _jwks_cache
    if _jwks_cache and force and now - _jwks_fetched_at < JWKS_MIN_REFETCH_SECONDS:
        return _jwks_cache
    try:
        return await _fetch_jwks()
    except Exception:
        # Supabase kısa süre erişilemezse eldeki eski anahtarlarla devam et.
        if _jwks_cache:
            return _jwks_cache
        raise


def _find_key(keys: list[dict], kid) -> dict | None:
    return next((k for k in keys if k.get('kid') == kid), None)


async def current_user(authorization: str | None = Header(None)):
    if not authorization or not authorization.lower().startswith('bearer '):
        raise HTTPException(401, 'missing_bearer')
    token = authorization.split(' ', 1)[1]
    try:
        header = jwt.get_unverified_header(token)
        keys = (await _jwks()).get('keys', [])
        key = _find_key(keys, header.get('kid'))
        if key is None:
            # Anahtar döndürülmüş olabilir: bir kez zorla yenile.
            keys = (await _jwks(force=True)).get('keys', [])
            key = _find_key(keys, header.get('kid'))
        if key is None:
            raise HTTPException(401, 'invalid_token')
        claims = jwt.decode(
            token, key, algorithms=[header.get('alg', 'RS256')],
            audience=settings.supabase_jwt_audience,
            issuer=f'{settings.supabase_url.rstrip("/")}/auth/v1',
        )
        return {'id': claims['sub'], 'email': claims.get('email'), 'claims': claims}
    except (JWTError, KeyError) as e:
        raise HTTPException(401, 'invalid_token') from e
