from __future__ import annotations
from fastapi import Header, HTTPException
from jose import jwt, JWTError
import httpx
from .config import settings
_jwks_cache: dict | None = None

async def _jwks():
    global _jwks_cache
    if _jwks_cache:
        return _jwks_cache
    if not settings.supabase_url:
        raise HTTPException(503, 'SUPABASE_URL is not configured')
    async with httpx.AsyncClient(timeout=10) as c:
        r = await c.get(f"{settings.supabase_url.rstrip('/')}/auth/v1/.well-known/jwks.json")
        r.raise_for_status()
        _jwks_cache = r.json()
        return _jwks_cache

async def current_user(authorization: str | None=Header(None)):
    if not authorization or not authorization.lower().startswith('bearer '):
        raise HTTPException(401, 'missing_bearer')
    token = authorization.split(' ', 1)[1]
    try:
        header = jwt.get_unverified_header(token)
        keys = (await _jwks()).get('keys', [])
        key = next((k for k in keys if k.get('kid') == header.get('kid')))
        claims = jwt.decode(token, key, algorithms=[header.get('alg', 'RS256')], audience=settings.supabase_jwt_audience, issuer=f"{settings.supabase_url.rstrip('/')}/auth/v1")
        return {'id': claims['sub'], 'email': claims.get('email'), 'claims': claims}
    except (JWTError, StopIteration, KeyError) as e:
        raise HTTPException(401, 'invalid_token') from e
