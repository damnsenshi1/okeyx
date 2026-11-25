from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum

class Color(str, Enum):
    RED='red'; BLACK='black'; BLUE='blue'; YELLOW='yellow'

@dataclass(frozen=True, slots=True)
class Tile:
    id: str
    color: Color | None
    number: int | None
    fake_joker: bool = False

    @property
    def face_value(self) -> int:
        return int(self.number or 0)

@dataclass(frozen=True, slots=True)
class JokerContext:
    indicator_color: Color
    indicator_number: int

    @property
    def joker_color(self) -> Color: return self.indicator_color
    @property
    def joker_number(self) -> int: return 1 if self.indicator_number == 13 else self.indicator_number + 1
    def is_real_joker(self, tile: Tile) -> bool:
        return (not tile.fake_joker and tile.color == self.joker_color and tile.number == self.joker_number)
    def normalized(self, tile: Tile) -> Tile:
        # Sahte okey, gösterge+1 olan gerçek okey taşının NORMAL yüzünü temsil eder.
        if tile.fake_joker: return Tile(tile.id, self.joker_color, self.joker_number, False)
        return tile

class MeldType(str, Enum):
    RUN='run'; SET='set'; PAIR='pair'

@dataclass(slots=True)
class Meld:
    id: str
    owner_seat: int
    meld_type: MeldType
    tiles: list[Tile] = field(default_factory=list)

@dataclass(slots=True)
class PlayerState:
    user_id: str
    seat: int
    hand: list[Tile]
    name: str=''
    opened: bool=False
    opening_mode: str | None=None  # series | pairs
    opening_score: int=0
    opening_pairs: int=0
    penalty: int=0
    bot: bool=False
    bot_level: str='medium'  # easy | medium | hard
    # 101: soldan alınan fiziksel taş bu tur mutlaka açılışta/işlemede kullanılmalı.
    pending_left_tile_id: str | None=None
    pending_left_from_seat: int | None=None
    # Son işlenen taş yalnızca aynı tur içinde geri alınabilir.
    last_layoff: tuple[str,str] | None=None  # (tile_id, meld_id)
    last_open_batch: dict | None=None  # same-turn GERİ TOPLA snapshot
    # Bu tur masaya yapılan ilk açma/işleme öncesindeki tam durum. GERİ TOPLA
    # tek tek değil, o tur masaya bırakılan bütün taşları güvenle geri getirir.
    turn_table_snapshot: dict | None=None
    one_tile_announced: bool=False

@dataclass(slots=True)
class TableState:
    room_id: str
    joker: JokerContext
    players: dict[int, PlayerState]
    indicator: Tile | None = None
    stock: list[Tile] = field(default_factory=list)
    melds: list[Meld]=field(default_factory=list)
    discard_piles: dict[int, list[Tile]]=field(default_factory=lambda: {0:[],1:[],2:[],3:[]})
    discard_meta: dict[int,dict]=field(default_factory=lambda:{0:{},1:{},2:{},3:{}})
    current_seat: int=0
    # Eli 22 taşla başlatan oyuncu. İlk turda bu oyuncu taş çekmeden atar.
    starter_seat: int=0
    phase: str='discard'  # draw | discard | finished
    winner_seat: int | None=None
    round_scores: dict[int,int]=field(default_factory=dict)
    round_breakdown: dict[int,dict]=field(default_factory=dict)
    round_end_reason: str | None=None
    round_finish_flags: dict = field(default_factory=dict)
    round_history: list[dict] = field(default_factory=list)
    total_scores: dict[int,int]=field(default_factory=lambda:{0:0,1:0,2:0,3:0})
    round_index: int=1
    max_rounds: int=3
    match_finished: bool=False
    event_seq: int=0
    last_event: dict | None=None
    event_history: list[dict]=field(default_factory=list)
    turn_no: int=1
    mode: str='101'       # 101 | normal
    variant: str='non_fold'  # non_fold | fold
    turbo: bool=False
    multiplier: int=1
    multiplier_tile_number: int | None=None
    turbo_stars_on_table: int=0
    turbo_committed_star_ids: list[str]=field(default_factory=list)
    entry_fee: int=500
    assisted: bool=True
    room_name: str='OkeyX Masası'
    team_mode: str='solo'
    pot: int=0
    started: bool=True
    turn_seconds: int=35
    turn_deadline_ms: int=0
    # Katlamalı global barajlar. Katlamasızda 101/5 sabit kalır.
    min_opening_score: int=101
    min_opening_pairs: int=5
    log: list[str]=field(default_factory=list)

    @property
    def stock_count(self) -> int: return len(self.stock)
    def player(self, seat:int) -> PlayerState: return self.players[seat]
