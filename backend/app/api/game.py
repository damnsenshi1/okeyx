from __future__ import annotations
import asyncio, secrets, time, uuid, hashlib, re, json
from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from app.services.game_runtime import ROOMS, new_room
from app.services.account_store import STORE, GIFT_CATALOG
from app.services.runtime_persistence import save_runtime, load_runtime
from app.core.config import settings
router = APIRouter(tags=['game'])

def _now() -> float:
    return time.time()

class ActionIn(BaseModel):
    seat: int = 0
    kind: str
    payload: dict = Field(default_factory=dict)
    reconnect_token: str | None = None
    request_id: str | None = None

class CreateRoomIn(BaseModel):
    name: str = 'OkeyX Masası'
    variant: str = 'non_fold'
    entry_fee: int = 5000
    assisted: bool = True
    turbo: bool = False
    team_mode: str = 'solo'
    rounds: int = 1
    owner_name: str = 'Sen'
    player_id: str = 'local-owner'
    account_token: str = ''
    turn_seconds: int = 35
    password: str | None = None

class JoinRoomIn(BaseModel):
    name: str = 'Oyuncu'
    player_id: str = 'local-player'
    account_token: str = ''
    turbo: bool | None = None
    variant: str | None = None
    team_mode: str | None = None
    entry_fee: int | None = None
    rounds: int | None = None
    assisted: bool | None = None
    password: str | None = None

class ChatIn(BaseModel):
    seat: int
    reconnect_token: str
    kind: str = 'quick'
    value: str
    to_seat: int | None = None

class LeaveIn(BaseModel):
    seat: int
    reconnect_token: str

class ReconnectIn(BaseModel):
    player_id: str
    account_token: str

class ManageRoomIn(BaseModel):
    seat: int = 0
    reconnect_token: str
    action: str
    target_seat: int | None = None
    room_name: str | None = None
    turn_seconds: int | None = None
    turbo: bool | None = None
    variant: str | None = None
    team_mode: str | None = None
    entry_fee: int | None = None
    rounds: int | None = None
    assisted: bool | None = None
    chat_enabled: bool | None = None
    gifts_enabled: bool | None = None
    auto_rematch: bool | None = None
SOCKETS: dict[str, dict[int, list[WebSocket]]] = {}
ROOM_META: dict[str, dict] = {}
WATCHDOG_TASK: asyncio.Task | None = None
_RUNTIME_LOADED = False
_LAST_PERSIST_AT = 0.0
_RUNTIME_DIRTY = False

def _token() -> str:
    return secrets.token_urlsafe(24)

def _persist_runtime(force: bool=False) -> None:
    global _LAST_PERSIST_AT, _RUNTIME_DIRTY
    now = time.monotonic()
    if not force and now - _LAST_PERSIST_AT < 0.35:
        _RUNTIME_DIRTY = True
        return
    try:
        save_runtime(settings.runtime_snapshot_path, settings.runtime_secret, ROOMS, ROOM_META)
        _LAST_PERSIST_AT = now
        _RUNTIME_DIRTY = False
    except Exception:
        _RUNTIME_DIRTY = True

def _restore_runtime_once() -> None:
    global _RUNTIME_LOADED
    if _RUNTIME_LOADED:
        return
    _RUNTIME_LOADED = True
    try:
        rooms, meta = load_runtime(settings.runtime_snapshot_path, settings.runtime_secret)
        ROOMS.update(rooms)
        ROOM_META.update(meta)
    except Exception:
        pass

def _touch(room_id: str) -> int:
    m = _ensure_meta(room_id, legacy=True)
    m['state_version'] = int(m.get('state_version', 0) or 0) + 1
    _persist_runtime()
    return m['state_version']

def _human_count(room_id: str) -> int:
    room = ROOMS.get(room_id)
    meta = ROOM_META.get(room_id) or {}
    if not room:
        return 0
    return sum((1 for seat, pid in (meta.get('player_ids') or {}).items() if pid and (not room.state.players[int(seat)].bot)))

def _free_human_seat(room_id: str) -> int | None:
    room = ROOMS.get(room_id)
    if not room:
        return None
    return next((seat for seat, p in room.state.players.items() if p.bot), None)

def _account(player_id: str, account_token: str):
    a = STORE.get(player_id)
    if not a:
        raise HTTPException(404, 'account_not_found')
    if not STORE.verify(player_id, account_token):
        raise HTTPException(401, 'invalid_account_token')
    try:
        from app.services.phase4_service import Phase4Service
        if Phase4Service(STORE).active_sanctions(player_id).get('banned'):
            raise HTTPException(403, 'account_banned')
    except HTTPException:
        raise
    except Exception:
        pass
    return a

def _ensure_meta(room_id: str, legacy: bool=False) -> dict:
    m = ROOM_META.get(room_id)
    if m:
        return m
    m = {'owner_seat': 0, 'seat_tokens': {}, 'player_ids': {}, 'connected': {}, 'disconnect_at': {}, 'afk_strikes': {0: 0, 1: 0, 2: 0, 3: 0}, 'action_times': {}, 'chat_times': {}, 'dedupe': {}, 'economy_charged': False, 'settled': False, 'recorded_rounds': set(), 'chat': [], 'reactions': [], 'legacy': legacy, 'created_at': _now(), 'password_hash': None, 'invited_player_ids': set(), 'chat_enabled': True, 'gifts_enabled': True, 'auto_rematch': False, 'state_version': 1, 'quick_match': False}
    ROOM_META[room_id] = m
    return m

def _bind_human(room_id: str, seat: int, player_id: str, name: str) -> str:
    room = ROOMS[room_id]
    m = _ensure_meta(room_id)
    token = m['seat_tokens'].get(seat) or _token()
    m['seat_tokens'][seat] = token
    m['player_ids'][seat] = player_id
    m['connected'].setdefault(seat, False)
    m['afk_strikes'][seat] = 0
    room.set_player_identity(seat, player_id, STORE.get(player_id)['name'], bot=False)
    _touch(room_id)
    return token

