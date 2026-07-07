from calendar import monthrange
from datetime import date, datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from app.database import get_db
from app.dependencies import get_current_user


router = APIRouter()


class AsistenciaCreate(BaseModel):
    empleado_id: int
    numero_nomina: Optional[str] = None
    tipo: str


class AcotacionCreate(BaseModel):
    empleado_id: int
    clave: str
    fecha: date
    observaciones: Optional[str] = None


def require_admin_or_supervisor(user):
    tipo = user.get("tipo")

    if tipo not in ["administrador", "supervisor"]:
        raise HTTPException(
            status_code=403,
            detail="No tienes permiso para modificar asistencias",
        )


def _time_text(value):
    if value is None:
        return None

    if hasattr(value, "strftime"):
        return value.strftime("%H:%M:%S")

    return str(value)


def _date_value(value, fallback: Optional[date] = None) -> date:
    if isinstance(value, date):
        return value
    if value is None:
        return fallback or date.today()
    return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()


def _month_range(anio: int, mes: int):
    inicio = date(anio, mes, 1)
    fin = date(anio, mes, monthrange(anio, mes)[1])
    return inicio, fin


def _valor_asistencia(row):
    if not row:
        return "F"

    entrada = int(row.get("entrada_ok") or 0)
    salida_comida = int(row.get("salida_comida_ok") or 0)
    entrada_comida = int(row.get("entrada_comida_ok") or 0)
    salida = int(row.get("salida_ok") or 0)

    if entrada and salida_comida and entrada_comida and salida:
        return "A"

    if entrada or salida_comida or entrada_comida or salida:
        return "ENT"

    return "F"


def _turnos_actuales(db, empleado_ids: list[int], fecha_jornada: date) -> dict[int, dict]:
    """
    Regresa el turno visible por empleado desde empleados_turnos_rotacion.

    Importante para Asistencias:
    - No depende de que el empleado haya checado asistencia.
    - No deja "SIN TURNO" si el empleado tiene cualquier rotación activa.
    - Primero intenta la semana exacta del año.
    - Si no existe, intenta la rotación vigente por fechas.
    - Si tampoco existe, usa la última rotación activa del empleado.
    """
    if not empleado_ids:
        return {}

    placeholders = ",".join(["%s"] * len(empleado_ids))
    actual_por_empleado: dict[int, dict] = {}
    semana_actual = int(fecha_jornada.isocalendar()[1])

    with db.cursor() as cur:
        cur.execute(
            f"""
            SELECT
                r.id,
                r.empleado_id,
                r.semana_orden,
                r.turno_id,
                r.fecha_inicio,
                r.fecha_fin,
                t.nombre AS turno,
                t.nombre AS turno_nombre,
                t.color AS turno_color,
                t.hora_inicio AS turno_hora_inicio,
                t.hora_fin AS turno_hora_fin
            FROM empleados_turnos_rotacion r
            INNER JOIN turnos t
                ON t.id = r.turno_id
               AND IFNULL(t.activo, 1) = 1
            WHERE IFNULL(r.activo, 1) = 1
              AND r.empleado_id IN ({placeholders})
            ORDER BY r.empleado_id ASC, r.semana_orden ASC, r.id ASC
            """,
            tuple(empleado_ids),
        )
        rotaciones = cur.fetchall()

        por_empleado: dict[int, list[dict]] = {}
        for row in rotaciones:
            try:
                empleado_id = int(row["empleado_id"])
            except Exception:
                continue
            por_empleado.setdefault(empleado_id, []).append(row)

        for empleado_id, rows in por_empleado.items():
            if not rows:
                continue

            def fecha_valida(row: dict) -> bool:
                fi = row.get("fecha_inicio")
                ff = row.get("fecha_fin")
                if fi is not None and _date_value(fi, fecha_jornada) > fecha_jornada:
                    return False
                if ff is not None and _date_value(ff, fecha_jornada) < fecha_jornada:
                    return False
                return True

            exactas = [r for r in rows if int(r.get("semana_orden") or 0) == semana_actual]
            vigentes = [r for r in rows if fecha_valida(r)]

            if exactas:
                actual = exactas[-1]
                origen = "rotacion_semana_exacta"
            elif vigentes:
                # Si hay varias vigentes, usa la más reciente por fecha_inicio/id.
                actual = sorted(
                    vigentes,
                    key=lambda r: (
                        str(r.get("fecha_inicio") or "0001-01-01"),
                        int(r.get("id") or 0),
                    ),
                )[-1]
                origen = "rotacion_vigente"
            else:
                # Último respaldo: si existe cualquier rotación activa, úsala para no mostrar SIN TURNO.
                actual = sorted(rows, key=lambda r: int(r.get("id") or 0))[-1]
                origen = "rotacion_activa_respaldo"

            actual_por_empleado[empleado_id] = {
                "turno_id": actual.get("turno_id"),
                "turno": actual.get("turno") or actual.get("turno_nombre"),
                "turno_nombre": actual.get("turno_nombre") or actual.get("turno"),
                "turno_color": actual.get("turno_color"),
                "turno_hora_inicio": _time_text(actual.get("turno_hora_inicio")),
                "turno_hora_fin": _time_text(actual.get("turno_hora_fin")),
                "turno_origen": origen,
                "turno_semana_orden": actual.get("semana_orden"),
            }

        # Respaldo para instalaciones viejas. Si la tabla empleados_turnos no existe,
        # no debe romper asistencias; simplemente se ignora.
        faltantes = [eid for eid in empleado_ids if eid not in actual_por_empleado]
        if faltantes:
            try:
                placeholders_faltantes = ",".join(["%s"] * len(faltantes))
                cur.execute(
                    f"""
                    SELECT
                        et.empleado_id,
                        et.turno_id,
                        t.nombre AS turno,
                        t.nombre AS turno_nombre,
                        t.color AS turno_color,
                        t.hora_inicio AS turno_hora_inicio,
                        t.hora_fin AS turno_hora_fin
                    FROM empleados_turnos et
                    INNER JOIN turnos t
                        ON t.id = et.turno_id
                       AND IFNULL(t.activo, 1) = 1
                    WHERE IFNULL(et.activo, 1) = 1
                      AND et.empleado_id IN ({placeholders_faltantes})
                    ORDER BY et.empleado_id ASC, et.id DESC
                    """,
                    tuple(faltantes),
                )
                directos = cur.fetchall()
            except Exception:
                directos = []

            for row in directos:
                empleado_id = int(row["empleado_id"])
                if empleado_id in actual_por_empleado:
                    continue
                actual_por_empleado[empleado_id] = {
                    "turno_id": row.get("turno_id"),
                    "turno": row.get("turno") or row.get("turno_nombre"),
                    "turno_nombre": row.get("turno_nombre") or row.get("turno"),
                    "turno_color": row.get("turno_color"),
                    "turno_hora_inicio": _time_text(row.get("turno_hora_inicio")),
                    "turno_hora_fin": _time_text(row.get("turno_hora_fin")),
                    "turno_origen": "empleados_turnos",
                }

    return actual_por_empleado

