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

            t.nombre AS turno,
            t.color AS turno_color,

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

        LEFT JOIN empleados_turnos et
            ON et.empleado_id = e.id
           AND et.activo = 1

        LEFT JOIN turnos t
            ON t.id = et.turno_id
           AND t.activo = 1

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

        cur.execute(
            """
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
            GROUP BY empleado_id, fecha_jornada
            """,
            (inicio_mes, fin_mes),
        )
        asistencia_rows = cur.fetchall()

        cur.execute(
            """
            SELECT
                ea.empleado_id,
                ea.fecha,
                DAY(ea.fecha) AS dia,
                ac.clave AS valor
            FROM empleados_acotaciones ea
            INNER JOIN acotaciones ac ON ac.id = ea.acotacion_id
            WHERE ea.fecha BETWEEN %s AND %s
              AND ac.activo = 1
            """,
            (inicio_mes, fin_mes),
        )
        acotacion_rows = cur.fetchall()

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