def _auth(room_id: str, seat: int, token: str | None) -> dict:
    room = ROOMS.get(room_id)
    if not room:
        raise HTTPException(404, 'room_not_found')
    m = _ensure_meta(room_id, legacy=True)
    if m.get('legacy') and (not m['seat_tokens']):
        return m
    expected = m['seat_tokens'].get(seat)
    if not expected or not token or (not secrets.compare_digest(expected, token)):
        raise HTTPException(401, 'invalid_reconnect_token')
    return m

def _rate_limit(m: dict, token: str | None):
    if not token:
        return
    now = _now()
    arr = m['action_times'].setdefault(token, [])
    arr[:] = [x for x in arr if now - x < 2.0]
    if len(arr) >= 24:
        raise HTTPException(429, 'too_many_actions')
    arr.append(now)

def _chat_rate_limit(m: dict, token: str, kind: str):
    now = _now()
    last = m.setdefault('chat_times', {}).get(token, 0.0)
    wait = 1.15 if kind == 'gift' else 0.8 if kind == 'text' else 0.55
    if now - last < wait:
        raise HTTPException(429, 'chat_cooldown')
    m['chat_times'][token] = now

def _state(room_id: str, viewer: int) -> dict:
    room = ROOMS[room_id]
    m = _ensure_meta(room_id, legacy=True)
    state = room.public_state(viewer)
    for p in state['players']:
        seat = p['seat']
        pid = m['player_ids'].get(seat)
        afk_bot = bool(p['bot'] and pid)
        p['afk_bot'] = afk_bot
        p['connected'] = bool(m['connected'].get(seat, False)) if pid else bool(p['bot'])
        p['afk_strikes'] = int(m['afk_strikes'].get(seat, 0))
        p['player_id'] = pid
        acc = STORE.get(pid) if pid else None
        p['avatar_url'] = acc.get('avatar_url') if acc else None
        if acc:
            p['level'] = int(acc.get('level', 1) or 1)
            p['chips'] = int(acc.get('chips', 0) or 0)
            vip = acc.get('vip') or {}
            p['vip_level'] = int(vip.get('level', 0) or 0)
            p['vip_badge'] = str(vip.get('badge') or (f"VIP {p['vip_level']}" if p['vip_level'] else ''))
            p['name_color'] = str(vip.get('name_color') or '')
            p['profile_frame'] = str((acc.get('equipped') or {}).get('frame') or '')
            p['loadout'] = dict(acc.get('equipped') or {})
            stats = acc.get('stats') or {}
            league = acc.get('league') or {}
            p['public_stats'] = {'games': int(stats.get('games', 0) or 0), 'wins': int(stats.get('wins', 0) or 0), 'losses': int(stats.get('losses', 0) or 0), 'best_streak': int(stats.get('best_streak', 0) or 0), 'city': str(league.get('city', 'Denizli') or 'Denizli'), 'tier': str(league.get('tier', 'Bronz') or 'Bronz')}
            p['gifts_received'] = list(acc.get('gifts_received', [])[:8])
        elif p['bot']:
            bot_level = p.get('bot_level') or 'medium'
            p['level'] = {'easy': 8, 'medium': 18, 'hard': 32, 'afk': 18}.get(bot_level, 18)
            p['chips'] = {'easy': 25000, 'medium': 85000, 'hard': 250000, 'afk': 85000}.get(bot_level, 85000)
            p['vip_level'] = 0
            p['vip_badge'] = ''
            p['name_color'] = ''
            p['profile_frame'] = ''
            p['loadout'] = {}
            p['gifts_received'] = []
            p['public_stats'] = {'games': {'easy': 38, 'medium': 146, 'hard': 412, 'afk': 0}.get(bot_level, 146), 'wins': {'easy': 9, 'medium': 57, 'hard': 196, 'afk': 0}.get(bot_level, 57), 'losses': {'easy': 29, 'medium': 89, 'hard': 216, 'afk': 0}.get(bot_level, 89), 'best_streak': {'easy': 2, 'medium': 5, 'hard': 11, 'afk': 0}.get(bot_level, 5), 'city': 'OkeyX', 'tier': {'easy': 'Bronz', 'medium': 'Gümüş', 'hard': 'Altın', 'afk': '—'}.get(bot_level, 'Gümüş')}
        else:
            p['level'] = 1
            p['chips'] = 0
            p['vip_level'] = 0
            p['vip_badge'] = ''
            p['name_color'] = ''
            p['profile_frame'] = ''
            p['loadout'] = {}
            p['gifts_received'] = []
            p['public_stats'] = {'games': 0, 'wins': 0, 'losses': 0, 'best_streak': 0, 'city': '—', 'tier': '—'}
    state['viewer_seat'] = viewer
    state['owner_seat'] = int(m.get('owner_seat', 0) or 0)
    state['chat_enabled'] = bool(m.get('chat_enabled', True))
    state['gifts_enabled'] = bool(m.get('gifts_enabled', True))
    state['auto_rematch'] = bool(m.get('auto_rematch', False))
    viewer_pid = m.get('player_ids', {}).get(viewer)
    viewer_account = STORE.get(viewer_pid) if viewer_pid else None
    hidden = set((viewer_account or {}).get('muted', [])) | set((viewer_account or {}).get('blocked', []))
    state['chat'] = [item for item in m['chat'][-20:] if item.get('kind') != 'gift' and (not item.get('player_id') or item.get('player_id') not in hidden)]
    state['reactions'] = [item for item in m.get('reactions', [])[-12:] if not item.get('player_id') or item.get('player_id') not in hidden]
    state['economy_charged'] = bool(m['economy_charged'])
    state['settlement'] = m.get('settlement')
    viewer_player = next((x for x in state['players'] if int(x.get('seat', -1)) == int(viewer)), {})
    state['viewer_afk_bot'] = bool(viewer_player.get('afk_bot'))
    state['viewer_chips'] = int(viewer_player.get('chips', 0) or 0)
    state['required_balance'] = _required_balance(int(state.get('entry_fee', 0) or 0), bool(state.get('turbo')))
    state['state_version'] = int(m.get('state_version', 1) or 1)
    state['server_time_ms'] = int(time.time() * 1000)
    state['human_count'] = _human_count(room_id)
    state['quick_match'] = bool(m.get('quick_match', False))
    return state

