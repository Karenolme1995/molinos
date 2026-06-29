import os
import uuid
from datetime import date, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, File
from pydantic import BaseModel

from app.database import fetch_all, fetch_one, execute, get_connection
from app.dependencies import get_current_user, require_admin_or_supervisor


router = APIRouter()


class EmpleadoIn(BaseModel):
    numero_nomina: Optional[str] = None
    nombre: Optional[str] = None
    foto: Optional[str] = None
    puesto: Optional[str] = None
    responsabilidades: Optional[str] = None
    fecha_nacimiento: Optional[date] = None
    telefono: Optional[str] = None
    direccion: Optional[str] = None
    status: Optional[str] = "ACTIVO"
    departamento: Optional[str] = "MOLINOS"
    activo: int = 1
    turno_id: Optional[int] = None
    fecha_inicio_turno: Optional[date] = None


class TurnoEmpleadoIn(BaseModel):
    empleado_id: int
    turno_id: int
    fecha_inicio: Optional[date] = None


class CambioGrupoTurnoIn(BaseModel):
    origen_turno_id: int
    destino_turno_id: int
    departamento: Optional[str] = "MOLINOS"
    fecha_inicio: Optional[date] = None


class RotacionEmpleadoItemIn(BaseModel):
    semana_orden: int
    turno_id: int
    fecha_inicio: Optional[date] = None
    fecha_fin: Optional[date] = None


class RotacionEmpleadoIn(BaseModel):
    empleado_id: int
    rotacion: list[RotacionEmpleadoItemIn]


class AcotacionEmpleadoIn(BaseModel):
    empleado_id: int
    clave: str
    fecha: date
    observaciones: Optional[str] = None


def hoy() -> date:
    return date.today()


def validar_turno(turno_id: int):
    turno = fetch_one(
        """
        SELECT id, nombre
        FROM turnos
        WHERE id = %s
          AND activo = 1
        """,
        (turno_id,),
    )

    if not turno:
        raise HTTPException(
            status_code=404,
            detail="Turno no encontrado o inactivo",
        )

    return turno


def validar_empleado(empleado_id: int):
    empleado = fetch_one(
        """
        SELECT id, numero_nomina, nombre
        FROM empleados
        WHERE id = %s
        """,
        (empleado_id,),
    )

    if not empleado:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    return empleado


