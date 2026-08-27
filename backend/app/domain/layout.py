from __future__ import annotations
from dataclasses import dataclass
from typing import Iterable
from .models import Meld, MeldType

@dataclass(frozen=True, slots=True)
class LanePosition:
    row: int
    col: int

def pack_series(melds: Iterable[Meld], columns: int=3) -> dict[str, LanePosition]:
    out: dict[str, LanePosition] = {}
    index = 0
    for meld in melds:
        if meld.meld_type == MeldType.PAIR:
            continue
        out[meld.id] = LanePosition(index // columns, index % columns)
        index += 1
    return out

def pack_pairs(melds: Iterable[Meld], rows_per_column: int=6) -> dict[str, LanePosition]:
    out: dict[str, LanePosition] = {}
    index = 0
    for meld in melds:
        if meld.meld_type != MeldType.PAIR:
            continue
        out[meld.id] = LanePosition(index % rows_per_column, index // rows_per_column)
        index += 1
    return out

def discard_anchor_for_seat(seat: int) -> str:
    anchors = {0: 'bottom-right', 1: 'right-bottom', 2: 'top-right', 3: 'left-right'}
    if seat not in anchors:
        raise ValueError('invalid_seat')
    return anchors[seat]
