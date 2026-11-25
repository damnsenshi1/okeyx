from fastapi import APIRouter,Depends
from app.core.auth import current_user
router=APIRouter()
@router.get('/auth/me')
async def me(user=Depends(current_user)):
    return {'id':user['id'],'email':user['email']}