def asignar_turno_empleado(
    empleado_id: int,
    turno_id: Optional[int],
    fecha_inicio: Optional[date] = None,
):
    if turno_id is None:
        return

    validar_turno(turno_id)

    if fecha_inicio is None:
        fecha_inicio = hoy()

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, turno_id
                FROM empleados_turnos
                WHERE empleado_id = %s
                  AND activo = 1
                ORDER BY id DESC
                LIMIT 1
                """,
                (empleado_id,),
            )

            actual = cur.fetchone()

            if actual and int(actual["turno_id"]) == int(turno_id):
                conn.commit()
                return

            fecha_fin = fecha_inicio - timedelta(days=1)

            cur.execute(
                """
                UPDATE empleados_turnos
                SET activo = 0,
                    fecha_fin = %s
                WHERE empleado_id = %s
                  AND activo = 1
                """,
                (fecha_fin, empleado_id),
            )

            cur.execute(
                """
                INSERT INTO empleados_turnos (
                    empleado_id,
                    turno_id,
                    fecha_inicio,
                    fecha_fin,
                    activo
                ) VALUES (%s, %s, %s, NULL, 1)
                """,
                (empleado_id, turno_id, fecha_inicio),
            )

        conn.commit()

    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


@router.get("/areas")
def listar_areas_empleados(user=Depends(get_current_user)):
    return fetch_all(
        """
        SELECT
            MIN(id) AS id,
            TRIM(nombre) AS nombre
        FROM areas
        WHERE nombre IS NOT NULL
          AND TRIM(nombre) <> ''
        GROUP BY TRIM(nombre)
        ORDER BY TRIM(nombre) ASC
        """
    )


@router.get("/turnos")
def listar_turnos(user=Depends(get_current_user)):
    return fetch_all(
        """
        SELECT
            id,
            nombre,
            hora_inicio,
            hora_fin,
            color,
            activo
        FROM turnos
        WHERE activo = 1
        ORDER BY id ASC
        """
    )


@router.get("/por-turno")
def listar_por_turno(
    departamento: str = Query(default="MOLINOS"),
    user=Depends(get_current_user),
):
    turnos = fetch_all(
        """
        SELECT
            id,
            nombre,
            hora_inicio,
            hora_fin,
            color,
            activo
        FROM turnos
        WHERE activo = 1
        ORDER BY id ASC
        """
    )

    resultado_turnos = []

    for turno in turnos:
        empleados = fetch_all(
            """
            SELECT
                e.id,
                e.numero_nomina,
                e.nombre,
                e.foto,
                e.puesto,
                e.responsabilidades,
                e.fecha_nacimiento,
                e.telefono,
                e.direccion,
                e.status,
                e.departamento,
                e.activo,
                t.id AS turno_id,
                t.nombre AS turno_nombre,
                t.hora_inicio AS turno_hora_inicio,
                t.hora_fin AS turno_hora_fin,
                et.fecha_inicio AS turno_fecha_inicio,
                et.fecha_fin AS turno_fecha_fin
            FROM empleados e
            INNER JOIN empleados_turnos et
                ON et.empleado_id = e.id
               AND et.activo = 1
            INNER JOIN turnos t
                ON t.id = et.turno_id
               AND t.activo = 1
            WHERE e.activo = 1
              AND et.turno_id = %s
              AND IFNULL(e.departamento, '') = %s
            ORDER BY e.nombre ASC
            """,
            (turno["id"], departamento),
        )

        resultado_turnos.append(
            {
                "turno": turno,
                "empleados": empleados,
            }
        )

    sin_turno = fetch_all(
        """
        SELECT
            e.id,
            e.numero_nomina,
            e.nombre,
            e.foto,
            e.puesto,
            e.responsabilidades,
            e.fecha_nacimiento,
            e.telefono,
            e.direccion,
            e.status,
            e.departamento,
            e.activo,
            NULL AS turno_id,
            NULL AS turno_nombre,
            NULL AS turno_hora_inicio,
            NULL AS turno_hora_fin,
            NULL AS turno_fecha_inicio,
            NULL AS turno_fecha_fin
        FROM empleados e
        LEFT JOIN empleados_turnos et
            ON et.empleado_id = e.id
           AND et.activo = 1
        WHERE e.activo = 1
          AND IFNULL(e.departamento, '') = %s
          AND et.id IS NULL
        ORDER BY e.nombre ASC
        """,
        (departamento,),
    )

    return {
        "departamento": departamento,
        "turnos": resultado_turnos,
        "sin_turno": sin_turno,
    }


@router.put("/grupo-turno")
def cambiar_grupo_turno(
    data: CambioGrupoTurnoIn,
    user=Depends(require_admin_or_supervisor),
):
    if data.origen_turno_id == data.destino_turno_id:
        raise HTTPException(
            status_code=400,
            detail="El turno origen y destino no pueden ser iguales",
        )

    validar_turno(data.origen_turno_id)
    validar_turno(data.destino_turno_id)

    fecha_inicio = data.fecha_inicio or hoy()
    fecha_fin = fecha_inicio - timedelta(days=1)

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    e.id AS empleado_id
                FROM empleados e
                INNER JOIN empleados_turnos et
                    ON et.empleado_id = e.id
                   AND et.activo = 1
                WHERE e.activo = 1
                  AND et.turno_id = %s
                  AND IFNULL(e.departamento, '') = %s
                ORDER BY e.nombre ASC
                """,
                (data.origen_turno_id, data.departamento),
            )

            empleados = cur.fetchall()

            if not empleados:
                raise HTTPException(
                    status_code=404,
                    detail="No hay empleados activos en el turno origen",
                )

            empleado_ids = [row["empleado_id"] for row in empleados]

            for empleado_id in empleado_ids:
                cur.execute(
                    """
                    UPDATE empleados_turnos
                    SET activo = 0,
                        fecha_fin = %s
                    WHERE empleado_id = %s
                      AND activo = 1
                    """,
                    (fecha_fin, empleado_id),
                )

                cur.execute(
                    """
                    INSERT INTO empleados_turnos (
                        empleado_id,
                        turno_id,
                        fecha_inicio,
                        fecha_fin,
                        activo
                    ) VALUES (%s, %s, %s, NULL, 1)
                    """,
                    (
                        empleado_id,
                        data.destino_turno_id,
                        fecha_inicio,
                    ),
                )

        conn.commit()

    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error al cambiar grupo de turno: {str(e)}",
        )
    finally:
        conn.close()

    return {
        "message": "Grupo de turno actualizado correctamente",
        "empleados_actualizados": len(empleado_ids),
        "origen_turno_id": data.origen_turno_id,
        "destino_turno_id": data.destino_turno_id,
        "fecha_inicio": str(fecha_inicio),
    }


