from __future__ import annotations
import random, uuid, time, copy
from itertools import combinations
from app.domain.models import Color, Tile, JokerContext, TableState, PlayerState, Meld, MeldType
from app.domain.rules import Rules101
from app.services.game_service import GameService, ActionResult
COLORS = list(Color)

def build_tiles() -> list[Tile]:
    out = []
    for copy in range(2):
        for c in COLORS:
            for n in range(1, 14):
                out.append(Tile(f'{c.value}-{n}-{copy}', c, n, False))
    out.extend([Tile('fake-0', None, None, True), Tile('fake-1', None, None, True)])
    return out

def _serialize_tile(t: Tile, joker: JokerContext, show_star: bool=True):
    nt = joker.normalized(t)
    star = bool(show_star and nt.number == joker.joker_number)
    return {'id': t.id, 'n': nt.number, 'c': nt.color.value if nt.color else 'black', 'joker': joker.is_real_joker(t), 'fake': t.fake_joker, 'star': star}

def _sort_key(t: Tile, joker: JokerContext):
    if joker.is_real_joker(t):
        return (9, 99, 99)
    nt = joker.normalized(t)
    order = {Color.RED: 0, Color.YELLOW: 1, Color.BLACK: 2, Color.BLUE: 3}
    return (order.get(nt.color, 9), int(nt.number or 99), t.id)

def legal_meld_candidates(rules: Rules101, hand: list[Tile]) -> list[tuple[int, list[Tile]]]:
    jokers = [t for t in hand if rules._is_joker(t)]
    natural = [t for t in hand if not rules._is_joker(t)]
    raw: list[list[Tile]] = []
    by_num = {}
    for t in natural:
        nt = rules._norm(t)
        by_num.setdefault(nt.number, []).append(t)
    for arr in by_num.values():
        pool = arr + jokers
        for size in (3, 4):
            if len(pool) >= size:
                for g in combinations(pool, size):
                    raw.append(list(g))
    for color in COLORS:
        arr = [t for t in natural if rules._norm(t).color == color] + jokers
        for size in range(3, min(13, len(arr)) + 1):
            for g in combinations(arr, size):
                raw.append(list(g))
    out = []
    seen = set()
    for g in raw:
        ids = tuple(sorted((t.id for t in g)))
        if ids in seen:
            continue
        r = rules.validate_meld(g)
        if r.valid:
            seen.add(ids)
            out.append((r.score, g))
    out.sort(key=lambda x: (x[0], len(x[1])), reverse=True)
    return out

def find_series_groups(rules: Rules101, hand: list[Tile], minimum: int=0, required_tile_id: str | None=None, max_used: int | None=None) -> list[list[Tile]] | None:
    candidates = legal_meld_candidates(rules, hand)
    best: list[list[Tile]] | None = None
    best_key = (-1, -10 ** 9, -10 ** 9, -1)
    natural_by_id = {t.id: t for t in hand if not rules._is_joker(t)}

    def replacement_waste(groups: list[list[Tile]], used: set[str]) -> int:
        unused = [t for tid, t in natural_by_id.items() if tid not in used]
        if not unused:
            return 0
        waste = 0
        for group in groups:
            joker_indexes = [i for i, t in enumerate(group) if rules._is_joker(t)]
            if not joker_indexes:
                continue
            for ji in joker_indexes:
                for tile in unused:
                    trial = list(group)
                    trial[ji] = tile
                    if rules.validate_meld(trial).valid:
                        waste += 1
                        break
        return waste

    def dfs(idx: int, used: set[str], groups: list[list[Tile]], score: int):
        nonlocal best, best_key
        requirement_ok = required_tile_id is None or required_tile_id in used
        if score >= minimum and requirement_ok and (max_used is None or len(used) <= max_used):
            wasted = replacement_waste(groups, used)
            joker_count = sum((1 for g in groups for t in g if rules._is_joker(t)))
            key = (len(used), -wasted, -joker_count, score)
            if key > best_key:
                best = [g[:] for g in groups]
                best_key = key
        for j in range(idx, len(candidates)):
            sc, g = candidates[j]
            ids = {t.id for t in g}
            if ids & used:
                continue
            if max_used is not None and len(used | ids) > max_used:
                continue
            dfs(j + 1, used | ids, groups + [g], score + sc)
    dfs(0, set(), [], 0)
    return best if best else None

def best_series_preview(rules: Rules101, hand: list[Tile], max_used: int | None=None) -> tuple[int, int]:
    candidates = legal_meld_candidates(rules, hand)
    best_score = 0
    best_used = 0
    seen = {}

    def dfs(idx: int, used: frozenset[str], score: int):
        nonlocal best_score, best_used
        key = (idx, used)
        if seen.get(key, -1) >= score:
            return
        seen[key] = score
        if score > best_score or (score == best_score and len(used) > best_used):
            best_score = score
            best_used = len(used)
        for j in range(idx, len(candidates)):
            sc, g = candidates[j]
            ids = frozenset((t.id for t in g))
            if ids & used:
                continue
            nu = used | ids
            if max_used is not None and len(nu) > max_used:
                continue
            dfs(j + 1, nu, score + sc)
    dfs(0, frozenset(), 0)
    return (best_score, best_used)

def find_pairs(rules: Rules101, hand: list[Tile]) -> list[list[Tile]]:
    groups = []
    leftovers = []
    jokers = [t for t in hand if rules._is_joker(t)]
    buckets = {}
    for tile in hand:
        if rules._is_joker(tile):
            continue
        nt = rules._norm(tile)
        buckets.setdefault((nt.color, nt.number), []).append(tile)
    for bucket in buckets.values():
        while len(bucket) >= 2:
            groups.append([bucket.pop(0), bucket.pop(0)])
        leftovers.extend(bucket)
    while jokers and leftovers:
        groups.append([leftovers.pop(0), jokers.pop(0)])
    while len(jokers) >= 2:
        groups.append([jokers.pop(0), jokers.pop(0)])
    return groups

