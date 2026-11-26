"""Supabase `okeyx_server_kv` tablosunun yedeği ve geri yüklemesi.

Kullanım (kendi bilgisayarında):
  set SUPABASE_URL=...  & set SUPABASE_SERVICE_ROLE_KEY=...
  python -m app.services.backup yedek  yedek.json
  python -m app.services.backup geri   yedek.json   (mevcut satırların üstüne yazar)
"""
from __future__ import annotations

import json
import os
import sys
import time

from app.services.remote_store import SupabaseKV


def backup(kv: SupabaseKV) -> dict:
    rows = kv.load_all()
    return {'format': 'okeyx-kv-backup-1', 'created_at': int(time.time()), 'count': len(rows), 'rows': rows}


def restore(kv: SupabaseKV, payload: dict) -> int:
    if payload.get('format') != 'okeyx-kv-backup-1' or not isinstance(payload.get('rows'), dict):
        raise ValueError('bad_backup_file')
    rows = payload['rows']
    if payload.get('count') != len(rows):
        raise ValueError('backup_count_mismatch')
    kv.upsert(rows)
    return len(rows)


def _main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] not in ('yedek', 'geri'):
        print(__doc__)
        return 2
    url, key = os.environ.get('SUPABASE_URL', ''), os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')
    if not url or not key:
        print('SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY ortam değişkenleri gerekli.')
        return 2
    kv = SupabaseKV(url, key)
    if argv[1] == 'yedek':
        data = backup(kv)
        with open(argv[2], 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)
        print(f"{data['count']} satır yedeklendi -> {argv[2]}")
    else:
        with open(argv[2], encoding='utf-8') as f:
            n = restore(kv, json.load(f))
        print(f'{n} satır geri yüklendi.')
    return 0


if __name__ == '__main__':
    raise SystemExit(_main(sys.argv))
