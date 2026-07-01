import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/empleado_molinos.dart';
import '../models/maquina_molinos.dart';
import 'api_service.dart';

class TableroMolinos {
  final DateTime? fechaJornada;
  final List<MaquinaMolinos> maquinas;
  final List<EmpleadoMolinos> supervisores;
  final List<EmpleadoMolinos> empleadosTurno;
  final List<EmpleadoMolinos> espera;
  final List<EmpleadoMolinos> ausentes;
  final List<EmpleadoMolinos> alertas;

  const TableroMolinos({
    this.fechaJornada,
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

  const MaquinaHistorialMolino({
    required this.tipo,
    required this.fecha,
    required this.hora,
    required this.titulo,
    this.subtitulo,
    this.observaciones,
    this.turno,
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
    );
  }

  static String? _nullable(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }
}


class MantenimientoMolino {
  final int id;
  final String tipoMant;
  final String tiempoMant;
  final int idArea;
  final String? area;

  const MantenimientoMolino({
    required this.id,
    required this.tipoMant,
    required this.tiempoMant,
    required this.idArea,
    this.area,
  });

  factory MantenimientoMolino.fromJson(Map<String, dynamic> json) {
    return MantenimientoMolino(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      tipoMant: (json['tipo_mant'] ?? '').toString(),
      tiempoMant: (json['tiempo_mant'] ?? '').toString(),
      idArea: int.tryParse((json['id_area'] ?? '0').toString()) ?? 0,
      area: MaquinaHistorialMolino._nullable(json['area']),
    );
  }
}

class MolinosService {
  final String token;
  MolinosService(this.token);

  String _fmt(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  Future<TableroMolinos> tablero(DateTime fecha) async {
    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/molinos/tablero?fecha_jornada=${_fmt(fecha)}'),
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

  Future<List<MaquinaHistorialMolino>> historialMaquina({
    required int maquinaId,
    required DateTime fecha,
    String turno = 'TODOS',
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/molinos/maquinas/$maquinaId/historial').replace(
      queryParameters: {'fecha_jornada': _fmt(fecha), 'turno': turno},
    );
    final res = await http.get(
      uri,
      headers: ApiService.headers(token: token),
    );
    final json = Map<String, dynamic>.from(ApiService.decode(res));
    return (json['historial'] as List? ?? [])
        .map((e) => MaquinaHistorialMolino.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
