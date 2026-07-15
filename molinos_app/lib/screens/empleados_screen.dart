import '../utils/web_file_picker.dart';
import '../utils/file_downloader.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/empleado_molinos.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/molinos_service.dart';

class _FotoSeleccionada {
  final Uint8List bytes;
  final String filename;

  const _FotoSeleccionada({
    required this.bytes,
    required this.filename,
  });
}

class EmpleadosScreen extends StatefulWidget {
  const EmpleadosScreen({super.key});

  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen> {
  final _qCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<EmpleadoMolinos> _empleados = [];
  List<TurnoMolino> _turnosFiltro = [];
  String _turnoFiltro = 'TODOS';
  bool _exportandoExcel = false;
  final Map<int, String> _turnoSemanaConsultada = {};
  final Map<int, String> _nombreTurnoSemanaConsultada = {};
  DateTime _fechaSemanaConsulta = DateTime.now();
  final Map<int, String> _estadoRolAnual = {};
  static const List<String> _puestos = [
    'AYUD.GENERAL',
    'LAVADOR',
    'MANGAS',
    'MONTACARGUISTA',
    'OP.MOLINOS',
    'SUPERVISOR',
    'OTRO',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  MolinosService _service() =>
      MolinosService(context.read<AuthService>().token!);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = _service();
      _turnosFiltro = _turnosUnicos(await service.turnos());
      _empleados =
          await service.empleados(q: _qCtrl.text.trim(), turno: _turnoFiltro);
      await _cargarResumenRoles(service);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _cargarResumenRoles(MolinosService service) async {
    _turnoSemanaConsultada.clear();
    _nombreTurnoSemanaConsultada.clear();
    _estadoRolAnual.clear();

    final ahora = DateTime.now();
    final anio = ahora.year;
    final totalSemanas = _semanasIsoDelAnio(anio);
    final semanaConsulta = _semanaDelAnio(_fechaSemanaConsulta);
    final anioSemanaConsulta = _anioIso(_fechaSemanaConsulta);
    final turnosPorId = {for (final t in _turnosFiltro) t.id: t.nombre};

    await Future.wait(_empleados.map((empleado) async {
      try {
        final rotacion = await service.rotacionEmpleado(empleado.id);

        bool perteneceAlAnio(RotacionTurnoMolino r, int targetYear) {
          final fecha = r.fechaInicio?.trim() ?? '';
          if (fecha.isEmpty) return targetYear == anio;
          return fecha.startsWith('$targetYear-');
        }

        final semanasAnio = rotacion
            .where((r) => perteneceAlAnio(r, anio))
            .where((r) => r.semanaOrden >= 1 && r.semanaOrden <= totalSemanas)
            .where((r) => turnosPorId.containsKey(r.turnoId))
            .map((r) => r.semanaOrden)
            .toSet();

        final completo = semanasAnio.length == totalSemanas;
        _estadoRolAnual[empleado.id] = completo
            ? 'ROL COMPLETO · ${semanasAnio.length}/$totalSemanas semanas'
            : 'ROL INCOMPLETO · ${semanasAnio.length}/$totalSemanas semanas';

        RotacionTurnoMolino? rolConsultado;
        for (final r in rotacion) {
          if (r.semanaOrden == semanaConsulta &&
              perteneceAlAnio(r, anioSemanaConsulta) &&
              turnosPorId.containsKey(r.turnoId)) {
            rolConsultado = r;
            break;
          }
        }

        final nombreTurno = rolConsultado == null
            ? 'SIN CONFIGURAR'
            : (turnosPorId[rolConsultado.turnoId] ?? 'SIN CONFIGURAR');
        _nombreTurnoSemanaConsultada[empleado.id] = nombreTurno;
        _turnoSemanaConsultada[empleado.id] =
            'Semana $semanaConsulta ($anioSemanaConsulta): $nombreTurno';
      } catch (_) {
        _estadoRolAnual[empleado.id] = 'ROL INCOMPLETO · no se pudo validar';
        _nombreTurnoSemanaConsultada[empleado.id] = 'SIN CONFIGURAR';
        _turnoSemanaConsultada[empleado.id] =
            'Semana $semanaConsulta ($anioSemanaConsulta): SIN CONFIGURAR';
      }
    }));
  }

  int _semanasIsoDelAnio(int year) {
    return _semanaDelAnio(DateTime(year, 12, 28));
  }

  int _anioIso(DateTime date) {
    final jueves = date.add(Duration(days: 4 - date.weekday));
    return jueves.year;
  }

  Future<void> _cambiarSemanaConsulta(int semanas) async {
    setState(() {
      _fechaSemanaConsulta =
          _fechaSemanaConsulta.add(Duration(days: semanas * 7));
    });
    await _load();
  }

  Future<void> _volverSemanaActual() async {
    setState(() => _fechaSemanaConsulta = DateTime.now());
    await _load();
  }

  bool get _consultandoSemanaActual {
    final ahora = DateTime.now();
    return _semanaDelAnio(_fechaSemanaConsulta) == _semanaDelAnio(ahora) &&
        _anioIso(_fechaSemanaConsulta) == _anioIso(ahora);
  }

  ExcelColor _colorTurnoExcel(String turno) {
    final nombre = turno.toUpperCase().trim();
    if (nombre.contains('TURNO 1')) {
      return ExcelColor.fromHexString('#D9EAF7');
    }
    if (nombre.contains('TURNO 2')) {
      return ExcelColor.fromHexString('#FFF2CC');
    }
    if (nombre.contains('TURNO 3')) {
      return ExcelColor.fromHexString('#D9EAD3');
    }
    if (nombre.contains('MIXTO')) {
      return ExcelColor.fromHexString('#FCE4D6');
    }
    return ExcelColor.fromHexString('#E7E6E6');
  }

  String _nombreHojaTurno(String turno) {
    final limpio = turno
        .toUpperCase()
        .replaceAll(RegExp(r'[\\/:?*\[\]]'), ' ')
        .trim();
    return limpio.isEmpty ? 'SIN CONFIGURAR' : limpio.substring(0, math.min(31, limpio.length));
  }

  bool _esSupervisor(EmpleadoMolinos empleado) {
    return (empleado.puesto ?? '').toUpperCase().contains('SUPERVISOR');
  }

  TextCellValue _excelText(Object? value) => TextCellValue('${value ?? ''}');

  CellStyle _estiloTituloExcel() => CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#1F4E78'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle _estiloEncabezadoExcel() => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle _estiloSupervisorExcel() => CellStyle(
        bold: true,
        fontColorHex: ExcelColor.white,
        backgroundColorHex: ExcelColor.fromHexString('#7030A0'),
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle _estiloFilaTurnoExcel(String turno) => CellStyle(
        backgroundColorHex: _colorTurnoExcel(turno),
        verticalAlign: VerticalAlign.Center,
      );

  Future<Map<int, String>> _turnosDeEmpleadosParaSemana(
    MolinosService service,
    List<EmpleadoMolinos> empleados,
  ) async {
    final resultado = <int, String>{};
    final semana = _semanaDelAnio(_fechaSemanaConsulta);
    final anio = _anioIso(_fechaSemanaConsulta);
    final turnosPorId = {for (final t in _turnosFiltro) t.id: t.nombre};

    await Future.wait(empleados.map((empleado) async {
      try {
        final rotacion = await service.rotacionEmpleado(empleado.id);
        RotacionTurnoMolino? encontrado;
        for (final rol in rotacion) {
          final fechaInicio = rol.fechaInicio?.trim() ?? '';
          final coincideAnio = fechaInicio.isEmpty || fechaInicio.startsWith('$anio-');
          if (rol.semanaOrden == semana && coincideAnio) {
            encontrado = rol;
            break;
          }
        }
        resultado[empleado.id] = encontrado == null
            ? 'SIN CONFIGURAR'
            : (turnosPorId[encontrado.turnoId] ?? 'SIN CONFIGURAR');
      } catch (_) {
        resultado[empleado.id] = 'SIN CONFIGURAR';
      }
    }));
    return resultado;
  }

  void _crearHojaTurnoExcel({
    required Excel excel,
    required String nombreHoja,
    required String turno,
    required List<EmpleadoMolinos> empleados,
    required int semana,
    required int anio,
    required DateTime inicio,
    required DateTime fin,
  }) {
    final sheet = excel[nombreHoja];
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('G1'));
    final titulo = sheet.cell(CellIndex.indexByString('A1'));
    titulo.value = _excelText('Rotación de turnos · $turno');
    titulo.cellStyle = _estiloTituloExcel();

    sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('G2'));
    final periodo = sheet.cell(CellIndex.indexByString('A2'));
    periodo.value = _excelText(
      'Semana $semana de $anio · ${DateFormat('dd/MM/yyyy').format(inicio)} al ${DateFormat('dd/MM/yyyy').format(fin)}',
    );
    periodo.cellStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      backgroundColorHex: _colorTurnoExcel(turno),
    );

