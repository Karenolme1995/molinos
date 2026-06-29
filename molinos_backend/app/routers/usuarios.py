from fastapi import APIRouter, Depends, HTTPException
from app.database import fetch_all, fetch_one, execute
from app.dependencies import require_admin, get_current_user
from app.security import hash_password
from app.schemas.common import UsuarioIn

router = APIRouter()

@router.get("")
def listar(q: str = "", user=Depends(get_current_user)):
    like = f"%{q}%"
    return fetch_all(
        """
        SELECT u.id, u.nombre, u.usuario, u.tipo, u.area_id, a.nombre AS area, u.correo, u.activo
        FROM usuarios u
        LEFT JOIN areas a ON a.id = u.area_id
        WHERE u.nombre LIKE %s OR u.usuario LIKE %s OR IFNULL(u.correo,'') LIKE %s
        ORDER BY u.nombre
        """,
        (like, like, like),
    )

@router.post("")
def crear(data: UsuarioIn, user=Depends(require_admin)):
    if not data.password:
        raise HTTPException(status_code=400, detail="La contraseña es obligatoria")
    new_id = execute(
        """
        INSERT INTO usuarios(nombre, usuario, password, tipo, area_id, correo, activo)
        VALUES (%s,%s,%s,%s,%s,%s,%s)
        """,
        (data.nombre, data.usuario, hash_password(data.password), data.tipo, data.area_id, data.correo, data.activo),
    )
    return {"id": new_id, "message": "Usuario creado"}

@router.put("/{usuario_id}")
def actualizar(usuario_id: int, data: UsuarioIn, user=Depends(require_admin)):
    current = fetch_one("SELECT id FROM usuarios WHERE id=%s", (usuario_id,))
    if not current:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    if data.password:
        execute(
            """
            UPDATE usuarios SET nombre=%s, usuario=%s, password=%s, tipo=%s, area_id=%s, correo=%s, activo=%s
            WHERE id=%s
            """,
            (data.nombre, data.usuario, hash_password(data.password), data.tipo, data.area_id, data.correo, data.activo, usuario_id),
        )
    else:
        execute(
            """
            UPDATE usuarios SET nombre=%s, usuario=%s, tipo=%s, area_id=%s, correo=%s, activo=%s
            WHERE id=%s
            """,
            (data.nombre, data.usuario, data.tipo, data.area_id, data.correo, data.activo, usuario_id),
        )
    return {"message": "Usuario actualizado"}

@router.delete("/{usuario_id}")
def eliminar(usuario_id: int, user=Depends(require_admin)):
    execute("UPDATE usuarios SET activo=0 WHERE id=%s", (usuario_id,))
    return {"message": "Usuario desactivado"}
