from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.database import get_db
from app.dependencies import get_current_user


router = APIRouter()

try:
    MX_TZ = ZoneInfo("America/Mexico_City")
except ZoneInfoNotFoundError:
    MX_TZ = timezone(timedelta(hours=-6))


TIPOS_ORDEN = [
    "entrada",
    "salida_comida",
    "entrada_comida",
    "salida",
]

TIPOS_LABEL = {
    "entrada": "Entrada",
    "salida_comida": "Salida a comer",
    "entrada_comida": "Regreso de comida",
    "salida": "Salida",
}


class ChecadaCreate(BaseModel):
    empleado_id: int


class ChecadaNominaCreate(BaseModel):
    numero_nomina: str


def now_mx() -> datetime:
    return datetime.now(MX_TZ)


def today_mx() -> date:
    return now_mx().date()


def require_admin_or_supervisor(user):
    tipo = user.get("tipo")

    if tipo not in ["administrador", "supervisor"]:
        raise HTTPException(
            status_code=403,
            detail="No tienes permiso para usar el checador",
        )


def seconds_to_hhmmss(seconds: int) -> str:
    seconds = max(0, int(seconds))

    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60

    return f"{h:02d}:{m:02d}:{s:02d}"


def parse_time_value(value):
    if value is None:
        return None

    if isinstance(value, time):
        return value

    if isinstance(value, timedelta):
        total = int(value.total_seconds())
        h = total // 3600
        m = (total % 3600) // 60
        s = total % 60

        return time(
            hour=h % 24,
            minute=m,
            second=s,
        )

    if isinstance(value, str):
        parts = value.split(":")
        if len(parts) >= 2:
            return time(
                hour=int(parts[0]),
                minute=int(parts[1]),
                second=int(parts[2]) if len(parts) > 2 else 0,
            )

    return None


def inicio_semana(fecha: date) -> date:
    return fecha - timedelta(days=fecha.weekday())


def calcular_semana_rotacion(
    fecha_base: date,
    fecha_actual: date,
    total_semanas: int,
) -> int:
    if total_semanas <= 0:
        return 1

    inicio_base = inicio_semana(fecha_base)
    inicio_actual = inicio_semana(fecha_actual)

    semanas_pasadas = (inicio_actual - inicio_base).days // 7

    return (semanas_pasadas % total_semanas) + 1


def get_empleado(db, empleado_id: int):
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                id,
                numero_nomina,
                nombre,
                foto,
                puesto,
                departamento,
                activo
            FROM empleados
            WHERE id = %s
              AND IFNULL(activo, 1) = 1
            """,
            (empleado_id,),
        )

        return cur.fetchone()


def get_empleado_por_nomina(db, numero_nomina: str):
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                id,
                numero_nomina,
                nombre,
                foto,
                puesto,
                departamento,
                activo
            FROM empleados
            WHERE numero_nomina = %s
              AND IFNULL(activo, 1) = 1
            LIMIT 1
            """,
            (numero_nomina,),
        )

        return cur.fetchone()


def get_turno_empleado(db, empleado_id: int, fecha_base: date | None = None):
    """Obtiene el turno desde empleados_turnos_rotacion.

    Ya no se consulta ni se alimenta empleados_turnos.
    Prioridad:
    1) fila activa/vigente con semana_orden igual a la semana ISO del año;
    2) si solo hay una rotación vigente, usarla;
    3) si hay varias, usar rotación cíclica desde la fecha_inicio más antigua.
    """
    fecha_hoy = fecha_base or today_mx()
    semana_anio = int(fecha_hoy.isocalendar().week)

    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                r.semana_orden,
                r.turno_id,
                r.fecha_inicio,
                r.fecha_fin,
                t.id,
                t.nombre,
                t.hora_inicio,
                t.hora_fin,
                t.color
            FROM empleados_turnos_rotacion r
            INNER JOIN turnos t ON t.id = r.turno_id
            WHERE r.empleado_id = %s
              AND r.activo = 1
              AND t.activo = 1
              AND (r.fecha_inicio IS NULL OR r.fecha_inicio <= %s)
              AND (r.fecha_fin IS NULL OR r.fecha_fin >= %s)
            ORDER BY r.semana_orden ASC, r.id ASC
            """,
            (empleado_id, fecha_hoy, fecha_hoy),
        )

        rotaciones = cur.fetchall()

    if not rotaciones:
        return None

    for r in rotaciones:
        if int(r.get("semana_orden") or 0) == semana_anio:
            return r

    if len(rotaciones) == 1:
        return rotaciones[0]

    fechas_base = [r.get("fecha_inicio") for r in rotaciones if r.get("fecha_inicio")]
    fecha_inicio_base = min(fechas_base) if fechas_base else fecha_hoy
    semana_rotacion = calcular_semana_rotacion(
        fecha_base=fecha_inicio_base,
        fecha_actual=fecha_hoy,
        total_semanas=len(rotaciones),
    )

    for r in rotaciones:
        if int(r.get("semana_orden") or 0) == int(semana_rotacion):
            return r

    return rotaciones[0]


def get_checada_dia(db, empleado_id: int, fecha_jornada: date):
    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                id,
                empleado_id,
                numero_nomina,
                tipo,
                fecha,
                fecha_jornada,
                hora,
                created_at
            FROM asistencias
            WHERE empleado_id = %s
              AND fecha_jornada = %s
            ORDER BY hora ASC, id ASC
            """,
            (empleado_id, fecha_jornada),
        )

        return cur.fetchall()


