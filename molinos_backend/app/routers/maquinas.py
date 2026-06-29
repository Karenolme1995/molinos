from fastapi import APIRouter, Depends
from app.database import fetch_all, execute
from app.dependencies import get_current_user, require_admin_or_supervisor
from app.schemas.common import MaquinaIn

router = APIRouter()

@router.get("")
def listar(area: str = "MOLINOS", user=Depends(get_current_user)):
    return fetch_all(
        """
        SELECT m.id, m.nombre, m.descripcion, m.id_area, a.nombre AS area, m.activo,
               COALESCE(me.clave, 'trabajando') AS estado,
               COALESCE(me.color, 'verde') AS estado_color
        FROM maquinas m
        LEFT JOIN areas a ON a.id = m.id_area
        LEFT JOIN maquinas_estado_actual mea ON mea.maquina_id = m.id
        LEFT JOIN maquina_estados me ON me.id = mea.estado_id
        WHERE m.activo=1 AND (%s='' OR UPPER(a.nombre)=UPPER(%s))
        ORDER BY m.nombre
        """,
        (area, area),
    )

@router.post("")
def crear(data: MaquinaIn, user=Depends(require_admin_or_supervisor)):
    new_id = execute(
        "INSERT INTO maquinas(nombre, descripcion, id_area, activo) VALUES (%s,%s,%s,%s)",
        (data.nombre, data.descripcion, data.id_area, data.activo),
    )
    return {"id": new_id, "message": "Máquina creada"}

@router.put("/{maquina_id}")
def actualizar(maquina_id: int, data: MaquinaIn, user=Depends(require_admin_or_supervisor)):
    execute(
        "UPDATE maquinas SET nombre=%s, descripcion=%s, id_area=%s, activo=%s WHERE id=%s",
        (data.nombre, data.descripcion, data.id_area, data.activo, maquina_id),
    )
    return {"message": "Máquina actualizada"}

@router.delete("/{maquina_id}")
def eliminar(maquina_id: int, user=Depends(require_admin_or_supervisor)):
    execute("UPDATE maquinas SET activo=0 WHERE id=%s", (maquina_id,))
    return {"message": "Máquina desactivada"}
