import asyncio
import pytest
from app.api import game as G
from app.services.account_store import AccountStore

def _clean():
    G.ROOMS.clear(); G.ROOM_META.clear(); G.SOCKETS.clear(); G.QUICK_FILL_TASKS.clear()

def test_explicit_bots_count_as_occupied_not_humans(tmp_path, monkeypatch):
    _clean()
    store=AccountStore(tmp_path / "accounts.json")
    monkeypatch.setattr(G, "STORE", store)
    monkeypatch.setattr(G, "_persist_runtime", lambda force=False: None)
    store.ensure("v14-owner", "Senshi", None, None, is_guest=True)
    room=G.new_room(room_name="V14 bot seats", waiting=True, entry_fee=0)
    rid=room.state.room_id; meta=G._ensure_meta(rid)
    G._bind_human(rid, 0, "v14-owner", "Senshi")
    for seat, name in zip((1,2,3), ("Mert","Ayşe","Kemal")):
        meta.setdefault("bot_seats", set()).add(seat)
        p=room.state.player(seat); p.bot=True; p.bot_level="hard"; p.user_id=f"bot-seat-{seat}"; p.name=name
    assert G._human_count(rid)==1
    assert G._bot_count(rid)==3
    assert G._occupied_count(rid)==4
    state=G._state(rid,0)
    assert (state["human_count"],state["bot_count"],state["occupied_count"],state["empty_count"])==(1,3,4,0)
    assert all(not p["empty"] for p in state["players"])
    _clean()

def test_private_room_open_seat_validation_accepts_three_bots(tmp_path, monkeypatch):
    _clean()
    store=AccountStore(tmp_path / "accounts.json")
    monkeypatch.setattr(G, "STORE", store)
    monkeypatch.setattr(G, "_persist_runtime", lambda force=False: None)
    store.ensure("v14-host", "Senshi", None, None, is_guest=True)
    room=G.new_room(room_name="V14 private bots", waiting=True, entry_fee=0)
    rid=room.state.room_id; meta=G._ensure_meta(rid); meta["legacy"]=False
    G._bind_human(rid,0,"v14-host","Senshi")
    for seat in (1,2,3):
        meta.setdefault("bot_seats",set()).add(seat)
        p=room.state.player(seat);p.bot=True;p.bot_level="medium";p.user_id=f"bot-seat-{seat}";p.name=f"Bot {seat}"
    open_seats=[seat for seat in range(4) if seat not in meta.get("player_ids",{}) and not (seat in meta.setdefault("bot_seats",set()) and room.state.player(seat).bot)]
    assert G._occupied_count(rid)==4 and open_seats==[]
    _clean()


def test_quick_fill_retries_after_temporary_entry_failure(tmp_path, monkeypatch):
    _clean()
    store=AccountStore(tmp_path / "accounts.json")
    monkeypatch.setattr(G, "STORE", store)
    monkeypatch.setattr(G, "_persist_runtime", lambda force=False: None)
    store.ensure("v14-retry", "Senshi", None, None, is_guest=True)
    room=G.new_room(room_name="V14 retry", waiting=True, entry_fee=0)
    rid=room.state.room_id; meta=G._ensure_meta(rid); meta["quick_match"]=True
    G._bind_human(rid,0,"v14-retry","Senshi")
    meta["quick_fill_at"]=G._now()
    calls={"n":0}
    def fill(_rid, _level):
        calls["n"] += 1
        if calls["n"] == 1:
            meta["quick_fill_error"]="not_enough_chips:0"
            return False
        # Complete the room through the real fill function after the retry.
        return original(_rid, _level)
    original=G._fill_bots_and_start
    async def no_wait(_seconds):
        return None
    async def no_broadcast(_room_id):
        return None
    monkeypatch.setattr(G, "_fill_bots_and_start", fill)
    monkeypatch.setattr(G.asyncio, "sleep", no_wait)
    monkeypatch.setattr(G, "_broadcast", no_broadcast)
    asyncio.run(G._quick_fill_after_delay(rid))
    assert calls["n"] == 2
    assert room.state.started is True
    _clean()