def _aplicar_turnos(db, empleados: list[dict], fecha_jornada: date) -> list[dict]:
    ids = [int(e["empleado_id"]) for e in empleados if e.get("empleado_id") is not None]
    turnos = _turnos_actuales(db, ids, fecha_jornada)

    for emp in empleados:
        empleado_id = int(emp.get("empleado_id") or 0)
        turno = turnos.get(empleado_id, {})
        emp["turno_id"] = turno.get("turno_id") or emp.get("turno_id")
        emp["turno"] = turno.get("turno") or turno.get("turno_nombre") or emp.get("turno") or emp.get("turno_nombre")
        emp["turno_nombre"] = turno.get("turno_nombre") or turno.get("turno") or emp.get("turno_nombre") or emp.get("turno")
        emp["turno_color"] = turno.get("turno_color") or emp.get("turno_color")
        emp["turno_hora_inicio"] = turno.get("turno_hora_inicio") or emp.get("turno_hora_inicio")
        emp["turno_hora_fin"] = turno.get("turno_hora_fin") or emp.get("turno_hora_fin")
        emp["turno_origen"] = turno.get("turno_origen") or ("empleados_turnos_rotacion" if turno.get("turno_id") else ("empleados_turnos" if emp.get("turno_id") else None))
        emp["turno_semana_orden"] = turno.get("turno_semana_orden") or emp.get("turno_semana_orden")

    return empleados


