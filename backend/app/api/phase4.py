from __future__ import annotations

import secrets
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from app.core.config import settings
from app.services.account_store import STORE
from app.services.phase4_service import Phase4Service

router = APIRouter(tags=["phase4"])


def _svc() -> Phase4Service:
    return Phase4Service(STORE)


def _require(player_id: str, token: str | None) -> None:
    if not STORE.ready:
        raise HTTPException(503, "storage_unavailable")
    if not STORE.get(player_id):
        raise HTTPException(404, "account_not_found")
    if not STORE.verify(player_id, token):
        raise HTTPException(401, "invalid_account_token")


def _admin(key: str | None) -> None:
    if not settings.admin_enabled:
        raise HTTPException(503, "admin_disabled")
    if not key or not secrets.compare_digest(key.encode("utf-8"), settings.admin_key.encode("utf-8")):
        raise HTTPException(401, "admin_key_invalid")


class ItemIn(BaseModel):
    player_id: str
    item_id: str


class PurchaseTestIn(BaseModel):
    player_id: str
    sku: str
    receipt_id: str
    amount_minor: int
    currency: str = "TRY"


class RefundIn(BaseModel):
    provider: str = "test"
    receipt_id: str
    reason: str = "refund"


class PassClaimIn(BaseModel):
    player_id: str
    level: int
    premium: bool = False


class PassTaskIn(BaseModel):
    player_id: str
    task_id: str


class AdStartIn(BaseModel):
    player_id: str
    reward_kind: str = "coins"


class AdClaimIn(BaseModel):
    player_id: str
    token: str


class SideGameIn(BaseModel):
    player_id:str
    game:str
    choice:int|None=None
    wager:int|None=None
    use_voucher:bool=False
    action:str|None=None
    challenge_id:str|None=None
    active_lines:list[int]|None=None


class VoiceIn(BaseModel):
    player_id: str
    enabled: bool | None = None
    mute_player_id: str | None = None
    muted: bool | None = None


class ModReportIn(BaseModel):
    player_id: str
    target_id: str
    reason: str = "other"
    room_id: str | None = None
    source: str = "voice"


class ConfigPatchIn(BaseModel):
    patch: dict
    actor: str = "admin"

class LiveEventIn(BaseModel):
    id: str | None = None
    title: str
    subtitle: str = ""
    starts_at: int | None = None
    ends_at: int | None = None
    enabled: bool = True
    kind: str = "seasonal"
    config: dict = {}
    actor: str = "admin"

class StaffRewardConfigIn(BaseModel):
    actor_id:str
    config:dict={}

class StaffSanctionIn(BaseModel):
    actor_id:str;player_id:str;sanction_type:str;duration_minutes:int=0;reason:str=""
class StaffWalletIn(BaseModel):
    actor_id:str;player_id:str;currency:str;amount:int;reason:str=""
class StaffRtpIn(BaseModel):
    actor_id:str;game:str;percent:float;event_title:str=""

@router.get("/phase4/{player_id}/hub")
def phase4_hub(player_id: str, x_account_token: str | None = Header(None)):
    _require(player_id, x_account_token)
    return _svc().hub(player_id)