async def _broadcast(room_id: str, skip_seat: int | None=None):
    room = ROOMS.get(room_id)
    if not room:
        return
    seats = SOCKETS.get(room_id, {})
    jobs = []
    refs = []
    for seat, sockets in list(seats.items()):
        if skip_seat is not None and int(seat) == int(skip_seat):
            continue
        payload = {'type': 'state', 'state': _state(room_id, seat)}
        for ws in list(sockets):
            refs.append((seat, ws))
            jobs.append(asyncio.create_task(asyncio.wait_for(ws.send_json(payload), timeout=1.25)))
    if not jobs:
        return
    results = await asyncio.gather(*jobs, return_exceptions=True)
    for (seat, ws), result in zip(refs, results):
        if isinstance(result, BaseException):
            if seat in seats and ws in seats[seat]:
                seats[seat].remove(ws)

def _required_balance(entry_fee: int, turbo: bool) -> int:
    stake = max(0, int(entry_fee))
    return stake * (10 if turbo else 1)

def _preflight_balance(account: dict, entry_fee: int, turbo: bool) -> None:
    required = _required_balance(entry_fee, turbo)
    current = int(account.get('chips', 0))
    if current < required:
        raise HTTPException(402, f'insufficient_balance:{required}:{current}')

def _charge_entries(room_id: str) -> tuple[bool, str]:
    room = ROOMS[room_id]
    m = _ensure_meta(room_id)
    if m['economy_charged']:
        return (True, 'already_checked')
    stake = max(0, int(room.state.entry_fee))
    required = _required_balance(stake, room.state.turbo)
    for seat, pid in m['player_ids'].items():
        if room.state.players[seat].bot:
            continue
        a = STORE.get(pid)
        if not a:
            return (False, 'account_not_found')
        if a['chips'] < required:
            return (False, f'not_enough_chips:{seat}')
    m['economy_charged'] = True
    return (True, 'stake_checked')

def _record_round_if_finished(room_id: str):
    room = ROOMS.get(room_id)
    m = ROOM_META.get(room_id)
    if not room or not m or room.state.phase != 'finished':
        return
    idx = int(room.state.round_index)
    recorded = m.setdefault('recorded_rounds', set())
    if idx in recorded:
        return
    recorded.add(idx)
    flags = dict(room.state.round_finish_flags or {})
    winner = room.state.winner_seat
    for seat, pid in list(m.get('player_ids', {}).items()):
        if not STORE.get(pid):
            continue
        player = room.state.players.get(seat)
        STORE.record_round(pid, opening_mode=getattr(player, 'opening_mode', None), winner=winner == seat, okey_finish=bool(flags.get('joker_finish')), pair_finish=bool(flags.get('pair_finish')))

def _settle_if_finished(room_id: str):
    room = ROOMS.get(room_id)
    m = ROOM_META.get(room_id)
    if not room or not m or m.get('settled') or (not room.state.match_finished):
        return
    scores = room.state.total_scores
    if not scores:
        return
    x = max(1, int(room.state.multiplier if room.state.turbo else 1))
    stake = max(0, int(room.state.entry_fee))

    def remaining(seat: int) -> int:
        return int(room.state.round_breakdown.get(seat, {}).get('rack', 0))

    def rank_key(seat: int):
        if room.state.max_rounds == 1:
            return (remaining(seat), seat)
        return (int(scores.get(seat, 0)), remaining(seat), seat)
    ordered = sorted(range(4), key=rank_key)
    rank_by_seat = {seat: i + 1 for i, seat in enumerate(ordered)}
    if room.state.turbo:
        first_win = int(round(stake * (x + 0.5)))
        second_win = int(round(stake * (x * 0.25)))
        loss_pool = first_win + second_win
        third_loss = loss_pool // 2
        fourth_loss = loss_pool - third_loss
        solo_deltas = {ordered[0]: first_win, ordered[1]: second_win, ordered[2]: -third_loss, ordered[3]: -fourth_loss}
    else:
        same_loss = int(stake)
        second_win = int(round(stake * 0.25))
        first_win = max(0, same_loss * 2 - second_win)
        solo_deltas = {ordered[0]: first_win, ordered[1]: second_win, ordered[2]: -same_loss, ordered[3]: -same_loss}
    if room.state.team_mode == 'paired':
        team_scores = room.team_score_map(scores)
        winning_team = min(team_scores, key=lambda t: (team_scores[t], t))
        winning_seats = set(room.team_members(winning_team))
        deltas = {seat: stake * x if seat in winning_seats else -stake * x for seat in range(4)}
        winner_ids = [pid for seat, pid in m['player_ids'].items() if seat in winning_seats]
        result_kind = 'paired'
    else:
        deltas = solo_deltas
        winning_seats = {ordered[0], ordered[1]}
        winner_ids = [pid for seat, pid in m['player_ids'].items() if seat in winning_seats]
        result_kind = 'solo'
    commission_rate = 0.15
    gross_deltas = {seat: int(v) for seat, v in deltas.items()}
    commissions = {seat: int(round(v * commission_rate)) if v > 0 else 0 for seat, v in gross_deltas.items()}
    net_deltas = {seat: gross_deltas[seat] - commissions[seat] for seat in gross_deltas}
    house_fee = sum(commissions.values())
    gross_total = sum(gross_deltas.values())
    net_total = sum(net_deltas.values())
    if gross_total != 0 or net_total + house_fee != 0:
        m['settlement'] = {'status': 'blocked', 'error': 'economy_invariant', 'gross_total': gross_total, 'net_total': net_total, 'house_fee': house_fee}
        m['settled'] = True
        return
    for seat, pid in m['player_ids'].items():
        delta = int(net_deltas.get(seat, 0))
        acc = STORE.get(pid)
        if acc and delta < 0 and (int(acc.get('chips', 0)) < -delta):
            m['settlement'] = {'status': 'blocked', 'error': 'insufficient_balance_at_settlement', 'seat': seat, 'required': -delta, 'available': int(acc.get('chips', 0)), 'house_fee': house_fee}
            m['settled'] = True
            return
    participants = []
    applied = []
    for seat, pid in m['player_ids'].items():
        participants.append({'id': pid, 'name': room.state.players[seat].name, 'seat': seat})
        delta = int(net_deltas.get(seat, 0))
        if not STORE.get(pid) or delta == 0:
            continue
        if delta > 0:
            STORE.credit(pid, delta, f'{room.state.room_name} • {rank_by_seat[seat]}. sıra • %15 masa komisyonu sonrası', notify=False)
            applied.append({'seat': seat, 'delta': delta, 'gross': gross_deltas[seat], 'commission': commissions[seat], 'ok': True})
        else:
            ok = STORE.debit(pid, -delta, f'{room.state.room_name} • {rank_by_seat[seat]}. sıra', notify=False)
            applied.append({'seat': seat, 'delta': delta, 'gross': gross_deltas[seat], 'commission': 0, 'ok': bool(ok)})
    finish_flags = dict(room.state.round_finish_flags or {})
    now_ms = int(time.time() * 1000)
    xp_multiplier = 1.0
    try:
        for ev in STORE._data.get('phase4', {}).get('global', {}).get('live_events', []):
            if not bool(ev.get('enabled', True)):
                continue
            if int(ev.get('starts_at', 0) or 0) <= now_ms <= int(ev.get('ends_at', 0) or 0):
                xp_multiplier = max(xp_multiplier, float((ev.get('config') or {}).get('xp_multiplier', 1.0) or 1.0))
    except Exception:
        xp_multiplier = 1.0
    STORE.settle_match(participants, winner_ids[0] if winner_ids else None, 0, room.state.max_rounds, {'scores': scores, 'winner_ids': winner_ids, 'paired': room.state.team_mode == 'paired', 'finish_flags': finish_flags}, xp_multiplier=xp_multiplier)
    canak_add = max(0, int(round(house_fee * 0.02)))
    canak_balance = STORE.add_canak(canak_add, room_id)
    canak_explosion = None
    if finish_flags.get('joker_finish') or finish_flags.get('pair_finish'):
        canak_explosion = STORE.pop_canak(winner_ids, room_id)
        canak_balance = STORE.canak_state().get('balance', 0)
    rankings = []
    for seat in ordered:
        pid = m['player_ids'].get(seat)
        acc = STORE.get(pid) if pid else None
        rankings.append({'rank': rank_by_seat[seat], 'seat': seat, 'name': room.state.players[seat].name, 'score': int(scores.get(seat, 0)), 'remaining': remaining(seat), 'delta': int(net_deltas.get(seat, 0)), 'gross_delta': int(gross_deltas.get(seat, 0)), 'commission': int(commissions.get(seat, 0)), 'balance_after': int((acc or {}).get('chips', 0) or 0) if acc else None, 'team': room.team_of(seat) if room.state.team_mode == 'paired' else None})
    m['settlement'] = {'stake': stake, 'multiplier': x, 'mode': 'turbo' if room.state.turbo else 'standard', 'team_mode': room.state.team_mode, 'result_kind': result_kind, 'rankings': rankings, 'winner_seat': ordered[0], 'winner_seats': sorted(winning_seats), 'team_scores': room.team_score_map(scores), 'commission_rate': commission_rate, 'house_fee': house_fee, 'gross_ledger_total': gross_total, 'net_ledger_total': net_total, 'wallet_applied': applied, 'wallet_ok': all((x.get('ok', False) for x in applied)), 'canak_contribution': canak_add, 'canak_balance': canak_balance, 'canak_explosion': canak_explosion, 'xp_multiplier': xp_multiplier}
    m['settled'] = True
