from fastapi import APIRouter

router = APIRouter()


@router.get('/healthz')
def healthz():
    return {'ok': True, 'service': 'okeyx-v10.0.0', 'stage': 'real-multiplayer-table-final'}
