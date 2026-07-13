import 'empleado_molinos.dart';

class MaquinaMolinos {
  final int id;
  final String nombre;
  final String? descripcion;
  final String estado;
  final String estadoNombre;
  final String estadoColor;
  final String? estadoHoraInicio;
  final String? estadoFechaInicio;
  final String? estadoObservaciones;
  final String? mantenimientoFechaProxima;
  final String? mantenimientoProximo;
  final bool mantenimientoAlerta;
  final int? mantenimientoDiasRestantes;
  final String? mantenimientoSemaforo;
  final List<EmpleadoMolinos> empleados;

  const MaquinaMolinos({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.estado,
    required this.estadoNombre,
    required this.estadoColor,
    this.estadoHoraInicio,
    this.estadoFechaInicio,
    this.estadoObservaciones,
    this.mantenimientoFechaProxima,
    this.mantenimientoProximo,
    this.mantenimientoAlerta = false,
    this.mantenimientoDiasRestantes,
    this.mantenimientoSemaforo,
    required this.empleados,
  });

  factory MaquinaMolinos.fromJson(Map<String, dynamic> json) {
    return MaquinaMolinos(
      id: _asInt(json['id']),
      nombre: (json['nombre'] ?? '').toString(),
      descripcion: _asNullableString(json['descripcion']),
      estado: (json['estado'] ?? 'trabajando').toString(),
      estadoNombre: (json['estado_nombre'] ?? 'Trabajando').toString(),
      estadoColor: (json['estado_color'] ?? 'verde').toString(),
      estadoHoraInicio: _asNullableString(json['estado_hora_inicio']),
      estadoFechaInicio: _asNullableString(json['estado_fecha_inicio']),
      estadoObservaciones: _asNullableString(json['estado_observaciones']),
      mantenimientoFechaProxima:
          _asNullableString(json['mantenimiento_fecha_proxima']),
      mantenimientoProximo: _asNullableString(json['mantenimiento_proximo']),
      mantenimientoAlerta: _asBool(json['mantenimiento_alerta']),
      mantenimientoDiasRestantes: json['mantenimiento_dias_restantes'] == null
          ? null
          : int.tryParse(json['mantenimiento_dias_restantes'].toString()),
      mantenimientoSemaforo: _asNullableString(json['mantenimiento_semaforo']),
      empleados: (json['empleados'] as List? ?? [])
          .map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  DateTime? get estadoInicioDateTime {
    if (estadoFechaInicio == null || estadoHoraInicio == null) return null;
    return DateTime.tryParse(
        '$estadoFechaInicio ${estadoHoraInicio!.padRight(5, '0')}');
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static bool _asBool(dynamic value) {
    if (value == null) return false;
    return value == true ||
        value == 1 ||
        value == '1' ||
        value.toString().toLowerCase() == 'true';
  }
}