@router.post("/turno")
def guardar_turno_empleado(
    data: TurnoEmpleadoIn,
    user=Depends(require_admin_or_supervisor),
):
    empleado = fetch_one(
        """
        SELECT id
        FROM empleados
        WHERE id = %s
          AND activo = 1
        """,
        (data.empleado_id,),
    )

    if not empleado:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    try:
        asignar_turno_empleado(
            empleado_id=data.empleado_id,
            turno_id=data.turno_id,
            fecha_inicio=data.fecha_inicio,
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Error al asignar turno: {str(e)}",
        )

    return {
        "message": "Turno asignado correctamente",
        "empleado_id": data.empleado_id,
        "turno_id": data.turno_id,
    }


@router.get("/rotacion/{empleado_id}")
def obtener_rotacion_empleado(
    empleado_id: int,
    user=Depends(get_current_user),
):
    empleado = validar_empleado(empleado_id)

    rotacion = fetch_all(
        """
        SELECT
            r.id,
            r.empleado_id,
            r.semana_orden,
            r.turno_id,
            r.fecha_inicio,
            r.fecha_fin,
            t.nombre AS turno_nombre,
            t.hora_inicio,
            t.hora_fin,
            r.activo,
            r.created_at
        FROM empleados_turnos_rotacion r
        INNER JOIN turnos t ON t.id = r.turno_id
        WHERE r.empleado_id = %s
          AND r.activo = 1
        ORDER BY r.semana_orden ASC
        """,
        (empleado_id,),
    )

    return {
        "empleado": empleado,
        "rotacion": rotacion,
    }


