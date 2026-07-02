import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/empleado_molinos.dart';
import '../models/maquina_molinos.dart';
import 'api_service.dart';

class TableroMolinos {
  final DateTime? fechaJornada;
  final int? semanaAnio;
  final List<MaquinaMolinos> maquinas;
  final List<EmpleadoMolinos> supervisores;
  final List<EmpleadoMolinos> empleadosTurno;
  final List<EmpleadoMolinos> espera;
  final List<EmpleadoMolinos> ausentes;
  final List<EmpleadoMolinos> alertas;

  const TableroMolinos({
    this.fechaJornada,
    this.semanaAnio,
    required this.maquinas,
    required this.supervisores,
    required this.empleadosTurno,
    required this.espera,
    required this.ausentes,
    required this.alertas,
  });

  factory TableroMolinos.fromJson(Map<String, dynamic> json) {
    List<EmpleadoMolinos> empleadosFrom(dynamic value) {
      return (value as List? ?? [])
          .map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return TableroMolinos(
      fechaJornada: DateTime.tryParse((json['fecha_jornada'] ?? '').toString()),
      semanaAnio: _toInt(json['semana_anio']),
      maquinas: (json['maquinas'] as List? ?? [])
          .map((e) => MaquinaMolinos.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      supervisores: empleadosFrom(json['supervisores']),
      empleadosTurno: empleadosFrom(json['empleados_turno']),
      espera: empleadosFrom(json['espera']),
      ausentes: empleadosFrom(json['ausentes']),
      alertas: empleadosFrom(json['alertas']),
    );
  }
}

class MaquinaHistorialMolino {
  final String tipo;
  final String fecha;
  final String hora;
  final String titulo;
  final String? subtitulo;
  final String? observaciones;
  final String? turno;
  final int? bitacoraId;
  final String? fechaProxima;
  final String? fechaTermino;
  final String? horaTermino;
  final String? tiempoMuerto;
  final int? dias;
  final int? diasRestantes;
  final String? semaforo;
  final String? statusManto;
  final String? descripcionPreven;
  final String? descripcionCorrec;
  final String? operador;
  final String? supervisor;
  final String? usuario;
  final String? numero;

  const MaquinaHistorialMolino({
    required this.tipo,
    required this.fecha,
    required this.hora,
    required this.titulo,
    this.subtitulo,
    this.observaciones,
    this.turno,
    this.bitacoraId,
    this.fechaProxima,
    this.fechaTermino,
    this.horaTermino,
    this.tiempoMuerto,
    this.dias,
    this.diasRestantes,
    this.semaforo,
    this.statusManto,
    this.descripcionPreven,
    this.descripcionCorrec,
    this.operador,
    this.supervisor,
    this.usuario,
    this.numero,
  });

  factory MaquinaHistorialMolino.fromJson(Map<String, dynamic> json) {
    return MaquinaHistorialMolino(
      tipo: (json['tipo'] ?? '').toString(),
      fecha: (json['fecha'] ?? '').toString(),
      hora: (json['hora'] ?? '').toString(),
      titulo: (json['titulo'] ?? '').toString(),
      subtitulo: _nullable(json['subtitulo']),
      observaciones: _nullable(json['observaciones']),
      turno: _nullable(json['turno']),
      bitacoraId: _intOrNull(json['bitacora_id']),
      fechaProxima: _nullable(json['fecha_proxima']),
      fechaTermino: _nullable(json['fecha_termino']),
      horaTermino: _nullable(json['hora_termino']),
      tiempoMuerto: _nullable(json['tiempo_muerto']),
      dias: _intOrNull(json['dias']),
      diasRestantes: _intOrNull(json['dias_restantes']),
      semaforo: _nullable(json['semaforo']),
      statusManto: _nullable(json['status_manto']),
      descripcionPreven: _nullable(json['descripcion_preven']),
      descripcionCorrec: _nullable(json['descripcion_correc']),
      operador: _nullable(json['operador']),
      supervisor: _nullable(json['supervisor']),
      usuario: _nullable(json['usuario']),
      numero: _nullable(json['numero']),
    );
  }

  static String? _nullable(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  bool get mantenimientoActivo {
    final s = (statusManto ?? '').toUpperCase();
    return tipo == 'mantenimiento' && s != 'TERMINO' && s != 'TERMINADO' && s != 'CERRADO';
  }
}



class MantenimientoMolino {
  final int id;
  final String tipoMant;
  final String tiempoMant;
  final int? idArea;
  final String? area;

  const MantenimientoMolino({
    required this.id,
    required this.tipoMant,
    required this.tiempoMant,
    this.idArea,
    this.area,
  });

  factory MantenimientoMolino.fromJson(Map<String, dynamic> json) {
    return MantenimientoMolino(
      id: _toInt(json['id']) ?? 0,
      tipoMant: (json['tipo_mant'] ?? json['tipoMant'] ?? '').toString(),
      tiempoMant: (json['tiempo_mant'] ?? json['tiempoMant'] ?? '').toString(),
      idArea: _toInt(json['id_area'] ?? json['idArea']),
      area: _toNullableString(json['area']),
    );
  }
}

class TurnoMolino {
  final int id;
  final String nombre;
  final String? horaInicio;
  final String? horaFin;
  final String? color;

  const TurnoMolino({
    required this.id,
    required this.nombre,
    this.horaInicio,
    this.horaFin,
    this.color,
  });

  factory TurnoMolino.fromJson(Map<String, dynamic> json) {
    return TurnoMolino(
      id: _toInt(json['id']) ?? 0,
      nombre: (json['nombre'] ?? '').toString(),
      horaInicio: _toNullableString(json['hora_inicio'] ?? json['horaInicio']),
      horaFin: _toNullableString(json['hora_fin'] ?? json['horaFin']),
      color: _toNullableString(json['color']),
    );
  }
}

class RotacionTurnoMolino {
  final int? id;
  final int? empleadoId;
  final int semanaOrden;
  final int turnoId;
  final String? turno;
  final String? horaInicio;
  final String? horaFin;
  final String? fechaInicio;
  final String? fechaFin;
  final bool activo;

  const RotacionTurnoMolino({
    this.id,
    this.empleadoId,
    required this.semanaOrden,
    required this.turnoId,
    this.turno,
    this.horaInicio,
    this.horaFin,
    this.fechaInicio,
    this.fechaFin,
    this.activo = true,
  });

  factory RotacionTurnoMolino.fromJson(Map<String, dynamic> json) {
    return RotacionTurnoMolino(
      id: _toInt(json['id']),
      empleadoId: _toInt(json['empleado_id'] ?? json['empleadoId']),
      semanaOrden: _toInt(json['semana_orden'] ?? json['semanaOrden']) ?? 1,
      turnoId: _toInt(json['turno_id'] ?? json['turnoId']) ?? 0,
      turno: _toNullableString(json['turno']),
      horaInicio: _toNullableString(json['hora_inicio'] ?? json['horaInicio']),
      horaFin: _toNullableString(json['hora_fin'] ?? json['horaFin']),
      fechaInicio: _toNullableString(json['fecha_inicio'] ?? json['fechaInicio']),
      fechaFin: _toNullableString(json['fecha_fin'] ?? json['fechaFin']),
      activo: json['activo'] == true || json['activo'] == 1 || json['activo']?.toString() == '1',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'semana_orden': semanaOrden,
      'turno_id': turnoId,
      'fecha_inicio': fechaInicio,
      'fecha_fin': fechaFin,
    };
  }
}

int? _toInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse(value.toString());
}

String? _toNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString();
  return text.trim().isEmpty ? null : text;
}

class MolinosService {
  final String token;
  MolinosService(this.token);