_CHAT_BLOCK_PATTERNS = (re.compile('https?://', re.I), re.compile('www\\.', re.I))
_CHAT_MASK_WORDS = ('amk', 'aq', 'orospu', 'sik', 'piç', 'pic')

def _moderate_chat_text(value: str) -> str:
    text = ' '.join((value or '').split())
    if not text:
        raise HTTPException(400, 'empty_message')
    if any((p.search(text) for p in _CHAT_BLOCK_PATTERNS)):
        raise HTTPException(400, 'chat_link_not_allowed')
    if re.search('(.)\\1{8,}', text, re.I):
        raise HTTPException(400, 'chat_spam_detected')
    for word in _CHAT_MASK_WORDS:
        text = re.sub(f'(?i)(?<!\\w){re.escape(word)}(?!\\w)', '***', text)
    return text[:120]

def _append_chat(room_id: str, seat: int, kind: str, value: str, to_seat: int | None=None) -> dict:
    room = ROOMS[room_id]
    m = _ensure_meta(room_id)
    p = room.state.player(seat)
    target = room.state.player(to_seat) if to_seat is not None and to_seat in room.state.players else None
    event = {'id': uuid.uuid4().hex[:10], 'seat': seat, 'player_id': m.get('player_ids', {}).get(seat), 'name': p.name, 'kind': kind, 'value': value[:120], 'to_seat': to_seat, 'to_name': target.name if target else None, 'created_at': int(_now())}
    if kind == 'gift':
        reactions = m.setdefault('reactions', [])
        reactions.append(event)
        m['reactions'] = reactions[-20:]
    else:
        m['chat'].append(event)
        m['chat'] = m['chat'][-30:]
    return event

@router.get('/lobby/rooms')
def list_rooms():
    out = []
    for rid, r in ROOMS.items():
        st = r.state
        m = _ensure_meta(rid, legacy=True)
        human = sum((1 for p in st.players.values() if not p.bot))
        if st.phase != 'waiting':
            continue
        out.append({'room_id': rid, 'name': st.room_name, 'variant': st.variant, 'entry_fee': st.entry_fee, 'assisted': st.assisted, 'turbo': st.turbo, 'rounds': st.max_rounds, 'players': human, 'capacity': 4, 'multiplier': st.multiplier, 'phase': st.phase, 'started': st.started, 'pot': st.pot, 'game_mode': 'turbo' if st.turbo else 'standard', 'team_mode': st.team_mode, 'turn_seconds': st.turn_seconds, 'locked': bool(m.get('password_hash')), 'required_balance': _required_balance(st.entry_fee, st.turbo)})
    return {'rooms': out}

