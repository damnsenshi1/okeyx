from fastapi import APIRouter

router = APIRouter()


@router.get('/healthz')
def healthz():
    # Render sağlık kontrolü her zaman 200 döner (sunucu ayakta). Depolama durumu
    # ayrıca bildirilir; 'storage.loaded' false ise Supabase tablosu/anahtarı eksiktir.
    from app.services.account_store import STORE
    status = STORE.remote_status()
    return {'ok': True, 'service': 'okeyx-v16.0', 'storage': {
        'mode': 'supabase' if status['enabled'] else 'local-file',
        'loaded': status['loaded'],
        'error': status['error'],
    }}