def siguiente_tipo(checadas):
    tipos_hechos = [row["tipo"] for row in checadas]

    for tipo in TIPOS_ORDEN:
        if tipo not in tipos_hechos:
            return tipo

    return None


def validar_secuencia(checadas, tipo_nuevo: str):
    esperado = siguiente_tipo(checadas)

    if esperado is None:
        raise HTTPException(
            status_code=400,
            detail="Este empleado ya tiene sus 4 checadas completas del día",
        )

    if tipo_nuevo != esperado:
        raise HTTPException(
            status_code=400,
            detail=f"Primero debe checar: {TIPOS_LABEL[esperado]}",
        )


def es_turno_nocturno(turno) -> bool:
    if not turno:
        return False

    hora_inicio = parse_time_value(turno.get("hora_inicio"))
    hora_fin = parse_time_value(turno.get("hora_fin"))

    if not hora_inicio or not hora_fin:
        return False

    return hora_fin <= hora_inicio


def calcular_fecha_jornada(turno, ahora: datetime) -> date:
    """Devuelve la fecha calendario real de la checada.

    Para evitar desfases, toda checada nueva guarda fecha_jornada igual a fecha.
    El parámetro turno se conserva para no cambiar las llamadas existentes.
    Los registros históricos de la base de datos no se modifican.
    """
    return ahora.date()


