"""V13 quick-match bot fill timer regression tests."""
import asyncio

from app.api import game as G
from app.services.account_store import AccountStore


def test_quick_fill_deadline_starts_room_and_uses_distinct_local_names(tmp_path, monkeypatch):
    G.ROOMS.clear(); G.ROOM_META.clear(); G.SOCKETS.clear()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    account = store.ensure('v13-human', 'Senshi', None, None, is_guest=True)
    room = G.new_room(room_name='V13 hızlı eşleşme', waiting=True, entry_fee=0)
    rid = room.state.room_id
    meta = G._ensure_meta(rid)
    meta['quick_match'] = True
    G._bind_human(rid, 0, 'v13-human', 'Senshi')
    meta['quick_fill_at'] = G._now()

    async def no_wait(_seconds):
        return None
    async def no_broadcast(_room_id):
        return None
    monkeypatch.setattr(G.asyncio, 'sleep', no_wait)
    monkeypatch.setattr(G, '_broadcast', no_broadcast)
    asyncio.run(G._quick_fill_after_delay(rid))

    assert room.state.started is True
    assert G._human_count(rid) == 1
    bots = [p for p in room.state.players.values() if p.bot]
    assert len(bots) == 3
    assert len({p.name for p in bots}) == 3
    assert all(p.name != 'Normal Bot' for p in bots)
    G.ROOMS.clear(); G.ROOM_META.clear(); G.SOCKETS.clear()


def test_quick_fill_does_not_leave_ghost_bots_when_balance_check_fails(tmp_path, monkeypatch):
    G.ROOMS.clear(); G.ROOM_META.clear(); G.SOCKETS.clear()
    store = AccountStore(tmp_path / 'accounts.json')
    monkeypatch.setattr(G, 'STORE', store)
    monkeypatch.setattr(G, '_persist_runtime', lambda force=False: None)
    store.ensure('v13-poor-human', 'Oyuncu', None, None, is_guest=True)
    room = G.new_room(room_name='V13 bakiye kontrolü', waiting=True, entry_fee=5000)
    rid = room.state.room_id
    G._ensure_meta(rid)
    G._bind_human(rid, 0, 'v13-poor-human', 'Oyuncu')
    monkeypatch.setattr(G, '_charge_entries', lambda _rid: (False, 'not_enough_chips:0'))

    assert G._fill_bots_and_start(rid) is False
    assert room.state.phase == 'waiting'
    assert not room.state.started
    assert not G.ROOM_META[rid].get('bot_seats')
    assert all(seat not in G.ROOM_META[rid].get('bot_seats', set()) for seat in (1, 2, 3))
    G.ROOMS.clear(); G.ROOM_META.clear(); G.SOCKETS.clear()