  String _fmt(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  Future<TableroMolinos> tablero(DateTime fecha, {String turno = 'TURNO 1', String vista = 'dia'}) async {
    final uri = Uri.parse('${ApiService.baseUrl}/molinos/tablero').replace(
      queryParameters: {
        'fecha_jornada': _fmt(fecha),
        'turno': turno,
        'vista': vista,
      },
    );
    final res = await http.get(
      uri,
      headers: ApiService.headers(token: token),
    );
    return TableroMolinos.fromJson(Map<String, dynamic>.from(ApiService.decode(res)));
  }

  Future<void> sincronizarTurnos(DateTime fecha) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/sincronizar-turnos'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({'fecha_jornada': _fmt(fecha)}),
    );
    ApiService.decode(res);
  }

  Future<void> asignar({
    required int empleadoId,
    required int maquinaId,
    required DateTime fecha,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/asignar'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'empleado_id': empleadoId,
        'maquina_id': maquinaId,
        'fecha_jornada': _fmt(fecha),
      }),
    );
    ApiService.decode(res);
  }

  Future<void> quitarEmpleado({
    required int empleadoId,
    required DateTime fecha,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/quitar-empleado'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'empleado_id': empleadoId,
        'fecha_jornada': _fmt(fecha),
      }),
    );
    ApiService.decode(res);
  }


  Future<List<MantenimientoMolino>> mantenimientosMolinos() async {
    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/molinos/mantenimientos'),
      headers: ApiService.headers(token: token),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return (json['mantenimientos'] as List? ?? [])
        .map((e) => MantenimientoMolino.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<int?> crearMantenimientoMolinos({
    required String tipoMant,
    required String tiempoMant,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/mantenimientos'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'tipo_mant': tipoMant,
        'tiempo_mant': tiempoMant,
        'activo': '1',
      }),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return _toInt(json['id']);
  }

  Future<void> cambiarEstado({
    required int maquinaId,
    required String estado,
    String? observaciones,
    String? mantenimiento,
    int? mantenimientoId,
    String? descripcionPreven,
    String? descripcionCorrec,
    int? dias,
    String? fechaProxima,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/maquina-estado'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'maquina_id': maquinaId,
        'estado': estado,
        'observaciones': observaciones,
        'mantenimiento': mantenimiento,
        'mantenimiento_id': mantenimientoId,
        'descripcion_preven': descripcionPreven,
        'descripcion_correc': descripcionCorrec,
        'dias': dias,
        'fecha_proxima': fechaProxima,
      }),
    );
    ApiService.decode(res);
  }

  Future<Map<String, dynamic>> historialMaquinaDetalle({
    required int maquinaId,
    required DateTime fecha,
    String turno = 'TODOS',
    String vista = 'dia',
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/molinos/maquinas/$maquinaId/historial').replace(
      queryParameters: {'fecha_jornada': _fmt(fecha), 'turno': turno, 'vista': vista},
    );
    final res = await http.get(
      uri,
      headers: ApiService.headers(token: token),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    final historial = (json['historial'] as List? ?? [])
        .map((e) => MaquinaHistorialMolino.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return {...json, 'historial': historial};
  }

  Future<List<MaquinaHistorialMolino>> historialMaquina({
    required int maquinaId,
    required DateTime fecha,
    String turno = 'TODOS',
    String vista = 'dia',
  }) async {
    final data = await historialMaquinaDetalle(maquinaId: maquinaId, fecha: fecha, turno: turno, vista: vista);
    return List<MaquinaHistorialMolino>.from(data['historial'] as List);
  }
  Future<void> cerrarMantenimiento({
    required int maquinaId,
    int? bitacoraId,
    String? descripcionCorrec,
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/maquinas/$maquinaId/mantenimiento/cerrar'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'bitacora_id': bitacoraId,
        'descripcion_correc': descripcionCorrec,
      }),
    );
    ApiService.decode(res);
  }



  Future<List<EmpleadoMolinos>> empleados({String q = '', String turno = 'TODOS'}) async {
    final uri = Uri.parse('${ApiService.baseUrl}/molinos/empleados').replace(
      queryParameters: {'q': q, 'turno': turno},
    );
    final res = await http.get(uri, headers: ApiService.headers(token: token));
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return (json['empleados'] as List? ?? [])
        .map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<int?> crearEmpleado({
    required String numeroNomina,
    required String nombre,
    String? puesto,
    String? responsabilidades,
    String departamento = 'MOLINOS',
    String? telefono,
    String? direccion,
    String status = 'ACTIVO',
  }) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/empleados'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'numero_nomina': numeroNomina,
        'nombre': nombre,
        'puesto': puesto,
        'responsabilidades': responsabilidades,
        'departamento': departamento,
        'telefono': telefono,
        'direccion': direccion,
        'status': status,
      }),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return int.tryParse(json['id']?.toString() ?? '');
  }

  Future<List<TurnoMolino>> turnos() async {
    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/molinos/turnos'),
      headers: ApiService.headers(token: token),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return (json['turnos'] as List? ?? [])
        .map((e) => TurnoMolino.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> actualizarEmpleado({
    required int empleadoId,
    required String numeroNomina,
    required String nombre,
    String? puesto,
    String? responsabilidades,
    String? departamento,
    String? telefono,
    String? direccion,
    String? status,
  }) async {
    final res = await http.put(
      Uri.parse('${ApiService.baseUrl}/molinos/empleados/$empleadoId'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'numero_nomina': numeroNomina,
        'nombre': nombre,
        'puesto': puesto,
        'responsabilidades': responsabilidades,
        'departamento': departamento,
        'telefono': telefono,
        'direccion': direccion,
        'status': status,
      }),
    );
    ApiService.decode(res);
  }

  Future<void> actualizarTurnoEmpleado({
    required int empleadoId,
    required int turnoId,
    required DateTime fechaInicio,
    DateTime? fechaFin,
  }) async {
    final res = await http.put(
      Uri.parse('${ApiService.baseUrl}/molinos/empleados/$empleadoId/turno'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({
        'turno_id': turnoId,
        'fecha_inicio': _fmt(fechaInicio),
        'fecha_fin': fechaFin == null ? null : _fmt(fechaFin),
      }),
    );
    ApiService.decode(res);
  }

  Future<List<RotacionTurnoMolino>> rotacionEmpleado(int empleadoId) async {
    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/molinos/empleados/$empleadoId/rotacion'),
      headers: ApiService.headers(token: token),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return (json['rotacion'] as List? ?? [])
        .map((e) => RotacionTurnoMolino.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> guardarRotacionEmpleado({
    required int empleadoId,
    required List<RotacionTurnoMolino> rotacion,
  }) async {
    final res = await http.put(
      Uri.parse('${ApiService.baseUrl}/molinos/empleados/$empleadoId/rotacion'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({'rotacion': rotacion.map((e) => e.toJson()).toList()}),
    );
    ApiService.decode(res);
  }

  Future<String?> subirFotoEmpleado({required int empleadoId, required List<int> bytes, required String filename}) async {
    final uri = Uri.parse('${ApiService.baseUrl}/molinos/empleados/$empleadoId/foto');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(http.MultipartFile.fromBytes('foto', bytes, filename: filename));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return json['foto']?.toString();
  }

}