def calcular_tiempo_extra(checadas, turno):
    entrada = None
    salida = None

    for row in checadas:
        if row["tipo"] == "entrada":
            entrada = parse_time_value(row["hora"])

        if row["tipo"] == "salida":
            salida = parse_time_value(row["hora"])

    if entrada is None or salida is None:
        return {
            "tiene_salida": False,
            "minutos_trabajados": 0,
            "minutos_turno": 480,
            "minutos_extra": 0,
            "tiempo_extra": "00:00:00",
            "tiempo_extra_pagable": False,
            "mensaje": "Aún no tiene entrada y salida completas",
        }

    fecha_base = today_mx()

    dt_entrada = datetime.combine(fecha_base, entrada)
    dt_salida = datetime.combine(fecha_base, salida)

    if dt_salida < dt_entrada:
        dt_salida += timedelta(days=1)

    minutos_trabajados = int((dt_salida - dt_entrada).total_seconds() // 60)

    minutos_turno = 480

    if turno:
        hora_inicio = parse_time_value(turno.get("hora_inicio"))
        hora_fin = parse_time_value(turno.get("hora_fin"))

        if hora_inicio and hora_fin:
            dt_inicio = datetime.combine(fecha_base, hora_inicio)
            dt_fin = datetime.combine(fecha_base, hora_fin)

            if dt_fin <= dt_inicio:
                dt_fin += timedelta(days=1)

            minutos_turno = int((dt_fin - dt_inicio).total_seconds() // 60)

    minutos_extra = max(0, minutos_trabajados - minutos_turno)

    return {
        "tiene_salida": True,
        "minutos_trabajados": minutos_trabajados,
        "minutos_turno": minutos_turno,
        "minutos_extra": minutos_extra,
        "tiempo_extra": seconds_to_hhmmss(minutos_extra * 60),
        "tiempo_extra_pagable": minutos_extra > 30,
        "mensaje": (
            "Tiempo extra pagable"
            if minutos_extra > 30
            else "Sin tiempo extra pagable"
        ),
    }


def normalizar_checada(row):
    hora = row.get("hora")

    if isinstance(hora, timedelta):
        hora_texto = seconds_to_hhmmss(int(hora.total_seconds()))
    elif isinstance(hora, time):
        hora_texto = hora.strftime("%H:%M:%S")
    else:
        hora_texto = str(hora) if hora is not None else None

    return {
        "id": row.get("id"),
        "empleado_id": row.get("empleado_id"),
        "numero_nomina": row.get("numero_nomina"),
        "tipo": row.get("tipo"),
        "tipo_label": TIPOS_LABEL.get(row.get("tipo"), row.get("tipo")),
        "fecha": str(row.get("fecha")),
        "fecha_jornada": str(row.get("fecha_jornada")),
        "hora": hora_texto,
    }


def aplicar_rotacion_empleado(db, empleado_id: int):
    """Valida la rotación del empleado sin escribir en empleados_turnos.

    La fuente única es empleados_turnos_rotacion. Se conserva el nombre de la
    función para no cambiar las llamadas del checador.
    """
    turno = get_turno_empleado(db, empleado_id)
    if not turno:
        return {
            "aplico": False,
            "message": "El empleado no tiene rotación vigente para la fecha actual",
        }

    return {
        "aplico": False,
        "message": "Turno obtenido desde empleados_turnos_rotacion",
        "turno_id": turno.get("id"),
        "semana_actual": turno.get("semana_orden"),
    }


def registrar_checada_empleado(db, empleado):
    aplicar_rotacion_empleado(db, empleado["id"])

    turno = get_turno_empleado(db, empleado["id"])
    ahora = now_mx()
    fecha_jornada = calcular_fecha_jornada(turno, ahora)

    checadas = get_checada_dia(db, empleado["id"], fecha_jornada)
    tipo = siguiente_tipo(checadas)

    if tipo is None:
        raise HTTPException(
            status_code=400,
            detail="Ya tienes tus 4 checadas completas de la jornada",
        )

    validar_secuencia(checadas, tipo)

    numero_nomina = empleado.get("numero_nomina")

    if not numero_nomina:
        raise HTTPException(
            status_code=400,
            detail="El empleado no tiene número de nómina",
        )

    try:
        with db.cursor() as cur:
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
                    empleado["id"],
                    numero_nomina,
                    tipo,
                    ahora.date(),
                    fecha_jornada,
                    ahora.time(),
                ),
            )

            # No se cierra maquina_asignaciones al registrar salida.
            # La ubicación del empleado en Molinos permanece hasta que
            # supervisor/administrador lo mueva manualmente.

        db.commit()

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Error al registrar checada: {str(e)}",
        )

    checadas_actualizadas = get_checada_dia(db, empleado["id"], fecha_jornada)
    turno_actualizado = get_turno_empleado(db, empleado["id"])
    tiempo_extra = calcular_tiempo_extra(checadas_actualizadas, turno_actualizado)
    siguiente = siguiente_tipo(checadas_actualizadas)

    return {
        "ok": True,
        "message": f"{TIPOS_LABEL[tipo]} registrada correctamente",
        "tipo": tipo,
        "tipo_label": TIPOS_LABEL[tipo],
        "fecha": str(ahora.date()),
        "fecha_jornada": str(fecha_jornada),
        "hora": ahora.strftime("%H:%M:%S"),
        "empleado": empleado,
        "turno": turno_actualizado,
        "checadas": [normalizar_checada(row) for row in checadas_actualizadas],
        "siguiente_tipo": siguiente,
        "siguiente_label": TIPOS_LABEL.get(siguiente) if siguiente else "Completo",
        "completo": siguiente is None,
        "tiempo_extra": tiempo_extra,
        "turno_nocturno": es_turno_nocturno(turno_actualizado),
    }


@router.get("/hora")
def hora_mexico():
    ahora = now_mx()

    return {
        "timezone": "America/Mexico_City",
        "fecha": ahora.strftime("%Y-%m-%d"),
        "hora": ahora.strftime("%H:%M:%S"),
        "dia_semana": ahora.strftime("%A"),
        "datetime": ahora.isoformat(),
    }