@router.post('/lobby/rooms')
def create_room(body: CreateRoomIn):
    if body.variant not in ('non_fold', 'fold'):
        raise HTTPException(400, 'bad_variant')
    if body.team_mode not in ('solo', 'paired'):
        raise HTTPException(400, 'bad_team_mode')
    if body.rounds not in (1, 2, 3):
        raise HTTPException(400, 'bad_round_count')
    if body.entry_fee not in (500, 2000, 5000, 10000, 20000, 50000):
        raise HTTPException(400, 'bad_entry_fee')
    account = _account(body.player_id, body.account_token)
    _preflight_balance(account, body.entry_fee, body.turbo)
    r = new_room(variant=body.variant, entry_fee=body.entry_fee, assisted=body.assisted, turbo=body.turbo, max_rounds=body.rounds, room_name=body.name, waiting=True, turn_seconds=body.turn_seconds, team_mode=body.team_mode, random_starter=True, intro_seconds=5)
    m = _ensure_meta(r.state.room_id)
    m['legacy'] = False
    password = (body.password or '').strip()
    if password:
        if len(password) < 3 or len(password) > 24:
            raise HTTPException(400, 'bad_room_password')
        m['password_hash'] = hashlib.sha256(password.encode('utf-8')).hexdigest()
    token = _bind_human(r.state.room_id, 0, body.player_id, account['name'])
    STORE.record_activity('room_created', body.player_id, f"{account['name']} yeni bir 101 masası açtı", {'room_id': r.state.room_id, 'entry_fee': body.entry_fee, 'turbo': body.turbo})
    return {'room_id': r.state.room_id, 'seat': 0, 'reconnect_token': token, 'state': _state(r.state.room_id, 0)}

@router.post('/lobby/quick')
async def quick_room(body: JoinRoomIn):
    account = _account(body.player_id, body.account_token)
    requested_fee = body.entry_fee if body.entry_fee in (500, 2000, 5000, 10000, 20000, 50000) else 5000
    requested_turbo = bool(body.turbo) if body.turbo is not None else False
    _preflight_balance(account, requested_fee, requested_turbo)
    for rid, r in list(ROOMS.items()):
        meta = _ensure_meta(rid, legacy=True)
        seat = next((s for s, pid in meta.get('player_ids', {}).items() if pid == body.player_id), None)
        if seat is not None and r.state.phase == 'waiting' and meta.get('quick_match'):
            token = meta['seat_tokens'].get(seat) or _token()
            meta['seat_tokens'][seat] = token
            return {'room_id': rid, 'seat': seat, 'reconnect_token': token, 'state': _state(rid, seat)}
    for rid, r in list(ROOMS.items()):
        if r.state.phase != 'waiting':
            continue
        m = _ensure_meta(rid)
        if not m.get('quick_match'):
            continue
        if m.get('password_hash'):
            continue
        if body.turbo is not None and r.state.turbo != body.turbo:
            continue
        if body.variant and r.state.variant != body.variant:
            continue
        if body.team_mode and r.state.team_mode != body.team_mode:
            continue
        if body.entry_fee is not None and r.state.entry_fee != body.entry_fee:
            continue
        if body.rounds is not None and r.state.max_rounds != body.rounds:
            continue
        if body.assisted is not None and r.state.assisted != body.assisted:
            continue
        seat = _free_human_seat(rid)
        if seat is None:
            continue
        _preflight_balance(account, r.state.entry_fee, r.state.turbo)
        m['legacy'] = False
        token = _bind_human(rid, seat, body.player_id, account['name'])
        STORE.record_activity('room_join', body.player_id, f"{account['name']} hızlı eşleşme masasına katıldı", {'room_id': rid, 'entry_fee': r.state.entry_fee, 'turbo': r.state.turbo})
        if _human_count(rid) >= 4:
            ok, code = _charge_entries(rid)
            if not ok:
                raise HTTPException(402, code)
            started = r.start_match(int(m.get('owner_seat', 0) or 0))
            if not started.ok:
                raise HTTPException(409, started.code)
            _touch(rid)
        await _broadcast(rid)
        return {'room_id': rid, 'seat': seat, 'reconnect_token': token, 'state': _state(rid, seat)}
    r = new_room(room_name='Hızlı Eşleşme', waiting=True, turbo=requested_turbo, variant=body.variant if body.variant in ('fold', 'non_fold') else 'non_fold', team_mode=body.team_mode if body.team_mode in ('solo', 'paired') else 'solo', entry_fee=requested_fee, max_rounds=body.rounds if body.rounds in (1, 2, 3) else 1, assisted=True if body.assisted is None else body.assisted, random_starter=True, intro_seconds=5)
    m = _ensure_meta(r.state.room_id)
    m['legacy'] = False
    m['quick_match'] = True
    token = _bind_human(r.state.room_id, 0, body.player_id, account['name'])
    STORE.record_activity('quick_play', body.player_id, f"{account['name']} hızlı eşleşme kuyruğuna katıldı", {'room_id': r.state.room_id, 'entry_fee': r.state.entry_fee, 'turbo': r.state.turbo})
    return {'room_id': r.state.room_id, 'seat': 0, 'reconnect_token': token, 'state': _state(r.state.room_id, 0)}

@router.post('/game/{room_id}/join')
async def join_room(room_id: str, body: JoinRoomIn):
    r = ROOMS.get(room_id)
    if not r:
        raise HTTPException(404, 'room_not_found')
    if r.state.phase != 'waiting':
        raise HTTPException(409, 'room_already_started')
    account = _account(body.player_id, body.account_token)
    _preflight_balance(account, r.state.entry_fee, r.state.turbo)
    m = _ensure_meta(room_id)
    password_hash = m.get('password_hash')
    invited = body.player_id in m.get('invited_player_ids', set())
    if password_hash and (not invited):
        given = hashlib.sha256((body.password or '').encode('utf-8')).hexdigest()
        if not secrets.compare_digest(password_hash, given):
            raise HTTPException(401, 'room_password_required')
    if body.player_id in m.get('player_ids', {}).values():
        seat = next((s for s, pid in m['player_ids'].items() if pid == body.player_id))
        return {'room_id': room_id, 'seat': seat, 'reconnect_token': m['seat_tokens'][seat], 'state': _state(room_id, seat)}
    seat = next((s for s, p in r.state.players.items() if p.bot), None)
    if seat is None:
        raise HTTPException(409, 'room_full')
    token = _bind_human(room_id, seat, body.player_id, account['name'])
    STORE.record_activity('room_join', body.player_id, f"{account['name']} bir masaya katıldı", {'room_id': room_id, 'entry_fee': r.state.entry_fee, 'turbo': r.state.turbo})
    if m.get('quick_match') and _human_count(room_id) >= 4:
        ok, code = _charge_entries(room_id)
        if not ok:
            raise HTTPException(402, code)
        started = r.start_match(int(m.get('owner_seat', 0) or 0))
        if not started.ok:
            raise HTTPException(409, started.code)
        _touch(room_id)
    await _broadcast(room_id)
    return {'room_id': room_id, 'seat': seat, 'reconnect_token': token, 'state': _state(room_id, seat)}

