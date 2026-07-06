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
        SELECT 
            u.id,
            u.nombre,
            u.usuario,
            u.tipo,
            u.area_id,
            a.nombre AS area,
            u.correo,
            u.activo,
            u.created_at,
            u.updated_at
        FROM usuarios u
        LEFT JOIN areas a ON a.id = u.area_id
        WHERE 
            u.nombre LIKE %s 
            OR u.usuario LIKE %s 
            OR IFNULL(u.correo, '') LIKE %s
            OR IFNULL(u.tipo, '') LIKE %s
        ORDER BY u.nombre ASC
        """,
        (like, like, like, like),
    )


@router.get("/{usuario_id}")
def obtener(usuario_id: int, user=Depends(get_current_user)):
    usuario = fetch_one(
        """
        SELECT 
            u.id,
            u.nombre,
            u.usuario,
            u.tipo,
            u.area_id,
            a.nombre AS area,
            u.correo,
            u.activo,
            u.created_at,
            u.updated_at
        FROM usuarios u
        LEFT JOIN areas a ON a.id = u.area_id
        WHERE u.id = %s
        """,
        (usuario_id,),
    )

    if not usuario:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    return usuario


@router.post("")
def crear(data: UsuarioIn, user=Depends(require_admin)):
    tipo = normalizar_tipo(data.tipo)

    if not data.password:
        raise HTTPException(status_code=400, detail="La contraseña es obligatoria")

    existe = fetch_one(
        "SELECT id FROM usuarios WHERE usuario = %s",
        (data.usuario,),
    )

    if existe:
        raise HTTPException(status_code=400, detail="El usuario ya existe")

    if data.correo:
        correo_existe = fetch_one(
            "SELECT id FROM usuarios WHERE correo = %s",
            (data.correo,),
        )

        if correo_existe:
            raise HTTPException(status_code=400, detail="El correo ya está registrado")

    new_id = execute(
        """
        INSERT INTO usuarios(
            nombre,
            usuario,
            password,
            tipo,
            area_id,
            correo,
            activo
        )
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        """,
        (
            data.nombre,
            data.usuario,
            hash_password(data.password),
            tipo,
            data.area_id,
            data.correo,
            data.activo,
        ),
    )

    return {
        "id": new_id,
        "message": "Usuario creado",
    }


@router.put("/{usuario_id}")
def actualizar(usuario_id: int, data: UsuarioIn, user=Depends(require_admin)):
    tipo = normalizar_tipo(data.tipo)

    current = fetch_one(
        "SELECT id FROM usuarios WHERE id = %s",
        (usuario_id,),
    )

    if not current:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    existe = fetch_one(
        """
        SELECT id 
        FROM usuarios 
        WHERE usuario = %s 
        AND id <> %s
        """,
        (data.usuario, usuario_id),
    )

    if existe:
        raise HTTPException(status_code=400, detail="El usuario ya existe")

    if data.correo:
        correo_existe = fetch_one(
            """
            SELECT id 
            FROM usuarios 
            WHERE correo = %s 
            AND id <> %s
            """,
            (data.correo, usuario_id),
        )

        if correo_existe:
            raise HTTPException(status_code=400, detail="El correo ya está registrado")

    if data.password:
        execute(
            """
            UPDATE usuarios 
            SET 
                nombre = %s,
                usuario = %s,
                password = %s,
                tipo = %s,
                area_id = %s,
                correo = %s,
                activo = %s
            WHERE id = %s
            """,
            (
                data.nombre,
                data.usuario,
                hash_password(data.password),
                tipo,
                data.area_id,
                data.correo,
                data.activo,
                usuario_id,
            ),
        )
    else:
        execute(
            """
            UPDATE usuarios 
            SET 
                nombre = %s,
                usuario = %s,
                tipo = %s,
                area_id = %s,
                correo = %s,
                activo = %s
            WHERE id = %s
            """,
            (
                data.nombre,
                data.usuario,
                tipo,
                data.area_id,
                data.correo,
                data.activo,
                usuario_id,
            ),
        )

    return {
        "message": "Usuario actualizado",
    }


@router.delete("/{usuario_id}")
def eliminar(usuario_id: int, user=Depends(require_admin)):
    current = fetch_one(
        "SELECT id FROM usuarios WHERE id = %s",
        (usuario_id,),
    )

    if not current:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    execute(
        """
        UPDATE usuarios 
        SET activo = 0 
        WHERE id = %s
        """,
        (usuario_id,),
    )

    return {
        "message": "Usuario desactivado",
    }


@router.patch("/{usuario_id}/activar")
def activar(usuario_id: int, user=Depends(require_admin)):
    current = fetch_one(
        "SELECT id FROM usuarios WHERE id = %s",
        (usuario_id,),
    )

    if not current:
        raise HTTPException(status_code=404, detail="Usuario no encontrado")

    execute(
        """
        UPDATE usuarios 
        SET activo = 1 
        WHERE id = %s
        """,
        (usuario_id,),
    )

    return {
        "message": "Usuario activado",
    }


def normalizar_tipo(tipo: str):
    if not tipo:
        raise HTTPException(status_code=400, detail="El tipo de usuario es obligatorio")

    value = tipo.strip().lower()

    if value == "administrador":
        return "Administrador"

    if value == "supervisor":
        return "Supervisor"

    if value == "usuario":
        return "Usuario"

    raise HTTPException(
        status_code=400,
        detail="Tipo de usuario inválido. Usa: Administrador, Supervisor o Usuario",
    )