@router.get("/estado/{empleado_id}")
def estado_checador(
    empleado_id: int,
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    empleado = get_empleado(db, empleado_id)

    if not empleado:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    aplicar_rotacion_empleado(db, empleado_id)

    turno = get_turno_empleado(db, empleado_id)
    ahora = now_mx()
    fecha_jornada = calcular_fecha_jornada(turno, ahora)
    checadas = get_checada_dia(db, empleado_id, fecha_jornada)
    siguiente = siguiente_tipo(checadas)
    tiempo_extra = calcular_tiempo_extra(checadas, turno)

    return {
        "fecha": str(ahora.date()),
        "fecha_jornada": str(fecha_jornada),
        "hora_mexico": ahora.strftime("%H:%M:%S"),
        "empleado": empleado,
        "turno": turno,
        "turno_nocturno": es_turno_nocturno(turno),
        "checadas": [normalizar_checada(row) for row in checadas],
        "siguiente_tipo": siguiente,
        "siguiente_label": TIPOS_LABEL.get(siguiente) if siguiente else "Completo",
        "completo": siguiente is None,
        "tiempo_extra": tiempo_extra,
    }


@router.post("/checar")
def checar(
    data: ChecadaCreate,
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    require_admin_or_supervisor(user)

    empleado = get_empleado(db, data.empleado_id)

    if not empleado:
        raise HTTPException(
            status_code=404,
            detail="Empleado no encontrado",
        )

    return registrar_checada_empleado(db, empleado)


@router.post("/checar-nomina")
def checar_por_nomina(
    data: ChecadaNominaCreate,
    db=Depends(get_db),
):
    numero_nomina = (data.numero_nomina or '').strip()

    if not numero_nomina:
        raise HTTPException(
            status_code=400,
            detail="Ingresa el número de nómina",
        )

    empleado = get_empleado_por_nomina(db, numero_nomina)

    if not empleado:
        raise HTTPException(
            status_code=404,
            detail="No se encontró empleado activo con ese número de nómina",
        )

    return registrar_checada_empleado(db, empleado)


@router.post("/aplicar-rotacion-turnos")
def aplicar_rotacion_turnos(
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    require_admin_or_supervisor(user)

    fecha_hoy = today_mx()

    with db.cursor() as cur:
        cur.execute(
            """
            SELECT DISTINCT empleado_id
            FROM empleados_turnos_rotacion
            WHERE activo = 1
            """
        )

        empleados = cur.fetchall()

    revisados = 0
    con_turno = 0

    for emp in empleados:
        revisados += 1
        if get_turno_empleado(db, emp["empleado_id"], fecha_hoy):
            con_turno += 1

    return {
        "message": "Rotación semanal revisada desde empleados_turnos_rotacion",
        "fecha": str(fecha_hoy),
        "empleados_revisados": revisados,
        "empleados_con_turno": con_turno,
        "empleados_actualizados": 0,
    }


@router.get("/castigos")
def castigos_dia(
    db=Depends(get_db),
    user=Depends(get_current_user),
):
    fecha = today_mx()
    weekday = fecha.weekday()

    aplica_castigo = weekday in [1, 2, 3]

    dias_castigo = {
        1: "martes",
        2: "miércoles",
        3: "jueves",
    }

    with db.cursor() as cur:
        cur.execute(
            """
            SELECT
                e.id AS empleado_id,
                e.numero_nomina,
                e.nombre,
                e.puesto,
                e.departamento
            FROM empleados e
            LEFT JOIN asistencias a
                ON a.empleado_id = e.id
               AND a.fecha_jornada = %s
               AND a.tipo = 'entrada'
            WHERE IFNULL(e.activo, 1) = 1
              AND a.id IS NULL
            ORDER BY e.nombre ASC
            """,
            (fecha,),
        )

        empleados = cur.fetchall()

    return {
        "fecha": str(fecha),
        "aplica_castigo": aplica_castigo,
        "dia_castigo": dias_castigo.get(weekday),
        "mensaje": (
            "Día de castigo por falta de checada"
            if aplica_castigo
            else "Hoy no aplica castigo automático"
        ),
        "empleados": empleados if aplica_castigo else [],
    }