@router.post("/rotacion")
def guardar_rotacion_empleado(
    data: RotacionEmpleadoIn,
    user=Depends(require_admin_or_supervisor),
):
    validar_empleado(data.empleado_id)

    if not data.rotacion:
        raise HTTPException(
            status_code=400,
            detail="Debes enviar al menos una semana de rotación",
        )

    semanas = set()

    for item in data.rotacion:
        if item.semana_orden <= 0:
            raise HTTPException(
                status_code=400,
                detail="La semana de rotación debe ser mayor a 0",
            )

        if item.semana_orden in semanas:
            raise HTTPException(
                status_code=400,
                detail=f"La semana {item.semana_orden} está repetida",
            )

        if item.fecha_inicio and item.fecha_fin and item.fecha_fin < item.fecha_inicio:
            raise HTTPException(
                status_code=400,
                detail=f"La fecha fin no puede ser menor a la fecha inicio en la semana {item.semana_orden}",
            )

        semanas.add(item.semana_orden)
        validar_turno(item.turno_id)

    conn = get_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE empleados_turnos_rotacion
                SET activo = 0
                WHERE empleado_id = %s
                """,
                (data.empleado_id,),
            )

            for item in sorted(data.rotacion, key=lambda x: x.semana_orden):
                cur.execute(
                    """
                    INSERT INTO empleados_turnos_rotacion (
                        empleado_id,
                        semana_orden,
                        turno_id,
                        fecha_inicio,
                        fecha_fin,
                        activo
                    ) VALUES (%s, %s, %s, %s, %s, 1)
                    """,
                    (
                        data.empleado_id,
                        item.semana_orden,
                        item.turno_id,
                        item.fecha_inicio,
                        item.fecha_fin,
                    ),
                )

        conn.commit()

    except Exception as e:
        conn.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error al guardar rotación: {str(e)}",
        )
    finally:
        conn.close()

    return {
        "message": "Rotación guardada correctamente",
        "empleado_id": data.empleado_id,
        "semanas": len(data.rotacion),
    }


@router.delete("/rotacion/{empleado_id}")
def eliminar_rotacion_empleado(
    empleado_id: int,
    user=Depends(require_admin_or_supervisor),
):
    validar_empleado(empleado_id)

    execute(
        """
        UPDATE empleados_turnos_rotacion
        SET activo = 0
        WHERE empleado_id = %s
        """,
        (empleado_id,),
    )

    return {
        "message": "Rotación eliminada correctamente",
        "empleado_id": empleado_id,
    }


@router.get("")
def listar(
    q: str = "",
    departamento: str = "",
    turno_id: Optional[int] = None,
    user=Depends(get_current_user),
):
    like = f"%{q}%"

    params = [like, like, like]
    filtro_depto = ""
    filtro_turno = ""

    if departamento:
        filtro_depto = " AND IFNULL(e.departamento, '') = %s"
        params.append(departamento)

    if turno_id is not None:
        filtro_turno = " AND et.turno_id = %s"
        params.append(turno_id)

    return fetch_all(
        f"""
        SELECT
            e.id,
            e.numero_nomina,
            e.nombre,
            e.foto,
            e.puesto,
            e.responsabilidades,
            e.fecha_nacimiento,
            e.telefono,
            e.direccion,
            e.status,
            e.departamento,
            e.activo,
            t.id AS turno_id,
            t.nombre AS turno_nombre,
            t.hora_inicio AS turno_hora_inicio,
            t.hora_fin AS turno_hora_fin,
            et.fecha_inicio AS turno_fecha_inicio,
            et.fecha_fin AS turno_fecha_fin
        FROM empleados e
        LEFT JOIN empleados_turnos et
            ON et.empleado_id = e.id
           AND et.activo = 1
        LEFT JOIN turnos t
            ON t.id = et.turno_id
           AND t.activo = 1
        WHERE e.activo = 1
          AND (
                IFNULL(e.nombre, '') LIKE %s
             OR IFNULL(e.numero_nomina, '') LIKE %s
             OR IFNULL(e.puesto, '') LIKE %s
          )
          {filtro_depto}
          {filtro_turno}
        ORDER BY t.id ASC, e.nombre ASC
        """,
        tuple(params),
    )


@router.post("/{empleado_id}/foto")
def subir_foto_empleado(
    empleado_id: int,
    foto: UploadFile = File(...),
    user=Depends(require_admin_or_supervisor),
):
    empleado = fetch_one(
        """
        SELECT id
        FROM empleados
        WHERE id = %s
        """,
        (empleado_id,),
    )

    if not empleado:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    upload_dir = os.path.join("uploads", "empleados")
    os.makedirs(upload_dir, exist_ok=True)

    original_name = foto.filename or ""
    original_name_lower = original_name.lower()

    content_type = foto.content_type or ""

    ext = ".jpg"

    if content_type == "image/png" or original_name_lower.endswith(".png"):
        ext = ".png"
    elif content_type == "image/webp" or original_name_lower.endswith(".webp"):
        ext = ".webp"
    elif (
        content_type == "image/jpeg"
        or original_name_lower.endswith(".jpg")
        or original_name_lower.endswith(".jpeg")
        or content_type == "application/octet-stream"
        or content_type == ""
    ):
        ext = ".jpg"
    else:
        raise HTTPException(
            status_code=400,
            detail=f"Solo se permiten imágenes JPG, PNG o WEBP. Tipo recibido: {content_type}",
        )

    filename = f"empleado_{empleado_id}_{uuid.uuid4().hex}{ext}"
    path = os.path.join(upload_dir, filename)

    contenido = foto.file.read()

    if not contenido:
        raise HTTPException(
            status_code=400,
            detail="El archivo de foto está vacío",
        )

    with open(path, "wb") as f:
        f.write(contenido)

    foto_url = f"/uploads/empleados/{filename}"

    execute(
        """
        UPDATE empleados
        SET foto = %s
        WHERE id = %s
        """,
        (foto_url, empleado_id),
    )

    return {
        "message": "Foto guardada correctamente",
        "foto": foto_url,
    }


@router.get("/{empleado_id}")
def obtener(
    empleado_id: int,
    user=Depends(get_current_user),
):
    emp = fetch_one(
        """
        SELECT
            e.id,
            e.numero_nomina,
            e.nombre,
            e.foto,
            e.puesto,
            e.responsabilidades,
            e.fecha_nacimiento,
            e.telefono,
            e.direccion,
            e.status,
            e.departamento,
            e.activo,
            t.id AS turno_id,
            t.nombre AS turno_nombre,
            t.hora_inicio AS turno_hora_inicio,
            t.hora_fin AS turno_hora_fin,
            et.fecha_inicio AS turno_fecha_inicio,
            et.fecha_fin AS turno_fecha_fin
        FROM empleados e
        LEFT JOIN empleados_turnos et
            ON et.empleado_id = e.id
           AND et.activo = 1
        LEFT JOIN turnos t
            ON t.id = et.turno_id
           AND t.activo = 1
        WHERE e.id = %s
        """,
        (empleado_id,),
    )

    if not emp:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    return emp


@router.post("")
def crear(
    data: EmpleadoIn,
    user=Depends(require_admin_or_supervisor),
):
    new_id = execute(
        """
        INSERT INTO empleados (
            numero_nomina,
            nombre,
            foto,
            puesto,
            responsabilidades,
            fecha_nacimiento,
            telefono,
            direccion,
            status,
            departamento,
            activo
        ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (
            data.numero_nomina,
            data.nombre,
            data.foto,
            data.puesto,
            data.responsabilidades,
            data.fecha_nacimiento,
            data.telefono,
            data.direccion,
            data.status,
            data.departamento,
            data.activo,
        ),
    )

    if data.turno_id is not None:
        try:
            asignar_turno_empleado(
                empleado_id=new_id,
                turno_id=data.turno_id,
                fecha_inicio=data.fecha_inicio_turno,
            )
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Empleado creado, pero falló la asignación de turno: {str(e)}",
            )

    return {
        "id": new_id,
        "message": "Empleado creado",
    }