def pair_plan_including(rules: Rules101, hand: list[Tile], minimum: int, required_id: str | None=None) -> list[list[Tile]] | None:
    pairs = find_pairs(rules, hand)
    if len(pairs) < minimum:
        return None
    max_pairs = max(0, (len(hand) - 1) // 2)
    if required_id is None:
        return pairs[:max_pairs] if len(pairs[:max_pairs]) >= minimum else None
    hit = next((p for p in pairs if any((t.id == required_id for t in p))), None)
    if not hit:
        return None
    pairs = [hit] + [p for p in pairs if p is not hit]
    pairs = pairs[:max_pairs]
    return pairs if len(pairs) >= minimum else None

class Room:

    def __init__(self, seed: int | None=None, variant: str='non_fold', *, entry_fee: int=5000, assisted: bool=True, room_name: str='OkeyX Masası', turbo: bool=False, max_rounds: int=3, waiting: bool=False, turn_seconds: int=35, team_mode: str='solo', random_starter: bool=False, intro_seconds: int=0):
        rng = random.Random(seed)
        tiles = build_tiles()
        rng.shuffle(tiles)
        ind_idx = next((i for i, t in enumerate(tiles) if not t.fake_joker))
        indicator = tiles.pop(ind_idx)
        joker = JokerContext(indicator.color, int(indicator.number))
        players = {0: PlayerState('local-human', 0, [], name='Sen'), 1: PlayerState('bot-deniz', 1, [], name='Deniz', bot=True, bot_level='easy'), 2: PlayerState('bot-mert', 2, [], name='Mert', bot=True, bot_level='medium'), 3: PlayerState('bot-eylul', 3, [], name='Eylül', bot=True, bot_level='hard')}
        for _ in range(21):
            for s in range(4):
                players[s].hand.append(tiles.pop())
        starter_seat = rng.randrange(4) if random_starter else 0
        players[starter_seat].hand.append(tiles.pop())
        variant = 'fold' if variant == 'fold' else 'non_fold'
        initial_phase = 'waiting' if waiting else 'discard'
        self.state = TableState(str(uuid.uuid4())[:8].upper(), joker, players, indicator=indicator, stock=tiles, current_seat=starter_seat, starter_seat=starter_seat, phase=initial_phase, variant=variant, turbo=bool(turbo), multiplier_tile_number=joker.joker_number, entry_fee=max(0, int(entry_fee)), assisted=bool(assisted), room_name=room_name or 'OkeyX Masası', team_mode='paired' if team_mode == 'paired' else 'solo', max_rounds=max(1, min(3, int(max_rounds))), pot=max(0, int(entry_fee)) * 4, started=not waiting, turn_seconds=max(10, min(120, int(turn_seconds))))
        self.service = GameService(self.state)
        self.opponent_interest: dict[tuple[str, int], int] = {}
        self.bot_next_action_at_ms = 0
        self.bot_pace_ms = 1400
        self._assist_cache_key = None
        self._assist_cache_value = (0, 0, [], [])
        self.intro_until_ms = int((time.time() + max(0, int(intro_seconds))) * 1000) if intro_seconds > 0 and (not waiting) else 0
        self.start_intro_seconds = max(0, int(intro_seconds))
        self.recalculate_turbo()
        if self.state.started and (not self.intro_until_ms):
            self._set_turn_deadline()
        self.state.log.append(f'Oyun başlıyor. İlk oyuncu: {self.state.player(self.state.current_seat).name}.' if self.state.started else 'Masa kuruldu. Oyuncular bekleniyor.')

    def _emit_table_event(self, event_type: str, seat: int, message: str, data: dict | None=None):
        self.state.event_seq += 1
        ev = {'seq': self.state.event_seq, 'type': event_type, 'seat': seat, 'message': message, 'data': data or {}}
        self.state.last_event = ev
        self.state.event_history.append(ev)
        self.state.event_history = self.state.event_history[-24:]

    def _set_turn_deadline(self):
        if self.state.phase in ('draw', 'discard') and self.state.started:
            self.state.turn_deadline_ms = int((time.time() + self.state.turn_seconds) * 1000)
        else:
            self.state.turn_deadline_ms = 0

    def start_match(self, seat: int=0) -> ActionResult:
        if self.state.started:
            return ActionResult(False, 'already_started')
        if seat != 0 and (not self.state.player(0).bot):
            return ActionResult(False, 'only_host_can_start')
        self.state.started = True
        self.state.phase = 'discard'
        if self.start_intro_seconds > 0:
            self.intro_until_ms = int((time.time() + self.start_intro_seconds) * 1000)
            self._set_turn_deadline()
            self.state.log.append(f'Masa başlıyor. İlk oyuncu: {self.state.player(self.state.current_seat).name}.')
        else:
            self.intro_until_ms = 0
            self._set_turn_deadline()
            self.state.log.append(f'Masa başladı. İlk oyuncu: {self.state.player(self.state.current_seat).name}.')
        return ActionResult(True, 'match_started')

    def set_player_identity(self, seat: int, user_id: str, name: str, *, bot: bool=False, bot_level: str | None=None):
        p = self.state.player(seat)
        p.user_id = user_id
        p.name = (name or f'Oyuncu {seat + 1}')[:24]
        p.bot = bot
        if bot_level:
            p.bot_level = bot_level

    def takeover_by_bot(self, seat: int, level: str='medium'):
        p = self.state.player(seat)
        p.bot = True
        p.bot_level = level
        self.state.log.append(f'{p.name} için bot devraldı.')
        if self.state.started and self.state.current_seat == seat:
            self.bot_turn(seat)
            self.run_bots_until_human()
        self._set_turn_deadline()

    def restore_human(self, seat: int):
        p = self.state.player(seat)
        p.bot = False
        self.state.log.append(f'{p.name} yeniden bağlandı.')
        self._set_turn_deadline()

    def advance_intro_if_ready(self) -> bool:
        if not self.intro_until_ms:
            return False
        if int(time.time() * 1000) < self.intro_until_ms:
            return False
        self.intro_until_ms = 0
        self._set_turn_deadline()
        self.state.log.append(f'Oyun başladı. İlk oyuncu: {self.state.player(self.state.current_seat).name}.')
        return True

    def timeout_turn(self, seat: int) -> ActionResult:
        if not self.state.started or self.state.phase not in ('draw', 'discard'):
            return ActionResult(False, 'bad_phase')
        if self.state.current_seat != seat:
            return ActionResult(False, 'not_your_turn')
        p = self.state.player(seat)
        if self.state.phase == 'discard' and p.pending_left_tile_id:
            pending = p.pending_left_tile_id
            if not any((t.id == pending for t in p.hand)):
                p.pending_left_tile_id = None
                p.pending_left_from_seat = None
            else:
                rr = self.return_left(seat)
                if not rr.ok:
                    return ActionResult(False, f'afk_return_left:{rr.code}')
        if self.state.phase == 'draw':
            r = self.draw(seat, 'stock')
            if not r.ok:
                return ActionResult(bool(self.state.phase == 'finished'), 'afk_stock_finished' if self.state.phase == 'finished' else r.code, r.payload)
        p = self.state.player(seat)
        if self.state.phase == 'discard' and p.hand:
            r = self._bot_discard(seat)
            if not r.ok:
                if p.pending_left_tile_id and (not any((t.id == p.pending_left_tile_id for t in p.hand))):
                    p.pending_left_tile_id = None
                    p.pending_left_from_seat = None
                candidates = [t for t in p.hand if not self.service.rules._is_joker(t)] or list(p.hand)
                for tile in candidates:
                    r = self.discard(seat, tile.id)
                    if r.ok:
                        break
            self._set_turn_deadline()
            return ActionResult(r.ok, 'afk_auto_play' if r.ok else r.code, r.payload)
        return ActionResult(False, 'afk_failed')

    def _check_one_tile_notice(self, seat: int):
        p = self.state.player(seat)
        if len(p.hand) > 2:
            p.one_tile_announced = False
            return
        if len(p.hand) == 1 and (not p.one_tile_announced) and (self.state.phase != 'finished'):
            p.one_tile_announced = True
            self._emit_table_event('one_tile', seat, f'{p.name}: TEK TAŞ KALDI! 🔥')
            self.state.log.append(f'{p.name} tek taşa düştü.')

    def _is_turbo_star(self, tile: Tile) -> bool:
        if not self.state.turbo:
            return False
        if self.service.rules._is_joker(tile) or self.service.rules.is_fake_okey(tile):
            return True
        return int(self.service.rules._norm(tile).number or 0) == int(self.state.joker.joker_number)

    def recalculate_turbo(self):
        if not self.state.turbo:
            self.state.turbo_stars_on_table = 0
            self.state.multiplier = 1
            return
        count = sum((1 for m in self.state.melds for t in m.tiles if self._is_turbo_star(t)))
        self.state.turbo_stars_on_table = count
        self.state.multiplier = max(1, count)

    def turbo_star_distribution(self) -> dict[int, int]:
        return {seat: sum((1 for t in p.hand if self._is_turbo_star(t))) for seat, p in self.state.players.items()}

    def audit_state(self) -> list[str]:
        ids = []
        if self.state.indicator:
            ids.append(self.state.indicator.id)
        ids.extend((t.id for t in self.state.stock))
        for p in self.state.players.values():
            ids.extend((t.id for t in p.hand))
        for pile in self.state.discard_piles.values():
            ids.extend((t.id for t in pile))
        for m in self.state.melds:
            ids.extend((t.id for t in m.tiles))
        issues = []
        if len(ids) != 106:
            issues.append(f'tile_count:{len(ids)}')
        if len(set(ids)) != len(ids):
            issues.append('duplicate_tile_id')
        for m in self.state.melds:
            if m.meld_type == MeldType.PAIR:
                if not self.service.rules.validate_pair(m.tiles).valid:
                    issues.append(f'invalid_pair:{m.id}')
            elif not self.service.rules.validate_meld(m.tiles).valid:
                issues.append(f'invalid_meld:{m.id}')
        return issues

    def _commit_round(self, cancelled: bool=False):
        history_item = {'round_index': self.state.round_index, 'reason': self.state.round_end_reason, 'winner_seat': self.state.winner_seat, 'scores': {str(k): int(v) for k, v in self.state.round_scores.items()}, 'breakdown': {str(k): dict(v) for k, v in self.state.round_breakdown.items()}, 'finish_flags': dict(self.state.round_finish_flags), 'cancelled': bool(cancelled)}
        self.state.round_history.append(history_item)
        if cancelled:
            return
        for seat, score in self.state.round_scores.items():
            self.state.total_scores[seat] = self.state.total_scores.get(seat, 0) + score
        if self.state.round_index >= self.state.max_rounds:
            self.state.match_finished = True

    def new_hand(self) -> ActionResult:
        if self.state.phase != 'finished':
            return ActionResult(False, 'round_not_finished')
        if self.state.match_finished:
            return ActionResult(False, 'match_finished')
        old = self.state
        cancelled = old.round_end_reason == 'four_pairs_cancelled'
        next_round = old.round_index if cancelled else old.round_index + 1
        participant_meta = {seat: (p.user_id, p.name, p.bot, p.bot_level) for seat, p in old.players.items()}
        fresh = Room(seed=random.randrange(1, 10000000), variant=old.variant, entry_fee=old.entry_fee, assisted=old.assisted, room_name=old.room_name, turbo=old.turbo, max_rounds=old.max_rounds, waiting=False, turn_seconds=old.turn_seconds, team_mode=old.team_mode, random_starter=True, intro_seconds=5)
        fresh.state.room_id = old.room_id
        fresh.state.total_scores = dict(old.total_scores)
        fresh.state.round_history = list(old.round_history)
        fresh.state.round_index = next_round
        fresh.state.match_finished = False
        fresh.state.pot = old.pot
        for seat, (uid, name, bot, level) in participant_meta.items():
            np = fresh.state.player(seat)
            np.user_id = uid
            np.name = name
            np.bot = bot
            np.bot_level = level
        self.state = fresh.state
        self.service = GameService(self.state)
        self.opponent_interest = {}
        self._set_turn_deadline()
        self.state.log.append(f'{self.state.round_index}/{self.state.max_rounds}. el başladı.')
        return ActionResult(True, payload={'round_index': self.state.round_index})

    def rematch(self) -> ActionResult:
        if self.state.phase != 'finished' or not self.state.match_finished:
            return ActionResult(False, 'match_not_finished')
        old = self.state
        participant_meta = {seat: (p.user_id, p.name, p.bot, p.bot_level) for seat, p in old.players.items()}
        fresh = Room(seed=random.randrange(1, 10000000), variant=old.variant, entry_fee=old.entry_fee, assisted=old.assisted, room_name=old.room_name, turbo=old.turbo, max_rounds=old.max_rounds, waiting=False, turn_seconds=old.turn_seconds, team_mode=old.team_mode, random_starter=True, intro_seconds=5)
        fresh.state.room_id = old.room_id
        fresh.state.round_index = 1
        fresh.state.total_scores = {seat: 0 for seat in old.players}
        fresh.state.round_history = []
        fresh.state.match_finished = False
        fresh.state.pot = old.pot
        for seat, (uid, name, bot, level) in participant_meta.items():
            np = fresh.state.player(seat)
            np.user_id = uid
            np.name = name
            np.bot = bot
            np.bot_level = level
        self.state = fresh.state
        self.service = GameService(self.state)
        self.opponent_interest = {}
        self._assist_cache_key = None
        self._assist_cache_value = (0, 0, [], [])
        self.intro_until_ms = fresh.intro_until_ms
        self.start_intro_seconds = 5
        self.bot_next_action_at_ms = 0
        self.recalculate_turbo()
        self.state.log.append('Rövanş başlıyor.')
        return ActionResult(True, 'rematch_started', {'round_index': 1})

    def sort_hand(self, seat: int, mode: str):
        p = self.state.player(seat)
        if mode == 'pairs':
            pairs = find_pairs(self.service.rules, p.hand)
            used = {t.id for g in pairs for t in g}
            p.hand = [t for g in pairs for t in g] + sorted([t for t in p.hand if t.id not in used], key=lambda t: _sort_key(t, self.state.joker))
        else:
            p.hand = sorted(p.hand, key=lambda t: _sort_key(t, self.state.joker))
        return ActionResult(True)

    def _can_use_left_tile(self, seat: int, tile: Tile) -> bool:
        p = self.state.player(seat)
        hand = p.hand + [tile]
        rules = self.service.rules
        if not p.opened:
            if find_series_groups(rules, hand, self.state.min_opening_score, tile.id, len(hand) - 1):
                return True
            if pair_plan_including(rules, hand, self.state.min_opening_pairs, tile.id):
                return True
            return False
        if len(hand) >= 2 and any((m.meld_type != MeldType.PAIR and rules.can_layoff(m, tile)[0] for m in self.state.melds)):
            return True
        if self.service._matching_open_pair(tile) is not None:
            return True
        if any((m.meld_type == MeldType.PAIR for m in self.state.melds)):
            for other in hand:
                if other.id != tile.id and rules.validate_pair([tile, other]).valid:
                    return True
        if p.opening_mode == 'series':
            return bool(find_series_groups(rules, hand, 0, tile.id, len(hand) - 1))
        if p.opening_mode == 'pairs':
            return len(hand) >= 3 and bool(pair_plan_including(rules, hand, 1, tile.id))
        return False

    def draw(self, seat: int, source: str='stock') -> ActionResult:
        if seat != self.state.current_seat:
            return ActionResult(False, 'not_your_turn')
        if self.state.phase != 'draw':
            return ActionResult(False, 'must_discard_first' if self.state.phase == 'discard' else 'bad_phase')
        p = self.state.player(seat)
        if source == 'left':
            left = (seat - 1) % 4
            if not self.state.discard_piles[left]:
                return ActionResult(False, 'no_left_discard')
            tile = self.state.discard_piles[left].pop()
            p.pending_left_tile_id = tile.id
            p.pending_left_from_seat = left
            nt = self.service.rules._norm(tile)
            self.opponent_interest[nt.color.value if nt.color else 'x', int(nt.number or 0)] = self.opponent_interest.get((nt.color.value if nt.color else 'x', int(nt.number or 0)), 0) + 1
            self.state.log.append(f'{p.name}, soldaki taşı aldı; bu tur kullanmak zorunda.')
            self._emit_table_event('take_left', seat, f'{p.name} soldan taş aldı')
        else:
            if not self.state.stock:
                self._finish_stock()
                return ActionResult(False, 'stock_empty')
            tile = self.state.stock.pop()
            p.pending_left_tile_id = None
            p.pending_left_from_seat = None
            self.state.log.append(f'{p.name}, desteden taş çekti.')
            self._emit_table_event('draw_stock', seat, f'{p.name} taş çekti')
        p.hand.append(tile)
        self.state.phase = 'discard'
        return ActionResult(True, payload={'tile': tile.id, 'must_use': source == 'left'})

    def return_left(self, seat: int) -> ActionResult:
        if seat != self.state.current_seat:
            return ActionResult(False, 'not_your_turn')
        if self.state.phase != 'discard':
            return ActionResult(False, 'bad_phase')
        p = self.state.player(seat)
        tile_id = p.pending_left_tile_id
        from_seat = p.pending_left_from_seat
        if not tile_id or from_seat is None:
            return ActionResult(False, 'no_pending_left_tile')
        tile = next((t for t in p.hand if t.id == tile_id), None)
        if tile is None:
            return ActionResult(False, 'left_tile_already_used')
        p.hand.remove(tile)
        self.state.discard_piles[from_seat].append(tile)
        p.pending_left_tile_id = None
        p.pending_left_from_seat = None
        self.state.phase = 'draw'
        self.state.log.append(f'{p.name}, soldan aldığı taşı geri bıraktı.')
        self._emit_table_event('return_left', seat, f'{p.name} soldan aldığı taşı geri bıraktı')
        return ActionResult(True, payload={'tile': tile.id})

    def team_of(self, seat: int) -> int:
        return seat % 2

    def team_members(self, team: int) -> list[int]:
        return [team, team + 2]

    def team_score_map(self, scores: dict[int, int]) -> dict[int, int]:
        if self.state.team_mode != 'paired':
            return {}
        return {0: int(scores.get(0, 0)) + int(scores.get(2, 0)), 1: int(scores.get(1, 0)) + int(scores.get(3, 0))}

    def _rack_value(self, seat: int) -> int:
        p = self.state.player(seat)
        rules = self.service.rules
        return sum((25 if rules._is_joker(t) else int(rules._norm(t).number or 0) for t in p.hand))

    def _finish_stock(self):
        scores = {}
        breakdown = {}
        for seat, p in self.state.players.items():
            rack = self._rack_value(seat)
            if not p.opened:
                base = 202
                note = 'El açmadı: sabit 202'
            elif p.opening_mode == 'pairs':
                base = rack * 2
                note = 'Çift açtı: elde kalan x2'
            else:
                base = rack
                note = 'Elde kalan taş toplamı'
            raw_total = base + p.penalty
            total = raw_total * self.state.multiplier
            scores[seat] = total
            breakdown[seat] = {'rack': rack, 'penalty': p.penalty, 'base': base, 'raw_total': raw_total, 'multiplier': self.state.multiplier, 'total': total, 'note': note + f' • Turbo x{self.state.multiplier}'}
        self.state.phase = 'finished'
        self.state.winner_seat = None
        self.state.round_scores = scores
        self.state.round_breakdown = breakdown
        self.state.round_end_reason = 'stock_empty'
        self.state.round_finish_flags = {'stock_empty': True, 'cancelled': False}
        self.state.log.append('Deste bitti. Tur puanları elde kalan taşlara göre hesaplandı.')
        self._commit_round()

    def _finish_by_player(self, finisher: int, finishing_tile: Tile, *, elden_finish: bool=False):
        joker_finish = self.service.rules._is_joker(finishing_tile)
        fp = self.state.player(finisher)
        pair_finish = fp.opening_mode == 'pairs'
        finish_multiplier = (2 if joker_finish else 1) * (2 if elden_finish else 1) * (2 if pair_finish else 1)
        scores = {}
        breakdown = {}
        for seat, p in self.state.players.items():
            rack = self._rack_value(seat)
            note = []
            if seat == finisher:
                base = -101
                note.append('Okey ile bitiş' if joker_finish else 'Normal bitiş')
                if elden_finish:
                    note.append('elden bitiş x2')
            else:
                base = 202 if not p.opened else rack
                note.append('El açmadı: 202' if not p.opened else 'Elde kalan')
                if p.opening_mode == 'pairs':
                    base *= 2
                    note.append('çift x2')
                if pair_finish:
                    note.append('çift bitiş x2')
                if joker_finish:
                    note.append('okey bitişi x2')
                if elden_finish:
                    note.append('elden bitiş x2')
            scored_base = base * finish_multiplier
            scored_penalty = p.penalty * finish_multiplier
            raw_total = scored_base + scored_penalty
            total = raw_total * self.state.multiplier
            scores[seat] = total
            breakdown[seat] = {'rack': rack, 'penalty': scored_penalty, 'original_penalty': p.penalty, 'base': scored_base, 'raw_total': raw_total, 'finish_multiplier': finish_multiplier, 'multiplier': self.state.multiplier, 'total': total, 'note': ' • '.join(note + [f'Bitiş x{finish_multiplier}', f'Turbo x{self.state.multiplier}'])}
        self.state.phase = 'finished'
        self.state.current_seat = finisher
        self.state.winner_seat = finisher
        self.state.round_scores = scores
        self.state.round_breakdown = breakdown
        self.state.round_end_reason = 'finish'
        self.state.round_finish_flags = {'stock_empty': False, 'cancelled': False, 'joker_finish': joker_finish, 'pair_finish': pair_finish, 'single_turn_finish': elden_finish, 'finish_multiplier': finish_multiplier}
        self.state.log.append(f'{fp.name} ' + ('okey ile ' if joker_finish else '') + 'eli bitirdi.')
        self._commit_round()

    def _cancel_four_pair_openers(self):
        if all((p.opened and p.opening_mode == 'pairs' for p in self.state.players.values())):
            self.state.phase = 'finished'
            self.state.winner_seat = None
            self.state.round_scores = {seat: 0 for seat in self.state.players}
            self.state.round_breakdown = {seat: {'rack': self._rack_value(seat), 'penalty': 0, 'base': 0, 'total': 0, 'note': 'Tur iptal'} for seat in self.state.players}
            self.state.round_end_reason = 'four_pairs_cancelled'
            self.state.round_finish_flags = {'cancelled': True, 'four_pair_openers': True}
            self.state.log.append('Dört oyuncu da çift açtı. Tur iptal edildi.')
            self._commit_round(cancelled=True)

    def discard(self, seat: int, tile_id: str) -> ActionResult:
        if self.state.phase != 'discard':
            return ActionResult(False, 'must_draw_first')
        p = self.state.player(seat)
        finishing_tile = next((t for t in p.hand if t.id == tile_id), None)
        elden_finish = bool(p.last_open_batch and (not p.last_open_batch.get('prev_opened', False)))
        r = self.service.discard(seat, tile_id)
        if r.ok:
            payload = r.payload or {}
            self.state.discard_meta[seat] = {'useful': bool(payload.get('useful_discard', False)), 'okey': bool(payload.get('okey_discard', False)), 'penalty': int(payload.get('penalty', 0) or 0)}
            self.state.log.append(f'{p.name} taş attı.')
            if payload.get('useful_discard'):
                self._emit_table_event('useful_discard', seat, f'{p.name}: İŞLER TAŞ ATTI • +101')
            elif payload.get('okey_discard'):
                self._emit_table_event('okey_discard', seat, f'{p.name}: OKEY ATTI • +101')
            else:
                self._emit_table_event('discard', seat, f'{p.name} taş attı')
            if len(p.hand) == 0 and finishing_tile is not None:
                self._finish_by_player(seat, finishing_tile, elden_finish=elden_finish)
            elif not self.state.stock:
                self._finish_stock()
            else:
                self.state.phase = 'draw'
                self.state.turn_no += 1
        return r

    def auto_open_series(self, seat: int) -> ActionResult:
        p = self.state.player(seat)
        required = p.pending_left_tile_id
        if not p.opened:
            groups = find_series_groups(self.service.rules, p.hand, self.state.min_opening_score, required, len(p.hand) - 1)
            if not groups:
                return ActionResult(False, 'no_101_opening_with_left' if required else 'no_101_opening')
        else:
            if p.opening_mode != 'series':
                return ActionResult(False, 'wrong_opening_mode')
            groups = find_series_groups(self.service.rules, p.hand, 0, required, len(p.hand) - 1)
            if not groups:
                return ActionResult(False, 'no_new_series')
        return self.service.open_series(seat, [[t.id for t in g] for g in groups])

    def auto_open_pairs(self, seat: int) -> ActionResult:
        p = self.state.player(seat)
        required = p.pending_left_tile_id
        if p.opened:
            return ActionResult(False, 'already_opened_use_add_pairs')
        pairs = pair_plan_including(self.service.rules, p.hand, self.state.min_opening_pairs, required)
        if not pairs:
            return ActionResult(False, 'no_pair_opening_with_left' if required else 'not_enough_pairs')
        r = self.service.open_pairs(seat, [[t.id for t in g] for g in pairs])
        if r.ok:
            self._cancel_four_pair_openers()
        return r

    def auto_add_pairs(self, seat: int) -> ActionResult:
        p = self.state.player(seat)
        if not p.opened:
            return ActionResult(False, 'must_open_first')
        if p.opening_mode != 'pairs':
            return ActionResult(False, 'wrong_opening_mode')
        if not any((m.meld_type == MeldType.PAIR for m in self.state.melds)):
            return ActionResult(False, 'pair_area_not_open')
        processed = 0
        guard = 0
        while len(p.hand) > 2 and guard < 12:
            guard += 1
            pending = p.pending_left_tile_id
            pairs = find_pairs(self.service.rules, p.hand)
            if pending:
                pairs = [g for g in pairs if any((t.id == pending for t in g))]
            if not pairs:
                break
            r = self.service.layoff_pair(seat, pairs[0][0].id)
            if not r.ok:
                break
            processed += 2
        if not processed:
            return ActionResult(False, 'no_new_pair')
        return ActionResult(True, 'pair_processed', {'processed': processed})

    def _bot_try_take_left(self, seat: int) -> bool:
        if self.state.phase != 'draw':
            return False
        p = self.state.player(seat)
        left = (seat - 1) % 4
        if not self.state.discard_piles[left]:
            return False
        tile = self.state.discard_piles[left][-1]
        if not self._can_use_left_tile(seat, tile):
            return False
        if p.bot_level == 'easy' and random.random() < 0.45:
            return False
        if p.bot_level == 'hard':
            hand = p.hand + [tile]
            if not p.opened:
                series = find_series_groups(self.service.rules, hand, self.state.min_opening_score, tile.id, len(hand) - 1)
                pairs = pair_plan_including(self.service.rules, hand, self.state.min_opening_pairs, tile.id)
                if not series and (not pairs):
                    return False
        return bool(self.draw(seat, 'left').ok)

    def _bot_try_reclaim_okey(self, seat: int) -> bool:
        p = self.state.player(seat)
        if not p.opened or len(p.hand) <= 1:
            return False
        for tile in list(p.hand):
            if self.service.rules._is_joker(tile):
                continue
            for meld in self.state.melds:
                if meld.meld_type == MeldType.PAIR:
                    continue
                if not any((self.service.rules._is_joker(x) for x in meld.tiles)):
                    continue
                r = self.service.replace_table_okey(seat, tile.id, meld.id)
                if r.ok:
                    self.state.log.append(f'{p.name} masadaki okeyi aldı.')
                    return True
        return False

    def _bot_open_best(self, seat: int):
        p = self.state.player(seat)
        if p.opened:
            required = p.pending_left_tile_id
            if p.opening_mode == 'series':
                groups = find_series_groups(self.service.rules, p.hand, 0, required, len(p.hand) - 1) or []
                if groups:
                    candidates = [g for g in groups if not required or any((t.id == required for t in g))]
                    if candidates:
                        best = max(candidates, key=lambda g: (self.service.rules.validate_meld(g).score, len(g)))
                        self.service.open_series(seat, [[t.id for t in best]])
            elif p.opening_mode == 'pairs' and any((m.meld_type == MeldType.PAIR for m in self.state.melds)):
                pairs = find_pairs(self.service.rules, p.hand)
                if required:
                    pairs = [g for g in pairs if any((t.id == required for t in g))]
                if pairs and len(p.hand) > 2:
                    self.service.layoff_pair(seat, pairs[0][0].id)
            return
        required = p.pending_left_tile_id
        max_used = max(0, len(p.hand) - 1)
        series = find_series_groups(self.service.rules, p.hand, self.state.min_opening_score, required, max_used)
        pairs = pair_plan_including(self.service.rules, p.hand, self.state.min_opening_pairs, required)
        if not series and (not pairs):
            return
        series_score = sum((self.service.rules.validate_meld(g).score for g in series or []))
        pair_count = len(pairs or [])
        if not required:
            if p.bot_level == 'easy' and series and (series_score < 120) and (pair_count < 6):
                return
            if p.bot_level == 'medium' and series and (series_score < 112) and (pair_count < 5):
                return
            if p.bot_level == 'hard' and series and (series_score < 105) and (pair_count < 5):
                return
        if pairs and (not series):
            result = self.auto_open_pairs(seat)
        elif series and (not pairs):
            result = self.auto_open_series(seat)
        elif p.bot_level == 'hard' and pairs and (len(pairs) >= 6):
            result = self.auto_open_pairs(seat)
        elif p.bot_level == 'medium' and pairs and (len(pairs) >= 7):
            result = self.auto_open_pairs(seat)
        else:
            result = self.auto_open_series(seat)
        if result.ok and p.opened:
            value = p.opening_pairs if p.opening_mode == 'pairs' else p.opening_score
            self._emit_table_event('opened', seat, f'{p.name} açtı', {'mode': p.opening_mode, 'value': value})

    def _tile_synergy(self, hand: list[Tile], tile: Tile) -> int:
        rules = self.service.rules
        if rules._is_joker(tile):
            return 100
        nt = rules._norm(tile)
        score = 0
        for other in hand:
            if other.id == tile.id:
                continue
            no = rules._norm(other)
            if no.number == nt.number and no.color != nt.color:
                score += 7
            if no.color == nt.color:
                d = abs(int(no.number or 0) - int(nt.number or 0))
                if d == 1:
                    score += 8
                elif d == 2:
                    score += 4
        if self._is_turbo_star(tile):
            score += 10
        return score

    def _bot_discard(self, seat: int) -> ActionResult:
        p = self.state.player(seat)
        rules = self.service.rules

        def protected(t: Tile) -> bool:
            return rules._is_joker(t) or self.service.is_useful_table_tile(p, t)
        safe = [t for t in p.hand if not protected(t)]
        if not safe and p.opened and (len(p.hand) > 1):
            moved = self.service.auto_layoff(seat, max_moves=1)
            if moved.ok and int((moved.payload or {}).get('processed', 0) or 0) > 0:
                p = self.state.player(seat)
                safe = [t for t in p.hand if not protected(t)]
        pool = safe if safe else [t for t in p.hand if not rules._is_joker(t)] or list(p.hand)
        if not pool:
            return ActionResult(False, 'no_tile')

        def danger(t: Tile) -> int:
            nt = rules._norm(t)
            interest = self.opponent_interest.get((nt.color.value if nt.color else 'x', int(nt.number or 0)), 0)
            return interest * 12

        def cost(t: Tile):
            return (1 if self._is_turbo_star(t) else 0, self._tile_synergy(p.hand, t) + danger(t), -int(rules._norm(t).number or 0))
        if p.bot_level == 'easy':
            ordered = sorted(pool, key=cost)
            pick = random.choice(ordered[:max(1, min(4, len(ordered)))])
        else:
            pick = sorted(pool, key=cost)[0]
        self.state.log.append(f'BOT_DISCARD_SCORE seat={seat} level={p.bot_level} tile={pick.id} safe={len(safe)}/{len(p.hand)} synergy={self._tile_synergy(p.hand, pick)}')
        return self.discard(seat, pick.id)

    def bot_turn(self, seat: int):
        if self.state.current_seat != seat or not self.state.player(seat).bot:
            return
        p = self.state.player(seat)
        if p.bot_level == 'afk':
            if self.state.phase == 'draw' and (not self.draw(seat, 'stock').ok):
                return
            if self.state.phase == 'discard' and p.hand:
                self._bot_discard(seat)
            self._check_one_tile_notice(seat)
            return
        if self.state.phase == 'draw':
            if not self._bot_try_take_left(seat) and (not self.draw(seat, 'stock').ok):
                return
        p = self.state.player(seat)
        self._bot_open_best(seat)
        if p.opened:
            guard = 0
            while self._bot_try_reclaim_okey(seat) and guard < 4:
                guard += 1
            self.service.auto_layoff(seat, max_moves={'easy': 1, 'medium': 1, 'hard': 2}.get(p.bot_level, 1))
        if p.pending_left_tile_id:
            self.return_left(seat)
            if self.state.phase == 'draw' and self.draw(seat, 'stock').ok:
                p = self.state.player(seat)
                self._bot_open_best(seat)
                if p.opened:
                    self.service.auto_layoff(seat, max_moves={'easy': 1, 'medium': 1, 'hard': 2}.get(p.bot_level, 1))
        if self.state.phase == 'discard' and p.hand:
            self._bot_discard(seat)
        self._check_one_tile_notice(seat)

    def run_bots_until_human(self) -> bool:
        if self.state.phase == 'finished' or not self.state.started:
            return False
        seat = self.state.current_seat
        if not self.state.player(seat).bot:
            self.bot_next_action_at_ms = 0
            return False
        now = int(time.time() * 1000)
        if self.bot_next_action_at_ms and now < self.bot_next_action_at_ms:
            return False
        self.bot_turn(seat)
        self.bot_next_action_at_ms = int(time.time() * 1000) + self.bot_pace_ms
        return True

    def action(self, seat: int, kind: str, payload: dict) -> ActionResult:
        if self.intro_until_ms and int(time.time() * 1000) < self.intro_until_ms:
            return ActionResult(False, 'round_intro')
        was_opened = self.state.player(seat).opened if seat in self.state.players else False
        if kind == 'start_match':
            return self.start_match(seat)
        if kind == 'new_hand':
            return self.new_hand()
        if kind == 'rematch':
            return self.rematch()
        if kind == 'return_to_game':
            return ActionResult(True, 'human_restored')
        if self.state.phase == 'waiting':
            return ActionResult(False, 'match_not_started')
        if self.state.phase == 'finished':
            return ActionResult(False, 'game_finished')
        action_snapshot = copy.deepcopy(self.state)
        finish_guard_kinds = {'open_series', 'open_pairs', 'add_pairs', 'auto_layoff', 'layoff', 'layoff_pair'}
        guard_snapshot = action_snapshot if kind in finish_guard_kinds else None
        try:
            if kind == 'draw_stock':
                r = self.draw(seat, 'stock')
            elif kind == 'take_left':
                r = self.draw(seat, 'left')
            elif kind == 'return_left':
                r = self.return_left(seat)
            elif kind == 'discard':
                r = self.discard(seat, payload.get('tile_id', ''))
            elif kind == 'open_series':
                manual = payload.get('groups')
                r = self.service.open_series(seat, manual) if manual else self.auto_open_series(seat)
            elif kind == 'open_pairs':
                manual = payload.get('pairs')
                r = self.service.open_pairs(seat, manual) if manual else self.auto_open_pairs(seat)
            elif kind == 'add_pairs':
                r = self.auto_add_pairs(seat)
            elif kind == 'auto_layoff':
                r = self.service.auto_layoff(seat)
            elif kind == 'layoff':
                r = self.service.layoff(seat, payload.get('tile_id', ''), payload.get('meld_id', ''))
            elif kind == 'layoff_pair':
                r = self.service.layoff_pair(seat, payload.get('tile_id', ''))
            elif kind == 'undo_layoff':
                r = self.service.undo_last_layoff(seat)
            elif kind == 'undo_opening':
                r = self.service.undo_last_opening(seat)
            elif kind == 'sort_series':
                r = self.sort_hand(seat, 'series')
            elif kind == 'sort_pairs':
                r = self.sort_hand(seat, 'pairs')
            else:
                r = ActionResult(False, 'unknown_action')
        except Exception as e:
            self.state = action_snapshot
            self.service = GameService(self.state)
            self._assist_cache_key = None
            code = str(e) if str(e) else 'rule_error'
            r = ActionResult(False, code)
        if not r.ok:
            self.state = action_snapshot
            self.service = GameService(self.state)
            self._assist_cache_key = None
        penalty_codes = {'below_opening_threshold', 'invalid_meld', 'run_not_consecutive', 'run_color_mismatch', 'run_duplicate_number', 'set_number_mismatch', 'set_duplicate_color', 'not_enough_pairs', 'pair_mismatch', 'illegal_layoff', 'tile_does_not_replace_okey'}
        if r.ok and kind in finish_guard_kinds and (len(self.state.player(seat).hand) < 1):
            self.state = guard_snapshot
            self.service = GameService(self.state)
            self._assist_cache_key = None
            return ActionResult(False, 'must_keep_finish_tile')
        if not r.ok and kind in ('open_series', 'open_pairs', 'add_pairs', 'layoff', 'layoff_pair') and (r.code in penalty_codes):
            p = self.state.player(seat)
            p.penalty += 101
            payload_out = dict(r.payload or {})
            payload_out.update({'penalty': 101, 'total_penalty': p.penalty})
            r = ActionResult(False, r.code, payload_out)
            self._emit_table_event('rule_penalty', seat, f'{p.name}: HATALI HAMLE • +101', {'code': r.code})
        if r.ok and kind in ('open_series', 'open_pairs') and (not was_opened) and self.state.player(seat).opened:
            p = self.state.player(seat)
            value = p.opening_pairs if p.opening_mode == 'pairs' else p.opening_score
            self._emit_table_event('opened', seat, f'{p.name} açtı', {'mode': p.opening_mode, 'value': value})
        if r.ok and kind == 'discard':
            self._check_one_tile_notice(seat)
            if self.state.phase != 'finished' and self.state.player(self.state.current_seat).bot:
                self.bot_next_action_at_ms = int(time.time() * 1000) + self.bot_pace_ms
        elif r.ok:
            self._check_one_tile_notice(seat)
        if r.ok:
            self.recalculate_turbo()
            self._set_turn_deadline()
            issues = self.audit_state()
            if issues:
                self.state = action_snapshot
                self.service = GameService(self.state)
                self._assist_cache_key = None
                return ActionResult(False, 'state_invariant_error', {'issues': issues})
        return r

    def left_opening_opportunity(self, viewer: int) -> dict | None:
        s = self.state
        if not s.started or s.phase != 'draw' or s.current_seat != viewer:
            return None
        p = s.player(viewer)
        if p.opened:
            return None
        left = (viewer - 1) % 4
        if not s.discard_piles[left]:
            return None
        current_score, _, _, _, _ = self._assisted_preview_cached(viewer)
        current_pair_count = len(find_pairs(self.service.rules, p.hand))
        current_pairs = pair_plan_including(self.service.rules, p.hand, minimum=s.min_opening_pairs)
        if current_score >= s.min_opening_score or current_pairs:
            return None
        tile = s.discard_piles[left][-1]
        hand = list(p.hand) + [tile]
        max_used = max(0, len(hand) - 1)
        series = find_series_groups(self.service.rules, hand, minimum=s.min_opening_score, required_tile_id=tile.id, max_used=max_used)
        series_score = 0
        if series:
            series_score = sum((self.service.rules.validate_meld(g).score for g in series))
        pairs = pair_plan_including(self.service.rules, hand, minimum=s.min_opening_pairs, required_id=tile.id)
        pair_count = len(pairs) if pairs else 0
        if not series and (not pairs):
            return None
        kind = 'both' if series and pairs else 'pairs' if pairs else 'series'
        return {'can_open': True, 'tile_id': tile.id, 'kind': kind, 'current_series_score': current_score, 'series_score': series_score, 'series_gain': max(0, series_score - current_score), 'current_pair_count': current_pair_count, 'pair_count': pair_count, 'pair_gain': max(0, pair_count - current_pair_count), 'series_threshold': s.min_opening_score, 'pair_threshold': s.min_opening_pairs}

    def _assisted_preview_cached(self, viewer: int):
        s = self.state
        p = s.player(viewer)
        key = (viewer, tuple(sorted((t.id for t in p.hand))), s.joker.joker_color.value, s.joker.joker_number, s.min_opening_score, s.min_opening_pairs)
        if self._assist_cache_key == key:
            return self._assist_cache_value
        max_used = max(0, len(p.hand) - 1)
        assist_groups = find_series_groups(self.service.rules, p.hand, minimum=0, max_used=max_used) or []
        assist_groups = [self.service.rules.canonical_meld_order(g, self.service.rules.validate_meld(g).meld_type or MeldType.RUN) for g in assist_groups]
        assist_used = {t.id for g in assist_groups for t in g}
        assist_score = sum((self.service.rules.validate_meld(g).score for g in assist_groups))
        preview_score, preview_used = best_series_preview(self.service.rules, p.hand, max_used)
        value = (preview_score, preview_used, assist_groups, list(assist_used), assist_score)
        self._assist_cache_key = key
        self._assist_cache_value = value
        return value

    def available_actions(self, viewer: int) -> dict[str, bool]:
        result = {'open_series': False, 'open_pairs': False, 'add_pairs': False, 'return_left': False, 'undo_opening': False, 'undo_layoff': False, 'auto_layoff': False}
        s = self.state
        if not s.started or s.phase != 'discard' or s.current_seat != viewer:
            return result
        p = s.player(viewer)
        required = p.pending_left_tile_id
        max_used = max(0, len(p.hand) - 1)
        cached_preview = self._assisted_preview_cached(viewer) if required is None else None
        if not p.opened:
            if required is None:
                result['open_series'] = bool(cached_preview and cached_preview[0] >= s.min_opening_score and (cached_preview[1] <= max_used))
            else:
                result['open_series'] = bool(find_series_groups(self.service.rules, p.hand, s.min_opening_score, required, max_used))
            result['open_pairs'] = bool(pair_plan_including(self.service.rules, p.hand, s.min_opening_pairs, required))
        else:
            if p.opening_mode == 'series':
                if required is None:
                    result['open_series'] = bool(cached_preview and cached_preview[2])
                else:
                    result['open_series'] = bool(find_series_groups(self.service.rules, p.hand, 0, required, max_used))
            if p.opening_mode == 'pairs':
                result['add_pairs'] = bool(pair_plan_including(self.service.rules, p.hand, 1, required))
            result['auto_layoff'] = self.service.can_auto_layoff(viewer)
        result['return_left'] = bool(required and any((t.id == required for t in p.hand)))
        result['undo_opening'] = p.turn_table_snapshot is not None or p.last_open_batch is not None
        result['undo_layoff'] = p.last_layoff is not None
        return result

    def public_state(self, viewer: int=0):
        s = self.state

        def player(p: PlayerState):
            return {'seat': p.seat, 'name': p.name, 'hand_count': len(p.hand), 'opened': p.opened, 'opening_mode': p.opening_mode, 'opening_score': p.opening_score, 'opening_pairs': p.opening_pairs, 'penalty': p.penalty, 'bot': p.bot, 'bot_level': p.bot_level, 'pending_left_tile_id': p.pending_left_tile_id, 'can_undo_layoff': p.last_layoff is not None, 'can_undo_opening': p.turn_table_snapshot is not None or p.last_open_batch is not None, 'turbo_star_count': sum((1 for t in p.hand if self._is_turbo_star(t))) if p.seat == viewer else None, 'rack_value': self._rack_value(p.seat) if p.seat == viewer else None, 'hand': [_serialize_tile(t, s.joker, s.turbo) for t in p.hand] if p.seat == viewer else []}
        viewer_p = s.player(viewer)
        active_turn = bool(s.started and s.current_seat == viewer)
        active_assist = bool(s.assisted and active_turn)
        penalty_tiles = [t.id for t in viewer_p.hand if self.service.rules._is_joker(t) or self.service.is_useful_table_tile(viewer_p, t)] if active_turn and s.phase == 'discard' else []
        useful = list(penalty_tiles) if active_assist else []
        if active_assist:
            preview_score, preview_used, assist_groups, assist_used, assist_score = self._assisted_preview_cached(viewer)
            preview_pairs = len(find_pairs(self.service.rules, viewer_p.hand))
            left_opportunity = self.left_opening_opportunity(viewer)
        else:
            preview_score, preview_used, assist_groups, assist_used, assist_score = (0, 0, [], [], 0)
            preview_pairs = 0
            left_opportunity = None
        left_useful_tile_id = None
        left_useful_reason = None
        if s.assisted and s.started and (s.phase == 'draw') and (s.current_seat == viewer):
            left = (viewer - 1) % 4
            if s.discard_piles[left]:
                lt = s.discard_piles[left][-1]
                if viewer_p.opened and self._can_use_left_tile(viewer, lt):
                    left_useful_tile_id = lt.id
                    left_useful_reason = 'İŞLENİR'
                elif not viewer_p.opened and left_opportunity and (left_opportunity.get('tile_id') == lt.id):
                    left_useful_tile_id = lt.id
                    kind = str(left_opportunity.get('kind') or '')
                    left_useful_reason = '101 AÇAR' if kind == 'series' else 'ÇİFT AÇAR' if kind == 'pairs' else 'AÇILIŞ YAPAR'
        return {'room_id': s.room_id, 'available_actions': self.available_actions(viewer), 'left_opening_opportunity': left_opportunity, 'left_useful_tile_id': left_useful_tile_id, 'left_useful_reason': left_useful_reason, 'penalty_tile_ids': penalty_tiles, 'opening_preview_score': preview_score, 'opening_preview_used': preview_used, 'opening_preview_pairs': preview_pairs, 'assisted_series_score': assist_score, 'assisted_series_groups': [[t.id for t in g] for g in assist_groups], 'assisted_series_used_ids': list(assist_used), 'current_seat': s.current_seat, 'starter_seat': s.starter_seat, 'phase': s.phase, 'winner_seat': s.winner_seat, 'turn_no': s.turn_no, 'stock_count': s.stock_count, 'useful_tile_ids': useful, 'round_scores': {str(k): v for k, v in s.round_scores.items()}, 'round_team_scores': {str(k): v for k, v in self.team_score_map(s.round_scores).items()}, 'round_breakdown': {str(k): v for k, v in s.round_breakdown.items()}, 'round_end_reason': s.round_end_reason, 'indicator': _serialize_tile(s.indicator, s.joker, s.turbo) if s.indicator else {'id': 'indicator', 'n': s.joker.indicator_number, 'c': s.joker.indicator_color.value, 'joker': False, 'fake': False}, 'joker': {'c': s.joker.joker_color.value, 'n': s.joker.joker_number}, 'multiplier': s.multiplier, 'turbo_stars_on_table': s.turbo_stars_on_table, 'turbo_star_number': s.joker.joker_number, 'entry_fee': s.entry_fee, 'pot': s.pot, 'assisted': s.assisted, 'room_name': s.room_name, 'turbo': s.turbo, 'game_mode': 'turbo' if s.turbo else 'standard', 'team_mode': s.team_mode, 'started': s.started, 'turn_seconds': s.turn_seconds, 'turn_deadline_ms': s.turn_deadline_ms, 'intro_until_ms': self.intro_until_ms, 'variant': s.variant, 'min_opening_score': s.min_opening_score, 'min_opening_pairs': s.min_opening_pairs, 'round_index': s.round_index, 'max_rounds': s.max_rounds, 'total_scores': {str(k): v for k, v in s.total_scores.items()}, 'team_total_scores': {str(k): v for k, v in self.team_score_map(s.total_scores).items()}, 'match_finished': s.match_finished, 'round_finish_flags': dict(s.round_finish_flags), 'round_history': list(s.round_history), 'players': [player(s.players[i]) for i in range(4)], 'melds': [{'id': m.id, 'owner_seat': m.owner_seat, 'kind': m.meld_type.value, 'tiles': [_serialize_tile(t, s.joker, s.turbo) for t in m.tiles]} for m in s.melds], 'discards': {str(i): _serialize_tile(v[-1], s.joker, s.turbo) if v else None for i, v in s.discard_piles.items()}, 'discard_trails': {str(i): [_serialize_tile(t, s.joker, s.turbo) for t in v[-4:]] for i, v in s.discard_piles.items()}, 'discard_meta': {str(i): s.discard_meta.get(i, {}) for i in range(4)}, 'last_event': s.last_event, 'events': s.event_history[-24:], 'log': s.log[-8:]}
ROOMS: dict[str, Room] = {}

def new_room(seed: int | None=None, variant: str='non_fold', **kwargs) -> Room:
    r = Room(seed, variant, **kwargs)
    ROOMS[r.state.room_id] = r
    return r
