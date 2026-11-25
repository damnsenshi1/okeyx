"""Aşama 1: oyuncular ve seyirciler başkasının taşlarını görememeli."""
from __future__ import annotations

import json

from app.api import game as g
from app.services.game_runtime import Room


def _room(seed=11):
    room = Room(seed=seed)
    rid = room.state.room_id
    g.ROOMS[rid] = room
    g._ensure_meta(rid)
    return room, rid


def _all_hand_ids(room, seat):
    return {t.id for t in room.state.players[seat].hand}


def test_player_view_contains_only_own_hand_ids():
    room, rid = _room()
    state = g._state(rid, 0)
    blob = json.dumps(state)
    for seat in (1, 2, 3):
        other = _all_hand_ids(room, seat)
        assert not any(f'"{i}"' in blob for i in other), f'seat {seat} taşları sızdı'
    mine = {t['id'] for t in state['players'][0]['hand']}
    assert mine == _all_hand_ids(room, 0)


def test_spectator_view_contains_no_rack_and_no_private_ids():
    room, rid = _room(seed=12)
    m = g._ensure_meta(rid)
    m['spectators']['spec-1'] = {'last_seen': g._now(), 'points': 0, 'prediction': {}}
    state = g._spectator_state(rid, 'spec-1')
    assert state['viewer_seat'] == -1
    assert all(p['hand'] == [] for p in state['players'])
    blob = json.dumps(state)
    for seat in range(4):
        assert not any(f'"{i}"' in blob for i in _all_hand_ids(room, seat)), f'seat {seat} seyirciye sızdı'
    stock_ids = {t.id for t in room.state.stock}
    assert not any(f'"{i}"' in blob for i in stock_ids), 'deste (istok) sırası seyirciye sızdı'
    assert not any(k in state for k in ('available_actions', 'useful_tile_ids', 'viewer_chips'))
