from collections import defaultdict
from datetime import datetime, time, date, timedelta
import re
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from app.database import fetch_all, fetch_one, execute, get_connection
from app.dependencies import get_current_user, require_admin_or_supervisor

router = APIRouter()


class FechaJornadaIn(BaseModel):
    fecha_jornada: str


class AsignarEmpleadoIn(BaseModel):
    empleado_id: int
    maquina_id: int | None = None
    fecha_jornada: str


class CambiarEstadoMaquinaIn(BaseModel):
    maquina_id: int
    estado: str
    observaciones: str | None = None
    mantenimiento: str | None = None
    mantenimiento_id: int | None = None
    descripcion_preven: str | None = None
    descripcion_correc: str | None = None
    dias: int | None = None
    fecha_proxima: str | None = None


def _es_supervisor_o_encargado(puesto: str | None) -> bool:
    texto = (puesto or '').upper()
    return 'SUPERVISOR' in texto or 'ENCARGAD' in texto


def _es_lavador(puesto: str | None) -> bool:
    return 'LAVADOR' in (puesto or '').upper()


def _time_to_min(value) -> int | None:
    if value is None:
        return None
    if isinstance(value, time):
        return value.hour * 60 + value.minute
    text = str(value)[:5]
    try:
        h, m = text.split(':')[:2]
        return int(h) * 60 + int(m)
    except Exception:
        return None


def _segments(start: int, end: int):
    if start == end:
        return [(0, 1440)]
    if start < end:
        return [(start, end)]
    return [(start, 1440), (0, end)]


def _overlap(start_a, end_a, start_b, end_b) -> bool:
    a1 = _time_to_min(start_a)
    a2 = _time_to_min(end_a)
    b1 = _time_to_min(start_b)
    b2 = _time_to_min(end_b)
    if a1 is None or a2 is None or b1 is None or b2 is None:
        return False
    for x1, x2 in _segments(a1, a2):
        for y1, y2 in _segments(b1, b2):
            if max(x1, y1) < min(x2, y2):
                return True
    return False


def _en_horario(start, end) -> bool:
    inicio = _time_to_min(start)
    fin = _time_to_min(end)
    if inicio is None or fin is None:
        return True
    ahora = datetime.now().hour * 60 + datetime.now().minute
    for s, e in _segments(inicio, fin):
        if s <= ahora < e:
            return True
    return False


def _turno_por_concluir(start, end, minutos_alerta: int = 10) -> bool:
    inicio = _time_to_min(start)
    fin = _time_to_min(end)
    if inicio is None or fin is None:
        return False
    ahora = datetime.now().hour * 60 + datetime.now().minute
    # Si el turno cruza medianoche, normalizamos el final hacia el futuro.
    for s, e in _segments(inicio, fin):
        actual = ahora
        if inicio > fin and s == 0 and ahora < fin:
            actual = ahora
        if s <= actual < e:
            faltan = e - actual
            return 0 <= faltan <= minutos_alerta
    if inicio > fin and ahora >= inicio:
        faltan = (1440 - ahora) + fin
        return 0 <= faltan <= minutos_alerta
    return False


def _turnos_catalogo():
    return fetch_all(
        """
        SELECT id, UPPER(nombre) AS nombre,
               TIME_FORMAT(hora_inicio, '%%H:%%i') AS hora_inicio,
               TIME_FORMAT(hora_fin, '%%H:%%i') AS hora_fin,
               color
        FROM turnos
        WHERE activo = 1
        ORDER BY id
        """
    )


def _turnos_visibles(turno_nombre, hora_inicio, hora_fin, catalogo):
    visibles = []
    if hora_inicio and hora_fin:
        for turno in catalogo:
            if _overlap(hora_inicio, hora_fin, turno.get('hora_inicio'), turno.get('hora_fin')):
                visibles.append(turno['nombre'])
    if not visibles and turno_nombre:
        visibles.append(str(turno_nombre).upper())
    return visibles


def _dias_desde_tiempo_mant(tiempo_mant: str | None) -> int | None:
    """Convierte textos como '7', '7 dias', '2 semanas', '1 mes' a días."""
    if not tiempo_mant:
        return None
    text = str(tiempo_mant).strip().lower()
    match = re.search(r'(\d+)', text)
    if not match:
        return None
    cantidad = int(match.group(1))
    if cantidad < 0:
        return None
    if 'sem' in text:
        return cantidad * 7
    if 'mes' in text:
        return cantidad * 30
    if 'año' in text or 'ano' in text or 'year' in text:
        return cantidad * 365
    return cantidad