    final encabezados = <CellValue?>[
      _excelText('Nómina'),
      _excelText('Empleado'),
      _excelText('Puesto'),
      _excelText('Turno'),
      _excelText('Semana'),
      _excelText('Periodo'),
      _excelText('Estatus'),
    ];
    sheet.appendRow(encabezados);
    for (var c = 0; c < encabezados.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2)).cellStyle =
          _estiloEncabezadoExcel();
    }

    empleados.sort((a, b) {
      final supervisorA = _esSupervisor(a) ? 0 : 1;
      final supervisorB = _esSupervisor(b) ? 0 : 1;
      final porSupervisor = supervisorA.compareTo(supervisorB);
      if (porSupervisor != 0) return porSupervisor;
      return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
    });

    for (final empleado in empleados) {
      sheet.appendRow(<CellValue?>[
        _excelText(empleado.numeroNomina),
        _excelText(empleado.nombre),
        _excelText(empleado.puesto ?? 'Sin puesto'),
        _excelText(turno),
        _excelText(semana),
        _excelText('${DateFormat('dd/MM/yyyy').format(inicio)} - ${DateFormat('dd/MM/yyyy').format(fin)}'),
        _excelText(empleado.status ?? (empleado.activo == 1 ? 'ACTIVO' : 'INACTIVO')),
      ]);
      final rowIndex = sheet.maxRows - 1;
      final estilo = _esSupervisor(empleado)
          ? _estiloSupervisorExcel()
          : _estiloFilaTurnoExcel(turno);
      for (var c = 0; c < 7; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).cellStyle = estilo;
      }
    }

    const widths = <double>[14, 30, 22, 16, 12, 26, 14];
    for (var c = 0; c < widths.length; c++) {
      sheet.setColumnWidth(c, widths[c]);
    }
  }

  Future<void> _exportarExcel({String? soloTurno}) async {
    if (_exportandoExcel) return;
    if (soloTurno != null && soloTurno == 'TODOS') {
      _msg('Selecciona TURNO 1, TURNO 2, TURNO 3 o MIXTO para descargar un solo turno.');
      return;
    }

    setState(() => _exportandoExcel = true);
    try {
      final service = _service();
      final empleados = await service.empleados(q: '', turno: 'TODOS');
      final turnosSemana = await _turnosDeEmpleadosParaSemana(service, empleados);
      final semana = _semanaDelAnio(_fechaSemanaConsulta);
      final anio = _anioIso(_fechaSemanaConsulta);
      final inicio = _inicioSemanaIso(semana, year: anio);
      final fin = _finSemanaIso(semana, year: anio);

      final grupos = <String, List<EmpleadoMolinos>>{};
      for (final empleado in empleados) {
        final turno = turnosSemana[empleado.id] ?? 'SIN CONFIGURAR';
        if (soloTurno != null && turno.toUpperCase() != soloTurno.toUpperCase()) {
          continue;
        }
        grupos.putIfAbsent(turno, () => <EmpleadoMolinos>[]).add(empleado);
      }

      if (grupos.isEmpty) {
        _msg('No hay empleados configurados para ese turno en la semana $semana.');
        return;
      }

      final excel = Excel.createExcel();
      final hojaInicial = excel.getDefaultSheet();
      final ordenPreferido = ['TURNO 1', 'TURNO 2', 'TURNO 3', 'MIXTO', 'SIN CONFIGURAR'];
      final nombresOrdenados = grupos.keys.toList()
        ..sort((a, b) {
          final ia = ordenPreferido.indexOf(a.toUpperCase());
          final ib = ordenPreferido.indexOf(b.toUpperCase());
          final oa = ia < 0 ? 999 : ia;
          final ob = ib < 0 ? 999 : ib;
          return oa != ob ? oa.compareTo(ob) : a.compareTo(b);
        });

      for (final turno in nombresOrdenados) {
        _crearHojaTurnoExcel(
          excel: excel,
          nombreHoja: _nombreHojaTurno(turno),
          turno: turno,
          empleados: List<EmpleadoMolinos>.from(grupos[turno]!),
          semana: semana,
          anio: anio,
          inicio: inicio,
          fin: fin,
        );
      }
      if (hojaInicial != null && !nombresOrdenados.contains(hojaInicial)) {
        excel.delete(hojaInicial);
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('No se pudo generar el archivo Excel.');
      final sufijo = soloTurno == null
          ? 'todos_los_turnos'
          : soloTurno.toLowerCase().replaceAll(' ', '_');
      final filename = 'rotacion_semana_${semana}_${anio}_$sufijo.xlsx';
      descargarArchivo(bytes: Uint8List.fromList(bytes), filename: filename);
      _msg('Excel generado: $filename');
    } catch (e) {
      _msg('Error al exportar Excel: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _exportandoExcel = false);
    }
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _editar([EmpleadoMolinos? empleado]) async {
    final esNuevo = empleado == null;
    final nomina = TextEditingController(text: empleado?.numeroNomina ?? '');
    final nombre = TextEditingController(text: empleado?.nombre ?? '');
    String puestoSeleccionado =
        _puestos.contains((empleado?.puesto ?? '').toUpperCase().trim())
            ? (empleado?.puesto ?? '').toUpperCase().trim()
            : 'OTRO';
    final responsabilidades =
        TextEditingController(text: empleado?.responsabilidades ?? '');
    final telefono = TextEditingController(text: empleado?.telefono ?? '');
    final direccion = TextEditingController(text: empleado?.direccion ?? '');
    int activoSeleccionado = empleado?.activo ?? 1;
    Uint8List? fotoBytes;
    String? fotoFilename;
    String? fotoPreviewUrl = empleado?.foto;

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(esNuevo ? 'Agregar empleado' : 'Editar empleado'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: nomina,
                        decoration: const InputDecoration(labelText: 'Nómina')),
                    TextField(
                        controller: nombre,
                        decoration: const InputDecoration(labelText: 'Nombre')),
                    DropdownButtonFormField<String>(
                      value: puestoSeleccionado,
                      items: _puestos
                          .map(
                              (p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (value) =>
                          puestoSeleccionado = value ?? 'OTRO',
                      decoration: const InputDecoration(labelText: 'Puesto'),
                    ),
                    TextField(
                        controller: responsabilidades,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                            labelText: 'Responsabilidades')),
                    TextField(
                        controller: telefono,
                        decoration:
                            const InputDecoration(labelText: 'Teléfono')),
                    TextField(
                        controller: direccion,
                        decoration:
                            const InputDecoration(labelText: 'Dirección')),
                    DropdownButtonFormField<int>(
                      value: activoSeleccionado,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Activo')),
                        DropdownMenuItem(value: 0, child: Text('Inactivo')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => activoSeleccionado = value);
                      },
                      decoration: const InputDecoration(labelText: 'Status'),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Departamento: MOLINOS',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 34,
                            backgroundImage: fotoBytes != null
                                ? MemoryImage(fotoBytes!)
                                : _fotoProvider(fotoPreviewUrl),
                            child: (fotoBytes == null &&
                                    (fotoPreviewUrl == null ||
                                        fotoPreviewUrl!.isEmpty))
                                ? const Icon(Icons.person, size: 34)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Foto del empleado',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                const Text('Se guardará en /uploads/empleados/',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.black54)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      icon: const Icon(Icons.photo_camera),
                                      label: const Text('Agregar / tomar foto'),
                                      onPressed: () async {
                                        final picked = await _seleccionarFoto();
                                        if (picked == null) return;
                                        setDialogState(() {
                                          fotoBytes = picked.bytes;
                                          fotoFilename = picked.filename;
                                        });
                                      },
                                    ),
                                    if (fotoBytes != null ||
                                        (fotoPreviewUrl ?? '').isNotEmpty)
                                      TextButton.icon(
                                        icon: const Icon(Icons.close),
                                        label: const Text('Quitar selección'),
                                        onPressed: () {
                                          setDialogState(() {
                                            fotoBytes = null;
                                            fotoFilename = null;
                                            fotoPreviewUrl = null;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Guardar')),
            ],
          ),
        ),
      );

      if (ok != true) return;
      if (nomina.text.trim().isEmpty || nombre.text.trim().isEmpty) {
        _msg('Nómina y nombre son obligatorios.');
        return;
      }

      int? empleadoIdParaFoto;

      if (esNuevo) {
        empleadoIdParaFoto = await _service().crearEmpleado(
          numeroNomina: nomina.text.trim(),
          nombre: nombre.text.trim(),
          puesto: puestoSeleccionado,
          responsabilidades: responsabilidades.text.trim(),
          departamento: 'MOLINOS',
          telefono: telefono.text.trim(),
          direccion: direccion.text.trim(),
          status: activoSeleccionado == 1 ? 'ACTIVO' : 'INACTIVO',
          activo: activoSeleccionado,
        );
        _msg('Empleado agregado.');
      } else {
        empleadoIdParaFoto = empleado.id;
        await _service().actualizarEmpleado(
          empleadoId: empleado.id,
          numeroNomina: nomina.text.trim(),
          nombre: nombre.text.trim(),
          puesto: puestoSeleccionado,
          responsabilidades: responsabilidades.text.trim(),
          departamento: 'MOLINOS',
          telefono: telefono.text.trim(),
          direccion: direccion.text.trim(),
          status: activoSeleccionado == 1 ? 'ACTIVO' : 'INACTIVO',
          activo: activoSeleccionado,
        );
        _msg('Empleado actualizado.');
      }

      if (fotoBytes != null && empleadoIdParaFoto != null) {
        await _service().subirFotoEmpleado(
          empleadoId: empleadoIdParaFoto,
          bytes: fotoBytes!,
          filename: fotoFilename ?? 'empleado.jpg',
        );
        _msg('Foto guardada en /uploads/empleados/.');
      }
      await _load();
    } finally {
      nomina.dispose();
      nombre.dispose();
      responsabilidades.dispose();
      telefono.dispose();
      direccion.dispose();
    }
  }

  List<TurnoMolino> _turnosUnicos(List<TurnoMolino> turnos) {
    final Map<int, TurnoMolino> map = {};
    for (final t in turnos) {
      if (t.id != 0) map[t.id] = t;
    }
    final list = map.values.toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  int? _turnoValido(int? value, List<TurnoMolino> turnos) {
    if (value == null || value == 0) return null;
    return turnos.any((t) => t.id == value) ? value : null;
  }

  ImageProvider? _fotoProvider(String? foto) {
    final value = foto?.trim() ?? '';
    if (value.isEmpty) return null;
    final url = value.startsWith('http')
        ? value
        : '${ApiService.baseUrl.replaceFirst('/api/v1', '')}$value';
    return NetworkImage(url);
  }

  Future<_FotoSeleccionada?> _seleccionarFoto() async {
    final picked = await seleccionarImagenWeb();
    if (picked == null) return null;

    return _FotoSeleccionada(
      bytes: picked.bytes,
      filename: picked.filename,
    );
  }

  Future<void> _subirFoto(EmpleadoMolinos empleado) async {
    final picked = await _seleccionarFoto();
    if (picked == null) return;
    await _service().subirFotoEmpleado(
        empleadoId: empleado.id,
        bytes: picked.bytes,
        filename: picked.filename);
    _msg('Foto guardada en /uploads/empleados/.');
    await _load();
  }

  DateTime _inicioSemanaIso(int semana, {int? year}) {
    final targetYear = year ?? DateTime.now().year;
    final jan4 = DateTime(targetYear, 1, 4);
    final mondayWeek1 = jan4.subtract(Duration(days: jan4.weekday - 1));
    return mondayWeek1.add(Duration(days: (semana.clamp(1, 53) - 1) * 7));
  }

  DateTime _finSemanaIso(int semana, {int? year}) {
    return _inicioSemanaIso(semana, year: year).add(const Duration(days: 6));
  }

  String _fechaSemanaInicio(int semana) {
    return DateFormat('yyyy-MM-dd').format(_inicioSemanaIso(semana));
  }

  String _fechaSemanaFin(int semana) {
    return DateFormat('yyyy-MM-dd').format(_finSemanaIso(semana));
  }

  RotacionTurnoMolino _rotacionConFechas({
    required int semanaOrden,
    required int turnoId,
  }) {
    return RotacionTurnoMolino(
      semanaOrden: semanaOrden,
      turnoId: turnoId,
      fechaInicio: _fechaSemanaInicio(semanaOrden),
      fechaFin: _fechaSemanaFin(semanaOrden),
    );
  }

  Future<void> _editarRotacion(EmpleadoMolinos empleado) async {
    final service = _service();
    List<TurnoMolino> turnos = _turnosUnicos(await service.turnos());
    List<RotacionTurnoMolino> rotacion =
        await service.rotacionEmpleado(empleado.id);

    if (turnos.isEmpty) {
      _msg('No hay turnos activos para asignar.');
      return;
    }

    if (rotacion.isEmpty) {
      rotacion = [
        _rotacionConFechas(
          semanaOrden: _semanaDelAnio(DateTime.now()),
          turnoId: turnos.first.id,
        ),
      ];
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Rotación semanal - ${empleado.nombre}'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Configura desde la semana actual del año en adelante. Molinos usa esta rotación para mostrar empleados por pestaña.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...rotacion.asMap().entries.map((entry) {
                      final i = entry.key;
                      final r = entry.value;
                      final semanaActual = _semanaDelAnio(DateTime.now());
                      final semanaValue = r.semanaOrden <= 0
                          ? semanaActual
                          : r.semanaOrden;
                      final maxSemana = math.max(
                        53,
                        rotacion.map((x) => x.semanaOrden).reduce(math.max),
                      );
                      // Incluye también semanas guardadas anteriores a la actual.
                      // Así el Dropdown siempre contiene exactamente un elemento
                      // con el valor seleccionado (por ejemplo, la semana 28).
                      final minSemana = math.min(semanaActual, semanaValue);
                      final semanasDisponibles = List<int>.generate(
                        (maxSemana - minSemana) + 1,
                        (idx) => minSemana + idx,
                      ).toSet().toList()
                        ..sort();
                      final semanaDropdownValue =
                          semanasDisponibles.contains(semanaValue)
                              ? semanaValue
                              : null;
                      final turnoValue = _turnoValido(r.turnoId, turnos);
                      final fechaInicioAuto = _fechaSemanaInicio(semanaValue);
                      final fechaFinAuto = _fechaSemanaFin(semanaValue);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 190,
                                    child: DropdownButtonFormField<int>(
                                      value: semanaDropdownValue,
                                      isExpanded: true,
                                      items: semanasDisponibles
                                          .map<DropdownMenuItem<int>>(
                                            (w) => DropdownMenuItem<int>(
                                              value: w,
                                              child: Text('Semana $w'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(() {
                                          rotacion[i] = _rotacionConFechas(
                                            semanaOrden: value,
                                            turnoId: r.turnoId,
                                          );
                                        });
                                      },
                                      decoration: const InputDecoration(
                                          labelText: 'Semana'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: turnoValue,
                                      isExpanded: true,
                                      items: turnos
                                          .map<DropdownMenuItem<int>>(
                                            (t) => DropdownMenuItem<int>(
                                              value: t.id,
                                              child: Text(
                                                  '${t.nombre} ${t.horaInicio ?? ''}-${t.horaFin ?? ''}'),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        setDialogState(() {
                                          rotacion[i] = _rotacionConFechas(
                                            semanaOrden: r.semanaOrden,
                                            turnoId: value,
                                          );
                                        });
                                      },
                                      decoration: const InputDecoration(
                                          labelText: 'Turno'),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Quitar semana',
                                    onPressed: rotacion.length == 1
                                        ? null
                                        : () => setDialogState(
                                            () => rotacion.removeAt(i)),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  Chip(
                                    avatar: const Icon(Icons.event_available,
                                        size: 18),
                                    label: Text(
                                        'Inicio: ${r.fechaInicio ?? fechaInicioAuto}'),
                                  ),
                                  Chip(
                                    avatar:
                                        const Icon(Icons.event_busy, size: 18),
                                    label: Text(
                                        'Fin: ${r.fechaFin ?? fechaFinAuto}'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setDialogState(() {
                          final nextWeek = rotacion.isEmpty
                              ? _semanaDelAnio(DateTime.now())
                              : rotacion
                                      .map((r) => r.semanaOrden)
                                      .reduce(math.max) +
                                  1;
                          rotacion.add(
                            _rotacionConFechas(
                              semanaOrden: nextWeek,
                              turnoId: turnos.first.id,
                            ),
                          );
                        }),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar semana'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Guardar rotación')),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      await service.guardarRotacionEmpleado(
          empleadoId: empleado.id, rotacion: rotacion);
      _msg('Rotación semanal actualizada.');
      await _load();
    }
  }

  int _semanaDelAnio(DateTime date) {
    final thursday =
        date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 +
        ((thursday.difference(firstThursday).inDays +
                (firstThursday.weekday == 7 ? 7 : firstThursday.weekday) -
                1) ~/
            7);
    return week.clamp(1, 53);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Ver semana anterior',
                onPressed: () => _cambiarSemanaConsulta(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Empleados Molinos · Semana ${_semanaDelAnio(_fechaSemanaConsulta)}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${_anioIso(_fechaSemanaConsulta)} · ${DateFormat('dd/MM/yyyy').format(_inicioSemanaIso(_semanaDelAnio(_fechaSemanaConsulta), year: _anioIso(_fechaSemanaConsulta)))} al ${DateFormat('dd/MM/yyyy').format(_finSemanaIso(_semanaDelAnio(_fechaSemanaConsulta), year: _anioIso(_fechaSemanaConsulta)))}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Ver semana siguiente',
                onPressed: () => _cambiarSemanaConsulta(1),
                icon: const Icon(Icons.chevron_right),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: _consultandoSemanaActual ? null : _volverSemanaActual,
                icon: const Icon(Icons.today),
                label: const Text('Hoy'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _qCtrl,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por nombre, nómina o puesto'),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _load, icon: const Icon(Icons.search)),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: _exportandoExcel ? null : () => _exportarExcel(),
                icon: _exportandoExcel
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.table_view),
                label: const Text('Excel semanal'),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: _exportandoExcel
                    ? null
                    : () => _exportarExcel(soloTurno: _turnoFiltro),
                icon: const Icon(Icons.download),
                label: const Text('Excel del turno'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                  onPressed: () => _editar(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar')),
            ],
          ),
        ),
        if (!_loading && _turnosFiltro.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Filtrar turno:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ChoiceChip(
                  label: const Text('TODOS'),
                  selected: _turnoFiltro == 'TODOS',
                  onSelected: (_) {
                    setState(() => _turnoFiltro = 'TODOS');
                    _load();
                  },
                ),
                ..._turnosFiltro.map((t) => ChoiceChip(
                      label: Text(t.nombre),
                      selected: _turnoFiltro == t.nombre.toUpperCase(),
                      onSelected: (_) {
                        setState(() => _turnoFiltro = t.nombre.toUpperCase());
                        _load();
                      },
                    )),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: Colors.red)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _empleados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _empleados[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: _fotoProvider(e.foto),
                            child: (e.foto ?? '').isEmpty
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(e.nombre,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nómina: ${e.numeroNomina} · ${e.puesto ?? 'Sin puesto'} · Actual: ${e.turno ?? 'Sin turno'} · ${e.status ?? (e.activo == 1 ? 'ACTIVO' : 'INACTIVO')}',
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _turnoSemanaConsultada[e.id] ??
                                    'Semana consultada: SIN CONFIGURAR',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Rol ${DateTime.now().year}: ${_estadoRolAnual[e.id] ?? 'ROL INCOMPLETO'}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: (_estadoRolAnual[e.id] ?? '')
                                          .startsWith('ROL COMPLETO')
                                      ? Colors.green.shade700
                                      : Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar rotación semanal',
                                icon: const Icon(Icons.calendar_view_week),
                                onPressed: () => _editarRotacion(e),
                              ),
                              IconButton(
                                tooltip: 'Agregar / tomar foto',
                                icon: const Icon(Icons.photo_camera),
                                onPressed: () => _subirFoto(e),
                              ),
                              IconButton(
                                tooltip: 'Editar empleado',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editar(e),
                              ),
                            ],
                          ),
                          onTap: () => _editar(e),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
