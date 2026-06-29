from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from app.database import fetch_one
from app.security import decode_token

bearer = HTTPBearer()


def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(bearer)):
    payload = decode_token(credentials.credentials)
    if not payload or "sub" not in payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token inválido")

    user = fetch_one(
        "SELECT id, nombre, usuario, tipo, area_id, correo, activo FROM usuarios WHERE id=%s AND activo=1",
        (payload["sub"],),
    )
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Usuario no encontrado")
    return user


def require_admin_or_supervisor(user=Depends(get_current_user)):
    if user["tipo"] not in ("administrador", "supervisor"):
        raise HTTPException(status_code=403, detail="No tienes permiso para modificar")
    return user


def require_admin(user=Depends(get_current_user)):
    if user["tipo"] != "administrador":
        raise HTTPException(status_code=403, detail="Solo administrador")
    return user