@router.post("/phase4/store/buy")
def phase4_buy(body: ItemIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().buy_cosmetic(body.player_id, body.item_id)


@router.post("/phase4/store/equip")
def phase4_equip(body: ItemIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().equip(body.player_id, body.item_id)


@router.post("/phase4/vip/{player_id}/daily")
def phase4_vip_daily(player_id: str, x_account_token: str | None = Header(None)):
    _require(player_id, x_account_token)
    return _svc().claim_vip_daily(player_id)

@router.post("/phase4/event/{player_id}/{event_id}/claim")
def phase4_event_claim(player_id: str, event_id: str, x_account_token: str | None = Header(None)):
    _require(player_id, x_account_token)
    return _svc().claim_live_event(player_id, event_id)


@router.post("/phase4/pass/task")
def phase4_pass_task(body: PassTaskIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().claim_pass_task(body.player_id, body.task_id)


@router.post("/phase4/pass/claim")
def phase4_pass_claim(body: PassClaimIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().claim_pass_level(body.player_id, body.level, body.premium)


@router.get("/phase4/side-games/catalog")
def phase4_side_catalog():
    return _svc().side_game_catalog()


@router.post("/phase4/side-games/play")
def phase4_side_play(body: SideGameIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().play_side_game(body.player_id,body.game,body.choice,body.wager,body.use_voucher,body.action,body.challenge_id,body.active_lines)


@router.post("/phase4/salon/claim/{player_id}")
def phase4_salon_claim(player_id: str, x_account_token: str | None = Header(None)):
    _require(player_id, x_account_token)
    return _svc().salon_claim(player_id)


@router.post("/phase4/ads/transition/{player_id}")
def phase4_ad_transition(player_id: str, x_account_token: str | None = Header(None)):
    _require(player_id, x_account_token)
    return _svc().match_transition_ad(player_id)


@router.post("/phase4/ads/start")
def phase4_ad_start(body: AdStartIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().start_ad_session(body.player_id, body.reward_kind)


@router.post("/phase4/ads/claim")
def phase4_ad_claim(body: AdClaimIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().claim_ad_reward(body.player_id, body.token)


@router.post("/phase4/voice")
def phase4_voice(body: VoiceIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().set_voice(body.player_id, body.enabled, body.mute_player_id, body.muted)


@router.post("/phase4/moderation/report")
def phase4_mod_report(body: ModReportIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().moderate_report(body.player_id, body.target_id, body.reason, body.room_id, body.source)


class GoogleVerifyIn(BaseModel):
    player_id: str
    product_id: str
    purchase_token: str


_GOOGLE_CLIENT = None


def _google_client():
    global _GOOGLE_CLIENT
    if not settings.google_play_service_account_json:
        raise HTTPException(503, "billing_not_configured")
    if _GOOGLE_CLIENT is None:
        from app.services.google_play import GooglePlayClient, GooglePlayError
        try:
            _GOOGLE_CLIENT = GooglePlayClient(settings.google_play_service_account_json, settings.android_package)
        except GooglePlayError:
            raise HTTPException(503, "billing_not_configured")
    return _GOOGLE_CLIENT


@router.post("/phase4/store/google-verify")
def phase4_google_verify(body: GoogleVerifyIn, x_account_token: str | None = Header(None)):
    """Gerçek satın alma: Google'a sorulur, katalogdaki ürün/tutar uygulanır, aynı sipariş iki kez işlenmez."""
    _require(body.player_id, x_account_token)
    from app.services.google_play import GooglePlayError, price_hint_to_minor
    client = _google_client()
    svc = _svc()
    product = next((x for x in svc._global()["config"].get("billing_products", []) if x["sku"] == body.product_id), None)
    if not product:
        raise HTTPException(404, "sku_not_found")
    try:
        data = client.verify_product(body.product_id, body.purchase_token)
    except GooglePlayError as exc:
        raise HTTPException(402, exc.code)
    order_id = str(data.get("orderId") or "")
    out = svc.grant_verified_purchase(body.player_id, body.product_id, order_id, price_hint_to_minor(str(product.get("price_hint", ""))), "TRY", "google_play")
    if out.get("ok"):
        try:
            client.acknowledge(body.product_id, body.purchase_token)
        except Exception:
            pass  # Google 3 gün içinde tekrar sorar; hediye zaten bir kez verildi
    return out


@router.post("/phase4/dev/verify-purchase")
def phase4_dev_purchase(body: PurchaseTestIn, x_account_token: str | None = Header(None)):
    _require(body.player_id, x_account_token)
    if not settings.allow_test_billing:
        raise HTTPException(403, "test_billing_disabled")
    return _svc().grant_verified_purchase(body.player_id, body.sku, body.receipt_id, body.amount_minor, body.currency, "test")


@router.get("/phase4/staff/{player_id}/me")
def staff_me(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token);return _svc().staff_me(player_id)

@router.get("/phase4/staff/{player_id}/snapshot")
def staff_snapshot(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token);svc=_svc()
    try:svc.require_staff(player_id,"moderate")
    except PermissionError:raise HTTPException(403,"staff_permission_denied")
    return {"ok":True,"staff":svc.staff_me(player_id),**svc.admin_snapshot()}

@router.get("/phase4/staff/{player_id}/players")
def staff_players(player_id:str,q:str="",x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    try:return {"ok":True,"players":_svc().staff_search_players(player_id,q)}
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.post("/phase4/staff/reward-config")
def staff_reward_config(body:StaffRewardConfigIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_reward_config(body.actor_id,body.config)
    except PermissionError as e:raise HTTPException(403,str(e))

@router.post("/phase4/staff/sanction")
def staff_sanction(body:StaffSanctionIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_sanction(body.actor_id,body.player_id,body.sanction_type,body.duration_minutes,body.reason)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.post("/phase4/staff/wallet")
def staff_wallet(body:StaffWalletIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_adjust_wallet(body.actor_id,body.player_id,body.currency,body.amount,body.reason)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

class StaffPatchIn(BaseModel):
    actor_id: str
    target: str = ""
    patch: dict = {}

@router.get("/phase4/staff/{player_id}/market")
def staff_market(player_id:str,x_account_token:str|None=Header(None)):
    _require(player_id,x_account_token)
    try:return _svc().staff_market(player_id)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.post("/phase4/staff/cosmetic")
def staff_cosmetic(body:StaffPatchIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_update_cosmetic(body.actor_id,body.target,body.patch)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.post("/phase4/staff/product")
def staff_product(body:StaffPatchIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_update_product(body.actor_id,body.target,body.patch)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.post("/phase4/staff/economy")
def staff_economy(body:StaffPatchIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_update_economy(body.actor_id,body.patch)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.post("/phase4/staff/rtp")
def staff_rtp(body:StaffRtpIn,x_account_token:str|None=Header(None)):
    _require(body.actor_id,x_account_token)
    try:return _svc().staff_set_rtp(body.actor_id,body.game,body.percent,body.event_title)
    except PermissionError:raise HTTPException(403,"staff_permission_denied")

@router.put("/phase4/staff/live-events")
def staff_event(body:LiveEventIn,actor_id:str,x_account_token:str|None=Header(None)):
    _require(actor_id,x_account_token);svc=_svc()
    try:svc.require_staff(actor_id,"events")
    except PermissionError:raise HTTPException(403,"staff_permission_denied")
    return svc.admin_upsert_live_event(body.model_dump(exclude_none=True),actor_id)

@router.delete("/phase4/staff/live-events/{event_id}")
def staff_event_delete(event_id:str,actor_id:str,x_account_token:str|None=Header(None)):
    _require(actor_id,x_account_token);svc=_svc()
    try:svc.require_staff(actor_id,"events")
    except PermissionError:raise HTTPException(403,"staff_permission_denied")
    return svc.admin_delete_live_event(event_id,actor_id)

@router.post("/phase4/admin/refund")
def phase4_admin_refund(body: RefundIn, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return _svc().refund_purchase(body.provider, body.receipt_id, body.reason)


@router.get("/phase4/admin/snapshot")
def phase4_admin_snapshot(x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return _svc().admin_snapshot()


@router.get("/phase4/admin/ops")
def phase4_admin_ops(x_admin_key: str | None = Header(None)):
    """Canlı sağlık: oda/oyuncu sayısı, hata ve yavaş istek sayaçları, depolama durumu."""
    _admin(x_admin_key)
    from app.core.observability import snapshot
    from app.api import game as G
    from app.services.account_store import STORE
    humans = sum(1 for rid, r in G.ROOMS.items() for seat, pid in (G.ROOM_META.get(rid, {}).get('player_ids') or {}).items() if pid and not r.state.players[int(seat)].bot)
    return {
        'rooms': len(G.ROOMS),
        'active_rooms': sum(1 for r in G.ROOMS.values() if r.state.started and not r.state.match_finished),
        'seated_humans': humans,
        'accounts': len(STORE._data.get('accounts', {})),
        'storage': STORE.remote_status(),
        **snapshot(),
    }


@router.patch("/phase4/admin/config")
def phase4_admin_config(body: ConfigPatchIn, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return {"ok": True, "config": _svc().update_config(body.patch, body.actor)}

@router.get("/phase4/admin/live-events")
def phase4_admin_live_events(x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return {"ok": True, "events": _svc().admin_live_events()}


@router.put("/phase4/admin/live-events")
def phase4_admin_live_event_upsert(body: LiveEventIn, x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return _svc().admin_upsert_live_event(body.model_dump(exclude_none=True), body.actor)


@router.delete("/phase4/admin/live-events/{event_id}")
def phase4_admin_live_event_delete(event_id: str, actor: str = "admin", x_admin_key: str | None = Header(None)):
    _admin(x_admin_key)
    return _svc().admin_delete_live_event(event_id, actor)


# ---------------------------------------------------------------- sistem testi
class StaffSelfTestIn(BaseModel):
    actor_id: str
    games: int = 200
    push: bool = True


_SELFTEST: dict = {'running': False, 'result': None, 'progress': 0, 'total': 0, 'started_at': 0}


def _selftest_worker(actor_id: str, games: int, push: bool) -> None:
    import time as _t
    import random as _r
    from app.services import selftest as st
    checks: list[dict] = []
    started = _t.time()
    try:
        # 1) Botlarla maç simülasyonu (canlı masalara dokunmaz). Her maçtan sonra
        # kısa mola: testi çalıştırmak gerçek oyuncuların hamlelerini bekletmesin.
        base = _r.randrange(1, 9_000_000)
        played = passed = 0
        failures: list[dict] = []
        reasons: dict[str, int] = {}
        for i in range(games):
            cfg = st._CONFIGS[i % len(st._CONFIGS)]
            try:
                res = st.play_one(base + i, cfg)
            except Exception as exc:  # noqa: BLE001
                res = {'ok': False, 'seed': base + i, 'mode': st._label(cfg), 'error': f'{type(exc).__name__}: {str(exc)[:120]}'}
            played += 1
            if res.get('ok'):
                passed += 1
                reasons[str(res.get('reason') or 'bitti')] = reasons.get(str(res.get('reason') or 'bitti'), 0) + 1
            elif len(failures) < 15:
                failures.append(res)
            _SELFTEST['progress'] = played
            _t.sleep(0.02)
        checks.append({'name': f'Botlarla {games} maç', 'ok': played == passed,
                       'detail': f'{passed}/{played} sorunsuz bitti • tohum {base}', 'end_reasons': reasons, 'failures': failures})
        # 2) Depolama
        try:
            status = STORE.remote_status()
            checks.append({'name': 'Veritabanı (Supabase)', 'ok': bool(status.get('loaded')) and not status.get('error'),
                           'detail': f"{'bağlı' if status.get('enabled') else 'yerel dosya'}{(' • hata: ' + str(status.get('error'))) if status.get('error') else ''}"})
        except Exception as exc:  # noqa: BLE001
            checks.append({'name': 'Veritabanı (Supabase)', 'ok': False, 'detail': str(exc)[:120]})
        # 3) Oda kaydı (sunucu yeniden başlayınca masaların geri gelmesi)
        try:
            from app.api import game as _g
            from app.services.runtime_persistence import build_runtime_blob
            blob = build_runtime_blob(_g.ROOMS, _g.ROOM_META)
            checks.append({'name': 'Masa kaydı (yeniden başlatma koruması)', 'ok': len(blob) > 0, 'detail': f'{len(_g.ROOMS)} masa • {len(blob) // 1024} KB'})
        except Exception as exc:  # noqa: BLE001
            checks.append({'name': 'Masa kaydı (yeniden başlatma koruması)', 'ok': False, 'detail': f'{type(exc).__name__}: {str(exc)[:120]}'})
        # 4) Anlık bildirim
        if push:
            try:
                from app.api.ops_extra import fcm, push_to_player
                if not fcm():
                    checks.append({'name': 'Anlık bildirim', 'ok': False, 'detail': 'Firebase anahtarı sunucuda yok'})
                else:
                    acc = STORE.get(actor_id) or {}
                    tokens = len(acc.get('push_tokens') or [])
                    sent = push_to_player(actor_id, 'OKEYX test bildirimi', 'Bu bildirimi görüyorsan anlık bildirim çalışıyor.', {'kind': 'event'})
                    checks.append({'name': 'Anlık bildirim', 'ok': sent > 0,
                                   'detail': f'{sent} cihaza gönderildi' if sent else (f'{tokens} kayıtlı cihaz var ama gönderilemedi' if tokens else 'Bu hesapta kayıtlı cihaz yok (oyunu açıp bildirim izni ver)')})
            except Exception as exc:  # noqa: BLE001
                checks.append({'name': 'Anlık bildirim', 'ok': False, 'detail': f'{type(exc).__name__}: {str(exc)[:120]}'})
    finally:
        _SELFTEST['result'] = {'checks': checks, 'seconds': round(_t.time() - started, 1), 'finished_at': int(_t.time()),
                               'ok': bool(checks) and all(c['ok'] for c in checks)}
        _SELFTEST['running'] = False


@router.post("/phase4/staff/selftest")
def staff_selftest_start(body: StaffSelfTestIn, x_account_token: str | None = Header(None)):
    _require(body.actor_id, x_account_token)
    try:
        _svc().require_staff(body.actor_id, "moderate")
    except PermissionError:
        raise HTTPException(403, "staff_permission_denied")
    if _SELFTEST['running']:
        return {'ok': True, 'running': True, 'progress': _SELFTEST['progress'], 'total': _SELFTEST['total']}
    import threading
    import time as _t
    games = max(10, min(int(body.games), 500))
    _SELFTEST.update({'running': True, 'result': None, 'progress': 0, 'total': games, 'started_at': int(_t.time())})
    threading.Thread(target=_selftest_worker, args=(body.actor_id, games, bool(body.push)), daemon=True).start()
    return {'ok': True, 'running': True, 'progress': 0, 'total': games}


@router.get("/phase4/staff/{player_id}/selftest")
def staff_selftest_status(player_id: str, x_account_token: str | None = Header(None)):
    _require(player_id, x_account_token)
    try:
        _svc().require_staff(player_id, "moderate")
    except PermissionError:
        raise HTTPException(403, "staff_permission_denied")
    return {'ok': True, 'running': _SELFTEST['running'], 'progress': _SELFTEST['progress'], 'total': _SELFTEST['total'], 'result': _SELFTEST['result']}
