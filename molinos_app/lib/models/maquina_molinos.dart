import 'empleado_molinos.dart';

class MaquinaMolinos {
  final int id;
  final String nombre;
  final String? descripcion;
  final String estado;
  final String estadoNombre;
  final String estadoColor;
  final List<EmpleadoMolinos> empleados;

  MaquinaMolinos({
    required this.id,
    required this.nombre,
    this.descripcion,
    required this.estado,
    required this.estadoNombre,
    required this.estadoColor,
    required this.empleados,
  });

  factory MaquinaMolinos.fromJson(Map<String, dynamic> json) {
    return MaquinaMolinos(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      estado: json['estado'] ?? 'trabajando',
      estadoNombre: json['estado_nombre'] ?? 'Trabajando',
      estadoColor: json['estado_color'] ?? 'verde',
      empleados: (json['empleados'] as List? ?? [])
          .map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
