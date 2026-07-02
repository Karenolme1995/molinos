import os
import uuid
from collections import defaultdict
from datetime import date, datetime
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


def _parse_fecha(value, fallback: date | None = None) -> date:
    if isinstance(value, date):
        return value
    if value is None:
        return fallback or hoy()
    return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()


def validar_turno(turno_id: int):
    turno = fetch_one(
        """
        SELECT id, nombre, hora_inicio, hora_fin, color
        FROM turnos
        WHERE id = %s AND activo = 1
        """,
        (turno_id,),
    )
    if not turno:
        raise HTTPException(status_code=404, detail="Turno no encontrado o inactivo")
    return turno


def validar_empleado(empleado_id: int):
    empleado = fetch_one(
        """
        SELECT id, numero_nomina, nombre, foto, puesto, responsabilidades,
               fecha_nacimiento, telefono, direccion, status, departamento, activo
        FROM empleados
        WHERE id = %s
        """,
        (empleado_id,),
    )
    if not empleado:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")
    return empleado


def _turnos_activos():
    return fetch_all(
        """
        SELECT id, nombre, hora_inicio, hora_fin, color, activo
        FROM turnos
        WHERE activo = 1
        ORDER BY id ASC
        """
    )


def _rotaciones_empleados(fecha_jornada: date, departamento: str = ""):
    params = []
    filtro_depto = ""
    if departamento:
        filtro_depto = " AND IFNULL(e.departamento, '') = %s"
        params.append(departamento)

    empleados = fetch_all(
        f"""
        SELECT e.id, e.numero_nomina, e.nombre, e.foto, e.puesto, e.responsabilidades,
               e.fecha_nacimiento, e.telefono, e.direccion, e.status, e.departamento, e.activo
        FROM empleados e
        WHERE e.activo = 1 {filtro_depto}
        ORDER BY e.nombre ASC
        """,
        tuple(params),
    )

    if not empleados:
        return [], {}

    ids = [int(e["id"]) for e in empleados]
    placeholders = ",".join(["%s"] * len(ids))
    rotaciones = fetch_all(
        f"""
        SELECT r.id, r.empleado_id, r.semana_orden, r.turno_id, r.fecha_inicio, r.fecha_fin,
               t.nombre AS turno_nombre, t.hora_inicio, t.hora_fin, t.color
        FROM empleados_turnos_rotacion r
        INNER JOIN turnos t ON t.id = r.turno_id AND t.activo = 1
        WHERE r.activo = 1
          AND r.empleado_id IN ({placeholders})
          AND (r.fecha_inicio IS NULL OR r.fecha_inicio <= %s)
          AND (r.fecha_fin IS NULL OR r.fecha_fin >= %s)
        ORDER BY r.empleado_id, r.semana_orden ASC
        """,
        tuple(ids + [fecha_jornada, fecha_jornada]),
    )

    por_empleado: dict[int, list[dict]] = defaultdict(list)
    for row in rotaciones:
        por_empleado[int(row["empleado_id"])].append(row)

    actual_por_empleado = {}
    for empleado in empleados:
        empleado_id = int(empleado["id"])
        rows = sorted(por_empleado.get(empleado_id, []), key=lambda r: int(r.get("semana_orden") or 1))
        if not rows:
            empleado.update({
                "turno_id": None,
                "turno_nombre": None,
                "turno_hora_inicio": None,
                "turno_hora_fin": None,
                "turno_color": None,
                "proximo_turno_id": None,
                "proximo_turno_nombre": None,
            })
            continue

        base_raw = next((r.get("fecha_inicio") for r in rows if r.get("fecha_inicio")), None)
        base = _parse_fecha(base_raw, fecha_jornada)
        weeks = max(0, (fecha_jornada - base).days // 7)
        index = weeks % len(rows)
        actual = rows[index]
        proximo = rows[(index + 1) % len(rows)] if len(rows) > 1 else actual

        empleado.update({
            "turno_id": actual.get("turno_id"),
            "turno_nombre": actual.get("turno_nombre"),
            "turno_hora_inicio": actual.get("hora_inicio"),
            "turno_hora_fin": actual.get("hora_fin"),
            "turno_color": actual.get("color"),
            "turno_fecha_inicio": actual.get("fecha_inicio"),
            "turno_fecha_fin": actual.get("fecha_fin"),
            "proximo_turno_id": proximo.get("turno_id"),
            "proximo_turno_nombre": proximo.get("turno_nombre"),
            "proximo_turno_hora_inicio": proximo.get("hora_inicio"),
            "proximo_turno_hora_fin": proximo.get("hora_fin"),
        })
        actual_por_empleado[empleado_id] = actual

    return empleados, actual_por_empleado


@router.get("/areas")
def listar_areas_empleados(user=Depends(get_current_user)):
    return fetch_all(
        """
        SELECT MIN(id) AS id, TRIM(nombre) AS nombre
        FROM areas
        WHERE nombre IS NOT NULL AND TRIM(nombre) <> ''
        GROUP BY TRIM(nombre)
        ORDER BY TRIM(nombre) ASC
        """
    )


@router.get("/turnos")
def listar_turnos(user=Depends(get_current_user)):
    return _turnos_activos()


@router.get("/por-turno")
def listar_por_turno(departamento: str = Query(default="MOLINOS"), user=Depends(get_current_user)):
    fecha = hoy()
    turnos = _turnos_activos()
    empleados, _ = _rotaciones_empleados(fecha, departamento)

    resultado_turnos = []
    for turno in turnos:
        empleados_turno = [e for e in empleados if str(e.get("turno_id")) == str(turno["id"])]
        resultado_turnos.append({"turno": turno, "empleados": empleados_turno})

    sin_turno = [e for e in empleados if e.get("turno_id") is None]
    return {"departamento": departamento, "fecha": str(fecha), "turnos": resultado_turnos, "sin_turno": sin_turno}


@router.put("/grupo-turno")
def cambiar_grupo_turno(data: CambioGrupoTurnoIn, user=Depends(require_admin_or_supervisor)):
    raise HTTPException(status_code=400, detail="El cambio por grupo directo fue deshabilitado. Configura la rotación semanal por empleado.")


@router.post("/turno")
def guardar_turno_empleado(data: TurnoEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    raise HTTPException(status_code=400, detail="El turno directo fue deshabilitado. Usa /empleados/rotacion.")


@router.get("/rotacion/{empleado_id}")
def obtener_rotacion_empleado(empleado_id: int, user=Depends(get_current_user)):
    empleado = validar_empleado(empleado_id)
    rotacion = fetch_all(
        """
        SELECT r.id, r.empleado_id, r.semana_orden, r.turno_id, r.fecha_inicio, r.fecha_fin,
               t.nombre AS turno_nombre, t.hora_inicio, t.hora_fin, r.activo, r.created_at
        FROM empleados_turnos_rotacion r
        INNER JOIN turnos t ON t.id = r.turno_id
        WHERE r.empleado_id = %s AND r.activo = 1
        ORDER BY r.semana_orden ASC
        """,
        (empleado_id,),
    )
    return {"empleado": empleado, "rotacion": rotacion}


@router.post("/rotacion")
def guardar_rotacion_empleado(data: RotacionEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    validar_empleado(data.empleado_id)
    if not data.rotacion:
        raise HTTPException(status_code=400, detail="Debes enviar al menos una semana de rotación")

    semanas = set()
    for item in data.rotacion:
        if item.semana_orden <= 0:
            raise HTTPException(status_code=400, detail="La semana de rotación debe ser mayor a 0")
        if item.semana_orden in semanas:
            raise HTTPException(status_code=400, detail=f"La semana {item.semana_orden} está repetida")
        if item.fecha_inicio and item.fecha_fin and item.fecha_fin < item.fecha_inicio:
            raise HTTPException(status_code=400, detail=f"La fecha fin no puede ser menor a la fecha inicio en la semana {item.semana_orden}")
        validar_turno(item.turno_id)
        semanas.add(item.semana_orden)

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE empleados_turnos_rotacion SET activo = 0 WHERE empleado_id = %s", (data.empleado_id,))
            for item in sorted(data.rotacion, key=lambda x: x.semana_orden):
                cur.execute(
                    """
                    INSERT INTO empleados_turnos_rotacion(empleado_id, semana_orden, turno_id, fecha_inicio, fecha_fin, activo)
                    VALUES (%s, %s, %s, %s, %s, 1)
                    """,
                    (data.empleado_id, item.semana_orden, item.turno_id, item.fecha_inicio, item.fecha_fin),
                )
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Error al guardar rotación: {str(e)}")
    finally:
        conn.close()

    return {"message": "Rotación guardada correctamente", "empleado_id": data.empleado_id, "semanas": len(data.rotacion)}


@router.delete("/rotacion/{empleado_id}")
def eliminar_rotacion_empleado(empleado_id: int, user=Depends(require_admin_or_supervisor)):
    validar_empleado(empleado_id)
    execute("UPDATE empleados_turnos_rotacion SET activo = 0 WHERE empleado_id = %s", (empleado_id,))
    return {"message": "Rotación eliminada correctamente", "empleado_id": empleado_id}


@router.get("")
def listar(q: str = "", departamento: str = "", turno_id: Optional[int] = None, user=Depends(get_current_user)):
    fecha = hoy()
    empleados, _ = _rotaciones_empleados(fecha, departamento)
    q_norm = q.strip().lower()
    if q_norm:
        empleados = [
            e for e in empleados
            if q_norm in " ".join(str(e.get(k) or "") for k in ["nombre", "numero_nomina", "puesto", "departamento", "turno_nombre"]).lower()
        ]
    if turno_id is not None:
        empleados = [e for e in empleados if str(e.get("turno_id")) == str(turno_id)]
    return empleados


@router.post("")
def crear(data: EmpleadoIn, user=Depends(require_admin_or_supervisor)):
    new_id = execute(
        """
        INSERT INTO empleados(numero_nomina, nombre, foto, puesto, responsabilidades, fecha_nacimiento, telefono, direccion, status, departamento, activo)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """,
        (data.numero_nomina, data.nombre, data.foto, data.puesto, data.responsabilidades, data.fecha_nacimiento, data.telefono, data.direccion, data.status, data.departamento, data.activo),
    )
    return {"id": new_id, "message": "Empleado creado. Configura su rotación semanal desde la lista."}


@router.get("/{empleado_id}")
def obtener(empleado_id: int, user=Depends(get_current_user)):
    empleado = validar_empleado(empleado_id)
    empleados, _ = _rotaciones_empleados(hoy(), empleado.get("departamento") or "")
    for e in empleados:
        if int(e["id"]) == int(empleado_id):
            return e
    return empleado


@router.put("/{empleado_id}")
def actualizar(empleado_id: int, data: EmpleadoIn, user=Depends(require_admin_or_supervisor)):
    validar_empleado(empleado_id)
    execute(
        """
        UPDATE empleados SET numero_nomina=%s, nombre=%s, foto=%s, puesto=%s, responsabilidades=%s,
            fecha_nacimiento=%s, telefono=%s, direccion=%s, status=%s, departamento=%s, activo=%s
        WHERE id=%s
        """,
        (data.numero_nomina, data.nombre, data.foto, data.puesto, data.responsabilidades, data.fecha_nacimiento, data.telefono, data.direccion, data.status, data.departamento, data.activo, empleado_id),
    )
    return {"message": "Empleado actualizado. El turno solo se modifica desde rotación semanal."}


@router.delete("/{empleado_id}")
def eliminar(empleado_id: int, user=Depends(require_admin_or_supervisor)):
    execute("UPDATE empleados SET activo = 0 WHERE id = %s", (empleado_id,))
    execute("UPDATE empleados_turnos_rotacion SET activo = 0 WHERE empleado_id = %s", (empleado_id,))
    return {"message": "Empleado desactivado"}


@router.post("/{empleado_id}/foto")
def subir_foto_empleado(empleado_id: int, foto: UploadFile = File(...), user=Depends(require_admin_or_supervisor)):
    validar_empleado(empleado_id)
    upload_dir = os.path.join("uploads", "empleados")
    os.makedirs(upload_dir, exist_ok=True)
    original = (foto.filename or "").lower()
    content_type = foto.content_type or ""
    if content_type == "image/png" or original.endswith(".png"):
        ext = ".png"
    elif content_type == "image/webp" or original.endswith(".webp"):
        ext = ".webp"
    elif content_type in ("image/jpeg", "application/octet-stream", "") or original.endswith((".jpg", ".jpeg")):
        ext = ".jpg"
    else:
        raise HTTPException(status_code=400, detail=f"Solo se permiten imágenes JPG, PNG o WEBP. Tipo recibido: {content_type}")
    filename = f"empleado_{empleado_id}_{uuid.uuid4().hex}{ext}"
    path = os.path.join(upload_dir, filename)
    contenido = foto.file.read()
    if not contenido:
        raise HTTPException(status_code=400, detail="El archivo de foto está vacío")
    with open(path, "wb") as f:
        f.write(contenido)
    foto_url = f"/uploads/empleados/{filename}"
    execute("UPDATE empleados SET foto = %s WHERE id = %s", (foto_url, empleado_id))
    return {"message": "Foto guardada correctamente", "foto": foto_url}


@router.post("/acotacion")
def guardar_acotacion(data: AcotacionEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    ac = fetch_one("SELECT id FROM acotaciones WHERE clave = %s AND activo = 1", (data.clave,))
    if not ac:
        raise HTTPException(status_code=404, detail="Acotación no encontrada")
    execute("DELETE FROM empleados_acotaciones WHERE empleado_id = %s AND fecha = %s", (data.empleado_id, data.fecha))
    new_id = execute(
        """
        INSERT INTO empleados_acotaciones(empleado_id, acotacion_id, fecha, observaciones, usuario_id)
        VALUES (%s,%s,%s,%s,%s)
        """,
        (data.empleado_id, ac["id"], data.fecha, data.observaciones, user["id"]),
    )
    return {"id": new_id, "message": "Acotación guardada"}
