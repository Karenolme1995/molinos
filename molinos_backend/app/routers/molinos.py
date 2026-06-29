from collections import defaultdict
from fastapi import APIRouter, Depends, HTTPException
from app.database import fetch_all, fetch_one, execute, get_connection
from app.dependencies import get_current_user, require_admin_or_supervisor
from app.schemas.common import AsignarEmpleadoIn, CambiarEstadoMaquinaIn

router = APIRouter()

@router.get("/tablero")
def tablero(fecha_jornada: str, user=Depends(get_current_user)):
    maquinas = fetch_all(
        """
        SELECT m.id, m.nombre, m.descripcion, m.id_area,
               COALESCE(me.clave, 'trabajando') AS estado,
               COALESCE(me.nombre, 'Trabajando') AS estado_nombre,
               COALESCE(me.color, 'verde') AS estado_color
        FROM maquinas m
        INNER JOIN areas a ON a.id = m.id_area
        LEFT JOIN maquinas_estado_actual mea ON mea.maquina_id = m.id
        LEFT JOIN maquina_estados me ON me.id = mea.estado_id
        WHERE m.activo=1 AND UPPER(a.nombre)=UPPER('MOLINOS')
        ORDER BY m.nombre
        """
    )

    empleados = fetch_all(
        """
        SELECT 
          e.id AS empleado_id,
          e.numero_nomina,
          e.nombre,
          e.foto,
          e.puesto,
          e.responsabilidades,
          e.departamento,
          t.nombre AS turno,
          t.color AS turno_color,
          ma.maquina_id,
          m.nombre AS maquina_nombre,
          ac.clave AS acotacion,
          ac.descripcion AS acotacion_descripcion,
          ac.color AS acotacion_color,
          EXISTS(
            SELECT 1 FROM asistencias ae
            WHERE ae.empleado_id=e.id AND ae.fecha_jornada=%s AND ae.tipo='entrada'
          ) AS presente,
          EXISTS(
            SELECT 1 FROM asistencias as2
            WHERE as2.empleado_id=e.id AND as2.fecha_jornada=%s AND as2.tipo='salida'
          ) AS checo_salida
        FROM empleados e
        LEFT JOIN empleados_turnos et ON et.empleado_id = e.id AND et.activo = 1
        LEFT JOIN turnos t ON t.id = et.turno_id
        LEFT JOIN maquina_asignaciones ma ON ma.empleado_id = e.id AND ma.fecha_jornada = %s AND ma.activo = 1
        LEFT JOIN maquinas m ON m.id = ma.maquina_id
        LEFT JOIN empleados_acotaciones ea ON ea.empleado_id = e.id AND ea.fecha = %s
        LEFT JOIN acotaciones ac ON ac.id = ea.acotacion_id
        WHERE UPPER(IFNULL(e.departamento,'')) = UPPER('MOLINOS')
          AND e.activo = 1
        ORDER BY e.nombre ASC
        """,
        (fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada),
    )

    por_maquina = defaultdict(list)
    espera = []
    ausentes = []
    alertas = []

    for e in empleados:
        e["presente"] = bool(e["presente"])
        e["checo_salida"] = bool(e["checo_salida"])

        if e["checo_salida"]:
            continue

        if e["acotacion"]:
            alertas.append(e)

        if e["presente"] and e["maquina_id"]:
            por_maquina[e["maquina_id"]].append(e)
        elif e["presente"]:
            espera.append(e)
        else:
            ausentes.append(e)

    for m in maquinas:
        m["empleados"] = por_maquina.get(m["id"], [])

    return {
        "fecha_jornada": fecha_jornada,
        "maquinas": maquinas,
        "espera": espera,
        "ausentes": ausentes,
        "alertas": alertas,
    }

