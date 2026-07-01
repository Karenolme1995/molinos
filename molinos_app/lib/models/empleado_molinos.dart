class EmpleadoMolinos {
  final int id;
  final String numeroNomina;
  final String nombre;
  final String? foto;
  final String? puesto;
  final String? responsabilidades;
  final String? turno;
  final String? turnoColor;
  final String? turnoHoraInicio;
  final String? turnoHoraFin;
  final bool turnoEnHorario;
  final bool turnoPorConcluir;
  final List<String> turnosVisibles;
  final String? acotacion;
  final String? acotacionDescripcion;
  final String? acotacionColor;
  final int? maquinaId;
  final String? maquinaNombre;
  final bool presente;
  final bool checoSalida;
  final String? horaEntrada;
  final String? horaSalidaComida;
  final String? horaRegresoComida;
  final String? horaSalida;
  final String? horaInicioMaquina;
  final String? horaFinMaquina;

  const EmpleadoMolinos({
    required this.id,
    required this.numeroNomina,
    required this.nombre,
    this.foto,
    this.puesto,
    this.responsabilidades,
    this.turno,
    this.turnoColor,
    this.turnoHoraInicio,
    this.turnoHoraFin,
    this.turnoEnHorario = true,
    this.turnoPorConcluir = false,
    this.turnosVisibles = const [],
    this.acotacion,
    this.acotacionDescripcion,
    this.acotacionColor,
    this.maquinaId,
    this.maquinaNombre,
    this.presente = false,
    this.checoSalida = false,
    this.horaEntrada,
    this.horaSalidaComida,
    this.horaRegresoComida,
    this.horaSalida,
    this.horaInicioMaquina,
    this.horaFinMaquina,
  });

  factory EmpleadoMolinos.fromJson(Map<String, dynamic> json) {
    return EmpleadoMolinos(
      id: _asInt(json['empleado_id'] ?? json['id']),
      numeroNomina: (json['numero_nomina'] ?? json['nomina'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      foto: _asNullableString(json['foto']),
      puesto: _asNullableString(json['puesto']),
      responsabilidades: _asNullableString(json['responsabilidades']),
      turno: _asNullableString(json['turno']),
      turnoColor: _asNullableString(json['turno_color']),
      turnoHoraInicio: _asNullableString(json['turno_hora_inicio']),
      turnoHoraFin: _asNullableString(json['turno_hora_fin']),
      turnoEnHorario: _asBool(json['turno_en_horario'], defaultValue: true),
      turnoPorConcluir: _asBool(json['turno_por_concluir']),
      turnosVisibles: _asStringList(json['turnos_visibles']),
      acotacion: _asNullableString(json['acotacion']),
      acotacionDescripcion: _asNullableString(json['acotacion_descripcion']),
      acotacionColor: _asNullableString(json['acotacion_color']),
      maquinaId: _asNullableInt(json['maquina_id']),
      maquinaNombre: _asNullableString(json['maquina_nombre']),
      presente: _asBool(json['presente']),
      checoSalida: _asBool(json['checo_salida']),
      horaEntrada: _asNullableString(json['hora_entrada']),
      horaSalidaComida: _asNullableString(json['hora_salida_comida']),
      horaRegresoComida: _asNullableString(json['hora_regreso_comida']),
      horaSalida: _asNullableString(json['hora_salida']),
      horaInicioMaquina: _asNullableString(json['hora_inicio_maquina']),
      horaFinMaquina: _asNullableString(json['hora_fin_maquina']),
    );
  }

  bool apareceEnTurno(String filtro) {
    final f = filtro.toUpperCase().trim();
    if (f == 'TODOS') return true;
    if (turnosVisibles.map((e) => e.toUpperCase().trim()).contains(f)) return true;
    return (turno ?? '').toUpperCase().trim() == f;
  }

  String get horarioTurno {
    if (turnoHoraInicio == null && turnoHoraFin == null) return '';
    return '${turnoHoraInicio ?? '--:--'} - ${turnoHoraFin ?? '--:--'}';
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _asNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static bool _asBool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    return value == true || value == 1 || value == '1' || value.toString().toLowerCase() == 'true';
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static List<String> _asStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    final text = value.toString();
    if (text.trim().isEmpty) return const [];
    return text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }
}