@router.post('/game/new')
def game_new(variant: str=Query('non_fold', pattern='^(non_fold|fold)$'), entry_fee: int=5000, assisted: bool=True, turbo: bool=False, rounds: int=1, name: str='OkeyX Masası'):
    r = new_room(variant=variant, entry_fee=entry_fee, assisted=assisted, turbo=turbo, max_rounds=rounds, room_name=name)
    _ensure_meta(r.state.room_id, legacy=True)
    return _state(r.state.room_id, 0)

@router.get('/game/{room_id}')
def game_state(room_id: str, seat: int=0, reconnect_token: str | None=None):
    if room_id not in ROOMS:
        raise HTTPException(404, 'room_not_found')
    m = _ensure_meta(room_id, legacy=True)
    if not m.get('legacy'):
        _auth(room_id, seat, reconnect_token)
    return _state(room_id, seat)

@router.post('/game/reconnect')
def reconnect_game(body: ReconnectIn):
    _account(body.player_id, body.account_token)
    candidates = []
    for room_id, room in ROOMS.items():
        meta = _ensure_meta(room_id, legacy=True)
        seat = next((s for s, pid in meta.get('player_ids', {}).items() if pid == body.player_id), None)
        if seat is None or room.state.match_finished:
            continue
        candidates.append((meta.get('created_at', 0), room_id, seat, meta))
    if not candidates:
        return {'ok': False, 'code': 'active_game_not_found'}
    _, room_id, seat, meta = max(candidates, key=lambda x: x[0])
    token = meta['seat_tokens'].get(seat) or _token()
    meta['seat_tokens'][seat] = token
    ROOMS[room_id].restore_human(seat)
    _touch(room_id)
    return {'ok': True, 'room_id': room_id, 'seat': seat, 'reconnect_token': token, 'state': _state(room_id, seat)}

async def _execute_action(room_id: str, body: ActionIn):
    r = ROOMS.get(room_id)
    if not r:
        raise HTTPException(404, 'room_not_found')
    m = _auth(room_id, body.seat, body.reconnect_token)
    _rate_limit(m, body.reconnect_token)
    if body.request_id and body.request_id in m['dedupe']:
        return m['dedupe'][body.request_id]
    if body.seat in m['player_ids'] and r.state.player(body.seat).bot:
        r.restore_human(body.seat)
    if body.kind == 'start_match':
        if m.get('quick_match') and _human_count(room_id) < 4:
            response = {'ok': False, 'code': 'quick_match_waiting_for_players', 'payload': {'humans': _human_count(room_id), 'required': 4}, 'request_id': body.request_id, 'state': _state(room_id, body.seat)}
            if body.request_id:
                m['dedupe'][body.request_id] = response
            return response
        ok, code = _charge_entries(room_id)
        if not ok:
            response = {'ok': False, 'code': code, 'payload': {}, 'request_id': body.request_id, 'state': _state(room_id, body.seat)}
            return response
    result = r.action(body.seat, body.kind, body.payload)
    if result.ok and body.kind == 'rematch':
        m['settled'] = False
        m['recorded_rounds'] = set()
        m['economy_charged'] = False
    if result.ok:
        m['afk_strikes'][body.seat] = 0
    _record_round_if_finished(room_id)
    _settle_if_finished(room_id)
    _touch(room_id)
    response = {'ok': result.ok, 'code': result.code, 'payload': result.payload or {}, 'request_id': body.request_id, 'state': _state(room_id, body.seat)}
    if body.request_id:
        m['dedupe'][body.request_id] = response
        if len(m['dedupe']) > 80:
            for k in list(m['dedupe'])[:-60]:
                m['dedupe'].pop(k, None)
    await _broadcast(room_id, skip_seat=body.seat)
    return response

@router.post('/game/{room_id}/action')
async def game_action(room_id: str, body: ActionIn):
    return await _execute_action(room_id, body)