@router.put("/{empleado_id}")
def actualizar(
    empleado_id: int,
    data: EmpleadoIn,
    user=Depends(require_admin_or_supervisor),
):
    emp = fetch_one(
        """
        SELECT id
        FROM empleados
        WHERE id = %s
        """,
        (empleado_id,),
    )

    if not emp:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    execute(
        """
        UPDATE empleados
        SET
            numero_nomina = %s,
            nombre = %s,
            foto = %s,
            puesto = %s,
            responsabilidades = %s,
            fecha_nacimiento = %s,
            telefono = %s,
            direccion = %s,
            status = %s,
            departamento = %s,
            activo = %s
        WHERE id = %s
        """,
        (
            data.numero_nomina,
            data.nombre,
            data.foto,
            data.puesto,
            data.responsabilidades,
            data.fecha_nacimiento,
            data.telefono,
            data.direccion,
            data.status,
            data.departamento,
            data.activo,
            empleado_id,
        ),
    )

    if data.turno_id is not None:
        try:
            asignar_turno_empleado(
                empleado_id=empleado_id,
                turno_id=data.turno_id,
                fecha_inicio=data.fecha_inicio_turno,
            )
        except Exception as e:
            raise HTTPException(
                status_code=500,
                detail=f"Empleado actualizado, pero falló la asignación de turno: {str(e)}",
            )

    return {
        "message": "Empleado actualizado",
    }


@router.delete("/{empleado_id}")
def eliminar(
    empleado_id: int,
    user=Depends(require_admin_or_supervisor),
):
    execute(
        """
        UPDATE empleados
        SET activo = 0
        WHERE id = %s
        """,
        (empleado_id,),
    )

    execute(
        """
        UPDATE empleados_turnos
        SET activo = 0,
            fecha_fin = %s
        WHERE empleado_id = %s
          AND activo = 1
        """,
        (hoy(), empleado_id),
    )

    return {
        "message": "Empleado desactivado",
    }


@router.post("/acotacion")
def guardar_acotacion(
    data: AcotacionEmpleadoIn,
    user=Depends(require_admin_or_supervisor),
):
    ac = fetch_one(
        """
        SELECT id
        FROM acotaciones
        WHERE clave = %s
          AND activo = 1
        """,
        (data.clave,),
    )

    if not ac:
        raise HTTPException(
            status_code=404,
            detail="Acotación no encontrada",
        )

    execute(
        """
        DELETE FROM empleados_acotaciones
        WHERE empleado_id = %s
          AND fecha = %s
        """,
        (data.empleado_id, data.fecha),
    )

    new_id = execute(
        """
        INSERT INTO empleados_acotaciones (
            empleado_id,
            acotacion_id,
            fecha,
            observaciones,
            usuario_id
        ) VALUES (%s,%s,%s,%s,%s)
        """,
        (
            data.empleado_id,
            ac["id"],
            data.fecha,
            data.observaciones,
            user["id"],
        ),
    )

    return {
        "id": new_id,
        "message": "Acotación guardada",
    }