@router.get("")
def listar_asistencias(
    fecha_jornada: Optional[date] = Query(default=None),
    empleado_id: Optional[int] = Query(default=None),
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    if fecha_jornada is None:
        fecha_jornada = date.today()

    sql = """
        SELECT
            a.id,
            a.empleado_id,
            e.nombre AS empleado_nombre,
            e.puesto,
            e.departamento,
            a.numero_nomina,
            a.tipo,
            a.fecha,
            a.fecha_jornada,
            a.hora,
            a.created_at
        FROM asistencias a
        INNER JOIN empleados e ON e.id = a.empleado_id
        WHERE a.fecha_jornada = %s
    """

    params = [fecha_jornada]

    if empleado_id:
        sql += " AND a.empleado_id = %s"
        params.append(empleado_id)

    sql += " ORDER BY e.nombre ASC, a.hora ASC"

    with db.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


@router.post("")
def registrar_asistencia(
    data: AsistenciaCreate,
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    require_admin_or_supervisor(user)

    tipos_validos = ["entrada", "salida_comida", "entrada_comida", "salida"]

    if data.tipo not in tipos_validos:
        raise HTTPException(
            status_code=400,
            detail="Tipo de asistencia inválido",
        )

    hoy = date.today()
    ahora = datetime.now().time()

    try:
        with db.cursor() as cur:
            cur.execute(
                """
                SELECT id, nombre, numero_nomina
                FROM empleados
                WHERE id = %s
                  AND IFNULL(activo, 1) = 1
                """,
                (data.empleado_id,),
            )

            empleado = cur.fetchone()

            if not empleado:
                raise HTTPException(
                    status_code=404,
                    detail="Empleado no encontrado",
                )

            numero_nomina = data.numero_nomina or empleado.get("numero_nomina")

            if not numero_nomina:
                raise HTTPException(
                    status_code=400,
                    detail="El empleado no tiene número de nómina",
                )

            cur.execute(
                """
                INSERT INTO asistencias (
                    empleado_id,
                    numero_nomina,
                    tipo,
                    fecha,
                    fecha_jornada,
                    hora
                ) VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (
                    data.empleado_id,
                    numero_nomina,
                    data.tipo,
                    hoy,
                    hoy,
                    ahora,
                ),
            )

            if data.tipo == "salida":
                cur.execute(
                    """
                    UPDATE maquina_asignaciones
                    SET activo = 0,
                        hora_fin = CURTIME()
                    WHERE empleado_id = %s
                      AND fecha_jornada = %s
                      AND activo = 1
                    """,
                    (data.empleado_id, hoy),
                )

        db.commit()

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error al registrar asistencia: {str(e)}",
        )

    return {
        "ok": True,
        "message": "Asistencia registrada correctamente",
    }


@router.get("/tablero")
def tablero_asistencias(
    fecha_jornada: Optional[date] = Query(default=None),
    departamento: str = Query(default="MOLINOS"),
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    if fecha_jornada is None:
        fecha_jornada = date.today()

    sql = """
        SELECT
            e.id AS empleado_id,
            e.numero_nomina,
            e.nombre,
            e.foto,
            e.puesto,
            e.responsabilidades,
            e.departamento,

            asi.entrada,
            asi.salida_comida,
            asi.entrada_comida,
            asi.salida,

            ac.clave AS acotacion,
            ac.descripcion AS acotacion_descripcion,
            ac.color AS acotacion_color,

            ma.maquina_id,
            m.nombre AS maquina_nombre

        FROM empleados e

        LEFT JOIN (
            SELECT
                empleado_id,
                MAX(CASE WHEN tipo = 'entrada' THEN hora END) AS entrada,
                MAX(CASE WHEN tipo = 'salida_comida' THEN hora END) AS salida_comida,
                MAX(CASE WHEN tipo = 'entrada_comida' THEN hora END) AS entrada_comida,
                MAX(CASE WHEN tipo = 'salida' THEN hora END) AS salida
            FROM asistencias
            WHERE fecha_jornada = %s
            GROUP BY empleado_id
        ) asi ON asi.empleado_id = e.id

        LEFT JOIN empleados_acotaciones ea
            ON ea.empleado_id = e.id
           AND ea.fecha = %s

        LEFT JOIN acotaciones ac
            ON ac.id = ea.acotacion_id
           AND ac.activo = 1

        LEFT JOIN maquina_asignaciones ma
            ON ma.empleado_id = e.id
           AND ma.fecha_jornada = %s
           AND ma.activo = 1

        LEFT JOIN maquinas m
            ON m.id = ma.maquina_id

        WHERE UPPER(IFNULL(e.departamento, '')) = UPPER(%s)
          AND IFNULL(e.activo, 1) = 1

        ORDER BY e.nombre ASC
    """

    with db.cursor() as cur:
        cur.execute(
            sql,
            (fecha_jornada, fecha_jornada, fecha_jornada, departamento),
        )
        empleados = cur.fetchall()

    empleados = _aplicar_turnos(db, empleados, fecha_jornada)

    presentes = []
    ausentes = []
    con_acotacion = []

    for emp in empleados:
        entrada = emp.get("entrada")
        salida_comida = emp.get("salida_comida")
        entrada_comida = emp.get("entrada_comida")
        salida = emp.get("salida")
        acotacion = emp.get("acotacion")

        emp["entrada"] = _time_text(entrada)
        emp["salida_comida"] = _time_text(salida_comida)
        emp["entrada_comida"] = _time_text(entrada_comida)
        emp["salida"] = _time_text(salida)

        completo = bool(entrada and salida_comida and entrada_comida and salida)
        parcial = bool(entrada or salida_comida or entrada_comida or salida)

        emp["asistencia_completa"] = completo

        if acotacion:
            con_acotacion.append(emp)

        if parcial:
            emp["estado_asistencia"] = "completa" if completo else "incompleta"
            presentes.append(emp)
        else:
            emp["estado_asistencia"] = "ausente"
            ausentes.append(emp)

    return {
        "fecha_jornada": str(fecha_jornada),
        "departamento": departamento,
        "empleados": empleados,
        "presentes": presentes,
        "ausentes": ausentes,
        "con_acotacion": con_acotacion,
    }


@router.get("/matriz")
def matriz_asistencia(
    mes: int = Query(..., ge=1, le=12),
    anio: int = Query(..., ge=2000, le=2100),
    departamento: str = Query(default="MOLINOS"),
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    inicio_mes, fin_mes = _month_range(anio, mes)
    hoy = date.today()

    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                id AS empleado_id,
                numero_nomina,
                nombre,
                puesto,
                departamento
            FROM empleados
            WHERE UPPER(IFNULL(departamento, '')) = UPPER(%s)
              AND IFNULL(activo, 1) = 1
            ORDER BY nombre ASC
            """,
            (departamento,),
        )
        empleados_rows = cur.fetchall()

        empleado_ids = [int(e["empleado_id"]) for e in empleados_rows if e.get("empleado_id") is not None]
        if empleado_ids:
            placeholders_ids = ",".join(["%s"] * len(empleado_ids))
            cur.execute(
                f"""
                SELECT
                    empleado_id,
                    fecha_jornada AS fecha,
                    DAY(fecha_jornada) AS dia,
                    MAX(CASE WHEN tipo = 'entrada' THEN 1 ELSE 0 END) AS entrada_ok,
                    MAX(CASE WHEN tipo = 'salida_comida' THEN 1 ELSE 0 END) AS salida_comida_ok,
                    MAX(CASE WHEN tipo = 'entrada_comida' THEN 1 ELSE 0 END) AS entrada_comida_ok,
                    MAX(CASE WHEN tipo = 'salida' THEN 1 ELSE 0 END) AS salida_ok
                FROM asistencias
                WHERE fecha_jornada BETWEEN %s AND %s
                  AND empleado_id IN ({placeholders_ids})
                GROUP BY empleado_id, fecha_jornada
                """,
                tuple([inicio_mes, fin_mes] + empleado_ids),
            )
            asistencia_rows = cur.fetchall()

            cur.execute(
                f"""
                SELECT
                    ea.empleado_id,
                    ea.fecha,
                    DAY(ea.fecha) AS dia,
                    ac.clave AS valor
                FROM empleados_acotaciones ea
                INNER JOIN acotaciones ac ON ac.id = ea.acotacion_id
                WHERE ea.fecha BETWEEN %s AND %s
                  AND ea.empleado_id IN ({placeholders_ids})
                  AND ac.activo = 1
                """,
                tuple([inicio_mes, fin_mes] + empleado_ids),
            )
            acotacion_rows = cur.fetchall()
        else:
            asistencia_rows = []
            acotacion_rows = []

    fecha_turno = hoy if inicio_mes <= hoy <= fin_mes else inicio_mes
    empleados_rows = _aplicar_turnos(db, empleados_rows, fecha_turno)

    asistencia_por_empleado_dia = {}
    for row in asistencia_rows:
        key = (row["empleado_id"], int(row["dia"]))
        asistencia_por_empleado_dia[key] = _valor_asistencia(row)

    acotacion_por_empleado_dia = {}
    for row in acotacion_rows:
        key = (row["empleado_id"], int(row["dia"]))
        acotacion_por_empleado_dia[key] = row["valor"]

    dias_mes = monthrange(anio, mes)[1]
    empleados = []

    for emp in empleados_rows:
        empleado_id = emp["empleado_id"]

        item = {
            "empleado_id": empleado_id,
            "numero_nomina": emp["numero_nomina"],
            "nombre": emp["nombre"],
            "puesto": emp["puesto"],
            "departamento": emp["departamento"],
            "turno_id": emp.get("turno_id"),
            "turno": emp.get("turno"),
            "turno_nombre": emp.get("turno_nombre"),
            "turno_color": emp.get("turno_color"),
            "turno_hora_inicio": emp.get("turno_hora_inicio"),
            "turno_hora_fin": emp.get("turno_hora_fin"),
            "dias": {},
        }

        for dia in range(1, dias_mes + 1):
            fecha_dia = date(anio, mes, dia)

            if fecha_dia > hoy:
                continue

            key = (empleado_id, dia)

            if key in acotacion_por_empleado_dia:
                valor = acotacion_por_empleado_dia[key]
            else:
                valor = asistencia_por_empleado_dia.get(key, "F")

            item["dias"][str(dia)] = valor

        empleados.append(item)

    return {
        "mes": mes,
        "anio": anio,
        "departamento": departamento,
        "dias_mes": dias_mes,
        "empleados": empleados,
    }


@router.get("/debug-turnos")
def debug_turnos_asistencias(
    fecha_jornada: Optional[date] = Query(default=None),
    departamento: str = Query(default="MOLINOS"),
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    if fecha_jornada is None:
        fecha_jornada = date.today()

    with db.cursor() as cur:
        cur.execute(
            """
            SELECT id AS empleado_id, numero_nomina, nombre, departamento
            FROM empleados
            WHERE UPPER(IFNULL(departamento, '')) = UPPER(%s)
              AND IFNULL(activo, 1) = 1
            ORDER BY nombre ASC
            """,
            (departamento,),
        )
        empleados = cur.fetchall()

    empleados = _aplicar_turnos(db, empleados, fecha_jornada)
    sin_turno = [e for e in empleados if not e.get("turno_id") and not e.get("turno") and not e.get("turno_nombre")]
    con_turno = [e for e in empleados if e not in sin_turno]

    return {
        "fecha_jornada": str(fecha_jornada),
        "departamento": departamento,
        "total": len(empleados),
        "con_turno": len(con_turno),
        "sin_turno": len(sin_turno),
        "empleados": empleados,
    }


@router.post("/acotacion")
def registrar_acotacion(
    data: AcotacionCreate,
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    require_admin_or_supervisor(user)

    try:
        with db.cursor() as cur:
            cur.execute(
                """
                SELECT id
                FROM empleados
                WHERE id = %s
                  AND IFNULL(activo, 1) = 1
                """,
                (data.empleado_id,),
            )

            empleado = cur.fetchone()

            if not empleado:
                raise HTTPException(
                    status_code=404,
                    detail="Empleado no encontrado",
                )

            cur.execute(
                """
                SELECT id
                FROM acotaciones
                WHERE clave = %s
                  AND activo = 1
                """,
                (data.clave,),
            )

            acotacion = cur.fetchone()

            if not acotacion:
                raise HTTPException(
                    status_code=404,
                    detail="Acotación no encontrada",
                )

            cur.execute(
                """
                DELETE FROM empleados_acotaciones
                WHERE empleado_id = %s
                  AND fecha = %s
                """,
                (data.empleado_id, data.fecha),
            )

            cur.execute(
                """
                INSERT INTO empleados_acotaciones (
                    empleado_id,
                    acotacion_id,
                    fecha,
                    observaciones,
                    usuario_id
                ) VALUES (%s, %s, %s, %s, %s)
                """,
                (
                    data.empleado_id,
                    acotacion["id"],
                    data.fecha,
                    data.observaciones,
                    user.get("id"),
                ),
            )

        db.commit()

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error al registrar acotación: {str(e)}",
        )

    return {
        "ok": True,
        "message": "Acotación registrada correctamente",
    }


@router.get("/acotaciones")
def listar_acotaciones(
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                id,
                clave,
                descripcion,
                color,
                requiere_alerta
            FROM acotaciones
            WHERE activo = 1
            ORDER BY clave ASC
            """
        )

        return cur.fetchall()