def _fecha_proxima_desde_tiempo(tiempo_mant: str | None) -> str | None:
    dias = _dias_desde_tiempo_mant(tiempo_mant)
    if dias is None:
        return None
    return (date.today() + timedelta(days=dias)).strftime('%Y-%m-%d')


@router.get('/mantenimientos')
def listar_mantenimientos_molinos(user=Depends(get_current_user)):
    return {
        'mantenimientos': fetch_all(
            """
            SELECT m.id,
                   m.tipo_mant,
                   m.tiempo_mant,
                   m.id_area,
                   a.nombre AS area
            FROM mantenimientos m
            INNER JOIN areas a ON a.id = m.id_area
            WHERE UPPER(a.nombre) = UPPER('MOLINOS')
              AND (m.activo IS NULL OR m.activo IN ('1', 'S', 'SI', 'A', 'Y'))
            ORDER BY m.tipo_mant
            """
        )
    }


def _turno_por_hora(hora_texto, catalogo):
    minuto = _time_to_min(hora_texto)
    if minuto is None:
        return None
    for turno in catalogo:
        inicio = _time_to_min(turno.get('hora_inicio'))
        fin = _time_to_min(turno.get('hora_fin'))
        if inicio is None or fin is None:
            continue
        for s, e in _segments(inicio, fin):
            if s <= minuto < e:
                return turno['nombre']
    return None


