class EmpleadoMolinos {
  final int id;
  final String numeroNomina;
  final String nombre;
  final String? foto;
  final String? puesto;
  final String? responsabilidades;
  final String? turno;
  final String? turnoColor;
  final String? acotacion;
  final String? acotacionDescripcion;
  final String? acotacionColor;
  final int? maquinaId;
  final String? maquinaNombre;
  final bool presente;
  final bool checoSalida;

  EmpleadoMolinos({
    required this.id,
    required this.numeroNomina,
    required this.nombre,
    this.foto,
    this.puesto,
    this.responsabilidades,
    this.turno,
    this.turnoColor,
    this.acotacion,
    this.acotacionDescripcion,
    this.acotacionColor,
    this.maquinaId,
    this.maquinaNombre,
    this.presente = false,
    this.checoSalida = false,
  });

  factory EmpleadoMolinos.fromJson(Map<String, dynamic> json) {
    return EmpleadoMolinos(
      id: json['empleado_id'] ?? json['id'],
      numeroNomina: json['numero_nomina']?.toString() ?? '',
      nombre: json['nombre'] ?? '',
      foto: json['foto'],
      puesto: json['puesto'],
      responsabilidades: json['responsabilidades'],
      turno: json['turno'],
      turnoColor: json['turno_color'],
      acotacion: json['acotacion'],
      acotacionDescripcion: json['acotacion_descripcion'],
      acotacionColor: json['acotacion_color'],
      maquinaId: json['maquina_id'],
      maquinaNombre: json['maquina_nombre'],
      presente: json['presente'] == true || json['presente'] == 1,
      checoSalida: json['checo_salida'] == true || json['checo_salida'] == 1,
    );
  }
}
