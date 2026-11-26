from __future__ import annotations

from app.services.game_runtime import Room
from app.services.runtime_persistence import load_runtime, save_runtime


def test_active_room_snapshot_roundtrip_is_signed_and_recoverable(tmp_path):
    path = tmp_path / 'active_rooms.bin'
    room = Room(seed=77, random_starter=False)
    room_id = room.state.room_id
    rooms = {room_id: room}
    meta = {
        room_id: {
            'state_version': 9,
            'seat_tokens': {0: 'token-0'},
            'player_ids': {0: 'player-0'},
            'connected': {0: True},
            'disconnect_at': {0: 123.0},
            'action_times': {'token-0': [1.0]},
            'chat_times': {'token-0': [1.0]},
            'dedupe': {'abc': {'ok': True}},
        }
    }

    save_runtime(str(path), 'test-secret', rooms, meta)
    loaded_rooms, loaded_meta = load_runtime(str(path), 'test-secret')

    assert room_id in loaded_rooms
    assert loaded_rooms[room_id].audit_state() == []
    assert loaded_rooms[room_id].service.state is loaded_rooms[room_id].state
    assert loaded_meta[room_id]['state_version'] == 9
    assert loaded_meta[room_id]['connected'][0] is False
    assert loaded_meta[room_id]['disconnect_at'] == {}
    assert loaded_meta[room_id]['action_times'] == {}
    assert loaded_meta[room_id]['chat_times'] == {}
    assert loaded_meta[room_id]['dedupe'] == {}

    wrong_rooms, wrong_meta = load_runtime(str(path), 'wrong-secret')
    assert wrong_rooms == {} and wrong_meta == {}
