from fastapi import FastAPI, APIRouter, HTTPException, Query
import re
import time
from html import unescape
import httpx
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from app.api.health import router as health_router
from app.api.game import router as game_router, start_watchdog
from app.core.auth import _jwks
from app.api.account import router as account_router
from app.api.phase4 import router as phase4_router
from app.core.ratelimit import rate_limit_middleware

app=FastAPI(title=settings.app_name,version='12.0.7')
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)
app.middleware('http')(rate_limit_middleware)
app.include_router(health_router)

_radio_cache: dict[str, tuple[float, dict]] = {}

@app.get('/api/radio/now-playing')
async def radio_now_playing(station: str = Query('kral_pop')):
    station = station.strip().lower()
    pages = {
        'kral_pop': 'https://www.kralmuzik.com.tr/radyo/kral-pop',
        'kral_fm': 'https://www.kralmuzik.com.tr/radyo/kral-fm/',
        'power_fm': 'https://www.powerapp.com.tr/radios/powerfm/',
        'power_turk': 'https://www.powerapp.com.tr/radios/powerturk/',
        'metro_fm': 'https://metrofm.com.tr/frekanslar',
        'fenomen': 'https://www.radyofenomen.com/',
    }
    url = pages.get(station)
    if not url:
        raise HTTPException(404, 'radio_station_not_found')
    cached = _radio_cache.get(station)
    now = time.monotonic()
    if cached and now - cached[0] < 12:
        return cached[1]
    try:
        async with httpx.AsyncClient(
            timeout=httpx.Timeout(4.0, connect=2.0),
            follow_redirects=True,
            headers={'User-Agent': 'Mozilla/5.0 OkeyX/12.0.7', 'Accept': 'text/html,application/xhtml+xml'},
        ) as client:
            response = await client.get(url)
            response.raise_for_status()
            page = response.text
        # The station pages expose current artist/title as adjacent H2/H3.
        matches = re.findall(r'<h2[^>]*>(.*?)</h2>\s*<h3[^>]*>(.*?)</h3>', page, re.I | re.S)
        def clean(value: str) -> str:
            value = re.sub(r'<[^>]+>', ' ', value)
            return re.sub(r'\s+', ' ', unescape(value)).strip()
        artist = title = ''
        for a, t in matches:
            a, t = clean(a), clean(t)
            if a and t and '%' not in a and '%' not in t and len(a) < 120 and len(t) < 160:
                artist, title = a, t
                break
        if not (artist or title):
            plain = clean(page)
            if station == 'fenomen':
                m = re.search(r"Şu anda Radyo Fenomen'de\s+(.+?)\s+(.+?)\s+DİNLE", plain, re.I)
                if m:
                    artist, title = m.group(1).strip(), m.group(2).strip()
            elif station == 'metro_fm':
                m = re.search(r'ŞU AN ÇALAN\s+(.{2,80}?)\s+CANLI DİNLE', plain, re.I)
                if m:
                    title = m.group(1).strip()
        payload = {'ok': bool(artist or title), 'station': station, 'artist': artist, 'title': title}
        if artist or title:
            _radio_cache[station] = (now, payload)
        elif cached:
            return cached[1]
        return payload
    except Exception as exc:
        if cached:
            return cached[1]
        return {'ok': False, 'station': station, 'artist': '', 'title': '', 'error': type(exc).__name__}


# Google/Supabase auth is optional for local guest development.
# An older venv can therefore still start the lobby instead of killing the whole backend.
try:
    from app.api.auth_me import router as auth_router
    app.include_router(auth_router,prefix='/api')
except ModuleNotFoundError:
    fallback=APIRouter()
    @fallback.get('/auth/me')
    async def auth_unavailable():
        raise HTTPException(503,'google_auth_dependencies_missing')
    app.include_router(fallback,prefix='/api')

app.include_router(game_router,prefix='/api')
app.include_router(account_router,prefix='/api')
app.include_router(phase4_router,prefix='/api')

@app.on_event('startup')
async def _startup_watchdog():
    # Local USB gameplay must become healthy immediately. Supabase JWKS is only
    # needed by the internet/release bootstrap path; waiting for it here was
    # making /healthz look ready late and the Flutter lobby time out.
    if not settings.local_dev_mode:
        try:
            await _jwks()
        except Exception as exc:
            print(f'OKEYX_JWKS_PREWARM_FAIL {exc}', flush=True)
    else:
        print('OKEYX_LOCAL_GAMEPLAY_READY', flush=True)
    start_watchdog()


@app.on_event('shutdown')
async def _shutdown_flush():
    # Kapanmadan önce bekleyen hesap değişikliklerini Supabase'e yaz.
    try:
        from app.services.account_store import STORE
        STORE.flush()
    except Exception as exc:
        print(f'OKEYX_SHUTDOWN_FLUSH_FAIL {exc}', flush=True)