def _sincronizar_turnos_fecha(fecha_jornada: str) -> int:
    """Vincula empleados_turnos_rotacion con empleados_turnos para la fecha indicada."""
    rows = fetch_all(
        """
        SELECT r.empleado_id, r.turno_id, r.semana_orden,
               COALESCE(r.fecha_inicio, %s) AS fecha_inicio_base
        FROM empleados_turnos_rotacion r
        WHERE r.activo = 1
          AND (r.fecha_inicio IS NULL OR r.fecha_inicio <= %s)
          AND (r.fecha_fin IS NULL OR r.fecha_fin >= %s)
        ORDER BY r.empleado_id, r.semana_orden
        """,
        (fecha_jornada, fecha_jornada, fecha_jornada),
    )
    if not rows:
        return 0

    por_empleado = defaultdict(list)
    for row in rows:
        por_empleado[row['empleado_id']].append(row)

    try:
        fecha = datetime.strptime(fecha_jornada, '%Y-%m-%d').date()
    except ValueError:
        raise HTTPException(status_code=400, detail='fecha_jornada debe tener formato YYYY-MM-DD')

    actualizados = 0
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            for empleado_id, rotaciones in por_empleado.items():
                rotaciones = sorted(rotaciones, key=lambda r: int(r['semana_orden'] or 1))
                base = rotaciones[0]['fecha_inicio_base']
                base_date = datetime.strptime(str(base)[:10], '%Y-%m-%d').date()
                weeks = max(0, (fecha - base_date).days // 7)
                elegido = rotaciones[weeks % len(rotaciones)]

                cur.execute(
                    """
                    UPDATE empleados_turnos
                    SET activo = 0, fecha_fin = DATE_SUB(%s, INTERVAL 1 DAY)
                    WHERE empleado_id = %s AND activo = 1 AND turno_id <> %s
                    """,
                    (fecha_jornada, empleado_id, elegido['turno_id']),
                )
                cur.execute(
                    """
                    INSERT INTO empleados_turnos(empleado_id, turno_id, fecha_inicio, fecha_fin, activo)
                    SELECT %s, %s, %s, NULL, 1
                    WHERE NOT EXISTS (
                      SELECT 1 FROM empleados_turnos
                      WHERE empleado_id = %s AND turno_id = %s AND activo = 1
                    )
                    """,
                    (empleado_id, elegido['turno_id'], fecha_jornada, empleado_id, elegido['turno_id']),
                )
                actualizados += 1
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return actualizados


def _cambiar_estado_tx(cur, maquina_id: int, estado_clave: str, observaciones: str | None, usuario_id: int, empleado_id: int | None = None):
    cur.execute('SELECT id FROM maquina_estados WHERE clave = %s', (estado_clave,))
    estado = cur.fetchone()
    if not estado:
        raise HTTPException(status_code=404, detail='Estado no encontrado')

    cur.execute(
        """
        INSERT INTO maquinas_estado_actual(maquina_id, estado_id, fecha, hora, observaciones, usuario_id, empleado_id)
        VALUES (%s, %s, CURDATE(), CURTIME(), %s, %s, %s)
        ON DUPLICATE KEY UPDATE
          estado_id = VALUES(estado_id),
          fecha = VALUES(fecha),
          hora = VALUES(hora),
          observaciones = VALUES(observaciones),
          usuario_id = VALUES(usuario_id),
          empleado_id = VALUES(empleado_id)
        """,
        (maquina_id, estado['id'], observaciones, usuario_id, empleado_id),
    )
    cur.execute(
        """
        INSERT INTO maquinas_estado_historial(maquina_id, estado_id, fecha, hora, observaciones, usuario_id, empleado_id)
        VALUES (%s, %s, CURDATE(), CURTIME(), %s, %s, %s)
        """,
        (maquina_id, estado['id'], observaciones, usuario_id, empleado_id),
    )


def _cerrar_bitacora_mantenimiento_tx(cur, maquina_id: int, descripcion_correc: str | None):
    """Cierra la última bitácora abierta cuando una máquina sale de mantenimiento."""
    cur.execute('SELECT nombre FROM maquinas WHERE id = %s', (maquina_id,))
    maquina = cur.fetchone()
    if not maquina:
        return

    cur.execute(
        """
        SELECT id, fecha_inicio, hora_inicio
        FROM bitacoras
        WHERE UPPER(TRIM(maquina)) = UPPER(TRIM(%s))
          AND (status_manto IS NULL OR UPPER(status_manto) NOT IN ('TERMINO', 'TERMINADO', 'CERRADO'))
        ORDER BY fecha_inicio DESC, hora_inicio DESC, id DESC
        LIMIT 1
        """,
        (maquina['nombre'],),
    )
    bitacora = cur.fetchone()
    if not bitacora:
        return

    cur.execute(
        """
        UPDATE bitacoras
        SET fecha_termino = CURDATE(),
            Hora_termino = CURTIME(),
            status_manto = 'TERMINO',
            descripcionCorrec = COALESCE(NULLIF(%s, ''), descripcionCorrec),
            tiempo_muerto = TIMEDIFF(CONCAT(CURDATE(), ' ', CURTIME()), CONCAT(fecha_inicio, ' ', hora_inicio))
        WHERE id = %s
        """,
        (descripcion_correc or '', bitacora['id']),
    )


def _insertar_bitacora_mantenimiento_tx(cur, maquina_id: int, data: CambiarEstadoMaquinaIn, usuario_nombre: str | None):
    """Abre una bitácora al poner la máquina en mantenimiento usando el catálogo de mantenimientos."""
    cur.execute('SELECT id, nombre, id_area FROM maquinas WHERE id = %s', (maquina_id,))
    maquina = cur.fetchone()
    if not maquina:
        raise HTTPException(status_code=404, detail='Máquina no encontrada')

    mantenimiento_id = data.mantenimiento_id
    mantenimiento_row = None
    if mantenimiento_id:
        cur.execute(
            """
            SELECT id, tipo_mant, tiempo_mant, id_area
            FROM mantenimientos
            WHERE id = %s
              AND id_area = %s
              AND (activo IS NULL OR activo IN ('1', 'S', 'SI', 'A', 'Y'))
            LIMIT 1
            """,
            (mantenimiento_id, maquina['id_area']),
        )
        mantenimiento_row = cur.fetchone()
        if not mantenimiento_row:
            raise HTTPException(status_code=400, detail='El mantenimiento no pertenece al área MOLINOS o no está activo')

    tiempo_mant = (mantenimiento_row or {}).get('tiempo_mant') if mantenimiento_row else None
    dias_catalogo = _dias_desde_tiempo_mant(tiempo_mant)
    dias = data.dias if data.dias is not None and data.dias >= 0 else dias_catalogo
    fecha_proxima = data.fecha_proxima or _fecha_proxima_desde_tiempo(tiempo_mant)
    mantenimiento = (
        (mantenimiento_row or {}).get('tipo_mant')
        or data.mantenimiento
        or data.observaciones
        or 'Mantenimiento'
    ).strip()
    descripcion_preven = (data.descripcion_preven or data.observaciones or '').strip()

    # Evita abrir duplicada si ya existe una bitácora activa para la máquina.
    cur.execute(
        """
        SELECT id
        FROM bitacoras
        WHERE UPPER(TRIM(maquina)) = UPPER(TRIM(%s))
          AND (status_manto IS NULL OR UPPER(status_manto) NOT IN ('TERMINO', 'TERMINADO', 'CERRADO'))
        ORDER BY id DESC
        LIMIT 1
        """,
        (maquina['nombre'],),
    )
    existente = cur.fetchone()
    if existente:
        cur.execute(
            """
            UPDATE bitacoras
            SET mantenimiento = %s,
                mantenimiento_id = COALESCE(%s, mantenimiento_id),
                tiempo_mant = COALESCE(%s, tiempo_mant),
                descripcionPreven = COALESCE(NULLIF(%s, ''), descripcionPreven),
                Dias = COALESCE(%s, Dias),
                fecha_proxima = COALESCE(%s, fecha_proxima),
                status_manto = 'MANTENIMIENTO'
            WHERE id = %s
            """,
            (mantenimiento, mantenimiento_id, tiempo_mant, descripcion_preven, dias, fecha_proxima, existente['id']),
        )
        return

    cur.execute(
        """
        INSERT INTO bitacoras(
            maquina, fecha_inicio, hora_inicio, mantenimiento, mantenimiento_id,
            tiempo_mant, descripcionPreven, operador, Supervisor, usuario, numero,
            fecha_proxima, Dias, area_id, status_manto
        )
        VALUES (
            %s, CURDATE(), CURTIME(), %s, %s,
            %s, %s, %s, %s, %s, CONCAT('MANTO-', DATE_FORMAT(NOW(), '%%Y%%m%%d%%H%%i%%s')),
            %s, %s, %s, 'MANTENIMIENTO'
        )
        """,
        (
            maquina['nombre'], mantenimiento, mantenimiento_id,
            tiempo_mant, descripcion_preven,
            usuario_nombre, usuario_nombre, usuario_nombre,
            fecha_proxima, dias, maquina['id_area'] or 1,
        ),
    )


@router.get('/tablero')
def tablero(fecha_jornada: str, user=Depends(get_current_user)):
    _sincronizar_turnos_fecha(fecha_jornada)
    catalogo_turnos = _turnos_catalogo()

    maquinas = fetch_all(
        """
        SELECT m.id, m.nombre, m.descripcion, m.id_area,
               COALESCE(me.clave, 'trabajando') AS estado,
               COALESCE(me.nombre, 'Trabajando') AS estado_nombre,
               COALESCE(me.color, 'verde') AS estado_color,
               DATE_FORMAT(mea.fecha, '%%Y-%%m-%%d') AS estado_fecha_inicio,
               TIME_FORMAT(mea.hora, '%%H:%%i') AS estado_hora_inicio,
               mea.observaciones AS estado_observaciones,
               mea.empleado_id AS estado_empleado_id,
               (
                 SELECT DATE_FORMAT(b.fecha_proxima, '%%Y-%%m-%%d')
                 FROM bitacoras b
                 WHERE (UPPER(TRIM(b.maquina)) = UPPER(TRIM(m.nombre))
                    OR UPPER(TRIM(b.maquina)) LIKE CONCAT('%%', UPPER(TRIM(m.nombre)), '%%'))
                   AND b.fecha_proxima IS NOT NULL
                   AND (b.status_manto IS NULL OR UPPER(b.status_manto) NOT IN ('TERMINO', 'TERMINADO', 'CERRADO'))
                 ORDER BY b.fecha_proxima ASC
                 LIMIT 1
               ) AS mantenimiento_fecha_proxima,
               (
                 SELECT b.mantenimiento
                 FROM bitacoras b
                 WHERE (UPPER(TRIM(b.maquina)) = UPPER(TRIM(m.nombre))
                    OR UPPER(TRIM(b.maquina)) LIKE CONCAT('%%', UPPER(TRIM(m.nombre)), '%%'))
                   AND b.fecha_proxima IS NOT NULL
                   AND (b.status_manto IS NULL OR UPPER(b.status_manto) NOT IN ('TERMINO', 'TERMINADO', 'CERRADO'))
                 ORDER BY b.fecha_proxima ASC
                 LIMIT 1
               ) AS mantenimiento_proximo,
               EXISTS(
                 SELECT 1 FROM bitacoras b
                 WHERE (UPPER(TRIM(b.maquina)) = UPPER(TRIM(m.nombre))
                    OR UPPER(TRIM(b.maquina)) LIKE CONCAT('%%', UPPER(TRIM(m.nombre)), '%%'))
                   AND b.fecha_proxima IS NOT NULL
                   AND b.fecha_proxima BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 3 DAY)
                   AND (b.status_manto IS NULL OR UPPER(b.status_manto) NOT IN ('TERMINO', 'TERMINADO', 'CERRADO'))
               ) AS mantenimiento_alerta
        FROM maquinas m
        INNER JOIN areas a ON a.id = m.id_area
        LEFT JOIN maquinas_estado_actual mea ON mea.maquina_id = m.id
        LEFT JOIN maquina_estados me ON me.id = mea.estado_id
        WHERE m.activo = 1 AND UPPER(a.nombre) = UPPER('MOLINOS')
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
          UPPER(t.nombre) AS turno,
          t.color AS turno_color,
          TIME_FORMAT(t.hora_inicio, '%%H:%%i') AS turno_hora_inicio,
          TIME_FORMAT(t.hora_fin, '%%H:%%i') AS turno_hora_fin,
          ma.maquina_id,
          m.nombre AS maquina_nombre,
          TIME_FORMAT(ma.hora_inicio, '%%H:%%i') AS hora_inicio_maquina,
          TIME_FORMAT(ma.hora_fin, '%%H:%%i') AS hora_fin_maquina,
          ac.clave AS acotacion,
          ac.descripcion AS acotacion_descripcion,
          ac.color AS acotacion_color,
          EXISTS(
            SELECT 1 FROM asistencias ae
            WHERE ae.empleado_id = e.id AND ae.fecha_jornada = %s AND ae.tipo = 'entrada'
          ) AS presente,
          EXISTS(
            SELECT 1 FROM asistencias as2
            WHERE as2.empleado_id = e.id AND as2.fecha_jornada = %s AND as2.tipo = 'salida'
          ) AS checo_salida,
          (
            SELECT TIME_FORMAT(ae.hora, '%%H:%%i')
            FROM asistencias ae
            WHERE ae.empleado_id = e.id AND ae.fecha_jornada = %s AND ae.tipo = 'entrada'
            ORDER BY ae.hora ASC LIMIT 1
          ) AS hora_entrada,
          (
            SELECT TIME_FORMAT(sc.hora, '%%H:%%i')
            FROM asistencias sc
            WHERE sc.empleado_id = e.id AND sc.fecha_jornada = %s AND sc.tipo = 'salida_comida'
            ORDER BY sc.hora ASC LIMIT 1
          ) AS hora_salida_comida,
          (
            SELECT TIME_FORMAT(ec.hora, '%%H:%%i')
            FROM asistencias ec
            WHERE ec.empleado_id = e.id AND ec.fecha_jornada = %s AND ec.tipo = 'entrada_comida'
            ORDER BY ec.hora ASC LIMIT 1
          ) AS hora_regreso_comida,
          (
            SELECT TIME_FORMAT(as2.hora, '%%H:%%i')
            FROM asistencias as2
            WHERE as2.empleado_id = e.id AND as2.fecha_jornada = %s AND as2.tipo = 'salida'
            ORDER BY as2.hora DESC LIMIT 1
          ) AS hora_salida
        FROM empleados e
        LEFT JOIN empleados_turnos et
          ON et.empleado_id = e.id
         AND et.activo = 1
         AND et.fecha_inicio <= %s
         AND (et.fecha_fin IS NULL OR et.fecha_fin >= %s)
        LEFT JOIN turnos t ON t.id = et.turno_id
        LEFT JOIN maquina_asignaciones ma
          ON ma.id = (
            SELECT ma2.id
            FROM maquina_asignaciones ma2
            WHERE ma2.empleado_id = e.id
              AND ma2.activo = 1
              AND ma2.fecha_jornada <= %s
            ORDER BY ma2.fecha_jornada DESC, ma2.id DESC
            LIMIT 1
          )
        LEFT JOIN maquinas m ON m.id = ma.maquina_id
        LEFT JOIN empleados_acotaciones ea ON ea.empleado_id = e.id AND ea.fecha = %s
        LEFT JOIN acotaciones ac ON ac.id = ea.acotacion_id
        WHERE UPPER(IFNULL(e.departamento, '')) = UPPER('MOLINOS')
          AND e.activo = 1
        ORDER BY t.nombre, e.puesto, e.nombre ASC
        """,
        (fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada, fecha_jornada),
    )

    por_maquina = defaultdict(list)
    supervisores = []
    empleados_turno = []
    espera = []
    ausentes = []
    alertas = []

    for empleado in empleados:
        empleado['presente'] = bool(empleado['presente'])
        empleado['checo_salida'] = bool(empleado['checo_salida'])
        empleado['turnos_visibles'] = _turnos_visibles(
            empleado.get('turno'),
            empleado.get('turno_hora_inicio'),
            empleado.get('turno_hora_fin'),
            catalogo_turnos,
        )
        empleado['turno_en_horario'] = _en_horario(empleado.get('turno_hora_inicio'), empleado.get('turno_hora_fin'))
        empleado['turno_por_concluir'] = _turno_por_concluir(empleado.get('turno_hora_inicio'), empleado.get('turno_hora_fin'))
        empleados_turno.append(empleado)

        # La asignación a máquina permanece hasta que el usuario arrastre el empleado a espera.
        # La salida de asistencia no borra la máquina asignada porque debe permanecer para el siguiente día.

        if empleado['acotacion']:
            alertas.append(empleado)

        if _es_supervisor_o_encargado(empleado['puesto']):
            # Los encargados/supervisores se muestran arriba aunque aún no sea su hora
            # o aunque todavía no hayan checado entrada, para respetar la pestaña del turno.
            supervisores.append(empleado)
            if not empleado['presente']:
                ausentes.append(empleado)
            continue

        if empleado['maquina_id']:
            # Si ya está asignado a un molino se muestra en el molino, esté o no dentro
            # del rango exacto de hora del turno.
            por_maquina[empleado['maquina_id']].append(empleado)
            if not empleado['presente']:
                ausentes.append(empleado)
        else:
            # Debe aparecer en la lista del turno asignado aunque aún no sea su turno.
            espera.append(empleado)
            if not empleado['presente']:
                ausentes.append(empleado)

    for maquina in maquinas:
        maquina['empleados'] = por_maquina.get(maquina['id'], [])

    return {
        'fecha_jornada': fecha_jornada,
        'maquinas': maquinas,
        'supervisores': supervisores,
        'empleados_turno': empleados_turno,
        'espera': espera,
        'ausentes': ausentes,
        'alertas': alertas,
    }


@router.post('/sincronizar-turnos')
def sincronizar_turnos(data: FechaJornadaIn, user=Depends(require_admin_or_supervisor)):
    actualizados = _sincronizar_turnos_fecha(data.fecha_jornada)
    return {'message': 'Turnos sincronizados', 'actualizados': actualizados}


@router.post('/asignar')
def asignar(data: AsignarEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    if data.maquina_id is None:
        raise HTTPException(status_code=400, detail='maquina_id es requerido')

    empleado = fetch_one('SELECT id, puesto FROM empleados WHERE id = %s AND activo = 1', (data.empleado_id,))
    if not empleado:
        raise HTTPException(status_code=404, detail='Empleado no encontrado')

    maquina = fetch_one('SELECT id FROM maquinas WHERE id = %s AND activo = 1', (data.maquina_id,))
    if not maquina:
        raise HTTPException(status_code=404, detail='Máquina no encontrada')

    salida = fetch_one(
        "SELECT id FROM asistencias WHERE empleado_id = %s AND fecha_jornada = %s AND tipo = 'salida' LIMIT 1",
        (data.empleado_id, data.fecha_jornada),
    )
    if salida:
        raise HTTPException(status_code=400, detail='El empleado ya checó salida')

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE maquina_asignaciones
                SET activo = 0, hora_fin = IFNULL(hora_fin, CURTIME())
                WHERE empleado_id = %s AND activo = 1
                """,
                (data.empleado_id,),
            )
            cur.execute(
                """
                INSERT INTO maquina_asignaciones(empleado_id, maquina_id, fecha_jornada, hora_inicio, activo, usuario_id)
                VALUES (%s, %s, %s, CURTIME(), 1, %s)
                """,
                (data.empleado_id, data.maquina_id, data.fecha_jornada, user['id']),
            )
            if _es_lavador(empleado['puesto']):
                _cambiar_estado_tx(
                    cur,
                    data.maquina_id,
                    'limpieza',
                    'Lavador asignado: inicia limpieza',
                    user['id'],
                    data.empleado_id,
                )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {'message': 'Empleado asignado a máquina'}


@router.post('/quitar-empleado')
def quitar_empleado(data: AsignarEmpleadoIn, user=Depends(require_admin_or_supervisor)):
    activo = fetch_one(
        """
        SELECT ma.maquina_id, e.puesto
        FROM maquina_asignaciones ma
        INNER JOIN empleados e ON e.id = ma.empleado_id
        WHERE ma.empleado_id = %s AND ma.activo = 1
        ORDER BY ma.fecha_jornada DESC, ma.id DESC
        LIMIT 1
        """,
        (data.empleado_id,),
    )

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE maquina_asignaciones
                SET activo = 0, hora_fin = IFNULL(hora_fin, CURTIME())
                WHERE empleado_id = %s AND activo = 1
                """,
                (data.empleado_id,),
            )
            if activo and _es_lavador(activo.get('puesto')):
                cur.execute(
                    """
                    SELECT COUNT(*) AS total
                    FROM maquina_asignaciones ma
                    INNER JOIN empleados e ON e.id = ma.empleado_id
                    WHERE ma.maquina_id = %s
                      AND ma.activo = 1
                      AND UPPER(IFNULL(e.puesto, '')) LIKE '%%LAVADOR%%'
                    """,
                    (activo['maquina_id'],),
                )
                total = cur.fetchone()['total']
                if int(total or 0) == 0:
                    _cambiar_estado_tx(
                        cur,
                        activo['maquina_id'],
                        'trabajando',
                        'Limpieza terminada: lavador regresado a espera',
                        user['id'],
                        data.empleado_id,
                    )
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {'message': 'Empleado enviado a espera'}


@router.post('/maquina-estado')
def cambiar_estado(data: CambiarEstadoMaquinaIn, user=Depends(require_admin_or_supervisor)):
    estado_nuevo = (data.estado or '').lower().strip()
    estado_actual = fetch_one(
        """
        SELECT me.clave
        FROM maquinas_estado_actual mea
        INNER JOIN maquina_estados me ON me.id = mea.estado_id
        WHERE mea.maquina_id = %s
        LIMIT 1
        """,
        (data.maquina_id,),
    )
    estado_anterior = (estado_actual.get('clave') if estado_actual else '') or ''

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            if estado_anterior.lower() == 'mantenimiento' and estado_nuevo != 'mantenimiento':
                _cerrar_bitacora_mantenimiento_tx(cur, data.maquina_id, data.descripcion_correc or data.observaciones)

            _cambiar_estado_tx(cur, data.maquina_id, estado_nuevo, data.observaciones, user['id'])

            if estado_nuevo == 'mantenimiento':
                _insertar_bitacora_mantenimiento_tx(cur, data.maquina_id, data, user.get('nombre') or user.get('usuario'))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    return {'message': 'Estado de máquina actualizado'}


@router.get('/maquinas/{maquina_id}/historial')
def historial_maquina(maquina_id: int, fecha_jornada: str, turno: str | None = None, user=Depends(get_current_user)):
    catalogo_turnos = _turnos_catalogo()
    estados = fetch_all(
        """
        SELECT 'estado' AS tipo,
               DATE_FORMAT(h.fecha, '%%Y-%%m-%%d') AS fecha,
               TIME_FORMAT(h.hora, '%%H:%%i') AS hora,
               me.nombre AS titulo,
               CONCAT(me.clave, IF(e.nombre IS NULL, '', CONCAT(' · ', e.nombre))) AS subtitulo,
               h.observaciones
        FROM maquinas_estado_historial h
        INNER JOIN maquina_estados me ON me.id = h.estado_id
        LEFT JOIN empleados e ON e.id = h.empleado_id
        WHERE h.maquina_id = %s AND h.fecha = %s
        ORDER BY h.fecha DESC, h.hora DESC, h.id DESC
        """,
        (maquina_id, fecha_jornada),
    )
    for row in estados:
        row['turno'] = _turno_por_hora(row.get('hora'), catalogo_turnos) or ''

    asignaciones = fetch_all(
        """
        SELECT 'asignacion' AS tipo,
               DATE_FORMAT(a.fecha_jornada, '%%Y-%%m-%%d') AS fecha,
               TIME_FORMAT(a.hora_inicio, '%%H:%%i') AS hora,
               e.nombre AS titulo,
               e.puesto AS subtitulo,
               UPPER(t.nombre) AS turno,
               TIME_FORMAT(t.hora_inicio, '%%H:%%i') AS turno_hora_inicio,
               TIME_FORMAT(t.hora_fin, '%%H:%%i') AS turno_hora_fin,
               CONCAT('Inicio: ', TIME_FORMAT(a.hora_inicio, '%%H:%%i'),
                      IF(a.hora_fin IS NULL, '', CONCAT(' / Fin: ', TIME_FORMAT(a.hora_fin, '%%H:%%i')))) AS observaciones
        FROM maquina_asignaciones a
        INNER JOIN empleados e ON e.id = a.empleado_id
        LEFT JOIN empleados_turnos et
          ON et.empleado_id = e.id
         AND et.fecha_inicio <= a.fecha_jornada
         AND (et.fecha_fin IS NULL OR et.fecha_fin >= a.fecha_jornada)
        LEFT JOIN turnos t ON t.id = et.turno_id
        WHERE a.maquina_id = %s AND a.fecha_jornada = %s
        ORDER BY a.hora_inicio DESC, a.id DESC
        """,
        (maquina_id, fecha_jornada),
    )

    for row in asignaciones:
        visibles = _turnos_visibles(row.get('turno'), row.get('turno_hora_inicio'), row.get('turno_hora_fin'), catalogo_turnos)
        row['turnos_visibles'] = visibles
        row['turno'] = ', '.join(visibles) if visibles else (row.get('turno') or '')

    mantenimientos = fetch_all(
        """
        SELECT 'mantenimiento' AS tipo,
               DATE_FORMAT(b.fecha_inicio, '%%Y-%%m-%%d') AS fecha,
               TIME_FORMAT(b.hora_inicio, '%%H:%%i') AS hora,
               COALESCE(b.mantenimiento, 'Mantenimiento') AS titulo,
               CONCAT('Operador: ', IFNULL(b.operador, ''),
                      ' / Supervisor: ', IFNULL(b.Supervisor, ''),
                      ' / Status: ', IFNULL(b.status_manto, '')) AS subtitulo,
               CONCAT(
                 'Preventivo: ', IFNULL(b.descripcionPreven, ''),
                 ' / Correctivo: ', IFNULL(b.descripcionCorrec, ''),
                 IF(b.Dias IS NULL, '', CONCAT(' / Días: ', b.Dias)),
                 IF(b.tiempo_mant IS NULL OR b.tiempo_mant = '', '', CONCAT(' / Frecuencia: ', b.tiempo_mant)),
                 IF(b.fecha_proxima IS NULL, '', CONCAT(' / Próximo: ', DATE_FORMAT(b.fecha_proxima, '%%Y-%%m-%%d'))),
                 IF(b.fecha_termino IS NULL, '', CONCAT(' / Termina: ', DATE_FORMAT(b.fecha_termino, '%%Y-%%m-%%d'), ' ', IFNULL(TIME_FORMAT(b.Hora_termino, '%%H:%%i'), ''))),
                 IF(b.tiempo_muerto IS NULL, '', CONCAT(' / Tiempo muerto: ', TIME_FORMAT(b.tiempo_muerto, '%%H:%%i')))
               ) AS observaciones,
               '' AS turno
        FROM bitacoras b
        INNER JOIN maquinas m ON m.id = %s
        WHERE UPPER(TRIM(b.maquina)) = UPPER(TRIM(m.nombre))
           OR UPPER(TRIM(b.maquina)) LIKE CONCAT('%%', UPPER(TRIM(m.nombre)), '%%')
        ORDER BY b.fecha_inicio DESC, b.hora_inicio DESC, b.id DESC
        LIMIT 100
        """,
        (maquina_id,),
    )

    historial = list(estados or []) + list(asignaciones or []) + list(mantenimientos or [])
    filtro = (turno or '').upper().strip()
    if filtro and filtro != 'TODOS':
        historial = [
            r for r in historial
            if r.get('tipo') == 'mantenimiento'
            or filtro == (r.get('turno') or '').upper().strip()
            or filtro in [x.upper().strip() for x in (r.get('turnos_visibles') or [])]
        ]
    historial.sort(key=lambda r: (r.get('fecha') or '', r.get('hora') or ''), reverse=True)
    return {'historial': historial}


@router.get('/asistencia-matriz')
def asistencia_matriz(mes: int, anio: int, user=Depends(get_current_user)):
    empleados = fetch_all(
        """
        SELECT id, numero_nomina, nombre, puesto, departamento
        FROM empleados
        WHERE activo = 1 AND UPPER(IFNULL(departamento, '')) = UPPER('MOLINOS')
        ORDER BY puesto, nombre
        """
    )
    rows = []
    for empleado in empleados:
        registros = fetch_all(
            """
            SELECT fecha_jornada, tipo
            FROM asistencias
            WHERE empleado_id = %s AND MONTH(fecha_jornada) = %s AND YEAR(fecha_jornada) = %s
            """,
            (empleado['id'], mes, anio),
        )
        acotaciones = fetch_all(
            """
            SELECT ea.fecha, ac.clave
            FROM empleados_acotaciones ea
            INNER JOIN acotaciones ac ON ac.id = ea.acotacion_id
            WHERE ea.empleado_id = %s AND MONTH(ea.fecha) = %s AND YEAR(ea.fecha) = %s
            """,
            (empleado['id'], mes, anio),
        )
        dias = {}
        for registro in registros:
            dia = registro['fecha_jornada'].day
            if registro['tipo'] == 'entrada':
                dias[dia] = 'A'
            elif registro['tipo'] == 'salida':
                dias[dia] = dias.get(dia, 'A')
        for acotacion in acotaciones:
            dias[acotacion['fecha'].day] = acotacion['clave']
        empleado['dias'] = dias
        rows.append(empleado)
    return {'mes': mes, 'anio': anio, 'empleados': rows}
