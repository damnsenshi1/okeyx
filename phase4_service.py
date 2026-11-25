from __future__ import annotations

from copy import deepcopy
import hashlib
import secrets
import time
import uuid
from typing import Any

from app.services.account_store import AccountStore, _day_key, _now
from app.services.chance_engine import (
    VOUCHERS, slot_catalog, spin_slot, horse_catalog, race, circus_catalog, circus_start, circus_finish,
    drop_catalog, play_drop, tower_catalog, tower_start, tower_choose, tower_cashout,
)


def _tier_curve(max_level: int = 200) -> list[dict[str, int]]:
    """Server-owned VIP curve. VIP 1 is intentionally a low-friction welcome tier."""
    out = [{"level": 0, "spend_minor": 0}]
    if max_level <= 0:
        return out
    out.append({"level": 1, "spend_minor": 499})
    total = 9_900
    if max_level >= 2:
        out.append({"level": 2, "spend_minor": total})
    for level in range(3, max_level + 1):
        step = 2_400 + (level - 2) * 120 + ((level - 1) // 10) * 600
        total += step
        out.append({"level": level, "spend_minor": total})
    return out


DEFAULT_PHASE4_CONFIG: dict[str, Any] = {
    "version": 1,
    "economy_test_mode": True,
    "billing_enabled": True,
    "ads_enabled": True,
    "interstitial_every_matches": 3,
    "interstitial_min_seconds": 240,
    "rewarded_daily_limit": 8,
    "rewarded_cooldown_seconds": 180,
    "rewarded_coin_amount": 3_500,
    "rewarded_ticket_amount": 1,
    "vip": {
        "max_level": 200,
        "thresholds": _tier_curve(200),
        "daily_coin_base": 1_000,
        "daily_coin_per_level": 150,
        "daily_ticket_every_levels": 10,
        "extra_wheel_every_levels": 20,
        "extra_task_every_levels": 25,
        "no_rule_advantage": True,
    },
    "chance_controls": {"enabled": True, "purchasable_tickets": False, "chip_multiplier": True},
    "billing_products": [
        {"sku":"okeyx.gold.50000","kind":"consumable","title":"750.000 Altın","coins":750000,"diamonds":0,"slot_vouchers":{},"price_hint":"₺39,90","value_label":"BAŞLANGIÇ","first_purchase":False},
        {"sku":"okeyx.gold.180000","kind":"consumable","title":"2.000.000 Altın","coins":2000000,"diamonds":0,"slot_vouchers":{},"price_hint":"₺79,90","value_label":"POPÜLER","first_purchase":False},
        {"sku":"okeyx.gold.500000","kind":"consumable","title":"5.000.000 Altın","coins":5000000,"diamonds":0,"slot_vouchers":{},"price_hint":"₺159,90","value_label":"AVANTAJLI","first_purchase":False},
        {"sku":"okeyx.gold.1200000","kind":"consumable","title":"15.000.000 Altın","coins":15000000,"diamonds":0,"slot_vouchers":{},"price_hint":"₺349,90","value_label":"SÜPER DEĞER","first_purchase":False},
        {"sku":"okeyx.gold.3000000","kind":"consumable","title":"40.000.000 Altın","coins":40000000,"diamonds":0,"slot_vouchers":{},"price_hint":"₺699,90","value_label":"EN İYİ DEĞER","first_purchase":False},
        {"sku":"okeyx.diamond.80","kind":"consumable","title":"80 Elmas","coins":0,"diamonds":80,"slot_vouchers":{},"price_hint":"₺49,90","first_purchase":False},
        {"sku":"okeyx.diamond.250","kind":"consumable","title":"250 Elmas","coins":0,"diamonds":250,"slot_vouchers":{},"price_hint":"₺119,90","value_label":"DAHA AVANTAJLI","first_purchase":False},
        {"sku":"okeyx.starter.1","kind":"consumable","title":"Hoş Geldin VIP Paketi","coins":300000,"diamonds":10,"slot_vouchers":{},"inventory":["frame_founder"],"price_hint":"₺4,99","first_purchase":True},
        {"sku":"okeyx.daily.300k","kind":"consumable","title":"Günlük Mini • 300K","coins":300000,"diamonds":0,"slot_vouchers":{},"price_hint":"₺9,99","first_purchase":False,"daily_offer":True},
        {"sku":"okeyx.daily.400k","kind":"consumable","title":"Günlük Plus • 400K","coins":400000,"diamonds":10,"slot_vouchers":{},"price_hint":"₺19,99","first_purchase":False,"daily_offer":True},
        {"sku":"okeyx.daily.1m","kind":"consumable","title":"Günlük Mega • 1M","coins":1000000,"diamonds":20,"slot_vouchers":{},"price_hint":"₺39,99","first_purchase":False,"daily_offer":True},
        {"sku":"okeyx.pass.s1","kind":"non_consumable","title":"Okey Pass Premium","coins":0,"diamonds":0,"slot_vouchers":{},"premium_pass":True,"price_hint":"₺149,90","first_purchase":False},
    ],
    "offers": [
        {"id":"welcome_72h","sku":"okeyx.starter.1","title":"VIP'E HOŞ GELDİN","badge":"VIP 1 • TEK SEFER","duration_seconds":72*3600,"normal_price_hint":"₺29,99","enabled":True},
        {"id":"daily_mini","sku":"okeyx.daily.300k","title":"GÜNLÜK MİNİ","badge":"BUGÜNE ÖZEL","daily":True,"normal_price_hint":"₺19,99","enabled":True},
        {"id":"daily_plus","sku":"okeyx.daily.400k","title":"GÜNLÜK PLUS","badge":"EN ÇOK TERCİH","daily":True,"normal_price_hint":"₺34,99","enabled":True},
        {"id":"daily_mega","sku":"okeyx.daily.1m","title":"GÜNLÜK MEGA","badge":"EN İYİ DEĞER","daily":True,"normal_price_hint":"₺79,99","enabled":True},
    ],
    "cosmetics": [
        {"id": "rack_classic", "category": "rack", "name": "Klasik Ceviz", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "rack_walnut", "category": "rack", "name": "Anadolu Cevizi", "currency": "coins", "price": 32000, "rarity": "common"},
        {"id": "rack_sakura", "category": "rack", "name": "Sakura Istaka", "currency": "coins", "price": 42000, "rarity": "rare"},
        {"id": "rack_bosphorus", "category": "rack", "name": "Boğaz Turkuazı", "currency": "coins", "price": 58000, "rarity": "rare"},
        {"id": "rack_obsidian", "category": "rack", "name": "Obsidyen Istaka", "currency": "diamonds", "price": 45, "rarity": "epic"},
        {"id": "rack_neon", "category": "rack", "name": "Neon İstanbul", "currency": "diamonds", "price": 65, "rarity": "legendary"},
        {"id": "rack_royal", "category": "rack", "name": "Kraliyet Altını", "currency": "diamonds", "price": 80, "rarity": "legendary"},
        {"id": "rack_ice", "category": "rack", "name": "Buz Kristali", "currency": "coins", "price": 72000, "rarity": "epic"},
        {"id": "rack_ember", "category": "rack", "name": "Kor Ateşi", "currency": "coins", "price": 88000, "rarity": "epic"},
        {"id": "rack_marble", "category": "rack", "name": "Mermer Salon", "currency": "diamonds", "price": 55, "rarity": "epic"},
        {"id": "tiles_classic", "category": "tiles", "name": "Klasik Fildişi", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "tiles_marble", "category": "tiles", "name": "Mermer Taşlar", "currency": "coins", "price": 36000, "rarity": "common"},
        {"id": "tiles_neon", "category": "tiles", "name": "Neon Taşlar", "currency": "coins", "price": 52000, "rarity": "rare"},
        {"id": "tiles_royal", "category": "tiles", "name": "Kraliyet Taşları", "currency": "diamonds", "price": 95, "rarity": "legendary"},
        {"id": "tiles_midnight", "category": "tiles", "name": "Gece Taşları", "currency": "diamonds", "price": 55, "rarity": "epic"},
        {"id": "tiles_sakura", "category": "tiles", "name": "Sakura Taşları", "currency": "coins", "price": 61000, "rarity": "rare"},
        {"id": "tiles_ice", "category": "tiles", "name": "Buz Taşları", "currency": "coins", "price": 75000, "rarity": "epic"},
        {"id": "tiles_ember", "category": "tiles", "name": "Kor Taşları", "currency": "diamonds", "price": 70, "rarity": "epic"},
        {"id": "tiles_bosphorus", "category": "tiles", "name": "Boğaz Taşları", "currency": "coins", "price": 68000, "rarity": "epic"},
        {"id": "tiles_carbon", "category": "tiles", "name": "Karbon Taşlar", "currency": "diamonds", "price": 85, "rarity": "legendary"},
        {"id": "cloth_green", "category": "cloth", "name": "Turnuva Yeşili", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "cloth_bosphorus", "category": "cloth", "name": "Boğaz Gecesi", "currency": "coins", "price": 45000, "rarity": "rare"},
        {"id": "cloth_midnight", "category": "cloth", "name": "Gece Mavisi", "currency": "coins", "price": 52000, "rarity": "rare"},
        {"id": "cloth_royal", "category": "cloth", "name": "Kraliyet Lacivert", "currency": "diamonds", "price": 70, "rarity": "legendary"},
        {"id": "cloth_sunset", "category": "cloth", "name": "Ege Gün Batımı", "currency": "coins", "price": 60000, "rarity": "rare"},
        {"id": "cloth_sakura", "category": "cloth", "name": "Sakura Bahçesi", "currency": "coins", "price": 68000, "rarity": "epic"},
        {"id": "cloth_obsidian", "category": "cloth", "name": "Obsidyen Salon", "currency": "diamonds", "price": 50, "rarity": "epic"},
        {"id": "cloth_ice", "category": "cloth", "name": "Kutup Işığı", "currency": "coins", "price": 76000, "rarity": "epic"},
        {"id": "cloth_ember", "category": "cloth", "name": "Kor Kırmızısı", "currency": "diamonds", "price": 65, "rarity": "epic"},
        {"id": "cloth_neon", "category": "cloth", "name": "Neon Gece", "currency": "diamonds", "price": 90, "rarity": "legendary"},
        {"id": "frame_none", "category": "frame", "name": "Çerçevesiz", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "frame_mint", "category": "frame", "name": "Mint Halka", "currency": "coins", "price": 18000, "rarity": "common"},
        {"id": "frame_gold", "category": "frame", "name": "Altın Çerçeve", "currency": "coins", "price": 35000, "rarity": "rare"},
        {"id": "frame_bosphorus", "category": "frame", "name": "Boğaz Işığı", "currency": "coins", "price": 42000, "rarity": "rare"},
        {"id": "frame_sakura", "category": "frame", "name": "Sakura Çiçeği", "currency": "coins", "price": 52000, "rarity": "epic"},
        {"id": "frame_neon", "category": "frame", "name": "Neon Halo", "currency": "diamonds", "price": 40, "rarity": "epic"},
        {"id": "frame_royal", "category": "frame", "name": "Kraliyet Tacı", "currency": "diamonds", "price": 65, "rarity": "legendary"},
        {"id": "frame_ice", "category": "frame", "name": "Buz Çemberi", "currency": "coins", "price": 58000, "rarity": "epic"},
        {"id": "frame_ember", "category": "frame", "name": "Kor Çemberi", "currency": "diamonds", "price": 50, "rarity": "epic"},
        {"id": "frame_dragon", "category": "frame", "name": "Ejderha Halkası", "currency": "diamonds", "price": 85, "rarity": "legendary"},
        {"id": "frame_veteran", "category": "frame", "name": "101 Veteranı", "currency": "coins", "price": 101000, "rarity": "legendary"},
        {"id": "frame_founder", "category": "frame", "name": "Kurucu Çerçevesi", "currency": "diamonds", "price": 9999, "rarity": "legendary", "store_hidden": True},
        {"id": "avatar_fox", "category": "avatar", "name": "Tilki", "currency": "coins", "price": 35000, "rarity": "common"},
        {"id": "avatar_samurai", "category": "avatar", "name": "Samuray", "currency": "diamonds", "price": 40, "rarity": "epic"},
        {"id": "avatar_cat", "category": "avatar", "name": "Masa Kedisi", "currency": "coins", "price": 42000, "rarity": "rare"},
        {"id": "avatar_phoenix", "category": "avatar", "name": "Anka", "currency": "diamonds", "price": 55, "rarity": "epic"},
        # Emoji packs are a standard entitlement, not store products. Every player
        # owns all four and can choose the active set from inventory.
        {"id": "emoji_cafe", "category": "emoji_pack", "name": "Kahvehane Klasikleri", "currency": "coins", "price": 0, "rarity": "common", "default": True, "standard_entitlement": True, "store_hidden": True},
        {"id": "emoji_party", "category": "emoji_pack", "name": "Kutlama Paketi", "currency": "coins", "price": 0, "rarity": "common", "standard_entitlement": True, "store_hidden": True},
        {"id": "emoji_troll", "category": "emoji_pack", "name": "Tatlı Troll Paketi", "currency": "coins", "price": 0, "rarity": "common", "standard_entitlement": True, "store_hidden": True},
        {"id": "emoji_neon", "category": "emoji_pack", "name": "Neon Reaksiyonlar", "currency": "coins", "price": 0, "rarity": "common", "standard_entitlement": True, "store_hidden": True},

        {"id": "sound_classic", "category": "sound_pack", "name": "Klasik Masa Sesleri", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "sound_retro", "category": "sound_pack", "name": "Retro Masa Sesleri", "currency": "diamonds", "price": 35, "rarity": "rare"},
        {"id": "sound_wood", "category": "sound_pack", "name": "Ahşap Taş Sesleri", "currency": "coins", "price": 48000, "rarity": "rare"},
        {"id": "sound_soft", "category": "sound_pack", "name": "Soft Studio Sesleri", "currency": "coins", "price": 52000, "rarity": "epic"},
        {"id": "music_kit_classic", "category": "music_kit", "name": "OkeyX Klasik", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "music_kit_istanbul", "category": "music_kit", "name": "Gece İstanbul", "currency": "diamonds", "price": 95, "rarity": "epic"},
        {"id": "music_kit_anadolu", "category": "music_kit", "name": "Anadolu Synth", "currency": "coins", "price": 88000, "rarity": "epic"},
        {"id": "music_kit_retro", "category": "music_kit", "name": "Retro Okey", "currency": "coins", "price": 62000, "rarity": "rare"},
        {"id": "music_kit_tokyo", "category": "music_kit", "name": "Tokyo Night", "currency": "diamonds", "price": 120, "rarity": "legendary"},
        {"id": "music_kit_ege", "category": "music_kit", "name": "Ege Akşamı", "currency": "coins", "price": 72000, "rarity": "rare"},
        {"id": "music_kit_bosphorus", "category": "music_kit", "name": "Boğaz Neon", "currency": "diamonds", "price": 75, "rarity": "epic"},
        {"id": "music_kit_arcade", "category": "music_kit", "name": "Arcade 101", "currency": "coins", "price": 68000, "rarity": "rare"},
        {"id": "music_kit_sakura", "category": "music_kit", "name": "Sakura Beat", "currency": "diamonds", "price": 90, "rarity": "epic"},
        {"id": "music_kit_finalboss", "category": "music_kit", "name": "Final Boss", "currency": "diamonds", "price": 140, "rarity": "legendary"},
        {"id": "victory_fx_classic", "category": "victory_fx", "name": "Klasik Parıltı", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "victory_fx_gold", "category": "victory_fx", "name": "Altın Yağmuru", "currency": "diamonds", "price": 70, "rarity": "epic"},
        {"id": "victory_fx_mint", "category": "victory_fx", "name": "Mint Patlama", "currency": "coins", "price": 42000, "rarity": "rare"},
        {"id": "victory_fx_neon", "category": "victory_fx", "name": "Neon Dalga", "currency": "diamonds", "price": 55, "rarity": "epic"},
        {"id": "victory_fx_rose", "category": "victory_fx", "name": "Gül Yaprakları", "currency": "coins", "price": 65000, "rarity": "epic"},
        {"id": "victory_fx_ice", "category": "victory_fx", "name": "Buz Kırılması", "currency": "coins", "price": 72000, "rarity": "epic"},
        {"id": "victory_fx_ember", "category": "victory_fx", "name": "Kor Patlaması", "currency": "diamonds", "price": 80, "rarity": "legendary"},
        {"id": "victory_fx_crown", "category": "victory_fx", "name": "Şampiyon Tacı", "currency": "diamonds", "price": 110, "rarity": "legendary"},
        {"id": "spawn_classic", "category": "spawn_fx", "name": "Klasik Oturuş", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "spawn_lightning", "category": "spawn_fx", "name": "Şimşek Girişi", "currency": "coins", "price": 68000, "rarity": "epic"},
        {"id": "spawn_fire", "category": "spawn_fx", "name": "Alevler İçinde", "currency": "diamonds", "price": 70, "rarity": "legendary"},
        {"id": "spawn_royal", "category": "spawn_fx", "name": "Kraliyet Sahnesi", "currency": "diamonds", "price": 95, "rarity": "legendary"},
        {"id": "title_none", "category": "title", "name": "Unvansız", "currency": "coins", "price": 0, "rarity": "common", "default": True},
        {"id": "title_okey_hunter", "category": "title", "name": "Okey Avcısı", "currency": "coins", "price": 25000, "rarity": "rare"},
        {"id": "title_pair_master", "category": "title", "name": "Çift Ustası", "currency": "coins", "price": 25000, "rarity": "rare"},
        {"id": "title_series_master", "category": "title", "name": "Seri Ustası", "currency": "coins", "price": 32000, "rarity": "rare"},
        {"id": "title_night_owl", "category": "title", "name": "Gece Kuşu", "currency": "coins", "price": 18000, "rarity": "common"},
        {"id": "title_table_legend", "category": "title", "name": "Masa Efsanesi", "currency": "diamonds", "price": 45, "rarity": "epic"},
        {"id": "title_comeback", "category": "title", "name": "Geri Dönüş Ustası", "currency": "coins", "price": 40000, "rarity": "epic"},
        {"id": "title_veteran", "category": "title", "name": "101 Veteranı", "currency": "coins", "price": 101000, "rarity": "legendary"},
        {"id": "title_lucky", "category": "title", "name": "Şanslı Taş", "currency": "coins", "price": 33000, "rarity": "rare"},
        {"id": "title_bosphorus", "category": "title", "name": "Boğazın Kralı", "currency": "diamonds", "price": 60, "rarity": "legendary"},
    ],
    "pass": {
        "season_id": "2026-S1",
        "title": "Okey Pass • Açılış Sezonu",
        "duration_days": 30,
        "level_points": 500,
        "max_level": 30,
        "free_rewards": {
            "1": {"coins": 2_500}, "3": {"tickets": 1}, "5": {"coins": 6_000}, "8": {"coins": 5000},
            "10": {"diamonds": 8}, "15": {"coins": 12_000}, "20": {"tickets": 2}, "25": {"diamonds": 15}, "30": {"item": "tiles_marble"},
        },
        "premium_rewards": {
            "1": {"diamonds": 5}, "2": {"coins": 5_000}, "4": {"item": "avatar_fox"}, "6": {"diamonds": 8},
            "10": {"item": "rack_obsidian"}, "12": {"coins": 15_000}, "18": {"diamonds": 15}, "22": {"item": "cloth_bosphorus"},
            "26": {"tickets": 5}, "30": {"item": "rack_neon", "diamonds": 30},
        },
        "tasks": [
            {"id": "pass_play_3", "title": "3 oyun oyna", "metric": "games", "target": 3, "points": 220},
            {"id": "pass_win_2", "title": "2 oyun kazan", "metric": "wins", "target": 2, "points": 260},
            {"id": "pass_round_10", "title": "10 el tamamla", "metric": "rounds", "target": 10, "points": 180},
        ],
    },
    "side_games": {
        "slot":{"title":"OkeyX Gold Reels","bet_options":[100,500,1000,2500,5000,10000,25000,50000,100000,250000],"rtp_percent":94.0,"volatility":"high","max_multiplier":5000},
        "horse":{"title":"OkeyX Hipodrom","bet_options":[500,1000,2500,5000,10000,25000,50000,100000,250000],"rtp_percent":90.0,"horses":[{"id":1,"name":"Şimşek","probability":38,"base_multiplier":2.4,"tag":"Favori"},{"id":2,"name":"Rüzgâr","probability":29,"base_multiplier":3.15,"tag":"Dengeli"},{"id":3,"name":"Kuzgun","probability":20,"base_multiplier":4.45,"tag":"Riskli"},{"id":4,"name":"Yıldırım","probability":13,"base_multiplier":6.85,"tag":"Sürpriz"}]},
        "circus":{"title":"Sirk Işıkları","bet_options":[500,1000,2500,5000,10000,25000,50000,100000,250000],"rtp_percent":90.0,"lamp_count":12,"speed_ms":185,"exact_multiplier":2.55,"near_multiplier":1.15},
        "drop":{"title":"Okey Drop","bet_options":[500,1000,2500,5000,10000,25000,50000,100000,250000],"rtp_percent":91.0,"max_multiplier":50},
        "tower":{"title":"Kasa Kulesi","bet_options":[1000,2500,5000,10000,25000,50000,100000,250000],"floors":6,"doors_per_floor":3},
    },
}


class Phase4Service:
    def __init__(self, store: AccountStore):
        self.store = store

    def _global(self) -> dict[str, Any]:
        root = self.store._data.setdefault("phase4", {})
        root.setdefault("config", deepcopy(DEFAULT_PHASE4_CONFIG))
        cfg=root["config"]
        if int(cfg.get("chance_schema_version", 0)) < 4:
            cfg["billing_products"] = deepcopy(DEFAULT_PHASE4_CONFIG["billing_products"])
            cfg["offers"] = deepcopy(DEFAULT_PHASE4_CONFIG["offers"])
            cfg["side_games"] = deepcopy(DEFAULT_PHASE4_CONFIG["side_games"])
            cfg["vip"] = deepcopy(DEFAULT_PHASE4_CONFIG["vip"])
            cfg["chance_schema_version"] = 4
            cfg["version"] = max(4, int(cfg.get("version", 1)) + 1)
        if int(cfg.get("pricing_schema_version", 0)) < 2:
            pricing={
                "okeyx.gold.50000":("750.000 Altın",750000,"₺39,90","BAŞLANGIÇ"),
                "okeyx.gold.180000":("2.000.000 Altın",2000000,"₺79,90","POPÜLER"),
                "okeyx.gold.500000":("5.000.000 Altın",5000000,"₺159,90","AVANTAJLI"),
                "okeyx.gold.1200000":("15.000.000 Altın",15000000,"₺349,90","SÜPER DEĞER"),
                "okeyx.gold.3000000":("40.000.000 Altın",40000000,"₺699,90","EN İYİ DEĞER"),
            }
            for product in cfg.get("billing_products",[]):
                if not isinstance(product,dict):continue
                row=pricing.get(str(product.get("sku") or ""))
                if row:
                    product["title"],product["coins"],product["price_hint"],product["value_label"]=row
                elif str(product.get("sku") or "")=="okeyx.diamond.250":
                    product["price_hint"],product["value_label"]="₺119,90","DAHA AVANTAJLI"
            cfg["pricing_schema_version"]=2
            cfg["version"]=max(7,int(cfg.get("version",1))+1)
        if int(cfg.get("living_schema_version", 0)) < 2:
            existing={str(x.get("id")) for x in cfg.get("cosmetics",[]) if isinstance(x,dict)}
            for item in DEFAULT_PHASE4_CONFIG.get("cosmetics",[]):
                if str(item.get("id")) not in existing:cfg.setdefault("cosmetics",[]).append(deepcopy(item))
            cfg.setdefault("chance_controls",deepcopy(DEFAULT_PHASE4_CONFIG.get("chance_controls",{})))
            cfg["living_schema_version"]=2
            cfg["version"]=max(5,int(cfg.get("version",1))+1)
        root.setdefault("receipts", {})
        root.setdefault("refund_events", [])
        root.setdefault("rng_events", [])
        root.setdefault("ad_sessions", {})
        root.setdefault("moderation_events", [])
        root.setdefault("admin_audit", [])
        root.setdefault("live_events", [])
        root.setdefault("circus_challenges", {})
        root.setdefault("tower_challenges", {})
        root.setdefault("staff_roles", {})
        root.setdefault("sanctions", [])
        root.setdefault("wallet_adjustments", [])
        return root

    def config(self) -> dict[str, Any]:
        with self.store._lock:
            return deepcopy(self._global()["config"])

    def update_config(self, patch: dict[str, Any], actor: str = "admin") -> dict[str, Any]:
        allowed = {
            "economy_test_mode", "billing_enabled", "ads_enabled", "interstitial_every_matches",
            "interstitial_min_seconds", "rewarded_daily_limit", "rewarded_cooldown_seconds",
            "rewarded_coin_amount", "rewarded_ticket_amount", "vip", "billing_products", "offers",
            "cosmetics", "pass", "side_games", "voice_chat_enabled", "chance_controls",
        }
        clean = {k: deepcopy(v) for k, v in patch.items() if k in allowed}
        with self.store._lock:
            g = self._global()
            before_version = int(g["config"].get("version", 1))
            g["config"].update(clean)
            g["config"]["version"] = before_version + 1
            g["admin_audit"].append({"id": uuid.uuid4().hex[:12], "actor": actor[:64], "action": "config_update", "keys": sorted(clean), "created_at": _now()})
            g["admin_audit"] = g["admin_audit"][-300:]
            self.store._save()
            return deepcopy(g["config"])

    def _ensure_account(self, player_id: str) -> dict[str, Any]:
        a = self.store._data["accounts"][player_id]
        a.setdefault("diamonds", 0)
        a.setdefault("tickets", 3)
        a.setdefault("slot_vouchers", {str(x):0 for x in VOUCHERS})
        for _v in VOUCHERS:a["slot_vouchers"].setdefault(str(_v),0)
        a.setdefault("economy_debt_coins",0)
        a.setdefault("economy_debt_minor", 0)
        a.setdefault("inventory", [])
        a.setdefault("equipped", {})
        a.setdefault("vip", {"level": 0, "lifetime_spend_minor": 0, "claimed_daily": None, "claimed_levels": []})
        a.setdefault("okey_pass", {
            "season_id": self._global()["config"]["pass"]["season_id"], "points": 0, "premium": False,
            "claimed_free": [], "claimed_premium": [], "task_claims": [], "baseline": {
                "games": 0,
                "wins": 0,
                "rounds": 0,
            }
        })
        a.setdefault("ads", {"day": _day_key(), "rewarded_claims": 0, "last_rewarded_at": 0, "match_transitions": 0, "last_interstitial_at": 0})
        a.setdefault("voice", {"enabled": False, "muted_player_ids": []})
        a.setdefault("live_event_claims", [])
        defaults = [x for x in self._global()["config"].get("cosmetics", []) if x.get("default")]
        for item in defaults:
            if item["id"] not in a["inventory"]:
                a["inventory"].append(item["id"])
            a["equipped"].setdefault(item["category"], item["id"])
        # Standard entitlements are owned by everyone but only one default per
        # category is equipped. This is used for free selectable emoji packs.
        for item in self._global()["config"].get("cosmetics", []):
            if item.get("standard_entitlement") and item["id"] not in a["inventory"]:
                a["inventory"].append(item["id"])
        self._sync_pass(a)
        self._recompute_vip(a)
        return a

    def _recompute_vip(self, a: dict[str, Any]) -> int:
        vip = a.setdefault("vip", {"level": 0, "lifetime_spend_minor": 0, "claimed_daily": None, "claimed_levels": []})
        spend = max(0, int(vip.get("lifetime_spend_minor", 0)))
        thresholds = self._global()["config"].get("vip", {}).get("thresholds", [])
        level = 0
        for row in thresholds:
            if spend >= int(row.get("spend_minor", 0)):
                level = max(level, int(row.get("level", 0)))
        vip["level"] = min(level, int(self._global()["config"].get("vip", {}).get("max_level", 200)))
        return vip["level"]

    def _vip_view(self, a: dict[str, Any]) -> dict[str, Any]:
        vip = a["vip"]
        thresholds = self._global()["config"]["vip"]["thresholds"]
        level = int(vip["level"])
        current_min = next((int(x["spend_minor"]) for x in thresholds if int(x["level"]) == level), 0)
        next_row = next((x for x in thresholds if int(x["level"]) == level + 1), None)
        next_min = int(next_row["spend_minor"]) if next_row else current_min
        span = max(1, next_min - current_min)
        progress = 1.0 if next_row is None else max(0.0, min(1.0, (int(vip["lifetime_spend_minor"]) - current_min) / span))
        color = "mint" if level < 10 else "gold" if level < 50 else "diamond" if level < 100 else "royal"
        return {
            "level": level,
            "lifetime_spend_minor": int(vip["lifetime_spend_minor"]),
            "current_threshold_minor": current_min,
            "next_threshold_minor": next_min,
            "progress": progress,
            "badge": f"VIP {level}",
            "name_color": color,
            "frame_tier": min(5, level // 20),
            "no_rule_advantage": True,
            "daily_claimed": vip.get("claimed_daily") == _day_key(),
            "extra_wheel": level // max(1, int(self._global()["config"]["vip"].get("extra_wheel_every_levels", 20))),
            "extra_tasks": level // max(1, int(self._global()["config"]["vip"].get("extra_task_every_levels", 25))),
        }

    def _sync_pass(self, a: dict[str, Any]) -> None:
        cfg = self._global()["config"]["pass"]
        p = a.setdefault("okey_pass", {})
        if p.get("season_id") != cfg["season_id"]:
            p.clear()
            p.update({"season_id": cfg["season_id"], "points": 0, "premium": False, "claimed_free": [], "claimed_premium": [], "task_claims": [], "baseline": {
                "games": int(a["stats"].get("games", 0)), "wins": int(a["stats"].get("wins", 0)), "rounds": int(a["stats"].get("rounds", 0)),
            }})
        base = p.setdefault("baseline", {"games": 0, "wins": 0, "rounds": 0})
        stats = a.get("stats", {})
        auto_points = max(0, int(stats.get("games", 0)) - int(base.get("games", 0))) * 80
        auto_points += max(0, int(stats.get("wins", 0)) - int(base.get("wins", 0))) * 70
        auto_points += max(0, int(stats.get("rounds", 0)) - int(base.get("rounds", 0))) * 10
        p["points"] = max(int(p.get("points", 0)), auto_points)

    def _pass_view(self, a: dict[str, Any]) -> dict[str, Any]:
        self._sync_pass(a)
        cfg = deepcopy(self._global()["config"]["pass"])
        p = a["okey_pass"]
        lp = max(1, int(cfg["level_points"]))
        level = min(int(cfg["max_level"]), int(p["points"]) // lp + 1)
        tasks = []
        for task in cfg.get("tasks", []):
            metric = task["metric"]
            base = int(p.get("baseline", {}).get(metric, 0))
            progress = max(0, int(a.get("stats", {}).get(metric, 0)) - base)
            tasks.append({**task, "progress": min(progress, int(task["target"])), "complete": progress >= int(task["target"]), "claimed": task["id"] in p.get("task_claims", [])})
        return {"season_id": p["season_id"], "title": cfg["title"], "points": int(p["points"]), "level": level, "max_level": int(cfg["max_level"]), "level_points": lp, "premium": bool(p.get("premium")), "claimed_free": list(p.get("claimed_free", [])), "claimed_premium": list(p.get("claimed_premium", [])), "free_rewards": cfg.get("free_rewards", {}), "premium_rewards": cfg.get("premium_rewards", {}), "tasks": tasks}

    def _active_events(self, now: int | None = None) -> list[dict[str, Any]]:
        stamp = int(now or _now())
        return [
            ev for ev in self._global().get("live_events", [])
            if ev.get("enabled", True)
            and int(ev.get("starts_at", 0) or 0) <= stamp
            and int(ev.get("ends_at", 0) or 0) > stamp
        ]

    def _event_player_view(self, a: dict[str, Any], ev: dict[str, Any]) -> dict[str, Any]:
        row = deepcopy(ev)
        cfg = deepcopy(row.get("config") if isinstance(row.get("config"), dict) else {})
        # A staff member only typing a title/description still publishes a real
        # event: claimable bonus + side-game bonus. Advanced values can be
        # overridden from Operations Center.
        cfg.setdefault("reward_coins", 25_000)
        cfg.setdefault("reward_diamonds", 0)
        cfg.setdefault("side_game_bonus_percent", 10)
        cfg.setdefault("xp_multiplier", 1.25)
        row["config"] = cfg
        claimed = str(row.get("id")) in set(str(x) for x in a.get("live_event_claims", []))
        row["claimed"] = claimed
        row["claimable"] = not claimed and int(row.get("starts_at", 0) or 0) <= _now() < int(row.get("ends_at", 0) or 0)
        return row

    def claim_live_event(self, player_id: str, event_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            ev = next((x for x in self._active_events() if str(x.get("id")) == str(event_id)), None)
            if not ev:
                return {"ok": False, "code": "event_not_active"}
            claims = a.setdefault("live_event_claims", [])
            if str(event_id) in set(str(x) for x in claims):
                return {"ok": False, "code": "event_already_claimed"}
            cfg = ev.get("config") if isinstance(ev.get("config"), dict) else {}
            coins = max(0, min(2_000_000, int(cfg.get("reward_coins", 25_000) or 25_000)))
            diamonds = max(0, min(100, int(cfg.get("reward_diamonds", 0) or 0)))
            a["chips"] = int(a.get("chips", 0)) + coins
            a["diamonds"] = int(a.get("diamonds", 0)) + diamonds
            a.setdefault("stats", {})["chips_won"] = int(a.get("stats", {}).get("chips_won", 0)) + coins
            claims.append(str(event_id)); a["live_event_claims"] = claims[-100:]
            self.store.record_activity("event_reward", player_id, f"{a.get('name','Oyuncu')} etkinlik ödülünü aldı", {"event_id": str(event_id), "coins": coins, "diamonds": diamonds})
            self.store._save()
            return {"ok": True, "reward_coins": coins, "reward_diamonds": diamonds, "wallet": {"coins": a["chips"], "diamonds": a["diamonds"], "tickets": a.get("tickets", 0), "slot_vouchers": deepcopy(a.get("slot_vouchers", {}))}}

    def hub(self, player_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            cfg = self._global()["config"]
            inventory = set(a["inventory"])
            cosmetics = [{**deepcopy(item), "owned": item["id"] in inventory, "equipped": a["equipped"].get(item["category"]) == item["id"]} for item in cfg.get("cosmetics", []) if (not item.get("store_hidden") or item["id"] in inventory)]
            first_purchase_done = any(r.get("player_id") == player_id and r.get("status") == "verified" for r in self._global()["receipts"].values())
            offers = []
            for offer in cfg.get("offers", []):
                if not offer.get("enabled", True):
                    continue
                if offer.get("id") == "welcome_72h":
                    if first_purchase_done:
                        continue
                    ends_at = int(a.get("created_at", _now())) + int(offer.get("duration_seconds", 0))
                    if _now() >= ends_at:
                        continue
                    offers.append({**deepcopy(offer), "ends_at": ends_at})
                elif offer.get("daily"):
                    now = int(_now())
                    ends_at = ((now // 86_400) + 1) * 86_400
                    offers.append({**deepcopy(offer), "ends_at": ends_at})
                else:
                    offers.append(deepcopy(offer))
            return {
                "ok": True,
                "config_version": int(cfg.get("version", 1)),
                "wallet": {"salon_chips": int(self._salon_ensure(a)["salon_chips"]), "coins": int(a["chips"]), "diamonds": int(a["diamonds"]), "tickets": int(a["tickets"]), "slot_vouchers":deepcopy(a.get("slot_vouchers",{})), "debt_minor": int(a.get("economy_debt_minor", 0)), "debt_coins":int(a.get("economy_debt_coins",0))},
                "vip": self._vip_view(a),
                "pass": self._pass_view(a),
                "billing_products": [({**deepcopy(x),"slot_vouchers":{}} if not bool((cfg.get("chance_controls") or {}).get("purchasable_tickets",False)) else deepcopy(x)) for x in cfg.get("billing_products",[])],
                "offers": offers,
                "first_purchase_done": first_purchase_done,
                "cosmetics": cosmetics,
                "equipped": deepcopy(a["equipped"]),
                "ads": self.ad_state(player_id, _locked=True),
                "side_games": self.side_game_catalog(),
                "voice": deepcopy(a["voice"]),
                # Player-facing live events. Staff-created events used to live
                # only inside the operations snapshot, so a published event
                # was impossible to find from the actual game UI. Keep active
                # and upcoming rows in the normal hub; expired/disabled rows
                # remain available only to staff/audit screens.
                "live_events": [
                    self._event_player_view(a, ev)
                    for ev in sorted(
                        (
                            ev for ev in self._global().get("live_events", [])
                            if ev.get("enabled", True)
                            and int(ev.get("ends_at", 0) or 0) > _now()
                        ),
                        key=lambda ev: (0 if int(ev.get("starts_at", 0) or 0) <= _now() else 1, int(ev.get("starts_at", 0) or 0)),
                    )[:12]
                ],
                "staff": self.staff_me(player_id),
                "sanctions": self.active_sanctions(player_id),
            }

    def buy_cosmetic(self, player_id: str, item_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            item = next((x for x in self._global()["config"].get("cosmetics", []) if x["id"] == item_id), None)
            if not item or item.get("store_hidden"):
                return {"ok": False, "code": "item_not_found"}
            if item_id in a["inventory"]:
                return {"ok": True, "already_owned": True, "item": deepcopy(item)}
            price = max(0, int(item.get("price", 0)))
            currency = item.get("currency", "coins")
            key = "chips" if currency == "coins" else "diamonds"
            if int(a.get(key, 0)) < price:
                return {"ok": False, "code": f"insufficient_{currency}"}
            a[key] = int(a.get(key, 0)) - price
            if key == "chips":
                a["stats"]["chips_spent"] = int(a["stats"].get("chips_spent", 0)) + price
            a["inventory"].append(item_id)
            self.store._save()
            return {"ok": True, "item": deepcopy(item), "wallet": {"coins": a["chips"], "diamonds": a["diamonds"], "tickets": a["tickets"]}}

    def equip(self, player_id: str, item_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            item = next((x for x in self._global()["config"].get("cosmetics", []) if x["id"] == item_id), None)
            if not item:
                return {"ok": False, "code": "item_not_found"}
            if item_id not in a["inventory"]:
                return {"ok": False, "code": "item_not_owned"}
            a["equipped"][item["category"]] = item_id
            self.store._save()
            return {"ok": True, "equipped": deepcopy(a["equipped"])}

    def grant_verified_purchase(self, player_id: str, sku: str, receipt_id: str, amount_minor: int, currency: str = "TRY", provider: str = "test") -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            cfg = self._global()["config"]
            product = next((x for x in cfg.get("billing_products", []) if x["sku"] == sku), None)
            if not product:
                return {"ok": False, "code": "sku_not_found"}
            key = f"{provider}:{receipt_id}"
            receipts = self._global()["receipts"]
            if key in receipts:
                prior = receipts[key]
                return {"ok": prior.get("status") == "verified", "code": "already_processed", "receipt": deepcopy(prior), "hub": self.hub(player_id)}
            if product.get("first_purchase") and any(r.get("player_id") == player_id and r.get("status") == "verified" for r in receipts.values()):
                return {"ok": False, "code": "first_purchase_only"}
            grant = {"coins": int(product.get("coins", 0)), "diamonds": int(product.get("diamonds", 0)), "tickets": int(product.get("tickets", 0)), "slot_vouchers":{str(k):int(v) for k,v in (product.get("slot_vouchers") or {}).items()}, "inventory": list(product.get("inventory", [])), "premium_pass": bool(product.get("premium_pass"))}
            a["chips"] += grant["coins"]
            a["diamonds"] += grant["diamonds"]
            a["tickets"] += grant["tickets"]
            for _d,_n in grant["slot_vouchers"].items():a["slot_vouchers"][_d]=int(a["slot_vouchers"].get(_d,0))+_n
            a["stats"]["chips_won"] += grant["coins"]
            for item in grant["inventory"]:
                if item not in a["inventory"]:
                    a["inventory"].append(item)
            if grant["premium_pass"]:
                a["okey_pass"]["premium"] = True
            vip = a["vip"]
            vip["lifetime_spend_minor"] = int(vip.get("lifetime_spend_minor", 0)) + max(0, int(amount_minor))
            old_level = int(vip.get("level", 0))
            new_level = self._recompute_vip(a)
            receipt = {"player_id": player_id, "sku": sku, "provider": provider, "receipt_id": receipt_id, "amount_minor": max(0, int(amount_minor)), "currency": currency[:3].upper(), "status": "verified", "grant": grant, "created_at": _now()}
            receipts[key] = receipt
            product_title=str(product.get('title') or 'paket')
            self.store.record_activity('purchase',player_id,f'{a["name"]} {product_title} aldı',{'sku':sku,'coins':grant['coins'],'diamonds':grant['diamonds']})
            if new_level > old_level:
                self.store.add_notification(player_id, "VIP yükseldi!", f"VIP {new_level} seviyesine ulaştın.", "vip")
            self.store._save()
            return {"ok": True, "receipt": deepcopy(receipt), "vip_level_up": new_level > old_level, "hub": self.hub(player_id)}

    def refund_purchase(self, provider: str, receipt_id: str, reason: str = "refund") -> dict[str, Any]:
        with self.store._lock:
            key = f"{provider}:{receipt_id}"
            r = self._global()["receipts"].get(key)
            if not r:
                return {"ok": False, "code": "receipt_not_found"}
            if r.get("status") in {"refunded", "chargeback"}:
                return {"ok": True, "already_reversed": True}
            a = self._ensure_account(r["player_id"])
            grant = r.get("grant", {})
            a["chips"] = max(0, int(a["chips"]) - int(grant.get("coins", 0)))
            a["diamonds"] = max(0, int(a["diamonds"]) - int(grant.get("diamonds", 0)))
            a["tickets"] = max(0, int(a["tickets"]) - int(grant.get("tickets", 0)))
            _claw=0
            for _d,_n in (grant.get("slot_vouchers") or {}).items():
                _cur=int(a["slot_vouchers"].get(str(_d),0));_take=min(_cur,int(_n));a["slot_vouchers"][str(_d)]=_cur-_take;_claw+=(int(_n)-_take)*int(_d)
            if _claw>0:
                _take=min(int(a["chips"]),_claw);a["chips"]-= _take;a["economy_debt_coins"]=int(a.get("economy_debt_coins",0))+(_claw-_take)
            if grant.get("premium_pass"):
                other_active = any(x is not r and x.get("player_id") == r["player_id"] and x.get("sku") == r["sku"] and x.get("status") == "verified" for x in self._global()["receipts"].values())
                if not other_active:
                    a["okey_pass"]["premium"] = False
            vip = a["vip"]
            vip["lifetime_spend_minor"] = max(0, int(vip.get("lifetime_spend_minor", 0)) - int(r.get("amount_minor", 0)))
            self._recompute_vip(a)
            r["status"] = "chargeback" if reason == "chargeback" else "refunded"
            r["reversed_at"] = _now()
            r["reverse_reason"] = reason[:64]
            if reason == "chargeback":
                flags = a.setdefault("security", {}).setdefault("risk_flags", [])
                if "chargeback" not in flags:
                    flags.append("chargeback")
            self._global()["refund_events"].append({"receipt_id": receipt_id, "provider": provider, "reason": reason, "player_id": r["player_id"], "created_at": _now()})
            self._global()["refund_events"] = self._global()["refund_events"][-500:]
            self.store._save()
            return {"ok": True, "status": r["status"], "vip": self._vip_view(a)}

    def claim_vip_daily(self, player_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            vip = a["vip"]
            if vip.get("claimed_daily") == _day_key():
                return {"ok": False, "code": "already_claimed"}
            level = int(vip["level"])
            cfg = self._global()["config"]["vip"]
            coins = int(cfg.get("daily_coin_base", 1000)) + level * int(cfg.get("daily_coin_per_level", 150))
            ticket_every = max(1, int(cfg.get("daily_ticket_every_levels", 10)))
            tickets = level // ticket_every
            a["chips"] += coins
            a["tickets"] += tickets
            a["stats"]["chips_won"] += coins
            vip["claimed_daily"] = _day_key()
            self.store._save()
            return {"ok": True, "coins": coins, "tickets": tickets, "vip": self._vip_view(a)}

    def claim_pass_task(self, player_id: str, task_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            view = self._pass_view(a)
            task = next((x for x in view["tasks"] if x["id"] == task_id), None)
            if not task:
                return {"ok": False, "code": "task_not_found"}
            if task["claimed"]:
                return {"ok": False, "code": "already_claimed"}
            if not task["complete"]:
                return {"ok": False, "code": "not_complete"}
            a["okey_pass"].setdefault("task_claims", []).append(task_id)
            a["okey_pass"]["points"] = int(a["okey_pass"].get("points", 0)) + int(task.get("points", 0))
            self.store._save()
            return {"ok": True, "points": int(task["points"]), "pass": self._pass_view(a)}

    def _grant_reward(self, a: dict[str, Any], reward: dict[str, Any]) -> None:
        coins = int(reward.get("coins", 0)); diamonds = int(reward.get("diamonds", 0)); tickets = int(reward.get("tickets", 0))
        a["chips"] += coins; a["diamonds"] += diamonds; a["tickets"] += tickets
        a["stats"]["chips_won"] += coins
        item = reward.get("item")
        if item and item not in a["inventory"]:
            a["inventory"].append(item)

    def claim_pass_level(self, player_id: str, level: int, premium: bool = False) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            view = self._pass_view(a)
            if level < 1 or level > int(view["max_level"]):
                return {"ok": False, "code": "level_invalid"}
            if level > int(view["level"]):
                return {"ok": False, "code": "level_locked"}
            bucket = "claimed_premium" if premium else "claimed_free"
            if premium and not a["okey_pass"].get("premium"):
                return {"ok": False, "code": "premium_required"}
            if level in a["okey_pass"].get(bucket, []):
                return {"ok": False, "code": "already_claimed"}
            rewards_key = "premium_rewards" if premium else "free_rewards"
            reward = self._global()["config"]["pass"].get(rewards_key, {}).get(str(level))
            if not reward:
                return {"ok": False, "code": "no_reward_at_level"}
            self._grant_reward(a, reward)
            a["okey_pass"].setdefault(bucket, []).append(level)
            self.store._save()
            return {"ok": True, "reward": deepcopy(reward), "pass": self._pass_view(a)}

    def ad_state(self, player_id: str, _locked: bool = False) -> dict[str, Any]:
        def body() -> dict[str, Any]:
            a = self._ensure_account(player_id)
            ads = a["ads"]
            if ads.get("day") != _day_key():
                ads.update({"day": _day_key(), "rewarded_claims": 0, "last_rewarded_at": 0})
            cfg = self._global()["config"]
            cooldown = max(0, int(cfg.get("rewarded_cooldown_seconds", 180)))
            next_at = int(ads.get("last_rewarded_at", 0)) + cooldown
            return {"enabled": bool(cfg.get("ads_enabled", True)), "rewarded_claims": int(ads.get("rewarded_claims", 0)), "rewarded_daily_limit": int(cfg.get("rewarded_daily_limit", 8)), "next_rewarded_at": next_at, "can_rewarded": int(ads.get("rewarded_claims", 0)) < int(cfg.get("rewarded_daily_limit", 8)) and _now() >= next_at, "coin_amount": int(cfg.get("rewarded_coin_amount", 3500)), "ticket_amount": int(cfg.get("rewarded_ticket_amount", 1)), "interstitial_every_matches": int(cfg.get("interstitial_every_matches", 3)), "interstitial_min_seconds": int(cfg.get("interstitial_min_seconds", 240))}
        if _locked:
            return body()
        with self.store._lock:
            out = body(); self.store._save(); return out

    def match_transition_ad(self, player_id: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            cfg = self._global()["config"]
            ads = a["ads"]
            ads["match_transitions"] = int(ads.get("match_transitions", 0)) + 1
            vip_level = int(a.get("vip", {}).get("level", 0))
            if not bool(cfg.get("ads_enabled", True)):
                self.store._save(); return {"ok": True, "show_interstitial": False, "reason": "ads_disabled"}
            if vip_level > 0:
                self.store._save(); return {"ok": True, "show_interstitial": False, "reason": "vip_ad_free"}
            every = max(1, int(cfg.get("interstitial_every_matches", 3)))
            min_seconds = max(0, int(cfg.get("interstitial_min_seconds", 240)))
            due_by_count = int(ads["match_transitions"]) % every == 0
            due_by_time = _now() - int(ads.get("last_interstitial_at", 0)) >= min_seconds
            show = due_by_count and due_by_time
            if show:
                ads["last_interstitial_at"] = _now()
            self.store._save()
            return {"ok": True, "show_interstitial": show, "reason": "due" if show else "rate_limited", "transitions": int(ads["match_transitions"]), "every": every, "min_seconds": min_seconds}

    def start_ad_session(self, player_id: str, reward_kind: str) -> dict[str, Any]:
        if reward_kind not in {"coins", "ticket"}:
            return {"ok": False, "code": "reward_kind_invalid"}
        with self.store._lock:
            a = self._ensure_account(player_id)
            state = self.ad_state(player_id, _locked=True)
            if not state["can_rewarded"]:
                return {"ok": False, "code": "ad_rate_limited", "ads": state}
            token = secrets.token_urlsafe(24)
            self._global()["ad_sessions"][token] = {"player_id": player_id, "reward_kind": reward_kind, "created_at": _now(), "used": False}
            self.store._save()
            return {"ok": True, "token": token, "expires_at": _now() + 15 * 60}

    def claim_ad_reward(self, player_id: str, token: str) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            s = self._global()["ad_sessions"].get(token)
            if not s or s.get("player_id") != player_id:
                return {"ok": False, "code": "ad_session_invalid"}
            if s.get("used"):
                return {"ok": False, "code": "ad_session_used"}
            if _now() - int(s.get("created_at", 0)) > 15 * 60:
                return {"ok": False, "code": "ad_session_expired"}
            state = self.ad_state(player_id, _locked=True)
            if not state["can_rewarded"]:
                return {"ok": False, "code": "ad_rate_limited", "ads": state}
            s["used"] = True; s["used_at"] = _now()
            kind = s["reward_kind"]
            reward = int(self._global()["config"].get("rewarded_coin_amount", 3500)) if kind == "coins" else int(self._global()["config"].get("rewarded_ticket_amount", 1))
            if kind == "coins":
                a["chips"] += reward; a["stats"]["chips_won"] += reward
            else:
                a["tickets"] += reward
            a["ads"]["rewarded_claims"] = int(a["ads"].get("rewarded_claims", 0)) + 1
            a["ads"]["last_rewarded_at"] = _now()
            self.store._save()
            return {"ok": True, "kind": kind, "reward": reward, "wallet": {"coins": a["chips"], "diamonds": a["diamonds"], "tickets": a["tickets"]}, "ads": self.ad_state(player_id, _locked=True)}

    SALON_START=20_000
    SALON_DAILY=15_000

    def _salon_ensure(self,a):
        if "salon_chips" not in a:a["salon_chips"]=self.SALON_START
        return a

    def salon_claim(self,player_id:str)->dict[str,Any]:
        """Günlük Salon hakkı: satın alınmaz, yalnız oynayarak/giriş yaparak kazanılır."""
        with self.store._lock:
            a=self._salon_ensure(self._ensure_account(player_id));today=_day_key()
            if a.get("salon_daily_day")==today:return {"ok":False,"code":"already_claimed","salon_chips":int(a["salon_chips"])}
            a["salon_daily_day"]=today;a["salon_chips"]=int(a["salon_chips"])+self.SALON_DAILY
            self.store._save();return {"ok":True,"granted":self.SALON_DAILY,"salon_chips":int(a["salon_chips"])}

    def side_game_catalog(self) -> dict[str, Any]:
        root=self._global()["config"];controls=root.get("chance_controls") or {}
        if not bool(controls.get("enabled",True)):return {"disabled":True,"cash_or_withdrawal":False,"real_money_prizes":False}
        cfg=deepcopy(root.get("side_games",{}))
        return {"slot":slot_catalog(cfg.get("slot",{})),"horse":horse_catalog(cfg.get("horse",{})),"circus":circus_catalog(cfg.get("circus",{})),"drop":drop_catalog(cfg.get("drop",{})),"tower":tower_catalog(cfg.get("tower",{})),"cash_or_withdrawal":False,"real_money_prizes":False,"currency":"salon_chips","purchasable_tickets":False,"earned_only":True}

    def play_side_game(self,player_id:str,game:str,choice:int|None=None,wager:int|None=None,use_voucher:bool=False,action:str|None=None,challenge_id:str|None=None,active_lines:list[int]|None=None)->dict[str,Any]:
        with self.store._lock:
            a=self._ensure_account(player_id);cfg=self._global()["config"].get("side_games",{}).get(game)
            if not cfg:return {"ok":False,"code":"game_not_found"}
            if use_voucher:return {"ok":False,"code":"vouchers_disabled"}
            # Salon yalnız kazanılmış bakiye ile oynanır: gerçek altın havuzu ayrılır,
            # motor salon bakiyesi üzerinde çalışır, bitince gerçek altın geri konur.
            self._salon_ensure(a);_real_chips=int(a.get("chips",0));a["chips"]=int(a["salon_chips"])
            # Geçici takas sırasında diske/Supabase'e yazılmasın: _save sonda tek sefer çağrılır.
            _orig_save=self.store._save;self.store._save=lambda:None
            try:
                out=self._play_side_game_inner(a,player_id,game,cfg,choice,wager,use_voucher,action,challenge_id,active_lines)
            finally:
                self.store._save=_orig_save
                a["salon_chips"]=max(0,int(a.get("chips",0)));a["chips"]=_real_chips
            if isinstance(out,dict) and isinstance(out.get("wallet"),dict):
                out["wallet"]["coins"]=_real_chips;out["wallet"]["salon_chips"]=int(a["salon_chips"])
            elif isinstance(out,dict):out["salon_chips"]=int(a["salon_chips"])
            self.store._save();return out

    def _play_side_game_inner(self,a,player_id,game,cfg,choice,wager,use_voucher,action,challenge_id,active_lines):
        if True:
            try:
                if game=="slot":out=spin_slot(a,cfg,int(wager or 100),use_voucher,active_lines)
                elif game=="horse":out=race(a,cfg,int(wager or 500),int(choice or 1))
                elif game=="circus":
                    ch=self._global().setdefault("circus_challenges",{})
                    if action=="finish":out=circus_finish(a,cfg,str(challenge_id or ""),ch)
                    else:
                        out=circus_start(a,cfg,int(wager or 500),ch);self.store._save();out["wallet"]={"coins":a["chips"],"diamonds":a["diamonds"],"slot_vouchers":deepcopy(a["slot_vouchers"])};return out
                elif game=="drop":out=play_drop(a,cfg,int(wager or 500))
                elif game=="tower":
                    ch=self._global().setdefault("tower_challenges",{})
                    if action=="choose":out=tower_choose(a,cfg,str(challenge_id or ""),int(choice if choice is not None else -1),ch)
                    elif action=="cashout":out=tower_cashout(a,cfg,str(challenge_id or ""),ch)
                    else:
                        out=tower_start(a,cfg,int(wager or 1000),ch);self.store._save();out["wallet"]={"coins":a["chips"],"diamonds":a["diamonds"],"slot_vouchers":deepcopy(a["slot_vouchers"])};return out
                else:return {"ok":False,"code":"game_not_supported"}
            except ValueError as e:return {"ok":False,"code":str(e)}
            payout=int(out.get("payout_coins",0))
            event_bonus=0
            active_events=self._active_events()
            if payout>0 and active_events:
                bonus_percent=max(
                    0,
                    min(100, max(int((ev.get("config") or {}).get("side_game_bonus_percent",10) or 0) for ev in active_events)),
                )
                if bonus_percent>0:
                    event_bonus=int(round(payout*bonus_percent/100.0))
                    a["chips"]=int(a.get("chips",0))+event_bonus
                    a.setdefault("stats",{})["chips_won"]=int(a.get("stats",{}).get("chips_won",0))+event_bonus
                    out["event_bonus_coins"]=event_bonus
                    out["event_bonus_percent"]=bonus_percent
                    out["event_title"]=str(active_events[0].get("title") or "Canlı Etkinlik")
            ev={"id":uuid.uuid4().hex[:14],"player_id":player_id,"game":game,"wager_coins":int(out.get("wager",0)),"payout_coins":payout,"event_bonus_coins":event_bonus,"outcome":deepcopy(out),"created_at":_now()};self._global()["rng_events"].append(ev);self._global()["rng_events"]=self._global()["rng_events"][-2000:]
            if payout+event_bonus>=100000:self.store.record_activity('big_win',player_id,f'{a["name"]} Şans Salonu’nda {payout+event_bonus:,} altın kazandı'.replace(',', '.'),{'game':game,'coins':payout+event_bonus})
            self.store._save();out.update({"ok":True,"wallet":{"coins":a["chips"],"diamonds":a["diamonds"],"tickets":a["tickets"],"slot_vouchers":deepcopy(a["slot_vouchers"] )}});return out

    def set_voice(self, player_id: str, enabled: bool | None = None, mute_player_id: str | None = None, muted: bool | None = None) -> dict[str, Any]:
        with self.store._lock:
            a = self._ensure_account(player_id)
            v = a["voice"]
            if enabled is not None:
                v["enabled"] = bool(enabled)
            if mute_player_id:
                ids = v.setdefault("muted_player_ids", [])
                if muted is not False and mute_player_id not in ids:
                    ids.append(mute_player_id)
                if muted is False and mute_player_id in ids:
                    ids.remove(mute_player_id)
            self.store._save(); return {"ok": True, "voice": deepcopy(v), "transport_enabled": bool(self._global()["config"].get("voice_chat_enabled", False))}

    def moderate_report(self, player_id: str, target_id: str, reason: str, room_id: str | None = None, source: str = "voice") -> dict[str, Any]:
        with self.store._lock:
            event = {"id": uuid.uuid4().hex[:14], "player_id": player_id, "target_id": target_id, "reason": (reason or "other")[:80], "room_id": room_id, "source": source[:24], "created_at": _now()}
            self._global()["moderation_events"].append(event); self._global()["moderation_events"] = self._global()["moderation_events"][-1000:]
            self.store._save(); return {"ok": True, "report_id": event["id"]}

    _STAFF_PERMISSIONS={"owner":{"moderate","wallet","events","rtp","economy","staff"},"admin":{"moderate","wallet","events","rtp","economy"},"moderator":{"moderate"},"event_manager":{"events","rtp"},"support":{"moderate"}}
    def _staff_role(self,pid):
        roles=self._global().setdefault("staff_roles",{})
        role=roles.get(pid)
        if role:return str(role)
        try:
            from app.core.config import settings
            if pid in settings.owner_ids:return "owner"
        except Exception:pass
        return None
    def staff_me(self,pid):
        role=self._staff_role(pid);return {"enabled":bool(role),"role":role,"permissions":sorted(self._STAFF_PERMISSIONS.get(role or "",set()))}
    def require_staff(self,pid,permission):
        me=self.staff_me(pid)
        if not me["enabled"] or permission not in me["permissions"]:raise PermissionError("staff_permission_denied")
        return me
    def staff_search_players(self,actor,q):
        self.require_staff(actor,"moderate");q=(q or "").strip().lower();rows=[]
        for pid,a in self.store._data.get("accounts",{}).items():
            public_id=str(a.get("public_id") or "").lower()
            if q and q not in pid.lower() and q not in public_id and q not in str(a.get("name","")).lower():continue
            rows.append({"id":pid,"public_id":a.get("public_id"),"name":a.get("name","Oyuncu"),"coins":int(a.get("chips",0)),"diamonds":int(a.get("diamonds",0)),"vip_level":int((a.get("vip") or {}).get("level",0)),"level":int(a.get("level",1)),"sanctions":[deepcopy(x) for x in self._global().get("sanctions",[]) if x.get("player_id")==pid and x.get("active",True)]})
            if len(rows)>=30:break
        return rows
    def active_sanctions(self,pid):
        now=_now();active=[]
        for x in self._global().setdefault("sanctions",[]):
            if x.get("player_id")!=pid or not x.get("active",True):continue
            if x.get("ends_at") and int(x["ends_at"])<=now:x["active"]=False;continue
            active.append(deepcopy(x))
        return {"banned":any(x.get("type")=="ban" for x in active),"muted":any(x.get("type")=="mute" for x in active),"chat_locked":any(x.get("type")=="chat_lock" for x in active),"gift_locked":any(x.get("type")=="gift_lock" for x in active),"invite_locked":any(x.get("type")=="invite_lock" for x in active),"rows":active}
    def staff_sanction(self,actor,pid,typ,duration_minutes=0,reason=""):
        self.require_staff(actor,"moderate")
        if pid==actor:return {"ok":False,"code":"cannot_sanction_self"}
        if pid not in self.store._data.get("accounts",{}):return {"ok":False,"code":"user_not_found"}
        now=_now();rows=self._global().setdefault("sanctions",[])
        if typ in {"unmute","unban","unchat_lock","ungift_lock","uninvite_lock"}:
            target=typ[2:] if typ in {"unmute","unban"} else typ[2:]
            for x in rows:
                if x.get("player_id")==pid and x.get("type")==target and x.get("active",True):x["active"]=False;x["revoked_at"]=now;x["revoked_by"]=actor
        elif typ in {"mute","ban","chat_lock","gift_lock","invite_lock"}:rows.append({"id":uuid.uuid4().hex[:14],"player_id":pid,"type":typ,"active":True,"reason":reason[:120] or "Yönetim kararı","starts_at":now,"ends_at":None if duration_minutes<=0 else now+min(int(duration_minutes),525600)*60,"actor":actor})
        else:return {"ok":False,"code":"invalid_sanction"}
        self._global()["admin_audit"].append({"actor":actor,"action":typ,"player_id":pid,"created_at":now});self.store.add_notification(pid,'Yönetim bildirimi',f'Hesabına {typ} işlemi uygulandı. {reason[:70]}','moderation');self.store._save();return {"ok":True}
    def staff_adjust_wallet(self,actor,pid,currency,amount,reason):
        self.require_staff(actor,"wallet")
        if pid not in self.store._data.get("accounts",{}):return {"ok":False,"code":"user_not_found"}
        if currency not in {"coins","diamonds"}:return {"ok":False,"code":"invalid_currency"}
        a=self._ensure_account(pid);key="chips" if currency=="coins" else "diamonds";before=int(a.get(key,0));amount=max(-9_000_000_000_000,min(9_000_000_000_000,int(amount)));after=max(0,before+amount);a[key]=after;row={"actor":actor,"player_id":pid,"currency":currency,"actual":after-before,"before":before,"after":after,"reason":reason[:120],"created_at":_now()};self._global()["wallet_adjustments"].append(row);self._global()["admin_audit"].append({"actor":actor,"action":"wallet_adjust","player_id":pid,"amount":after-before,"created_at":_now()});unit='altın' if currency=='coins' else 'elmas';self.store.add_notification(pid,'Hesabın güncellendi',f"Yönetim hesabına {after-before:+,} {unit} uyguladı. {reason[:60]}".replace(',','.'),'admin');self.store._save();return {"ok":True,"wallet":{"coins":a["chips"],"diamonds":a["diamonds"]},"actual":after-before}
    def staff_set_rtp(self,actor,game,percent,event_title=""):
        self.require_staff(actor,"rtp")
        return {"ok":False,"code":"rtp_control_removed"}  # Şans Salonu oranları sabit; personel değiştiremez.
        if game not in {"slot","horse","circus","drop"}:return {"ok":False,"code":"invalid_game"}
        p=round(max(60.,min(98.,float(percent))),2);cfg=self._global()["config"]["side_games"][game];before=float(cfg.get("rtp_percent",90));cfg["rtp_percent"]=p;self._global()["config"]["version"]=int(self._global()["config"].get("version",1))+1;self._global()["admin_audit"].append({"actor":actor,"action":"rtp_update","game":game,"before":before,"after":p,"event_title":event_title[:80],"created_at":_now()});self.store._save();return {"ok":True,"rtp_percent":p}
    def staff_reward_config(self,actor,patch):
        self.require_staff(actor,"rtp")
        cfg=self.store.update_reward_config(patch if isinstance(patch,dict) else {})
        self._global()["admin_audit"].append({"actor":actor,"action":"reward_config_update","created_at":_now()})
        self.store._save();return {"ok":True,"reward_config":cfg}

    def admin_live_events(self) -> list[dict[str, Any]]:
        with self.store._lock:
            return deepcopy(sorted(self._global()["live_events"], key=lambda x: (x.get("starts_at", 0), x.get("id", "")), reverse=True))

    def admin_upsert_live_event(self, payload: dict[str, Any], actor: str = "admin") -> dict[str, Any]:
        title = str(payload.get("title") or "").strip()[:80]
        if not title:
            return {"ok": False, "code": "title_required"}
        now = _now()
        starts_at = int(payload.get("starts_at") or now)
        ends_at = int(payload.get("ends_at") or (starts_at + 86400))
        if ends_at <= starts_at:
            return {"ok": False, "code": "invalid_event_window"}
        event_id = str(payload.get("id") or f"evt-{uuid.uuid4().hex[:10]}")[:48]
        raw_config = deepcopy(payload.get("config") if isinstance(payload.get("config"), dict) else {})
        raw_config.setdefault("reward_coins", 25_000)
        raw_config.setdefault("reward_diamonds", 0)
        raw_config.setdefault("side_game_bonus_percent", 10)
        raw_config.setdefault("xp_multiplier", 1.25)
        event = {
            "id": event_id,
            "title": title,
            "subtitle": str(payload.get("subtitle") or "").strip()[:140],
            "starts_at": starts_at,
            "ends_at": ends_at,
            "enabled": bool(payload.get("enabled", True)),
            "kind": str(payload.get("kind") or "seasonal")[:32],
            "config": raw_config,
            "updated_at": now,
        }
        with self.store._lock:
            g = self._global()
            rows = g["live_events"]
            idx = next((i for i, row in enumerate(rows) if row.get("id") == event_id), None)
            if idx is None:
                event["created_at"] = now
                rows.append(event)
            else:
                event["created_at"] = rows[idx].get("created_at", now)
                rows[idx] = event
            g["admin_audit"].append({"id": uuid.uuid4().hex[:12], "actor": actor[:64], "action": "live_event_upsert", "event_id": event_id, "created_at": now})
            g["admin_audit"] = g["admin_audit"][-300:]
            self.store._save()
            # Surface the publication in the compact lobby activity ticker too.
            # record_activity takes the same RLock, so call after the mutation is
            # saved and outside no additional state transformation.
            self.store.record_activity(
                "event",
                None,
                f"ETKİNLİK • {title}" + (f" • {event['subtitle']}" if event.get("subtitle") else ""),
                {"event_id": event_id, "starts_at": starts_at, "ends_at": ends_at},
            )
            return {"ok": True, "event": deepcopy(event)}

    def admin_delete_live_event(self, event_id: str, actor: str = "admin") -> dict[str, Any]:
        with self.store._lock:
            g = self._global()
            before = len(g["live_events"])
            g["live_events"] = [x for x in g["live_events"] if x.get("id") != event_id]
            if len(g["live_events"]) == before:
                return {"ok": False, "code": "event_not_found"}
            g["admin_audit"].append({"id": uuid.uuid4().hex[:12], "actor": actor[:64], "action": "live_event_delete", "event_id": event_id, "created_at": _now()})
            g["admin_audit"] = g["admin_audit"][-300:]
            self.store._save()
            return {"ok": True}

    def admin_snapshot(self) -> dict[str, Any]:
        with self.store._lock:
            g = self._global()
            accounts = list(self.store._data.get("accounts", {}).values())
            return {
                "config": deepcopy(g["config"]),
                "metrics": {
                    "accounts": len(accounts),
                    "verified_receipts": sum(1 for x in g["receipts"].values() if x.get("status") == "verified"),
                    "refunded_receipts": sum(1 for x in g["receipts"].values() if x.get("status") in {"refunded", "chargeback"}),
                    "rng_events": len(g["rng_events"]),
                    "moderation_events": len(g["moderation_events"]),
                    "vip_users": sum(1 for a in accounts if int(a.get("vip", {}).get("level", 0)) > 0), "active_bans":sum(1 for x in g.get("sanctions",[]) if x.get("active",True) and x.get("type")=="ban"), "active_mutes":sum(1 for x in g.get("sanctions",[]) if x.get("active",True) and x.get("type")=="mute"),
                },
                "recent_refunds": deepcopy(g["refund_events"][-50:]),
                "recent_rng": deepcopy(g["rng_events"][-50:]),
                "recent_moderation": deepcopy(g["moderation_events"][-50:]),
                "live_events": deepcopy(g["live_events"]), "reward_config": self.store.reward_config(),
                "audit": deepcopy(g["admin_audit"][-80:]), "wallet_adjustments":deepcopy(g.get("wallet_adjustments",[])[-50:]), "sanctions":deepcopy(g.get("sanctions",[])[-100:]),
            }
