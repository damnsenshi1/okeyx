from __future__ import annotations
import secrets
import time
import uuid
from copy import deepcopy
from typing import Any
SLOT_PAYLINES = [[0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [2, 2, 2, 2, 2], [0, 1, 2, 1, 0], [2, 1, 0, 1, 2], [0, 0, 1, 2, 2], [2, 2, 1, 0, 0], [1, 0, 1, 2, 1], [1, 2, 1, 0, 1]]
DEFAULT_BETS = [100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000]
SLOT_LINE_IDS = list(range(1, 10))
VOUCHERS = [100, 1000, 5000, 10000, 25000, 50000, 100000, 250000]
SLOT_BASE_RTP = 0.94
SLOT_TIERS: list[dict[str, Any]] = [{'multiplier': 0.5, 'probability': 0.2, 'symbol': 'cherry', 'count': 3, 'label': 'Kısmi dönüş', 'jackpot_tier': ''}, {'multiplier': 1.0, 'probability': 0.15, 'symbol': 'bar', 'count': 3, 'label': 'Bahis iadesi', 'jackpot_tier': ''}, {'multiplier': 2.0, 'probability': 0.1, 'symbol': 'cherry', 'count': 4, 'label': 'Mini Win', 'jackpot_tier': ''}, {'multiplier': 5.0, 'probability': 0.04, 'symbol': 'star', 'count': 3, 'label': 'Star Win', 'jackpot_tier': ''}, {'multiplier': 8.0, 'probability': 0.015, 'symbol': 'bar', 'count': 5, 'label': 'Nice Win', 'jackpot_tier': ''}, {'multiplier': 20.0, 'probability': 0.004, 'symbol': 'star', 'count': 5, 'label': 'MINI JACKPOT', 'jackpot_tier': 'MINI'}, {'multiplier': 50.0, 'probability': 0.0008, 'symbol': 'crown', 'count': 5, 'label': 'MAJOR JACKPOT', 'jackpot_tier': 'MAJOR'}, {'multiplier': 150.0, 'probability': 0.0002, 'symbol': 'okey', 'count': 5, 'label': 'MEGA JACKPOT', 'jackpot_tier': 'MEGA'}, {'multiplier': 750.0, 'probability': 2e-05, 'symbol': 'diamond', 'count': 5, 'label': 'EPIC WIN', 'jackpot_tier': 'EPIC'}, {'multiplier': 5000.0, 'probability': 1e-06, 'symbol': 'seven', 'count': 5, 'label': 'GRAND JACKPOT', 'jackpot_tier': 'GRAND'}]
SLOT_SYMBOLS = ['cherry', 'bar', 'star', 'crown', 'okey', 'diamond', 'seven']

def weighted(rows, key='weight'):
    total = sum((max(0, int(x.get(key, 0))) for x in rows))
    if total <= 0:
        return rows[0]
    r = secrets.randbelow(total)
    c = 0
    for x in rows:
        c += max(0, int(x.get(key, 0)))
        if r < c:
            return x
    return rows[-1]

def _slot_probabilities(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    target = max(0.6, min(0.98, float(cfg.get('rtp_percent', SLOT_BASE_RTP * 100)) / 100.0))
    scale = target / SLOT_BASE_RTP
    positive = [{**row, 'probability': float(row['probability']) * scale} for row in SLOT_TIERS]
    positive_total = sum((float(x['probability']) for x in positive))
    loss = max(0.0, 1.0 - positive_total)
    return [{'multiplier': 0.0, 'probability': loss, 'symbol': None, 'count': 0, 'label': 'Kayıp'}] + positive

def _pick_slot_tier(cfg: dict[str, Any]) -> dict[str, Any]:
    rows = _slot_probabilities(cfg)
    weights = [max(0, int(round(float(x['probability']) * 100000000))) for x in rows]
    total = sum(weights)
    if total <= 0:
        return rows[0]
    draw = secrets.randbelow(total)
    acc = 0
    for row, weight in zip(rows, weights):
        acc += weight
        if draw < acc:
            return row
    return rows[-1]

def base_rtp(cfg: dict[str, Any]) -> float:
    return round(sum((float(x['multiplier']) * float(x['probability']) for x in SLOT_TIERS)) * 100, 6)

def slot_catalog(cfg: dict[str, Any]) -> dict[str, Any]:
    out = deepcopy(cfg)
    active = max(60.0, min(98.0, float(cfg.get('rtp_percent', 94.0))))
    tiers = _slot_probabilities({**cfg, 'rtp_percent': active})
    out.update({'reels': 5, 'rows': 3, 'paylines': deepcopy(SLOT_PAYLINES), 'payline_count': 9, 'line_options': deepcopy(SLOT_LINE_IDS), 'bet_mode': 'per_line', 'bet_options': cfg.get('bet_options') or DEFAULT_BETS, 'voucher_denominations': VOUCHERS, 'base_rtp_percent': round(base_rtp(cfg), 2), 'active_rtp_percent': round(active, 2), 'volatility': 'high', 'max_multiplier': 5000, 'example_max_50k': 250000000, 'symbols': deepcopy(SLOT_SYMBOLS), 'jackpots': [{'name': 'MINI', 'multiplier': 20}, {'name': 'MAJOR', 'multiplier': 50}, {'name': 'MEGA', 'multiplier': 150}, {'name': 'GRAND', 'multiplier': 5000}], 'payout_tiers': [{'multiplier': x['multiplier'], 'probability_percent': round(float(x['probability']) * 100, 6), 'label': x['label'], 'jackpot_tier': x.get('jackpot_tier', '')} for x in tiers if float(x['multiplier']) > 0]})
    return out

def validate_bet(cfg: dict[str, Any], wager: int) -> int:
    wager = int(wager)
    allowed = [int(x) for x in cfg.get('bet_options', DEFAULT_BETS)]
    if wager not in allowed or wager < 1 or wager > 250000:
        raise ValueError('invalid_wager')
    return wager

def charge(a: dict[str, Any], wager: int, use_voucher: bool=False):
    if use_voucher:
        v = a.setdefault('slot_vouchers', {})
        k = str(wager)
        if int(v.get(k, 0)) <= 0:
            raise ValueError('slot_voucher_unavailable')
        v[k] = int(v[k]) - 1
        return
    if int(a.get('chips', 0)) < wager:
        raise ValueError('insufficient_coins')
    a['chips'] = int(a.get('chips', 0)) - wager
    a.setdefault('stats', {})['chips_spent'] = int(a.get('stats', {}).get('chips_spent', 0)) + wager

def _safe_grid() -> list[list[str]]:
    return [[SLOT_SYMBOLS[(row * 2 + col * 3) % len(SLOT_SYMBOLS)] for col in range(5)] for row in range(3)]

def _grid_for_tier(tier: dict[str, Any], line: int=2) -> tuple[list[list[str]], list[dict[str, Any]]]:
    grid = _safe_grid()
    mult = float(tier.get('multiplier', 0))
    if mult <= 0:
        return (grid, [])
    symbol = str(tier.get('symbol') or 'cherry')
    count = max(3, min(5, int(tier.get('count', 3))))
    line = int(line)
    if line < 1 or line > len(SLOT_PAYLINES):
        line = 2
    rows = SLOT_PAYLINES[line - 1]
    for reel in range(count):
        grid[rows[reel]][reel] = symbol
    if count < 5 and grid[rows[count]][count] == symbol:
        grid[rows[count]][count] = 'diamond' if symbol != 'diamond' else 'bar'
    return (grid, [{'line': line, 'symbol': symbol, 'count': count, 'multiplier': mult, 'rows': rows}])

def _validate_slot_lines(active_lines: list[int] | None) -> list[int]:
    if active_lines is None:
        return [2]
    cleaned: list[int] = []
    for raw in active_lines:
        try:
            line = int(raw)
        except (TypeError, ValueError):
            continue
        if 1 <= line <= len(SLOT_PAYLINES) and line not in cleaned:
            cleaned.append(line)
    if not cleaned:
        raise ValueError('invalid_paylines')
    return cleaned[:len(SLOT_PAYLINES)]

def spin_slot(a: dict[str, Any], cfg: dict[str, Any], wager: int, use_voucher: bool=False, active_lines: list[int] | None=None) -> dict[str, Any]:
    line_bet = validate_bet(cfg, wager)
    lines = _validate_slot_lines(active_lines)
    line_count = len(lines)
    total_wager = line_bet * line_count
    if total_wager < 1 or total_wager > 2250000:
        raise ValueError('invalid_total_wager')
    charge(a, total_wager, use_voucher)
    tier = _pick_slot_tier(cfg)
    mult = float(tier.get('multiplier', 0))
    payout = max(0, int(round(total_wager * mult)))
    chosen_line = lines[secrets.randbelow(len(lines))]
    grid, wins = _grid_for_tier(tier, chosen_line)
    if wins:
        wins[0]['payout_coins'] = payout
        wins[0]['line_bet'] = line_bet
        wins[0]['active_line_count'] = line_count
    diamonds = 0
    if mult >= 5000:
        diamonds = 25
    elif mult >= 500:
        diamonds = 5
    elif mult >= 100:
        diamonds = 1
    a['chips'] = int(a.get('chips', 0)) + payout
    a['diamonds'] = int(a.get('diamonds', 0)) + diamonds
    stats = a.setdefault('stats', {})
    stats['chips_won'] = int(stats.get('chips_won', 0)) + payout
    stats['slot_spins'] = int(stats.get('slot_spins', 0)) + 1
    stats['slot_best_win'] = max(int(stats.get('slot_best_win', 0)), payout)
    stats['slot_best_multiplier'] = max(float(stats.get('slot_best_multiplier', 0)), mult)
    net = payout if use_voucher else payout - total_wager
    if mult >= 5000:
        result_class = 'jackpot'
    elif mult >= 100:
        result_class = 'mega'
    elif mult >= 10:
        result_class = 'big'
    elif mult >= 2:
        result_class = 'win'
    elif mult >= 1:
        result_class = 'push'
    elif mult > 0:
        result_class = 'partial'
    else:
        result_class = 'loss'
    return {'game': 'slot', 'wager': total_wager, 'line_bet': line_bet, 'active_lines': lines, 'line_count': line_count, 'used_voucher': bool(use_voucher), 'grid': grid, 'wins': wins, 'payout_coins': payout, 'net_coins': net, 'multiplier': mult, 'result_class': result_class, 'result_label': tier.get('label', ''), 'jackpot_tier': tier.get('jackpot_tier', ''), 'premium_diamonds': diamonds, 'rtp_percent': round(float(cfg.get('rtp_percent', 94.0)), 2), 'big_win': mult >= 10, 'mega_win': mult >= 100, 'jackpot': mult >= 5000, 'max_possible_coins': total_wager * 5000}

def horse_catalog(cfg: dict[str, Any]) -> dict[str, Any]:
    out = deepcopy(cfg)
    out['bet_options'] = cfg.get('bet_options') or DEFAULT_BETS
    out['active_rtp_percent'] = round(float(cfg.get('rtp_percent', 90)), 2)
    return out

def race(a: dict[str, Any], cfg: dict[str, Any], wager: int, choice: int) -> dict[str, Any]:
    wager = validate_bet(cfg, wager)
    horses = cfg.get('horses', [])
    selected = next((x for x in horses if int(x['id']) == int(choice)), None)
    if not selected:
        raise ValueError('invalid_horse')
    charge(a, wager)
    winner = weighted([{**x, 'weight': int(x.get('probability', 0))} for x in horses])
    scale = float(cfg.get('rtp_percent', 90)) / 90.0
    won = int(winner['id']) == int(selected['id'])
    mult = float(selected.get('base_multiplier', 0)) * scale if won else 0.0
    payout = int(round(wager * mult)) if won else 0
    a['chips'] += payout
    a['stats']['chips_won'] = int(a['stats'].get('chips_won', 0)) + payout
    rest = [x for x in horses if x['id'] != winner['id']]
    order = [int(winner['id'])]
    while rest:
        order.append(int(rest.pop(secrets.randbelow(len(rest)))['id']))
    return {'game': 'horse', 'wager': wager, 'selected': int(choice), 'winner': int(winner['id']), 'order': order, 'won': won, 'multiplier': round(mult, 2), 'payout_coins': payout, 'net_coins': payout - wager, 'rtp_percent': round(float(cfg.get('rtp_percent', 90)), 2)}

def circus_catalog(cfg: dict[str, Any]) -> dict[str, Any]:
    out = deepcopy(cfg)
    out['bet_options'] = cfg.get('bet_options') or DEFAULT_BETS
    out['active_rtp_percent'] = round(float(cfg.get('rtp_percent', 90)), 2)
    out.setdefault('title', 'Sirk Işıkları')
    return out

def circus_start(a: dict[str, Any], cfg: dict[str, Any], wager: int, challenges: dict[str, Any]) -> dict[str, Any]:
    wager = validate_bet(cfg, wager)
    charge(a, wager)
    now = int(time.time() * 1000)
    count = int(cfg.get('lamp_count', 12))
    cid = uuid.uuid4().hex[:18]
    row = {'wager': wager, 'target': secrets.randbelow(count), 'count': count, 'speed': int(cfg.get('speed_ms', 185)), 'start': now, 'expires': now + 12000, 'used': False}
    challenges[cid] = row
    return {'ok': True, 'game': 'circus', 'action': 'start', 'challenge_id': cid, 'wager': wager, 'target_index': row['target'], 'lamp_count': count, 'speed_ms': row['speed'], 'started_at_ms': now, 'expires_at_ms': row['expires']}

def circus_finish(a: dict[str, Any], cfg: dict[str, Any], cid: str, challenges: dict[str, Any]) -> dict[str, Any]:
    row = challenges.get(cid)
    if not row:
        raise ValueError('circus_challenge_not_found')
    if row.get('used'):
        raise ValueError('circus_challenge_used')
    now = int(time.time() * 1000)
    if now > row['expires']:
        row['used'] = True
        raise ValueError('circus_challenge_expired')
    row['used'] = True
    stop = (now - row['start']) // max(1, row['speed']) % row['count']
    target = row['target']
    dist = min((stop - target) % row['count'], (target - stop) % row['count'])
    scale = float(cfg.get('rtp_percent', 90)) / 90.0
    if dist == 0:
        grade = 'perfect'
        mult = float(cfg.get('exact_multiplier', 2.55)) * scale
    elif dist == 1:
        grade = 'near'
        mult = float(cfg.get('near_multiplier', 1.15)) * scale
    else:
        grade = 'miss'
        mult = 0.0
    payout = int(round(row['wager'] * mult))
    a['chips'] += payout
    a['stats']['chips_won'] = int(a['stats'].get('chips_won', 0)) + payout
    return {'ok': True, 'game': 'circus', 'action': 'finish', 'challenge_id': cid, 'stop_index': int(stop), 'target_index': int(target), 'distance': int(dist), 'grade': grade, 'wager': row['wager'], 'multiplier': round(mult, 2), 'payout_coins': payout, 'net_coins': payout - int(row['wager']), 'rtp_percent': round(float(cfg.get('rtp_percent', 90)), 2)}
DROP_MULTIPLIERS = [50.0, 10.0, 5.0, 2.0, 0.5, 0.0, 0.5, 2.0, 5.0, 10.0, 50.0]
DROP_WEIGHTS = [1, 4, 12, 40, 120, 283, 120, 40, 12, 4, 1]
DROP_BASE_RTP = sum((w * m for w, m in zip(DROP_WEIGHTS, DROP_MULTIPLIERS))) / sum(DROP_WEIGHTS)

def drop_catalog(cfg: dict[str, Any]) -> dict[str, Any]:
    out = deepcopy(cfg)
    out.setdefault('title', 'Okey Drop')
    out['bet_options'] = cfg.get('bet_options') or DEFAULT_BETS
    out['multipliers'] = list(DROP_MULTIPLIERS)
    out['rows'] = 10
    out['active_rtp_percent'] = round(float(cfg.get('rtp_percent', 91.0)), 2)
    return out

def play_drop(a: dict[str, Any], cfg: dict[str, Any], wager: int) -> dict[str, Any]:
    wager = validate_bet(cfg, wager)
    charge(a, wager)
    idx = int(weighted([{'id': i, 'weight': w} for i, w in enumerate(DROP_WEIGHTS)])['id'])
    scale = float(cfg.get('rtp_percent', 91.0)) / 100.0 / DROP_BASE_RTP
    mult = DROP_MULTIPLIERS[idx] * scale
    payout = int(round(wager * mult))
    a['chips'] += payout
    a['stats']['chips_won'] = int(a['stats'].get('chips_won', 0)) + payout
    return {'game': 'drop', 'wager': wager, 'landing_index': idx, 'multiplier': round(mult, 2), 'payout_coins': payout, 'net_coins': payout - wager, 'path_seed': secrets.randbelow(2 ** 31 - 1), 'rtp_percent': round(float(cfg.get('rtp_percent', 91.0)), 2)}
TOWER_MULTIPLIERS = [1.35, 1.9, 2.8, 4.4, 7.5, 13.0]

def tower_catalog(cfg: dict[str, Any]) -> dict[str, Any]:
    out = deepcopy(cfg)
    out.setdefault('title', 'Kasa Kulesi')
    out['bet_options'] = cfg.get('bet_options') or [1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000]
    out['floors'] = len(TOWER_MULTIPLIERS)
    out['multipliers'] = list(TOWER_MULTIPLIERS)
    out['doors_per_floor'] = 3
    return out

def tower_start(a: dict[str, Any], cfg: dict[str, Any], wager: int, challenges: dict[str, Any]) -> dict[str, Any]:
    wager = validate_bet(cfg, wager)
    charge(a, wager)
    cid = uuid.uuid4().hex[:18]
    now = int(time.time() * 1000)
    traps = [secrets.randbelow(3) for _ in TOWER_MULTIPLIERS]
    challenges[cid] = {'wager': wager, 'floor': 0, 'traps': traps, 'used': False, 'created': now, 'expires': now + 120000}
    return {'ok': True, 'game': 'tower', 'action': 'start', 'challenge_id': cid, 'wager': wager, 'floor': 0, 'next_multiplier': TOWER_MULTIPLIERS[0], 'expires_at_ms': now + 120000}

def tower_choose(a: dict[str, Any], cfg: dict[str, Any], cid: str, choice: int, challenges: dict[str, Any]) -> dict[str, Any]:
    row = challenges.get(cid)
    if not row:
        raise ValueError('tower_challenge_not_found')
    if row.get('used'):
        raise ValueError('tower_challenge_used')
    if int(time.time() * 1000) > int(row.get('expires', 0)):
        row['used'] = True
        raise ValueError('tower_challenge_expired')
    floor = int(row.get('floor', 0))
    if floor < 0 or floor >= len(TOWER_MULTIPLIERS):
        raise ValueError('tower_finished')
    choice = int(choice)
    if choice not in (0, 1, 2):
        raise ValueError('tower_invalid_door')
    trap = int(row['traps'][floor])
    if choice == trap:
        row['used'] = True
        return {'ok': True, 'game': 'tower', 'action': 'choose', 'challenge_id': cid, 'floor': floor, 'choice': choice, 'safe': False, 'payout_coins': 0, 'multiplier': 0.0, 'finished': True}
    row['floor'] = floor + 1
    if row['floor'] >= len(TOWER_MULTIPLIERS):
        mult = TOWER_MULTIPLIERS[-1]
        payout = int(round(int(row['wager']) * mult))
        a['chips'] += payout
        a['stats']['chips_won'] = int(a['stats'].get('chips_won', 0)) + payout
        row['used'] = True
        return {'ok': True, 'game': 'tower', 'action': 'choose', 'challenge_id': cid, 'floor': floor, 'choice': choice, 'safe': True, 'payout_coins': payout, 'multiplier': mult, 'finished': True, 'cleared': True}
    current_mult = TOWER_MULTIPLIERS[floor]
    return {'ok': True, 'game': 'tower', 'action': 'choose', 'challenge_id': cid, 'floor': row['floor'], 'choice': choice, 'safe': True, 'payout_coins': 0, 'current_multiplier': current_mult, 'next_multiplier': TOWER_MULTIPLIERS[row['floor']], 'finished': False}

def tower_cashout(a: dict[str, Any], cfg: dict[str, Any], cid: str, challenges: dict[str, Any]) -> dict[str, Any]:
    row = challenges.get(cid)
    if not row:
        raise ValueError('tower_challenge_not_found')
    if row.get('used'):
        raise ValueError('tower_challenge_used')
    floor = int(row.get('floor', 0))
    if floor <= 0:
        raise ValueError('tower_nothing_to_cashout')
    mult = TOWER_MULTIPLIERS[floor - 1]
    payout = int(round(int(row['wager']) * mult))
    a['chips'] += payout
    a['stats']['chips_won'] = int(a['stats'].get('chips_won', 0)) + payout
    row['used'] = True
    return {'ok': True, 'game': 'tower', 'action': 'cashout', 'challenge_id': cid, 'floor': floor, 'multiplier': mult, 'payout_coins': payout, 'net_coins': payout - int(row['wager']), 'finished': True}
