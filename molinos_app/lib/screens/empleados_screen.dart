import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/empleado_molinos.dart';
import '../services/auth_service.dart';
import '../services/molinos_service.dart';

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

  MolinosService _service() => MolinosService(context.read<AuthService>().token!);

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = _service();
      _turnosFiltro = _turnosUnicos(await service.turnos());
      _empleados = await service.empleados(q: _qCtrl.text.trim(), turno: _turnoFiltro);
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
    String puestoSeleccionado = _puestos.contains((empleado?.puesto ?? '').toUpperCase().trim()) ? (empleado?.puesto ?? '').toUpperCase().trim() : 'OTRO';
    final responsabilidades = TextEditingController(text: empleado?.responsabilidades ?? '');
    final telefono = TextEditingController();
    final direccion = TextEditingController();
    final status = TextEditingController(text: 'ACTIVO');

    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(esNuevo ? 'Agregar empleado' : 'Editar empleado'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nomina, decoration: const InputDecoration(labelText: 'Nómina')),
                  TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre')),
                  DropdownButtonFormField<String>(
                    value: puestoSeleccionado,
                    items: _puestos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (value) => puestoSeleccionado = value ?? 'OTRO',
                    decoration: const InputDecoration(labelText: 'Puesto'),
                  ),
                  TextField(controller: responsabilidades, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Responsabilidades')),
                  TextField(controller: telefono, decoration: const InputDecoration(labelText: 'Teléfono')),
                  TextField(controller: direccion, decoration: const InputDecoration(labelText: 'Dirección')),
                  TextField(controller: status, decoration: const InputDecoration(labelText: 'Status')),
                  const SizedBox(height: 10),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Departamento: MOLINOS', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      );

      if (ok != true) return;
      if (nomina.text.trim().isEmpty || nombre.text.trim().isEmpty) {
        _msg('Nómina y nombre son obligatorios.');
        return;
      }

      if (esNuevo) {
        await _service().crearEmpleado(
          numeroNomina: nomina.text.trim(),
          nombre: nombre.text.trim(),
          puesto: puestoSeleccionado,
          responsabilidades: responsabilidades.text.trim(),
          departamento: 'MOLINOS',
          telefono: telefono.text.trim(),
          direccion: direccion.text.trim(),
          status: status.text.trim().isEmpty ? 'ACTIVO' : status.text.trim(),
        );
        _msg('Empleado agregado.');
      } else {
        await _service().actualizarEmpleado(
          empleadoId: empleado.id,
          numeroNomina: nomina.text.trim(),
          nombre: nombre.text.trim(),
          puesto: puestoSeleccionado,
          responsabilidades: responsabilidades.text.trim(),
          departamento: 'MOLINOS',
          telefono: telefono.text.trim(),
          direccion: direccion.text.trim(),
          status: status.text.trim().isEmpty ? null : status.text.trim(),
        );
        _msg('Empleado actualizado.');
      }
      await _load();
    } finally {
      nomina.dispose();
      nombre.dispose();
      responsabilidades.dispose();
      telefono.dispose();
      direccion.dispose();
      status.dispose();
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

  Future<void> _subirFoto(EmpleadoMolinos empleado) async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    // En Flutter Web no existe el setter capture; se agrega como atributo HTML.
    input.setAttribute('capture', 'environment');
    input.click();
    await input.onChange.first;
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final bytes = Uint8List.view(reader.result as ByteBuffer);
    await _service().subirFotoEmpleado(empleadoId: empleado.id, bytes: bytes, filename: file.name);
    _msg('Foto actualizada.');
    await _load();
  }

  Future<void> _editarRotacion(EmpleadoMolinos empleado) async {
    final service = _service();
    List<TurnoMolino> turnos = _turnosUnicos(await service.turnos());
    List<RotacionTurnoMolino> rotacion = await service.rotacionEmpleado(empleado.id);

    if (turnos.isEmpty) {
      _msg('No hay turnos activos para asignar.');
      return;
    }

    if (rotacion.isEmpty) {
      rotacion = [
        RotacionTurnoMolino(
          semanaOrden: _semanaDelAnio(DateTime.now()),
          turnoId: turnos.first.id,
          fechaInicio: DateFormat('yyyy-MM-dd').format(DateTime.now()),
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
                      final maxSemana = math.max(53, rotacion.map((x) => x.semanaOrden).reduce(math.max));
                      final semanaValue = r.semanaOrden <= 0 ? _semanaDelAnio(DateTime.now()) : r.semanaOrden;
                      final turnoValue = _turnoValido(r.turnoId, turnos);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: DropdownButtonFormField<int>(
                                  value: semanaValue,
                                  items: List.generate((maxSemana - semanaActual) + 1, (idx) => semanaActual + idx)
                                      .map<DropdownMenuItem<int>>((w) => DropdownMenuItem<int>(value: w, child: Text('Semana del año $w')))
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      rotacion[i] = RotacionTurnoMolino(
                                        semanaOrden: value,
                                        turnoId: r.turnoId,
                                        fechaInicio: r.fechaInicio ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                        fechaFin: r.fechaFin,
                                      );
                                    });
                                  },
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
                                          child: Text('${t.nombre} ${t.horaInicio ?? ''}-${t.horaFin ?? ''}'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      rotacion[i] = RotacionTurnoMolino(
                                        semanaOrden: r.semanaOrden,
                                        turnoId: value,
                                        fechaInicio: r.fechaInicio ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
                                        fechaFin: r.fechaFin,
                                      );
                                    });
                                  },
                                  decoration: const InputDecoration(labelText: 'Turno'),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Quitar semana',
                                onPressed: rotacion.length == 1 ? null : () => setDialogState(() => rotacion.removeAt(i)),
                                icon: const Icon(Icons.delete_outline),
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
                          final nextWeek = rotacion.isEmpty ? _semanaDelAnio(DateTime.now()) : rotacion.map((r) => r.semanaOrden).reduce(math.max) + 1;
                          rotacion.add(
                            RotacionTurnoMolino(
                              semanaOrden: nextWeek,
                              turnoId: turnos.first.id,
                              fechaInicio: DateFormat('yyyy-MM-dd').format(DateTime.now()),
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
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar rotación')),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      await service.guardarRotacionEmpleado(empleadoId: empleado.id, rotacion: rotacion);
      _msg('Rotación semanal actualizada.');
      await _load();
    }
  }

  int _semanaDelAnio(DateTime date) {
    final thursday = date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 + ((thursday.difference(firstThursday).inDays + (firstThursday.weekday == 7 ? 7 : firstThursday.weekday) - 1) ~/ 7);
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
              Text('Empleados Molinos · Semana del año ${_semanaDelAnio(DateTime.now())}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _qCtrl,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, nómina o puesto'),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _load, icon: const Icon(Icons.search)),
              FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Agregar')),
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
                const Text('Filtrar turno:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _empleados.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _empleados[i];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Nómina: ${e.numeroNomina} · ${e.puesto ?? 'Sin puesto'} · ${e.turno ?? 'Sin turno'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar rotación semanal',
                                icon: const Icon(Icons.calendar_view_week),
                                onPressed: () => _editarRotacion(e),
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