@router.post('/game/{room_id}/manage')
async def manage_room(room_id: str, body: ManageRoomIn):
    r = ROOMS.get(room_id)
    if not r:
        raise HTTPException(404, 'room_not_found')
    m = _auth(room_id, body.seat, body.reconnect_token)
    if int(m.get('owner_seat', 0)) != int(body.seat):
        raise HTTPException(403, 'host_only')
    action = (body.action or '').strip().lower()
    if action == 'kick':
        if r.state.phase != 'waiting':
            raise HTTPException(409, 'kick_waiting_only')
        target = body.target_seat
        if target is None or target not in range(4) or target == body.seat:
            raise HTTPException(400, 'bad_target_seat')
        pid = m.get('player_ids', {}).get(target)
        if not pid:
            raise HTTPException(404, 'player_not_found')
        p = r.state.player(target)
        p.bot = True
        p.user_id = f'bot-seat-{target}'
        p.name = ['Sen', 'Deniz', 'Mert', 'Eylül'][target]
        m['player_ids'].pop(target, None)
        m['seat_tokens'].pop(target, None)
        m['connected'][target] = False
        m['disconnect_at'][target] = _now()
        _touch(room_id)
        await _broadcast(room_id)
        return {'ok': True, 'code': 'player_kicked', 'seat': target}
    if action == 'settings':
        if r.state.phase != 'waiting':
            raise HTTPException(409, 'settings_waiting_only')
        if body.room_name is not None:
            name = ' '.join(body.room_name.strip().split())[:28]
            if name:
                r.state.room_name = name
        if body.turn_seconds is not None:
            r.state.turn_seconds = max(15, min(90, int(body.turn_seconds)))
        if body.turbo is not None:
            r.state.turbo = bool(body.turbo)
        if body.variant is not None:
            r.state.variant = 'fold' if body.variant == 'fold' else 'non_fold'
        if body.team_mode is not None:
            r.state.team_mode = 'paired' if body.team_mode == 'paired' else 'solo'
        if body.assisted is not None:
            r.state.assisted = bool(body.assisted)
        if body.rounds is not None:
            r.state.max_rounds = max(1, min(3, int(body.rounds)))
        if body.entry_fee is not None:
            requested = max(1000, min(1000000, int(body.entry_fee)))
            liability = requested * (10 if r.state.turbo else 1)
            for pid in m.get('player_ids', {}).values():
                if not pid:
                    continue
                acc = STORE.get(pid)
                if acc and int(acc.get('chips', 0) or 0) < liability:
                    return {'ok': False, 'code': 'room_player_insufficient_balance', 'required': liability}
            r.state.entry_fee = requested
            r.state.pot = requested * 4
        if body.chat_enabled is not None:
            m['chat_enabled'] = bool(body.chat_enabled)
        if body.gifts_enabled is not None:
            m['gifts_enabled'] = bool(body.gifts_enabled)
        if body.auto_rematch is not None:
            m['auto_rematch'] = bool(body.auto_rematch)
        r.recalculate_turbo()
        _touch(room_id)
        await _broadcast(room_id)
        return {'ok': True, 'code': 'settings_updated', 'state': _state(room_id, body.seat)}
    raise HTTPException(400, 'bad_manage_action')

@router.post('/game/{room_id}/leave')
async def leave_room(room_id: str, body: LeaveIn):
    r = ROOMS.get(room_id)
    if not r:
        raise HTTPException(404, 'room_not_found')
    m = _auth(room_id, body.seat, body.reconnect_token)
    intro_active = bool(getattr(r, 'intro_until_ms', 0) and int(time.time() * 1000) < int(r.intro_until_ms))
    if r.state.phase in ('waiting', 'finished') or intro_active:
        if r.state.phase == 'waiting' or intro_active:
            p = r.state.player(body.seat)
            p.bot = True
            p.user_id = f'bot-seat-{body.seat}'
            p.name = ['Sen', 'Deniz', 'Mert', 'Eylül'][body.seat]
            m['player_ids'].pop(body.seat, None)
            m['seat_tokens'].pop(body.seat, None)
            if int(m.get('owner_seat', 0)) == int(body.seat):
                remaining = sorted((int(seat) for seat, pid in m.get('player_ids', {}).items() if pid))
                if remaining:
                    m['owner_seat'] = remaining[0]
        m['connected'][body.seat] = False
        m['disconnect_at'][body.seat] = _now()
        _touch(room_id)
        await _broadcast(room_id)
        return {'ok': True, 'code': 'left_intro' if intro_active else 'left_free'}
    if r.state.turbo:
        return {'ok': False, 'code': 'turbo_leave_locked'}
    pid = m['player_ids'].get(body.seat)
    stake = max(0, int(r.state.entry_fee))
    if pid and STORE.get(pid):
        ok = STORE.debit(pid, stake, f'{r.state.room_name} • maçtan ayrılma cezası', notify=False)
        if not ok:
            return {'ok': False, 'code': 'leave_forfeit_insufficient_balance'}
    r.takeover_by_bot(body.seat, 'medium')
    m['player_ids'].pop(body.seat, None)
    m['seat_tokens'].pop(body.seat, None)
    m['connected'][body.seat] = False
    m['disconnect_at'][body.seat] = _now()
    _touch(room_id)
    await _broadcast(room_id)
    return {'ok': True, 'code': 'left_forfeit', 'forfeit': stake}

@router.post('/game/{room_id}/chat')
async def table_chat(room_id: str, body: ChatIn):
    r = ROOMS.get(room_id)
    if not r:
        raise HTTPException(404, 'room_not_found')
    m = _auth(room_id, body.seat, body.reconnect_token)
    sender_id = m.get('player_ids', {}).get(body.seat)
    if sender_id:
        from app.services.phase4_service import Phase4Service
        if Phase4Service(STORE).active_sanctions(sender_id).get('muted'):
            raise HTTPException(403, 'account_muted')
    if body.kind not in ('quick', 'emoji', 'text', 'gift'):
        raise HTTPException(400, 'bad_chat_kind')
    if body.kind == 'gift' and (not bool(m.get('gifts_enabled', True))):
        raise HTTPException(403, 'gifts_disabled')
    if body.kind != 'gift' and (not bool(m.get('chat_enabled', True))):
        raise HTTPException(403, 'chat_disabled')
    value = body.value.strip()
    if body.kind == 'emoji':
        allowed = {'😂', '😎', '🔥', '👏', '🤝', '😱', '🍀', '⭐'}
        if value not in allowed:
            raise HTTPException(400, 'emoji_not_allowed')
        _chat_rate_limit(m, body.reconnect_token, body.kind)
    elif body.kind == 'quick':
        allowed = {'İyi oyun!', 'Bol şans!', 'Güzel el.', 'Hadi bakalım 😄', 'Tebrikler!', 'Biraz hızlı 😅', 'Okey sende mi?', 'Çift gidiyorum 😄', 'Eline sağlık.', 'Şans bugün benden yana 🍀', 'Son taş!', 'Vay be!', 'Devam devam 🔥', 'Kusura bakma 😅'}
        if value not in allowed:
            raise HTTPException(400, 'quick_message_not_allowed')
        _chat_rate_limit(m, body.reconnect_token, body.kind)
    elif body.kind == 'text':
        if len(value) > 120:
            raise HTTPException(400, 'message_too_long')
        value = _moderate_chat_text(value)
        _chat_rate_limit(m, body.reconnect_token, body.kind)
    else:
        table_gift = body.to_seat == -1
        if body.to_seat is None or (not table_gift and body.to_seat not in range(4)) or body.to_seat == body.seat:
            raise HTTPException(400, 'target_required')
        if value not in GIFT_CATALOG:
            raise HTTPException(400, 'gift_not_found')
        _chat_rate_limit(m, body.reconnect_token, body.kind)
        from_id = m['player_ids'].get(body.seat)
        to_id = None if table_gift else m['player_ids'].get(body.to_seat)
        gift = GIFT_CATALOG[value]
        if table_gift:
            cost = max(0, int(gift.get('cost', 0) or 0))
            if from_id and cost and (not STORE.debit(from_id, cost, f"Masaya hediye • {gift['name']}", notify=False)):
                return {'ok': False, 'code': 'insufficient_coins', 'required': cost}
            value = str(gift['name'])
        elif from_id and to_id:
            g = STORE.send_gift(from_id, to_id, value)
            if not g.get('ok'):
                return g
            value = str(g.get('gift', {}).get('name') or gift['name'])
        else:
            cost = max(0, int(gift.get('cost', 0) or 0))
            if from_id and cost:
                if not STORE.debit(from_id, cost, f"Masa hediyesi • {gift['name']}", notify=False):
                    return {'ok': False, 'code': 'insufficient_coins', 'required': cost}
            value = str(gift['name'])
    event = _append_chat(room_id, body.seat, body.kind, value, body.to_seat)
    _touch(room_id)
    await _broadcast(room_id)
    return {'ok': True, 'event': event}

