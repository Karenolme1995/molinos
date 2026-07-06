from fastapi import APIRouter, Depends, HTTPException
from app.database import fetch_all, fetch_one, execute
from app.dependencies import get_current_user, require_admin

router = APIRouter()


@router.get("")
def listar_areas(q: str = "", user=Depends(get_current_user)):
    like = f"%{q}%"

    return fetch_all(
        """
        SELECT 
            id,
            nombre,
            created_at
        FROM areas
        WHERE nombre LIKE %s
        ORDER BY nombre ASC
        """,
        (like,),
    )


@router.get("/{area_id}")
def obtener_area(area_id: int, user=Depends(get_current_user)):
    area = fetch_one(
        """
        SELECT 
            id,
            nombre,
            created_at
        FROM areas
        WHERE id = %s
        """,
        (area_id,),
    )

    if not area:
        raise HTTPException(status_code=404, detail="Área no encontrada")

    return area


@router.post("")
def crear_area(data: dict, user=Depends(require_admin)):
    nombre = data.get("nombre")

    if not nombre or not str(nombre).strip():
        raise HTTPException(status_code=400, detail="El nombre del área es obligatorio")

    existe = fetch_one(
        """
        SELECT id 
        FROM areas 
        WHERE nombre = %s
        """,
        (nombre.strip(),),
    )

    if existe:
        raise HTTPException(status_code=400, detail="El área ya existe")

    new_id = execute(
        """
        INSERT INTO areas(nombre)
        VALUES (%s)
        """,
        (nombre.strip(),),
    )

    return {
        "id": new_id,
        "message": "Área creada",
    }


@router.put("/{area_id}")
def actualizar_area(area_id: int, data: dict, user=Depends(require_admin)):
    nombre = data.get("nombre")

    if not nombre or not str(nombre).strip():
        raise HTTPException(status_code=400, detail="El nombre del área es obligatorio")

    current = fetch_one(
        """
        SELECT id 
        FROM areas 
        WHERE id = %s
        """,
        (area_id,),
    )

    if not current:
        raise HTTPException(status_code=404, detail="Área no encontrada")

    existe = fetch_one(
        """
        SELECT id 
        FROM areas 
        WHERE nombre = %s 
        AND id <> %s
        """,
        (nombre.strip(), area_id),
    )

    if existe:
        raise HTTPException(status_code=400, detail="Ya existe otra área con ese nombre")

    execute(
        """
        UPDATE areas 
        SET nombre = %s
        WHERE id = %s
        """,
        (nombre.strip(), area_id),
    )

    return {
        "message": "Área actualizada",
    }


@router.delete("/{area_id}")
def eliminar_area(area_id: int, user=Depends(require_admin)):
    current = fetch_one(
        """
        SELECT id 
        FROM areas 
        WHERE id = %s
        """,
        (area_id,),
    )

    if not current:
        raise HTTPException(status_code=404, detail="Área no encontrada")

    usuarios = fetch_one(
        """
        SELECT COUNT(*) AS total
        FROM usuarios
        WHERE area_id = %s
        """,
        (area_id,),
    )

    if usuarios and usuarios.get("total", 0) > 0:
        raise HTTPException(
            status_code=400,
            detail="No puedes eliminar esta área porque tiene usuarios asignados",
        )

    execute(
        """
        DELETE FROM areas
        WHERE id = %s
        """,
        (area_id,),
    )

    return {
        "message": "Área eliminada",
    }