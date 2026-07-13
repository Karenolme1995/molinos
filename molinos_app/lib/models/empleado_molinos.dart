class EmpleadoMolinos {
  // Atributos principales del empleado
  final int id;
  final String numeroNomina;
  final String nombre;
  final String? foto;
  final String? puesto;
  final String? responsabilidades;
  final String? fechaNacimiento;
  final String? telefono;
  final String? direccion;
  final String? status;
  final String? departamento;
  final int activo;
//Atributos del turno actual y del próximo turno
  final int? turnoId;
  final String? turno;
  final String? turnoColor;
  final String? turnoHoraInicio;
  final String? turnoHoraFin;
  final String? turnoFechaInicio;
  final String? turnoFechaFin;
//Atributos del próximo turno
  final int? proximoTurnoId;
  final String? proximoTurno;
  final String? proximoTurnoHoraInicio;
  final String? proximoTurnoHoraFin;
  final String? proximoTurnoFechaInicio;
  final String? proximoTurnoFechaFin;
  final int? proximoTurnoSemana;
//Atributos de control de turno
  final bool turnoEnHorario;
  final bool turnoPorConcluir;
  final List<String> turnosVisibles;
//Atributos de acotación
  final String? acotacion;
  final String? acotacionDescripcion;
  final String? acotacionColor;
//Atributos de máquina
  final int? maquinaId;
  final String? maquinaNombre;
//Atributos de checadas
  final bool presente;
  final bool checoSalida;
  final String? horaEntrada;
  final String? horaSalidaComida;
  final String? horaRegresoComida;
  final String? horaSalida;
  final String? horaInicioMaquina;
  final String? horaFinMaquina;
//Atributos de rol
  final bool rolCompleto;
  final String rolEstado;
  final int rolSemanasCubiertas;
  final int rolSemanasEsperadas;
  final int semanasRolCapturadas;
  final int semanasRolRequeridas;
  final int? semanaActual;
  final String? semanaActualFechaInicio;
  final String? semanaActualFechaFin;
  final String? rolFechaInicio;
  final String? rolFechaFin;
// Constructor
  const EmpleadoMolinos({
    // Atributos principales del empleado
    required this.id,
    required this.numeroNomina,
    required this.nombre,
    this.foto,
    this.puesto,
    this.responsabilidades,
    this.fechaNacimiento,
    this.telefono,
    this.direccion,
    this.status,
    this.departamento,
    this.activo = 1,
    this.turnoId,
    this.turno,
    this.turnoColor,
    this.turnoHoraInicio,
    this.turnoHoraFin,
    this.turnoFechaInicio,
    this.turnoFechaFin,
    this.proximoTurnoId,
    this.proximoTurno,
    this.proximoTurnoHoraInicio,
    this.proximoTurnoHoraFin,
    this.proximoTurnoFechaInicio,
    this.proximoTurnoFechaFin,
    this.proximoTurnoSemana,
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
    this.rolCompleto = false,
    this.rolEstado = 'Rol incompleto',
    this.rolSemanasCubiertas = 0,
    this.rolSemanasEsperadas = 0,
    this.semanasRolCapturadas = 0,
    this.semanasRolRequeridas = 0,
    this.semanaActual,
    this.semanaActualFechaInicio,
    this.semanaActualFechaFin,
    this.rolFechaInicio,
    this.rolFechaFin,
  });

  factory EmpleadoMolinos.fromJson(Map<String, dynamic> json) {
    final rolCompletoValue =
        _asBool(json['rol_completo'] ?? json['rolCompleto']);
    final rolEstadoValue =
        _asNullableString(json['rol_estado'] ?? json['rolEstado']) ??
            (rolCompletoValue ? 'Rol completo' : 'Rol incompleto');

    final cubiertas = _asInt(
      json['rol_semanas_cubiertas'] ??
          json['semanas_rol_capturadas'] ??
          json['semanas_rol_cubiertas'] ??
          json['rolSemanasCubiertas'] ??
          0,
    );

    final esperadas = _asInt(
      json['rol_semanas_esperadas'] ??
          json['semanas_rol_requeridas'] ??
          json['semanas_rol_esperadas'] ??
          json['rolSemanasEsperadas'] ??
          0,
    );

    return EmpleadoMolinos(
      id: _asInt(json['empleado_id'] ?? json['id']),
      numeroNomina: (json['numero_nomina'] ??
              json['nomina'] ??
              json['numeroNomina'] ??
              '')
          .toString(),
      nombre: (json['nombre'] ?? '').toString(),
      foto: _asNullableString(json['foto']),
      puesto: _asNullableString(json['puesto']),
      responsabilidades: _asNullableString(json['responsabilidades']),
      fechaNacimiento: _asNullableString(
          json['fecha_nacimiento'] ?? json['fechaNacimiento']),
      telefono: _asNullableString(json['telefono']),
      direccion: _asNullableString(json['direccion']),
      status: _asNullableString(json['status']),
      departamento: _asNullableString(json['departamento']),
      activo: _asInt(json['activo'] ?? 1),

      turnoId: _asNullableInt(json['turno_id'] ?? json['turnoId']),
      turno: _asNullableString(json['turno_nombre'] ?? json['turno']),
      turnoColor: _asNullableString(json['turno_color'] ?? json['turnoColor']),
      turnoHoraInicio: _asNullableString(
          json['turno_hora_inicio'] ?? json['turnoHoraInicio']),
      turnoHoraFin:
          _asNullableString(json['turno_hora_fin'] ?? json['turnoHoraFin']),
      turnoFechaInicio: _asNullableString(
        json['turno_fecha_inicio'] ??
            json['fecha_inicio_turno'] ??
            json['turnoFechaInicio'],
      ),
      turnoFechaFin: _asNullableString(
        json['turno_fecha_fin'] ??
            json['fecha_fin_turno'] ??
            json['turnoFechaFin'],
      ),

      proximoTurnoId:
          _asNullableInt(json['proximo_turno_id'] ?? json['proximoTurnoId']),

      // IMPORTANTE:
      // Primero se lee proximo_turno_nombre porque el backend debe mandar el nombre real
      // del turno siguiente desde empleados_turnos_rotacion.
      // Si no existe, se usan alias anteriores para no romper compatibilidad.
      proximoTurno: _asNullableString(
        json['proximo_turno_nombre'] ??
            json['proximo_turno'] ??
            json['proximoTurno'],
      ),
      proximoTurnoHoraInicio: _asNullableString(
        json['proximo_turno_hora_inicio'] ?? json['proximoTurnoHoraInicio'],
      ),
      proximoTurnoHoraFin: _asNullableString(
        json['proximo_turno_hora_fin'] ?? json['proximoTurnoHoraFin'],
      ),
      proximoTurnoFechaInicio: _asNullableString(
        json['proximo_turno_fecha_inicio'] ?? json['proximoTurnoFechaInicio'],
      ),
      proximoTurnoFechaFin: _asNullableString(
        json['proximo_turno_fecha_fin'] ?? json['proximoTurnoFechaFin'],
      ),
      proximoTurnoSemana: _asNullableInt(
        json['proximo_turno_semana'] ??
            json['proximo_semana_orden'] ??
            json['proximo_semana'] ??
            json['proximoTurnoSemana'],
      ),

      turnoEnHorario: _asBool(
          json['turno_en_horario'] ?? json['turnoEnHorario'],
          defaultValue: true),
      turnoPorConcluir:
          _asBool(json['turno_por_concluir'] ?? json['turnoPorConcluir']),
      turnosVisibles:
          _asStringList(json['turnos_visibles'] ?? json['turnosVisibles']),

      acotacion: _asNullableString(json['acotacion']),
      acotacionDescripcion: _asNullableString(
          json['acotacion_descripcion'] ?? json['acotacionDescripcion']),
      acotacionColor:
          _asNullableString(json['acotacion_color'] ?? json['acotacionColor']),

      maquinaId: _asNullableInt(json['maquina_id'] ?? json['maquinaId']),
      maquinaNombre:
          _asNullableString(json['maquina_nombre'] ?? json['maquinaNombre']),

      presente: _asBool(json['presente']),
      checoSalida: _asBool(json['checo_salida'] ?? json['checoSalida']),
      horaEntrada:
          _asNullableString(json['hora_entrada'] ?? json['horaEntrada']),
      horaSalidaComida: _asNullableString(
          json['hora_salida_comida'] ?? json['horaSalidaComida']),
      horaRegresoComida: _asNullableString(
          json['hora_regreso_comida'] ?? json['horaRegresoComida']),
      horaSalida: _asNullableString(json['hora_salida'] ?? json['horaSalida']),
      horaInicioMaquina: _asNullableString(
          json['hora_inicio_maquina'] ?? json['horaInicioMaquina']),
      horaFinMaquina:
          _asNullableString(json['hora_fin_maquina'] ?? json['horaFinMaquina']),

      rolCompleto: rolCompletoValue,
      rolEstado: rolEstadoValue,
      rolSemanasCubiertas: cubiertas,
      rolSemanasEsperadas: esperadas,
      semanasRolCapturadas: cubiertas,
      semanasRolRequeridas: esperadas,
      semanaActual: _asNullableInt(
          json['semana_actual'] ?? json['semana_anio'] ?? json['semanaActual']),
      semanaActualFechaInicio: _asNullableString(
          json['semana_actual_fecha_inicio'] ??
              json['semanaActualFechaInicio']),
      semanaActualFechaFin: _asNullableString(
          json['semana_actual_fecha_fin'] ?? json['semanaActualFechaFin']),
      rolFechaInicio:
          _asNullableString(json['rol_fecha_inicio'] ?? json['rolFechaInicio']),
      rolFechaFin:
          _asNullableString(json['rol_fecha_fin'] ?? json['rolFechaFin']),
    );
  }

  bool apareceEnTurno(String filtro) {
    final f = filtro.toUpperCase().trim();
    if (f == 'TODOS') return true;
    if (turnosVisibles.map((e) => e.toUpperCase().trim()).contains(f))
      return true;
    return (turno ?? '').toUpperCase().trim() == f;
  }

  String get horarioProximoTurno {
    if (proximoTurnoHoraInicio == null && proximoTurnoHoraFin == null)
      return '';
    return '${proximoTurnoHoraInicio ?? '--:--'} - ${proximoTurnoHoraFin ?? '--:--'}';
  }

  String get horarioTurno {
    if (turnoHoraInicio == null && turnoHoraFin == null) return '';
    return '${turnoHoraInicio ?? '--:--'} - ${turnoHoraFin ?? '--:--'}';
  }

  String get rangoTurnoActual {
    if ((turnoFechaInicio ?? '').trim().isEmpty &&
        (turnoFechaFin ?? '').trim().isEmpty) {
      return '';
    }
    return '${turnoFechaInicio ?? '---- -- --'} al ${turnoFechaFin ?? '---- -- --'}';
  }

  String get rangoProximoTurno {
    if ((proximoTurnoFechaInicio ?? '').trim().isEmpty &&
        (proximoTurnoFechaFin ?? '').trim().isEmpty) {
      return '';
    }
    return '${proximoTurnoFechaInicio ?? '---- -- --'} al ${proximoTurnoFechaFin ?? '---- -- --'}';
  }

  String get resumenRol {
    return rolCompleto ? 'Rol completo' : 'Rol incompleto';
  }

  String get resumenRolConConteo {
    final esperadas =
        semanasRolRequeridas > 0 ? semanasRolRequeridas : rolSemanasEsperadas;
    final capturadas =
        semanasRolCapturadas > 0 ? semanasRolCapturadas : rolSemanasCubiertas;
    if (esperadas <= 0) return resumenRol;
    return '$resumenRol ($capturadas/$esperadas)';
  }

  String get resumenSemanaActual {
    if (semanaActual == null) return '';
    if ((semanaActualFechaInicio ?? '').trim().isEmpty &&
        (semanaActualFechaFin ?? '').trim().isEmpty) {
      return 'Semana del año $semanaActual';
    }
    return 'Semana del año $semanaActual · ${semanaActualFechaInicio ?? ''} al ${semanaActualFechaFin ?? ''}';
  }

  String get resumenTurnoQueSigue {
    final partes = <String>[];

    if (proximoTurnoSemana != null) {
      partes.add('Semana del año $proximoTurnoSemana');
    }

    if (rangoProximoTurno.trim().isNotEmpty) {
      partes.add(rangoProximoTurno);
    }

    partes.add('Turno que sigue: ${proximoTurno ?? 'Sin próximo turno'}');

    return partes.join(' · ');
  }

  String get resumenChecadas {
    final partes = <String>[];

    if ((horaEntrada ?? '').trim().isNotEmpty) {
      partes.add('Entrada: ${horaEntrada!.trim()}');
    }
    if ((horaSalidaComida ?? '').trim().isNotEmpty) {
      partes.add('Salida comida: ${horaSalidaComida!.trim()}');
    }
    if ((horaRegresoComida ?? '').trim().isNotEmpty) {
      partes.add('Regreso comida: ${horaRegresoComida!.trim()}');
    }
    if ((horaSalida ?? '').trim().isNotEmpty) {
      partes.add('Salida: ${horaSalida!.trim()}');
    }

    if (partes.isNotEmpty) return partes.join(' · ');
    if (!presente) return 'No se presentó';
    return 'Sin checadas registradas';
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
    return value == true ||
        value == 1 ||
        value == '1' ||
        value.toString().trim().toLowerCase() == 'true' ||
        value.toString().trim().toLowerCase() == 'si' ||
        value.toString().trim().toLowerCase() == 'sí';
  }

  static String? _asNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString();
    return text.trim().isEmpty ? null : text;
  }

  static List<String> _asStringList(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    final text = value.toString();
    if (text.trim().isEmpty) return const [];

    return text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
