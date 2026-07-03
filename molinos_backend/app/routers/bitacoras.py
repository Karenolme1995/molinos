from datetime import date, datetime, timedelta
import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.database import fetch_all, fetch_one, execute, get_connection
from app.dependencies import get_current_user, require_admin_or_supervisor

router = APIRouter()


class AreaIn(BaseModel):
    nombre: str


class MaquinaIn(BaseModel):
    nombre: str
    descripcion: str | None = None
    id_area: int
    activo: int = 1


class MantenimientoIn(BaseModel):
    tipo_mant: str
    tiempo_mant: str
    id_area: int
    activo: str | None = "1"


class BitacoraIn(BaseModel):
    area_id: int
    maquina_id: int | None = None
    maquina: str | None = None
    mantenimiento_id: int | None = None
    mantenimiento: str | None = None
    operador: str | None = None
    descripcionPreven: str | None = None
    status_manto: str | None = "EN ESPERA"


class BitacoraUpdateIn(BaseModel):
    maquina_id: int | None = None
    maquina: str | None = None
    mantenimiento_id: int | None = None
    mantenimiento: str | None = None
    operador: str | None = None
    descripcionPreven: str | None = None
    Supervisor2: str | None = None
    descripcionCorrec: str | None = None
    status_manto: str | None = None
    cerrar: bool | None = False


def _usuario_nombre(user: dict | None) -> str:
    if not user:
        return ""
    return (
        user.get("nombre")
        or user.get("name")
        or user.get("usuario")
        or user.get("username")
        or ""
    )


def _dias_desde_tiempo_mant(value: str | None) -> int | None:
    if not value:
        return None
    text = str(value).strip().lower()
    match = re.search(r"(\d+)", text)
    if not match:
        return None
    cantidad = int(match.group(1))
    if cantidad < 0:
        return None
    if "sem" in text:
        return cantidad * 7
    if "mes" in text:
        return cantidad * 30
    if "año" in text or "ano" in text or "year" in text:
        return cantidad * 365
    return cantidad


def _fecha_proxima(dias: int | None) -> str | None:
    if dias is None:
        return None
    return (date.today() + timedelta(days=dias)).strftime("%Y-%m-%d")


def _normalizar_status(value: str | None) -> str:
    text = (value or "").strip().upper()
    if text in {"CERRADO", "CERRADA", "TERMINO", "TERMINADO", "FINALIZADO"}:
        return "CERRADO"
    if text in {"TRABAJANDO", "ABIERTO", "MANTENIMIENTO"}:
        return "TRABAJANDO"
    return text or "EN ESPERA"


def _get_area(area_id: int):
    row = fetch_one("SELECT id, nombre FROM areas WHERE id = %s LIMIT 1", (area_id,))
    if not row:
        raise HTTPException(status_code=404, detail="Área no encontrada")
    return row