@router.websocket('/game/{room_id}/ws')
async def game_ws(ws: WebSocket, room_id: str, seat: int=0, reconnect_token: str | None=None):
    r = ROOMS.get(room_id)
    if not r:
        await ws.close(code=4404)
        return
    m = _ensure_meta(room_id, legacy=True)
    if not m.get('legacy'):
        expected = m['seat_tokens'].get(seat)
        if not expected or not reconnect_token or (not secrets.compare_digest(expected, reconnect_token)):
            await ws.close(code=4401)
            return
    await ws.accept()
    if seat in m['player_ids'] and r.state.player(seat).bot:
        r.restore_human(seat)
    m['connected'][seat] = True
    m['disconnect_at'].pop(seat, None)
    m['afk_strikes'][seat] = 0
    SOCKETS.setdefault(room_id, {}).setdefault(seat, []).append(ws)
    _touch(room_id)
    await _broadcast(room_id)
    try:
        while True:
            msg = await ws.receive_text()
            if msg == 'ping':
                m['connected'][seat] = True
                await ws.send_text('pong')
                continue
            try:
                packet = json.loads(msg)
            except Exception:
                await ws.send_json({'type': 'error', 'code': 'bad_socket_payload'})
                continue
            if not isinstance(packet, dict):
                await ws.send_json({'type': 'error', 'code': 'bad_socket_payload'})
                continue
            kind = str(packet.get('type') or '')
            if kind == 'action':
                try:
                    body = ActionIn(seat=seat, kind=str(packet.get('kind') or ''), payload=packet.get('payload') if isinstance(packet.get('payload'), dict) else {}, reconnect_token=reconnect_token, request_id=str(packet.get('request_id') or '') or None)
                    result = await _execute_action(room_id, body)
                    await ws.send_json({'type': 'action_result', **result})
                except HTTPException as exc:
                    await ws.send_json({'type': 'action_result', 'ok': False, 'code': str(exc.detail), 'request_id': packet.get('request_id'), 'payload': {}, 'state': _state(room_id, seat)})
                except Exception as exc:
                    await ws.send_json({'type': 'action_result', 'ok': False, 'code': 'socket_action_failed', 'request_id': packet.get('request_id'), 'payload': {'error': type(exc).__name__}, 'state': _state(room_id, seat)})
            elif kind == 'sync':
                await ws.send_json({'type': 'state', 'state': _state(room_id, seat)})
            else:
                await ws.send_json({'type': 'error', 'code': 'unknown_socket_message'})
    except WebSocketDisconnect:
        pass
    finally:
        lst = SOCKETS.get(room_id, {}).get(seat, [])
        if ws in lst:
            lst.remove(ws)
        if not lst:
            m['connected'][seat] = False
            m['disconnect_at'][seat] = _now()
            _touch(room_id)
        await _broadcast(room_id)

async def room_watchdog():
    while True:
        now = _now()
        for rid, room in list(ROOMS.items()):
            try:
                m = _ensure_meta(rid, legacy=True)
                changed = False
                if room.state.started and room.intro_until_ms:
                    changed = room.advance_intro_if_ready() or changed
                if room.state.started and (not room.intro_until_ms) and (room.state.phase in ('draw', 'discard')):
                    seat = room.state.current_seat
                    p = room.state.player(seat)
                    if not p.bot and seat in m['player_ids'] and (not m['connected'].get(seat, False)):
                        disc = m['disconnect_at'].get(seat)
                        if disc and now - disc >= 20:
                            room.takeover_by_bot(seat, 'afk')
                            changed = True
                    if not p.bot and room.state.turn_deadline_ms and (int(now * 1000) >= room.state.turn_deadline_ms):
                        result = room.timeout_turn(seat)
                        if result.ok:
                            m['afk_strikes'][seat] = m['afk_strikes'].get(seat, 0) + 1
                            changed = True
                            if m['afk_strikes'][seat] >= 2:
                                room.takeover_by_bot(seat, 'afk')
                        else:
                            room.state.log.append(f'WATCHDOG_TIMEOUT_RETRY seat={seat} code={result.code}')
                            room._set_turn_deadline()
                    elif p.bot and room.state.current_seat == seat:
                        changed = room.run_bots_until_human() or changed
                _record_round_if_finished(rid)
                _settle_if_finished(rid)
                if changed:
                    _touch(rid)
                    await _broadcast(rid)
            except Exception as exc:
                try:
                    room.state.log.append(f'WATCHDOG_ERROR {type(exc).__name__}:{exc}')
                except Exception:
                    pass
        if _RUNTIME_DIRTY and time.monotonic() - _LAST_PERSIST_AT >= 0.35:
            _persist_runtime(force=True)
        await asyncio.sleep(0.75)

def start_watchdog():
    global WATCHDOG_TASK
    _restore_runtime_once()
    if WATCHDOG_TASK is None or WATCHDOG_TASK.done():
        WATCHDOG_TASK = asyncio.create_task(room_watchdog())