@router.post("/asignar")
def asignar(data: AsignarEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    empleado = fetch_one("SELECT id FROM empleados WHERE id=%s AND activo=1", (data.empleado_id,))
    if not empleado:
        raise HTTPException(status_code=404, detail="Empleado no encontrado")

    maquina = fetch_one("SELECT id FROM maquinas WHERE id=%s AND activo=1", (data.maquina_id,))
    if not maquina:
        raise HTTPException(status_code=404, detail="Máquina no encontrada")

    salida = fetch_one(
        "SELECT id FROM asistencias WHERE empleado_id=%s AND fecha_jornada=%s AND tipo='salida' LIMIT 1",
        (data.empleado_id, data.fecha_jornada),
    )
    if salida:
        raise HTTPException(status_code=400, detail="El empleado ya checó salida")

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE maquina_asignaciones
                SET activo=0, hora_fin=CURTIME()
                WHERE empleado_id=%s AND fecha_jornada=%s AND activo=1
                """,
                (data.empleado_id, data.fecha_jornada),
            )
            cur.execute(
                """
                INSERT INTO maquina_asignaciones(empleado_id, maquina_id, fecha_jornada, hora_inicio, activo, usuario_id)
                VALUES (%s,%s,%s,CURTIME(),1,%s)
                """,
                (data.empleado_id, data.maquina_id, data.fecha_jornada, user["id"]),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {"message": "Empleado asignado a máquina"}

@router.post("/quitar-empleado")
def quitar_empleado(data: AsignarEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    execute(
        """
        UPDATE maquina_asignaciones
        SET activo=0, hora_fin=CURTIME()
        WHERE empleado_id=%s AND fecha_jornada=%s AND activo=1
        """,
        (data.empleado_id, data.fecha_jornada),
    )
    return {"message": "Empleado quitado de máquina"}

@router.post("/maquina-estado")
def cambiar_estado(data: CambiarEstadoMaquinaIn, user=Depends(require_admin_or_supervisor)):
    estado = fetch_one("SELECT id FROM maquina_estados WHERE clave=%s", (data.estado,))
    if not estado:
        raise HTTPException(status_code=404, detail="Estado no encontrado")

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO maquinas_estado_actual(maquina_id, estado_id, fecha, hora, observaciones, usuario_id)
                VALUES (%s,%s,CURDATE(),CURTIME(),%s,%s)
                ON DUPLICATE KEY UPDATE
                  estado_id=VALUES(estado_id), fecha=VALUES(fecha), hora=VALUES(hora),
                  observaciones=VALUES(observaciones), usuario_id=VALUES(usuario_id)
                """,
                (data.maquina_id, estado["id"], data.observaciones, user["id"]),
            )
            cur.execute(
                """
                INSERT INTO maquinas_estado_historial(maquina_id, estado_id, fecha, hora, observaciones, usuario_id)
                VALUES (%s,%s,CURDATE(),CURTIME(),%s,%s)
                """,
                (data.maquina_id, estado["id"], data.observaciones, user["id"]),
            )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {"message": "Estado de máquina actualizado"}

@router.post("/cerrar-salida-empleado")
def cerrar_salida_empleado(empleado_id: int, fecha_jornada: str, user=Depends(require_admin_or_supervisor)):
    execute(
        """
        UPDATE maquina_asignaciones
        SET activo=0, hora_fin=CURTIME()
        WHERE empleado_id=%s AND fecha_jornada=%s AND activo=1
        """,
        (empleado_id, fecha_jornada),
    )
    return {"message": "Asignación cerrada por salida"}

@router.get("/asistencia-matriz")
def asistencia_matriz(mes: int, anio: int, user=Depends(get_current_user)):
    empleados = fetch_all(
        """
        SELECT id, numero_nomina, nombre, puesto, departamento
        FROM empleados
        WHERE activo=1 AND UPPER(IFNULL(departamento,''))=UPPER('MOLINOS')
        ORDER BY puesto, nombre
        """
    )
    rows = []
    for e in empleados:
        registros = fetch_all(
            """
            SELECT fecha_jornada, tipo
            FROM asistencias
            WHERE empleado_id=%s AND MONTH(fecha_jornada)=%s AND YEAR(fecha_jornada)=%s
            """,
            (e["id"], mes, anio),
        )
        acotaciones = fetch_all(
            """
            SELECT ea.fecha, ac.clave
            FROM empleados_acotaciones ea
            INNER JOIN acotaciones ac ON ac.id=ea.acotacion_id
            WHERE ea.empleado_id=%s AND MONTH(ea.fecha)=%s AND YEAR(ea.fecha)=%s
            """,
            (e["id"], mes, anio),
        )
        dias = {}
        for r in registros:
            dia = r["fecha_jornada"].day
            if r["tipo"] == "entrada":
                dias[dia] = "A"
            elif r["tipo"] == "salida":
                dias[dia] = dias.get(dia, "A")
        for a in acotaciones:
            dias[a["fecha"].day] = a["clave"]
        e["dias"] = dias
        rows.append(e)
    return {"mes": mes, "anio": anio, "empleados": rows}