def _get_maquina(maquina_id: int, area_id: int | None = None):
    params: tuple = (maquina_id,)
    extra = ""
    if area_id is not None:
        extra = " AND id_area = %s"
        params = (maquina_id, area_id)
    row = fetch_one(
        f"""
        SELECT id, nombre, descripcion, id_area, activo
        FROM maquinas
        WHERE id = %s AND activo = 1{extra}
        LIMIT 1
        """,
        params,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Máquina no encontrada para el área seleccionada")
    return row


def _get_mantenimiento(mantenimiento_id: int, area_id: int | None = None):
    params: tuple = (mantenimiento_id,)
    extra = ""
    if area_id is not None:
        extra = " AND id_area = %s"
        params = (mantenimiento_id, area_id)
    row = fetch_one(
        f"""
        SELECT id, tipo_mant, tiempo_mant, id_area, activo
        FROM mantenimientos
        WHERE id = %s{extra}
          AND (activo IS NULL OR activo IN ('1', 'S', 'SI', 'A', 'Y'))
        LIMIT 1
        """,
        params,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Mantenimiento no encontrado para el área seleccionada")
    return row


@router.get("/areas")
def listar_areas(user=Depends(get_current_user)):
    return {
        "areas": fetch_all(
            """
            SELECT id, nombre, DATE_FORMAT(created_at, '%%Y-%%m-%%d %%H:%%i') AS created_at
            FROM areas
            ORDER BY nombre
            """
        )
    }


@router.post("/areas")
def crear_area(data: AreaIn, user=Depends(require_admin_or_supervisor)):
    nombre = (data.nombre or "").strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre de área obligatorio")
    new_id = execute("INSERT INTO areas(nombre) VALUES (%s)", (nombre,))
    return {"id": new_id, "message": "Área creada"}


@router.put("/areas/{area_id}")
def actualizar_area(area_id: int, data: AreaIn, user=Depends(require_admin_or_supervisor)):
    nombre = (data.nombre or "").strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre de área obligatorio")
    _get_area(area_id)
    execute("UPDATE areas SET nombre = %s WHERE id = %s", (nombre, area_id))
    return {"message": "Área actualizada"}


@router.delete("/areas/{area_id}")
def eliminar_area(area_id: int, user=Depends(require_admin_or_supervisor)):
    _get_area(area_id)
    usados = fetch_one(
        """
        SELECT
          (SELECT COUNT(*) FROM maquinas WHERE id_area = %s AND activo = 1) AS maquinas,
          (SELECT COUNT(*) FROM bitacoras WHERE area_id = %s) AS bitacoras
        """,
        (area_id, area_id),
    )
    if usados and (int(usados.get("maquinas") or 0) > 0 or int(usados.get("bitacoras") or 0) > 0):
        raise HTTPException(status_code=400, detail="No se puede eliminar: el área tiene máquinas o bitácoras")
    execute("DELETE FROM areas WHERE id = %s", (area_id,))
    return {"message": "Área eliminada"}


@router.get("/maquinas")
def listar_maquinas(area_id: int | None = None, user=Depends(get_current_user)):
    filtro = ""
    params: tuple = ()
    if area_id:
        filtro = " AND m.id_area = %s"
        params = (area_id,)
    return {
        "maquinas": fetch_all(
            f"""
            SELECT m.id, m.nombre, m.descripcion, m.id_area, a.nombre AS area, m.activo,
                   DATE_FORMAT(m.created_at, '%%Y-%%m-%%d %%H:%%i') AS created_at
            FROM maquinas m
            LEFT JOIN areas a ON a.id = m.id_area
            WHERE m.activo = 1{filtro}
            ORDER BY a.nombre, LENGTH(m.nombre), m.nombre
            """,
            params,
        )
    }


@router.post("/maquinas")
def crear_maquina(data: MaquinaIn, user=Depends(require_admin_or_supervisor)):
    nombre = (data.nombre or "").strip()
    if not nombre:
        raise HTTPException(status_code=400, detail="Nombre de máquina obligatorio")
    _get_area(data.id_area)
    new_id = execute(
        "INSERT INTO maquinas(nombre, descripcion, id_area, activo) VALUES (%s, %s, %s, %s)",
        (nombre, data.descripcion, data.id_area, data.activo),
    )
    return {"id": new_id, "message": "Máquina creada"}


@router.put("/maquinas/{maquina_id}")
def actualizar_maquina(maquina_id: int, data: MaquinaIn, user=Depends(require_admin_or_supervisor)):
    _get_area(data.id_area)
    _get_maquina(maquina_id)
    execute(
        "UPDATE maquinas SET nombre = %s, descripcion = %s, id_area = %s, activo = %s WHERE id = %s",
        (data.nombre.strip(), data.descripcion, data.id_area, data.activo, maquina_id),
    )
    return {"message": "Máquina actualizada"}


@router.delete("/maquinas/{maquina_id}")
def eliminar_maquina(maquina_id: int, user=Depends(require_admin_or_supervisor)):
    _get_maquina(maquina_id)
    execute("UPDATE maquinas SET activo = 0 WHERE id = %s", (maquina_id,))
    return {"message": "Máquina desactivada"}


@router.get("/mantenimientos")
def listar_mantenimientos(area_id: int | None = None, user=Depends(get_current_user)):
    filtro = ""
    params: tuple = ()
    if area_id:
        filtro = " AND m.id_area = %s"
        params = (area_id,)
    return {
        "mantenimientos": fetch_all(
            f"""
            SELECT m.id, m.tipo_mant, m.tiempo_mant, m.id_area, a.nombre AS area, m.activo,
                   DATE_FORMAT(m.created_at, '%%Y-%%m-%%d %%H:%%i') AS created_at
            FROM mantenimientos m
            INNER JOIN areas a ON a.id = m.id_area
            WHERE (m.activo IS NULL OR m.activo IN ('1', 'S', 'SI', 'A', 'Y')){filtro}
            ORDER BY a.nombre, m.tipo_mant
            """,
            params,
        )
    }


@router.post("/mantenimientos")
def crear_mantenimiento(data: MantenimientoIn, user=Depends(require_admin_or_supervisor)):
    tipo = (data.tipo_mant or "").strip()
    tiempo = (data.tiempo_mant or "").strip()
    if not tipo or not tiempo:
        raise HTTPException(status_code=400, detail="Tipo y tiempo de mantenimiento son obligatorios")
    _get_area(data.id_area)
    new_id = execute(
        "INSERT INTO mantenimientos(tipo_mant, tiempo_mant, id_area, activo) VALUES (%s, %s, %s, %s)",
        (tipo, tiempo, data.id_area, data.activo or "1"),
    )
    return {"id": new_id, "message": "Mantenimiento creado"}


@router.put("/mantenimientos/{mantenimiento_id}")
def actualizar_mantenimiento(mantenimiento_id: int, data: MantenimientoIn, user=Depends(require_admin_or_supervisor)):
    _get_area(data.id_area)
    _get_mantenimiento(mantenimiento_id)
    execute(
        """
        UPDATE mantenimientos
        SET tipo_mant = %s, tiempo_mant = %s, id_area = %s, activo = %s
        WHERE id = %s
        """,
        (data.tipo_mant.strip(), data.tiempo_mant.strip(), data.id_area, data.activo or "1", mantenimiento_id),
    )
    return {"message": "Mantenimiento actualizado"}


@router.delete("/mantenimientos/{mantenimiento_id}")
def eliminar_mantenimiento(mantenimiento_id: int, user=Depends(require_admin_or_supervisor)):
    _get_mantenimiento(mantenimiento_id)
    execute("UPDATE mantenimientos SET activo = '0' WHERE id = %s", (mantenimiento_id,))
    return {"message": "Mantenimiento desactivado"}


@router.get("/bitacoras")
def listar_bitacoras(
    area_id: int | None = None,
    maquina: str = "",
    status: str = "TODOS",
    user=Depends(get_current_user),
):
    params: list = []
    filtro = " WHERE 1 = 1"
    if area_id:
        filtro += " AND b.area_id = %s"
        params.append(area_id)
    if maquina.strip():
        filtro += " AND UPPER(b.maquina) LIKE UPPER(%s)"
        params.append(f"%{maquina.strip()}%")

    rows = fetch_all(
        f"""
        SELECT b.id, b.maquina, b.fecha_inicio, TIME_FORMAT(b.hora_inicio, '%%H:%%i:%%s') AS hora_inicio,
               b.mantenimiento, b.descripcionPreven, b.descripcionCorrec, b.operador,
               b.Supervisor, b.usuario, b.numero, b.fecha_proxima, b.fecha_termino,
               TIME_FORMAT(b.Hora_termino, '%%H:%%i:%%s') AS Hora_termino,
               b.Supervisor2, b.Dias, b.area_id, a.nombre AS area,
               b.mantenimiento_id, m.tipo_mant, m.tiempo_mant,
               b.tiempo_muerto, b.status_manto,
               CASE
                 WHEN b.fecha_proxima IS NULL THEN NULL
                 ELSE DATEDIFF(b.fecha_proxima, CURDATE())
               END AS dias_restantes,
               CASE
                 WHEN UPPER(IFNULL(b.status_manto, '')) IN ('CERRADO','CERRADA','TERMINO','TERMINADO','FINALIZADO') OR b.fecha_termino IS NOT NULL THEN 'cerrado'
                 WHEN b.fecha_proxima IS NULL THEN 'en_espera'
                 WHEN DATEDIFF(b.fecha_proxima, CURDATE()) < 0 THEN 'vencido'
                 WHEN DATEDIFF(b.fecha_proxima, CURDATE()) = 0 THEN 'hoy'
                 WHEN DATEDIFF(b.fecha_proxima, CURDATE()) BETWEEN 1 AND 5 THEN '1_5'
                 WHEN DATEDIFF(b.fecha_proxima, CURDATE()) BETWEEN 6 AND 10 THEN '6_10'
                 ELSE 'a_tiempo'
               END AS semaforo,
               CASE
                 WHEN b.fecha_inicio IS NOT NULL AND b.hora_inicio IS NOT NULL AND b.fecha_termino IS NULL THEN
                   TIMEDIFF(NOW(), CONCAT(b.fecha_inicio, ' ', b.hora_inicio))
                 ELSE b.tiempo_muerto
               END AS tiempo_muerto_actual,
               CASE
                 WHEN b.fecha_inicio IS NOT NULL AND b.hora_inicio IS NOT NULL AND b.fecha_termino IS NULL THEN
                   TIMESTAMPDIFF(MINUTE, CONCAT(b.fecha_inicio, ' ', b.hora_inicio), NOW())
                 WHEN b.tiempo_muerto IS NOT NULL THEN
                   FLOOR(TIME_TO_SEC(b.tiempo_muerto) / 60)
                 ELSE NULL
               END AS tiempo_muerto_minutos
        FROM bitacoras b
        INNER JOIN areas a ON a.id = b.area_id
        LEFT JOIN mantenimientos m ON m.id = b.mantenimiento_id
        {filtro}
        ORDER BY b.fecha_inicio DESC, b.hora_inicio DESC, b.id DESC
        """,
        tuple(params),
    )

    rows_all = list(rows)

    conteos = {
        "a_tiempo": 0,
        "6_10": 0,
        "1_5": 0,
        "hoy": 0,
        "vencido": 0,
        "en_espera": 0,
        "cerrado": 0,
    }
    for row in rows_all:
        key = row.get("semaforo") or "en_espera"
        if key in conteos:
            conteos[key] += 1

    alertas_proximas = [
        r for r in rows_all
        if (r.get("semaforo") or "").lower() == "1_5"
    ]
    alertas_hoy = [
        r for r in rows_all
        if (r.get("semaforo") or "").lower() == "hoy"
    ]

    status_norm = (status or "TODOS").strip().lower()
    if status_norm and status_norm != "todos":
        rows = [r for r in rows_all if (r.get("semaforo") or "").lower() == status_norm]
    else:
        rows = rows_all

    return {
        "bitacoras": rows,
        "conteos": conteos,
        "total": len(rows),
        "alertas_proximas": alertas_proximas[:20],
        "alertas_hoy": alertas_hoy[:20],
    }


@router.post("/bitacoras")
def crear_bitacora(data: BitacoraIn, user=Depends(require_admin_or_supervisor)):
    area = _get_area(data.area_id)
    maquina_nombre = (data.maquina or "").strip()
    if data.maquina_id:
        maquina = _get_maquina(data.maquina_id, data.area_id)
        maquina_nombre = maquina["nombre"]
    if not maquina_nombre:
        raise HTTPException(status_code=400, detail="Selecciona o escribe una máquina")

    mant = None
    mantenimiento_nombre = (data.mantenimiento or "").strip()
    dias = None
    if data.mantenimiento_id:
        mant = _get_mantenimiento(data.mantenimiento_id, data.area_id)
        mantenimiento_nombre = mant["tipo_mant"]
        dias = _dias_desde_tiempo_mant(mant.get("tiempo_mant"))
    if not mantenimiento_nombre:
        raise HTTPException(status_code=400, detail="Selecciona o escribe un mantenimiento/falla")

    fecha_proxima = _fecha_proxima(dias)
    supervisor = _usuario_nombre(user)
    numero = f"BIT-{datetime.now().strftime('%Y%m%d%H%M%S')}"
    status = _normalizar_status(data.status_manto)

    new_id = execute(
        """
        INSERT INTO bitacoras(
            maquina, fecha_inicio, hora_inicio, mantenimiento, mantenimiento_id,
            descripcionPreven, operador, Supervisor, usuario, numero,
            fecha_proxima, Dias, area_id, status_manto
        ) VALUES (
            %s, CURDATE(), CURTIME(), %s, %s,
            %s, %s, %s, %s, %s,
            %s, %s, %s, %s
        )
        """,
        (
            maquina_nombre,
            mantenimiento_nombre,
            data.mantenimiento_id,
            data.descripcionPreven,
            data.operador,
            supervisor,
            supervisor,
            numero,
            fecha_proxima,
            dias,
            area["id"],
            status,
        ),
    )
    return {"id": new_id, "message": "Bitácora creada"}


@router.put("/bitacoras/{bitacora_id}")
def actualizar_bitacora(bitacora_id: int, data: BitacoraUpdateIn, user=Depends(require_admin_or_supervisor)):
    actual = fetch_one("SELECT * FROM bitacoras WHERE id = %s LIMIT 1", (bitacora_id,))
    if not actual:
        raise HTTPException(status_code=404, detail="Bitácora no encontrada")

    maquina_nombre = data.maquina
    if data.maquina_id:
        maquina = _get_maquina(data.maquina_id, int(actual["area_id"]))
        maquina_nombre = maquina["nombre"]

    mantenimiento_nombre = data.mantenimiento
    dias = None
    fecha_proxima = None
    if data.mantenimiento_id:
        mant = _get_mantenimiento(data.mantenimiento_id, int(actual["area_id"]))
        mantenimiento_nombre = mant["tipo_mant"]
        dias = _dias_desde_tiempo_mant(mant.get("tiempo_mant"))
        fecha_proxima = _fecha_proxima(dias)

    status = _normalizar_status(data.status_manto) if data.status_manto is not None else None
    cerrar = bool(data.cerrar) or (status == "CERRADO")

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            if cerrar:
                cur.execute(
                    """
                    UPDATE bitacoras
                    SET maquina = COALESCE(NULLIF(%s, ''), maquina),
                        mantenimiento = COALESCE(NULLIF(%s, ''), mantenimiento),
                        mantenimiento_id = COALESCE(%s, mantenimiento_id),
                        operador = COALESCE(NULLIF(%s, ''), operador),
                        descripcionPreven = COALESCE(NULLIF(%s, ''), descripcionPreven),
                        Supervisor2 = COALESCE(NULLIF(%s, ''), Supervisor2),
                        descripcionCorrec = COALESCE(NULLIF(%s, ''), descripcionCorrec),
                        Dias = COALESCE(%s, Dias),
                        fecha_proxima = COALESCE(%s, fecha_proxima),
                        fecha_termino = CURDATE(),
                        Hora_termino = CURTIME(),
                        tiempo_muerto = TIMEDIFF(CONCAT(CURDATE(), ' ', CURTIME()), CONCAT(fecha_inicio, ' ', hora_inicio)),
                        status_manto = 'CERRADO'
                    WHERE id = %s
                    """,
                    (
                        maquina_nombre or "",
                        mantenimiento_nombre or "",
                        data.mantenimiento_id,
                        data.operador or "",
                        data.descripcionPreven or "",
                        data.Supervisor2 or "",
                        data.descripcionCorrec or "",
                        dias,
                        fecha_proxima,
                        bitacora_id,
                    ),
                )
            else:
                cur.execute(
                    """
                    UPDATE bitacoras
                    SET maquina = COALESCE(NULLIF(%s, ''), maquina),
                        mantenimiento = COALESCE(NULLIF(%s, ''), mantenimiento),
                        mantenimiento_id = COALESCE(%s, mantenimiento_id),
                        operador = COALESCE(NULLIF(%s, ''), operador),
                        descripcionPreven = COALESCE(NULLIF(%s, ''), descripcionPreven),
                        Supervisor2 = COALESCE(NULLIF(%s, ''), Supervisor2),
                        descripcionCorrec = COALESCE(NULLIF(%s, ''), descripcionCorrec),
                        Dias = COALESCE(%s, Dias),
                        fecha_proxima = COALESCE(%s, fecha_proxima),
                        status_manto = COALESCE(%s, status_manto)
                    WHERE id = %s
                    """,
                    (
                        maquina_nombre or "",
                        mantenimiento_nombre or "",
                        data.mantenimiento_id,
                        data.operador or "",
                        data.descripcionPreven or "",
                        data.Supervisor2 or "",
                        data.descripcionCorrec or "",
                        dias,
                        fecha_proxima,
                        status,
                        bitacora_id,
                    ),
                )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {"message": "Bitácora actualizada"}


@router.post("/bitacoras/{bitacora_id}/cerrar")
def cerrar_bitacora(bitacora_id: int, data: BitacoraUpdateIn, user=Depends(require_admin_or_supervisor)):
    data.cerrar = True
    data.status_manto = "CERRADO"
    return actualizar_bitacora(bitacora_id, data, user)
