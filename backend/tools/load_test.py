"""OKEYX yük testi.

Kullanım:
  python tools/load_test.py --base https://okeyx-mp-eu.onrender.com --players 100 --seconds 60

Her sanal oyuncu: misafir hesap açar -> botlu antrenman masasına oturur ->
sırası geldikçe desteden çekip bir taş atar, diğer zamanlarda durumu sorgular.
Sonunda istek sayısı, hata oranı ve gecikme yüzdelikleri yazılır.
NOT: Canlı sunucuda çalıştırırsan hız sınırına takılmamak için az oyuncuyla başla.
"""
from __future__ import annotations

import argparse
import asyncio
import statistics
import time
import uuid

import httpx


SIMULATE_DEVICES = False


class Stats:
    def __init__(self):
        self.lat: list[float] = []
        self.errors: dict[str, int] = {}
        self.ok = 0
        self.moves = 0

    def add(self, dt: float, code: str | None):
        self.lat.append(dt)
        if code is None:
            self.ok += 1
        else:
            self.errors[code] = self.errors.get(code, 0) + 1


async def call(client: httpx.AsyncClient, stats: Stats, method: str, path: str, **kw):
    t = time.perf_counter()
    try:
        r = await client.request(method, path, **kw)
        dt = time.perf_counter() - t
        if r.status_code >= 400:
            stats.add(dt, f'http_{r.status_code}')
            if r.status_code == 429:
                await asyncio.sleep(1.5)  # sunucu hız sınırı: gerçek istemci gibi geri çekil
            return None
        stats.add(dt, None)
        return r.json()
    except Exception as exc:  # zaman aşımı / bağlantı
        stats.add(time.perf_counter() - t, type(exc).__name__)
        return None


async def player(base: str, stats: Stats, deadline: float, idx: int, mode: str = 'practice'):
    pid = f'load-{uuid.uuid4().hex[:10]}'
    # Yerel testte her sanal oyuncu ayrı bir cihaz gibi görünsün (IP bazlı
    # hesap açma sınırı tek makineden gelen tüm oyuncuları kesmesin).
    hdr = {'X-Forwarded-For': f'10.{idx // 65536 % 256}.{idx // 256 % 256}.{idx % 256}'} if SIMULATE_DEVICES else {}
    async with httpx.AsyncClient(base_url=base, timeout=15.0, headers=hdr) as c:
        acc = await call(c, stats, 'POST', '/api/account/bootstrap', json={'player_id': pid, 'name': f'Yuk{idx}'})
        if not acc:
            return
        tok = acc.get('session_token', '')
        path = '/api/lobby/practice' if mode == 'practice' else '/api/lobby/quick'
        body = {'player_id': pid, 'account_token': tok, 'name': f'Yuk{idx}'}
        if mode == 'quick':
            body.update({'entry_fee': 500, 'turbo': False, 'variant': 'non_fold', 'team_mode': 'solo', 'rounds': 1, 'assisted': True})
        room = await call(c, stats, 'POST', path, json=body)
        if not room:
            return
        rid, seat, rtok = room['room_id'], room['seat'], room['reconnect_token']
        while time.time() < deadline:
            st = await call(c, stats, 'GET', f'/api/game/{rid}', params={'seat': seat, 'reconnect_token': rtok})
            if not st:
                await asyncio.sleep(1.0); continue
            st = st.get('state', st)
            if st.get('phase') == 'finished':
                break
            if st.get('current_seat') == seat and st.get('started'):
                if st.get('phase') == 'draw':
                    await call(c, stats, 'POST', f'/api/game/{rid}/action', json={'seat': seat, 'kind': 'draw_stock', 'reconnect_token': rtok})
                    continue
                if st.get('phase') == 'discard':
                    me = next(p for p in st['players'] if p['seat'] == seat)
                    hand = [t for t in me.get('hand', []) if not t.get('joker')] or me.get('hand', [])
                    if hand:
                        out = await call(c, stats, 'POST', f'/api/game/{rid}/action', json={'seat': seat, 'kind': 'discard', 'payload': {'tile_id': hand[0]['id']}, 'reconnect_token': rtok})
                        if out is not None:
                            stats.moves += 1
                    continue
            await asyncio.sleep(0.8)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--base', default='http://127.0.0.1:8000')
    ap.add_argument('--players', type=int, default=100)
    ap.add_argument('--seconds', type=int, default=60)
    ap.add_argument('--ramp', type=float, default=10.0, help='oyuncuların kaç saniyede katılacağı')
    ap.add_argument('--simulate-devices', action='store_true', help='yalnızca yerel test: her oyuncuya ayrı X-Forwarded-For')
    ap.add_argument('--mode', choices=['practice', 'quick'], default='quick', help='quick: 4 gerçek oyunculu masalar; practice: herkese 3 botlu masa (en ağır senaryo)')
    a = ap.parse_args()
    global SIMULATE_DEVICES
    SIMULATE_DEVICES = bool(a.simulate_devices)
    stats = Stats()
    deadline = time.time() + a.seconds
    tasks = []
    for i in range(a.players):
        tasks.append(asyncio.create_task(player(a.base, stats, deadline, i, a.mode)))
        await asyncio.sleep(a.ramp / max(1, a.players))
    await asyncio.gather(*tasks)
    lat = sorted(stats.lat) or [0.0]
    pct = lambda p: lat[min(len(lat) - 1, int(len(lat) * p))] * 1000
    total = stats.ok + sum(stats.errors.values())
    print(f'mod={a.mode} oyuncu={a.players} sure={a.seconds}s istek={total} basarili={stats.ok} hamle={stats.moves}')
    print(f'hata_orani=%{100 * (total - stats.ok) / max(1, total):.2f} hatalar={stats.errors}')
    print(f'gecikme ms: ort={statistics.mean(lat) * 1000:.0f} p50={pct(.5):.0f} p95={pct(.95):.0f} p99={pct(.99):.0f} max={lat[-1] * 1000:.0f}')
    print(f'istek/sn={total / a.seconds:.1f}')


if __name__ == '__main__':
    asyncio.run(main())
