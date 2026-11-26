"""Yük testi için: Supabase yerine bellek içi KV ile sunucuyu başlatır.

Üretimdeki kalıcılık yolunu (RemoteSync, 2 sn'de bir değişen satırları
gönderme) gerçek ağ olmadan çalıştırır; yerel dosya modundaki "her işlemde
tüm veritabanını diske yaz" davranışı ölçümü bozmasın diye.
  python tools/serve_fake_remote.py 8765
"""
import os
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.services import remote_store as RS

_DB: dict = {}
_LOCK = threading.Lock()


def _load_all(self):
    with _LOCK:
        return dict(_DB)


def _get(self, key):
    with _LOCK:
        return _DB.get(key)


def _upsert(self, rows):
    with _LOCK:
        _DB.update(rows)


def _delete(self, keys):
    with _LOCK:
        for k in keys:
            _DB.pop(k, None)


RS.SupabaseKV.__init__ = lambda self, *a, **k: None
RS.SupabaseKV.load_all = _load_all
RS.SupabaseKV.get = _get
RS.SupabaseKV.upsert = _upsert
RS.SupabaseKV.delete = _delete

from app.core.config import settings  # noqa: E402

settings.supabase_url = settings.supabase_url or 'https://fake.supabase.co'
settings.supabase_service_role_key = settings.supabase_service_role_key or 'fake'

import uvicorn  # noqa: E402

if __name__ == '__main__':
    uvicorn.run('app.main:app', host='127.0.0.1', port=int(sys.argv[1]) if len(sys.argv) > 1 else 8765, log_level='warning')
