from __future__ import annotations
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from app.core.config import settings
from app.services.account_store import STORE
from app.services.phase4_service import Phase4Service
router = APIRouter(tags=['phase4'])

def _svc() -> Phase4Service:
    return Phase4Service(STORE)

def _require(player_id: str, token: str | None) -> None:
    if not STORE.get(player_id):
        raise HTTPException(404, 'account_not_found')
    if not STORE.verify(player_id, token):
        raise HTTPException(401, 'invalid_account_token')

def _admin(key: str | None) -> None:
    expected = settings.admin_key
    if not expected or not key or key != expected:
        raise HTTPException(401, 'admin_key_invalid')

class ItemIn(BaseModel):
    player_id: str
    item_id: str

class PurchaseTestIn(BaseModel):
    player_id: str
    sku: str
    receipt_id: str
    amount_minor: int
    currency: str = 'TRY'

class RefundIn(BaseModel):
    provider: str = 'test'
    receipt_id: str
    reason: str = 'refund'

class PassClaimIn(BaseModel):
    player_id: str
    level: int
    premium: bool = False

class PassTaskIn(BaseModel):
    player_id: str
    task_id: str

class AdStartIn(BaseModel):
    player_id: str
    reward_kind: str = 'coins'

class AdClaimIn(BaseModel):
    player_id: str
    token: str

class SideGameIn(BaseModel):
    player_id: str
    game: str
    choice: int | None = None
    wager: int | None = None
    use_voucher: bool = False
    action: str | None = None
    challenge_id: str | None = None
    active_lines: list[int] | None = None

class VoiceIn(BaseModel):
    player_id: str
    enabled: bool | None = None
    mute_player_id: str | None = None
    muted: bool | None = None

class ModReportIn(BaseModel):
    player_id: str
    target_id: str
    reason: str = 'other'
    room_id: str | None = None
    source: str = 'voice'

class ConfigPatchIn(BaseModel):
    patch: dict
    actor: str = 'admin'

class LiveEventIn(BaseModel):
    id: str | None = None
    title: str
    subtitle: str = ''
    starts_at: int | None = None
    ends_at: int | None = None
    enabled: bool = True
    kind: str = 'seasonal'
    config: dict = {}
    actor: str = 'admin'

class StaffSanctionIn(BaseModel):
    actor_id: str
    player_id: str
    sanction_type: str
    duration_minutes: int = 0
    reason: str = ''

class StaffWalletIn(BaseModel):
    actor_id: str
    player_id: str
    currency: str
    amount: int
    reason: str = ''

class StaffRtpIn(BaseModel):
    actor_id: str
    game: str
    percent: float
    event_title: str = ''

