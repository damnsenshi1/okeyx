"""Haftalık turnuva: puanı yalnızca sunucu hesaplar (settle_match), ödül yalnızca sunucuda verilir."""
from __future__ import annotations

from copy import deepcopy
from typing import Any

WIN_POINTS = 30
LOSS_POINTS = 5
MIN_GAMES_FOR_PRIZE = 3
PRIZES = ((1, 1, 250_000), (2, 2, 150_000), (3, 3, 100_000), (4, 10, 40_000), (11, 50, 15_000))
PARTICIPATION = 5_000


def prize_for_rank(rank: int) -> int:
    for lo, hi, coins in PRIZES:
        if lo <= rank <= hi:
            return coins
    return PARTICIPATION


def _board(store) -> dict[str, Any]:
    return store._data.setdefault('tournaments', {})


def record_result(store, week: str, player_id: str, name: str, won: bool) -> None:
    """settle_match içinden (kilit altında) çağrılır."""
    week_row = _board(store).setdefault(week, {'players': {}, 'claimed': []})
    row = week_row['players'].setdefault(player_id, {'name': name, 'points': 0, 'games': 0, 'wins': 0})
    row['name'] = name
    row['games'] += 1
    row['wins'] += 1 if won else 0
    row['points'] += WIN_POINTS if won else LOSS_POINTS
    # Son 6 haftayı tut.
    for old in sorted(_board(store))[:-6]:
        _board(store).pop(old, None)


def standings(store, week: str) -> list[dict[str, Any]]:
    rows = [{'id': pid, **r} for pid, r in (_board(store).get(week, {}).get('players') or {}).items()]
    rows.sort(key=lambda r: (-r['points'], -r['wins'], r['games'], r['name'].lower()))
    for i, r in enumerate(rows, 1):
        r['rank'] = i
    return rows


def view(store, week: str, prev_week: str, player_id: str) -> dict[str, Any]:
    with store._lock:
        cur = standings(store, week)
        prev = standings(store, prev_week)
        mine = next((deepcopy(r) for r in cur if r['id'] == player_id), None)
        my_prev = next((r for r in prev if r['id'] == player_id), None)
        claimed = player_id in (_board(store).get(prev_week, {}).get('claimed') or [])
        claimable = 0
        if my_prev and not claimed:
            claimable = prize_for_rank(my_prev['rank']) if my_prev['games'] >= MIN_GAMES_FOR_PRIZE else 0
        return {
            'week': week,
            'rows': [{k: r[k] for k in ('rank', 'name', 'points', 'games', 'wins')} for r in cur[:20]],
            'me': mine,
            'prizes': [{'from': lo, 'to': hi, 'coins': c} for lo, hi, c in PRIZES],
            'min_games_for_prize': MIN_GAMES_FOR_PRIZE,
            'previous': {'week': prev_week, 'my_rank': my_prev['rank'] if my_prev else None, 'claimable_coins': claimable, 'claimed': claimed},
        }


def claim_previous(store, prev_week: str, player_id: str) -> dict[str, Any]:
    with store._lock:
        rows = standings(store, prev_week)
        mine = next((r for r in rows if r['id'] == player_id), None)
        wk = _board(store).get(prev_week)
        if not mine or not wk:
            return {'ok': False, 'code': 'no_result'}
        if player_id in wk['claimed']:
            return {'ok': False, 'code': 'already_claimed'}
        if mine['games'] < MIN_GAMES_FOR_PRIZE:
            return {'ok': False, 'code': 'not_enough_games', 'needed': MIN_GAMES_FOR_PRIZE}
        coins = prize_for_rank(mine['rank'])
        acc = store._data['accounts'][player_id]
        acc['chips'] = int(acc.get('chips', 0)) + coins
        acc.setdefault('stats', {})['chips_won'] = int(acc.get('stats', {}).get('chips_won', 0)) + coins
        wk['claimed'].append(player_id)
        store._save()
        return {'ok': True, 'rank': mine['rank'], 'coins': coins, 'chips': int(acc['chips'])}
