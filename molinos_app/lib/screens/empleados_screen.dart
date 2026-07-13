import '../utils/web_file_picker.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.setAttribute('capture', 'environment');
    input.click();
    await input.onChange.first;

    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return null;

    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;

    final result = reader.result;
    late final Uint8List bytes;

    if (result is ByteBuffer) {
      bytes = Uint8List.view(result);
    } else if (result is Uint8List) {
      bytes = result;
    } else if (result is List<int>) {
      bytes = Uint8List.fromList(result);
    } else {
      throw Exception(
          'No se pudo leer la foto seleccionada. Intenta con otra imagen JPG, PNG o WEBP.');
    }

    return _FotoSeleccionada(
        bytes: bytes, filename: file.name.isEmpty ? 'empleado.jpg' : file.name);
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
                      final maxSemana = math.max(53,
                          rotacion.map((x) => x.semanaOrden).reduce(math.max));
                      final semanaValue = r.semanaOrden <= 0
                          ? _semanaDelAnio(DateTime.now())
                          : r.semanaOrden;
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
                                      value: semanaValue,
                                      items: List.generate(
                                              (maxSemana - semanaActual) + 1,
                                              (idx) => semanaActual + idx)
                                          .map<DropdownMenuItem<int>>((w) =>
                                              DropdownMenuItem<int>(
                                                  value: w,
                                                  child: Text('Semana $w')))
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
              Text(
                  'Empleados Molinos · Semana del año ${_semanaDelAnio(DateTime.now())}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
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
                          subtitle: Text(
                            'Nómina: ${e.numeroNomina} · ${e.puesto ?? 'Sin puesto'} · Actual: ${e.turno ?? 'Sin turno'} · Sigue: ${e.proximoTurno ?? 'Sin próximo turno'} · ${e.status ?? (e.activo == 1 ? 'ACTIVO' : 'INACTIVO')}',
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