@router.get('/phase4/{player_id}/hub')
def phase4_hub(player_id: str, x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    return _svc().hub(player_id)

@router.post('/phase4/store/buy')
def phase4_buy(body: ItemIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().buy_cosmetic(body.player_id, body.item_id)

@router.post('/phase4/store/equip')
def phase4_equip(body: ItemIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().equip(body.player_id, body.item_id)

@router.post('/phase4/vip/{player_id}/daily')
def phase4_vip_daily(player_id: str, x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    return _svc().claim_vip_daily(player_id)

@router.post('/phase4/event/{player_id}/{event_id}/claim')
def phase4_event_claim(player_id: str, event_id: str, x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    return _svc().claim_live_event(player_id, event_id)

@router.post('/phase4/pass/task')
def phase4_pass_task(body: PassTaskIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().claim_pass_task(body.player_id, body.task_id)

@router.post('/phase4/pass/claim')
def phase4_pass_claim(body: PassClaimIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().claim_pass_level(body.player_id, body.level, body.premium)

@router.get('/phase4/side-games/catalog')
def phase4_side_catalog():
    return _svc().side_game_catalog()

@router.post('/phase4/side-games/play')
def phase4_side_play(body: SideGameIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().play_side_game(body.player_id, body.game, body.choice, body.wager, body.use_voucher, body.action, body.challenge_id, body.active_lines)

@router.post('/phase4/ads/transition/{player_id}')
def phase4_ad_transition(player_id: str, x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    return _svc().match_transition_ad(player_id)

@router.post('/phase4/ads/start')
def phase4_ad_start(body: AdStartIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().start_ad_session(body.player_id, body.reward_kind)

@router.post('/phase4/ads/claim')
def phase4_ad_claim(body: AdClaimIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().claim_ad_reward(body.player_id, body.token)

@router.post('/phase4/voice')
def phase4_voice(body: VoiceIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().set_voice(body.player_id, body.enabled, body.mute_player_id, body.muted)

@router.post('/phase4/moderation/report')
def phase4_mod_report(body: ModReportIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    return _svc().moderate_report(body.player_id, body.target_id, body.reason, body.room_id, body.source)

@router.post('/phase4/dev/verify-purchase')
def phase4_dev_purchase(body: PurchaseTestIn, x_account_token: str | None=Header(None)):
    _require(body.player_id, x_account_token)
    if not settings.allow_test_billing:
        raise HTTPException(403, 'test_billing_disabled')
    return _svc().grant_verified_purchase(body.player_id, body.sku, body.receipt_id, body.amount_minor, body.currency, 'test')

@router.get('/phase4/staff/{player_id}/me')
def staff_me(player_id: str, x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    return _svc().staff_me(player_id)

@router.get('/phase4/staff/{player_id}/snapshot')
def staff_snapshot(player_id: str, x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    svc = _svc()
    try:
        svc.require_staff(player_id, 'moderate')
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')
    return {'ok': True, 'staff': svc.staff_me(player_id), **svc.admin_snapshot()}

@router.get('/phase4/staff/{player_id}/players')
def staff_players(player_id: str, q: str='', x_account_token: str | None=Header(None)):
    _require(player_id, x_account_token)
    try:
        return {'ok': True, 'players': _svc().staff_search_players(player_id, q)}
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')

@router.post('/phase4/staff/sanction')
def staff_sanction(body: StaffSanctionIn, x_account_token: str | None=Header(None)):
    _require(body.actor_id, x_account_token)
    try:
        return _svc().staff_sanction(body.actor_id, body.player_id, body.sanction_type, body.duration_minutes, body.reason)
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')

@router.post('/phase4/staff/wallet')
def staff_wallet(body: StaffWalletIn, x_account_token: str | None=Header(None)):
    _require(body.actor_id, x_account_token)
    try:
        return _svc().staff_adjust_wallet(body.actor_id, body.player_id, body.currency, body.amount, body.reason)
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')

@router.post('/phase4/staff/rtp')
def staff_rtp(body: StaffRtpIn, x_account_token: str | None=Header(None)):
    _require(body.actor_id, x_account_token)
    try:
        return _svc().staff_set_rtp(body.actor_id, body.game, body.percent, body.event_title)
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')

@router.put('/phase4/staff/live-events')
def staff_event(body: LiveEventIn, actor_id: str, x_account_token: str | None=Header(None)):
    _require(actor_id, x_account_token)
    svc = _svc()
    try:
        svc.require_staff(actor_id, 'events')
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')
    return svc.admin_upsert_live_event(body.model_dump(exclude_none=True), actor_id)

@router.delete('/phase4/staff/live-events/{event_id}')
def staff_event_delete(event_id: str, actor_id: str, x_account_token: str | None=Header(None)):
    _require(actor_id, x_account_token)
    svc = _svc()
    try:
        svc.require_staff(actor_id, 'events')
    except PermissionError:
        raise HTTPException(403, 'staff_permission_denied')
    return svc.admin_delete_live_event(event_id, actor_id)

@router.post('/phase4/admin/refund')
def phase4_admin_refund(body: RefundIn, x_admin_key: str | None=Header(None)):
    _admin(x_admin_key)
    return _svc().refund_purchase(body.provider, body.receipt_id, body.reason)

@router.get('/phase4/admin/snapshot')
def phase4_admin_snapshot(x_admin_key: str | None=Header(None)):
    _admin(x_admin_key)
    return _svc().admin_snapshot()

@router.patch('/phase4/admin/config')
def phase4_admin_config(body: ConfigPatchIn, x_admin_key: str | None=Header(None)):
    _admin(x_admin_key)
    return {'ok': True, 'config': _svc().update_config(body.patch, body.actor)}

@router.get('/phase4/admin/live-events')
def phase4_admin_live_events(x_admin_key: str | None=Header(None)):
    _admin(x_admin_key)
    return {'ok': True, 'events': _svc().admin_live_events()}

@router.put('/phase4/admin/live-events')
def phase4_admin_live_event_upsert(body: LiveEventIn, x_admin_key: str | None=Header(None)):
    _admin(x_admin_key)
    return _svc().admin_upsert_live_event(body.model_dump(exclude_none=True), body.actor)

@router.delete('/phase4/admin/live-events/{event_id}')
def phase4_admin_live_event_delete(event_id: str, actor: str='admin', x_admin_key: str | None=Header(None)):
    _admin(x_admin_key)
    return _svc().admin_delete_live_event(event_id, actor)
