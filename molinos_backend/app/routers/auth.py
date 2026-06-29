from fastapi import APIRouter, HTTPException, Depends
from app.database import fetch_one
from app.security import verify_password, create_access_token
from app.dependencies import get_current_user
from app.schemas.common import LoginIn

router = APIRouter()

@router.post("/login")
def login(data: LoginIn):
    user = fetch_one(
        "SELECT id, nombre, usuario, password, tipo, area_id, correo, activo FROM usuarios WHERE usuario=%s AND activo=1",
        (data.usuario,),
    )
    if not user or not verify_password(data.password, user["password"]):
        raise HTTPException(status_code=401, detail="Usuario o contraseña incorrectos")

    token = create_access_token({"sub": str(user["id"]), "tipo": user["tipo"]})
    user.pop("password", None)
    return {"access_token": token, "token_type": "bearer", "user": user}

@router.get("/me")
def me(user=Depends(get_current_user)):
    return user
