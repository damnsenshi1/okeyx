"""Google Play satın alma doğrulaması (sunucu tarafı).

İstemciye güvenilmez: purchase_token Google'a sorulur; yalnız purchaseState==0 (satın alınmış)
ve henüz tüketilmemiş/işlenmemiş ürünler kabul edilir. Tutar Google'dan değil katalogdan gelir.
"""
from __future__ import annotations

import json
import re
import time
from typing import Any

import httpx
from jose import jwt

TOKEN_URI = 'https://oauth2.googleapis.com/token'
API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'


class GooglePlayError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class GooglePlayClient:
    def __init__(self, service_account_json: str, package: str, transport: httpx.BaseTransport | None = None):
        try:
            self.sa = json.loads(service_account_json)
            self.sa['client_email']; self.sa['private_key']
        except Exception as exc:
            raise GooglePlayError('google_play_service_account_invalid') from exc
        self.package = package
        self._http = httpx.Client(timeout=12.0, transport=transport)
        self._token: tuple[str, float] | None = None

    def _access_token(self) -> str:
        now = time.time()
        if self._token and self._token[1] > now + 60:
            return self._token[0]
        claims = {'iss': self.sa['client_email'], 'scope': SCOPE, 'aud': self.sa.get('token_uri', TOKEN_URI), 'iat': int(now), 'exp': int(now) + 3300}
        assertion = jwt.encode(claims, self.sa['private_key'], algorithm='RS256')
        r = self._http.post(self.sa.get('token_uri', TOKEN_URI), data={'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': assertion})
        if r.status_code != 200 or 'access_token' not in r.json():
            raise GooglePlayError('google_auth_failed')
        tok = r.json()
        self._token = (tok['access_token'], now + int(tok.get('expires_in', 3300)))
        return self._token[0]

    def verify_product(self, product_id: str, purchase_token: str) -> dict[str, Any]:
        url = f'{API}/{self.package}/purchases/products/{product_id}/tokens/{purchase_token}'
        r = self._http.get(url, headers={'Authorization': f'Bearer {self._access_token()}'})
        if r.status_code in (400, 404, 410):
            raise GooglePlayError('purchase_not_found')
        if r.status_code != 200:
            raise GooglePlayError(f'google_error_{r.status_code}')
        data = r.json()
        if int(data.get('purchaseState', 1)) != 0:  # 0 purchased, 1 canceled, 2 pending
            raise GooglePlayError('purchase_not_completed')
        if not data.get('orderId'):
            raise GooglePlayError('order_id_missing')
        return data

    def acknowledge(self, product_id: str, purchase_token: str) -> None:
        url = f'{API}/{self.package}/purchases/products/{product_id}/tokens/{purchase_token}:acknowledge'
        self._http.post(url, headers={'Authorization': f'Bearer {self._access_token()}'}, json={})

    def voided_purchases(self, start_time_ms: int) -> list[dict[str, Any]]:
        """İade/chargeback edilen siparişler (Google Play Voided Purchases API)."""
        out: list[dict[str, Any]] = []
        page: str | None = None
        for _ in range(10):
            params: dict[str, Any] = {'startTime': int(start_time_ms), 'maxResults': 1000}
            if page:
                params['token'] = page
            r = self._http.get(f'{API}/{self.package}/purchases/voidedpurchases', params=params,
                               headers={'Authorization': f'Bearer {self._access_token()}'})
            if r.status_code != 200:
                raise GooglePlayError(f'google_error_{r.status_code}')
            data = r.json()
            out.extend(data.get('voidedPurchases', []) or [])
            page = (data.get('tokenPagination') or {}).get('nextPageToken')
            if not page:
                break
        return out


def price_hint_to_minor(hint: str) -> int:
    """'₺39,90' -> 3990 (VIP harcama hesabı için katalog fiyatı)."""
    m = re.search(r'(\d+)(?:[.,](\d{1,2}))?', hint or '')
    if not m:
        return 0
    whole = int(m.group(1)); frac = (m.group(2) or '0').ljust(2, '0')
    return whole * 100 + int(frac)
