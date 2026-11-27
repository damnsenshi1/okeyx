"""Yönetici paneli için canlı sistem testi.

Sunucuda gerçek masalara dokunmadan, botlarla yüzlerce maç oynatır ve her
hamleden sonra kural bütünlüğünü denetler (106 taş, kopya taş yok, yerdeki
perler geçerli). Ayrıca depolama ve anlık bildirim bağlantısını dener.
Sonuç, hatanın örnekleriyle birlikte döner; aynı sonuç tekrar çıkarsa
tohum (seed) ile birebir yeniden üretilebilir.
"""
from __future__ import annotations

import random
import time
import traceback
from typing import Any

from app.services.game_runtime import Room

_CONFIGS = [
    {'variant': 'non_fold', 'turbo': False, 'team_mode': 'solo', 'assisted': True},
    {'variant': 'fold', 'turbo': False, 'team_mode': 'solo', 'assisted': True},
    {'variant': 'duz', 'turbo': False, 'team_mode': 'solo', 'assisted': True},
    {'variant': 'non_fold', 'turbo': True, 'team_mode': 'paired', 'assisted': True},
    {'variant': 'fold', 'turbo': False, 'team_mode': 'paired', 'assisted': False},
    {'variant': 'non_fold', 'turbo': False, 'team_mode': 'solo', 'assisted': False},
]


def _label(cfg: dict) -> str:
    v = {'non_fold': '101 katlamasız', 'fold': '101 katlamalı', 'duz': 'Klasik'}[cfg['variant']]
    return f"{v}{' • turbo' if cfg['turbo'] else ''}{' • eşli' if cfg['team_mode'] == 'paired' else ''}{'' if cfg['assisted'] else ' • yardımsız'}"


def play_one(seed: int, cfg: dict, max_steps: int = 900) -> dict[str, Any]:
    r = Room(seed, cfg['variant'], entry_fee=5000, assisted=cfg['assisted'], turbo=cfg['turbo'],
             max_rounds=1, waiting=False, team_mode=cfg['team_mode'], random_starter=True, intro_seconds=0)
    for seat in range(4):
        r.set_player_identity(seat, f'selftest-{seat}', f'Bot {seat + 1}', bot=True, bot_level='hard' if seat % 2 else 'medium')
    steps = 0
    while r.state.phase != 'finished' and steps < max_steps:
        seat = r.state.current_seat
        before = (r.state.turn_no, seat, r.state.phase, len(r.state.stock))
        r.bot_turn(seat)
        steps += 1
        issues = r.audit_state()
        if issues:
            return {'ok': False, 'seed': seed, 'mode': _label(cfg), 'steps': steps, 'error': 'kural bütünlüğü: ' + ', '.join(issues[:3])}
        if (r.state.turn_no, r.state.current_seat, r.state.phase, len(r.state.stock)) == before:
            return {'ok': False, 'seed': seed, 'mode': _label(cfg), 'steps': steps, 'error': f'bot hamle yapamadı (koltuk {seat + 1}, aşama {r.state.phase})'}
    if r.state.phase != 'finished':
        return {'ok': False, 'seed': seed, 'mode': _label(cfg), 'steps': steps, 'error': 'el bitmedi (takıldı)'}
    return {'ok': True, 'steps': steps, 'reason': r.state.round_end_reason}


def run_games(count: int = 200, time_budget_s: float = 25.0, seed_base: int | None = None) -> dict[str, Any]:
    count = max(1, min(int(count), 500))
    base = seed_base if seed_base is not None else random.randrange(1, 9_000_000)
    started = time.time()
    played = passed = 0
    failures: list[dict] = []
    reasons: dict[str, int] = {}
    total_steps = 0
    for i in range(count):
        if time.time() - started > time_budget_s:
            break
        cfg = _CONFIGS[i % len(_CONFIGS)]
        seed = base + i
        try:
            res = play_one(seed, cfg)
        except Exception as exc:  # noqa: BLE001 — hata rapora yazılır
            tb = traceback.extract_tb(exc.__traceback__)
            where = f'{tb[-1].filename.rsplit("/", 1)[-1]}:{tb[-1].lineno}' if tb else ''
            res = {'ok': False, 'seed': seed, 'mode': _label(cfg), 'error': f'{type(exc).__name__}: {str(exc)[:120]} ({where})'}
        played += 1
        if res.get('ok'):
            passed += 1
            total_steps += int(res.get('steps', 0))
            key = str(res.get('reason') or 'bitti')
            reasons[key] = reasons.get(key, 0) + 1
        elif len(failures) < 15:
            failures.append(res)
    return {
        'name': 'Botlarla maç simülasyonu', 'requested': count, 'played': played, 'passed': passed,
        'failed': played - passed, 'seed_base': base, 'seconds': round(time.time() - started, 1),
        'avg_moves': round(total_steps / passed, 1) if passed else 0, 'end_reasons': reasons, 'failures': failures,
        'ok': played > 0 and played == passed,
    }
