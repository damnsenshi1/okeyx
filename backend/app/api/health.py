from fastapi import APIRouter

router = APIRouter()


@router.get('/healthz')
def healthz():
    # Render sağlık kontrolü her zaman 200 döner (sunucu ayakta). Depolama durumu
    # ayrıca bildirilir; 'storage.loaded' false ise Supabase tablosu/anahtarı eksiktir.
    from app.services.account_store import STORE
    status = STORE.remote_status()
    import time
    from app.api import game as _g
    runtime = {'boot_id': _g.SERVER_BOOT_ID, 'uptime_s': int(time.time() - _g.SERVER_BOOT_AT), 'rooms': len(_g.ROOMS),
               'active_rooms': sum(1 for r in _g.ROOMS.values() if r.state.started and r.state.phase not in ('waiting', 'finished')),
               'restore': dict(_g.RUNTIME_RESTORE_INFO)}
    try:
        from app.api import ops_extra as _ox
        _s = _ox.fcm()
        import os as _os
        _names = {k: len(v or '') for k, v in _os.environ.items() if 'FCM' in k.upper() or 'FIREBASE' in k.upper()}
        runtime['push'] = {'configured': _s is not None, 'project': getattr(_s, 'project', '') if _s else '', 'reason': '' if _s else _ox.FCM_ERROR, 'env_lengths': _names}
    except Exception as exc:  # pragma: no cover
        runtime['push'] = {'configured': False, 'error': type(exc).__name__}
    return {'ok': True, 'service': 'okeyx-v20', 'runtime': runtime, 'storage': {
        'mode': 'supabase' if status['enabled'] else 'local-file',
        'loaded': status['loaded'],
        'error': status['error'],
    }}
