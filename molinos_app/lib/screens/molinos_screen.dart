import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/empleado_molinos.dart';
import '../models/maquina_molinos.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/molinos_service.dart';
import '../widgets/empleado_muneco.dart';

class MolinosScreen extends StatefulWidget {
  const MolinosScreen({super.key});

  @override
  State<MolinosScreen> createState() => _MolinosScreenState();
}

class _MolinosScreenState extends State<MolinosScreen> {
  DateTime _fecha = DateTime.now();
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String _turnoFiltro = _turnoAutomaticoInicial();
  TableroMolinos? _tablero;

  final List<String> _turnos = const ['TODOS', 'TURNO 1', 'TURNO 2', 'TURNO 3'];

  static String _turnoAutomaticoInicial() {
    final now = TimeOfDay.now();
    final minutes = now.hour * 60 + now.minute;
    // Turno 1: 06:00 a 14:00
    if (minutes >= 6 * 60 && minutes < 14 * 60) return 'TURNO 1';
    // Turno 2: 14:00 a 21:30
    if (minutes >= 14 * 60 && minutes < (21 * 60 + 30)) return 'TURNO 2';
    // Turno 3: 21:30 a 06:00
    return 'TURNO 3';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthService>().token!;
      final data = await MolinosService(token).tablero(_fecha);
      if (!mounted) return;
      setState(() => _tablero = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sincronizarTurnos() async {
    if (!mounted) return;
    setState(() => _syncing = true);
    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).sincronizarTurnos(_fecha);
      await _load();
      _ok('Turnos sincronizados con empleados_turnos_rotacion.');
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _asignar(EmpleadoMolinos empleado, int maquinaId) async {
    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).asignar(
        empleadoId: empleado.id,
        maquinaId: maquinaId,
        fecha: _fecha,
      );
      await _load();
      if (_esLavador(empleado)) {
        _ok('Lavador asignado al molino. Inició limpieza. Al regresarlo a espera se termina la limpieza.');
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _quitarDeMaquina(EmpleadoMolinos empleado) async {
    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).quitarEmpleado(empleadoId: empleado.id, fecha: _fecha);
      await _load();
      if (_esLavador(empleado)) {
        _ok('Lavador regresado a espera. Limpieza terminada.');
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _estado(MaquinaMolinos maquina, String estado) async {
    final data = await _pedirDatosEstado(maquina, estado);
    if (data == null) return;

    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).cambiarEstado(
        maquinaId: maquina.id,
        estado: estado,
        observaciones: _clean(data['observaciones'] as String?),
        mantenimiento: _clean(data['mantenimiento'] as String?),
        mantenimientoId: data['mantenimiento_id'] as int?,
        descripcionPreven: _clean(data['descripcion_preven'] as String?),
        descripcionCorrec: _clean(data['descripcion_correc'] as String?),
        dias: data['dias'] as int?,
        fechaProxima: _clean(data['fecha_proxima'] as String?),
      );
      await _load();
      if (estado == 'mantenimiento') {
        _ok('Mantenimiento iniciado y bitácora registrada.');
      } else if (maquina.estado == 'mantenimiento') {
        _ok('Mantenimiento cerrado. Se registró fecha, hora de término y tiempo muerto.');
      }
    } catch (e) {
      _showError(e);
    }
  }

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Future<Map<String, dynamic>?> _pedirDatosEstado(MaquinaMolinos maquina, String estado) async {
    String observaciones = '';
    String mantenimiento = '';
    String descripcionPreven = '';
    String descripcionCorrec = '';
    int? mantenimientoId;
    int? diasAuto;
    String fechaProximaAuto = '';

    final esMantenimiento = estado == 'mantenimiento';
    final cierraMantenimiento = maquina.estado == 'mantenimiento' && estado != 'mantenimiento';
    List<MantenimientoMolino> mantenimientos = const [];

    if (esMantenimiento) {
      try {
        final token = context.read<AuthService>().token!;
        mantenimientos = await MolinosService(token).mantenimientosMolinos();
      } catch (e) {
        _showError(e);
      }
    }

    int? diasDesdeTiempoMant(String value) {
      final text = value.toLowerCase().trim();
      final match = RegExp(r'\d+').firstMatch(text);
      if (match == null) return null;
      final n = int.tryParse(match.group(0) ?? '');
      if (n == null) return null;
      if (text.contains('sem')) return n * 7;
      if (text.contains('mes')) return n * 30;
      if (text.contains('año') || text.contains('ano')) return n * 365;
      return n;
    }

    String fechaProximaDesdeDias(int dias) {
      final f = DateTime.now().add(Duration(days: dias));
      return DateFormat('yyyy-MM-dd').format(f);
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(esMantenimiento ? 'Abrir bitácora de mantenimiento' : 'Cambiar ${maquina.nombre}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (esMantenimiento) ...[
                  StatefulBuilder(
                    builder: (context, setDialogState) {
                      return DropdownButtonFormField<int>(
                        value: mantenimientoId,
                        isExpanded: true,
                        items: mantenimientos.map((m) {
                          return DropdownMenuItem<int>(
                            value: m.id,
                            child: Text(
                              '${m.tipoMant} · cada ${m.tiempoMant}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          MantenimientoMolino? seleccionado;
                          for (final m in mantenimientos) {
                            if (m.id == value) {
                              seleccionado = m;
                              break;
                            }
                          }
                          setDialogState(() {
                            mantenimientoId = value;
                            mantenimiento = seleccionado?.tipoMant ?? '';
                            diasAuto = diasDesdeTiempoMant(seleccionado?.tiempoMant ?? '');
                            fechaProximaAuto = diasAuto == null ? '' : fechaProximaDesdeDias(diasAuto!);
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Mantenimiento',
                          helperText: mantenimientos.isEmpty
                              ? 'No hay mantenimientos activos para el área MOLINOS'
                              : 'Se carga desde la tabla mantenimientos',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fechaProximaAuto.isEmpty
                          ? 'Fecha próxima: se calculará con tiempo_mant'
                          : 'Fecha próxima automática: $fechaProximaAuto',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.blueGrey.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    maxLines: 3,
                    onChanged: (value) => descripcionPreven = value,
                    decoration: InputDecoration(
                      labelText: 'Descripción preventiva / inicio',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ] else ...[
                  TextField(
                    maxLines: 3,
                    autofocus: true,
                    onChanged: (value) => observaciones = value,
                    decoration: InputDecoration(
                      labelText: cierraMantenimiento ? 'Descripción correctiva / término' : 'Observaciones',
                      hintText: cierraMantenimiento ? 'Qué se corrigió o cómo terminó el mantenimiento' : 'Opcional',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, {
              'observaciones': observaciones,
              'mantenimiento': mantenimiento,
              'mantenimiento_id': mantenimientoId,
              'descripcion_preven': descripcionPreven,
              'descripcion_correc': cierraMantenimiento ? observaciones : descripcionCorrec,
              'dias': diasAuto,
              'fecha_proxima': fechaProximaAuto,
            }),
            child: Text(esMantenimiento ? 'Abrir mantenimiento' : 'Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _verHistorial(MaquinaMolinos maquina) async {
    try {
      final token = context.read<AuthService>().token!;
      final rows = await MolinosService(token).historialMaquina(
        maquinaId: maquina.id,
        fecha: _fecha,
        turno: _turnoFiltro,
      );
      if (!mounted) return;

      final historial = rows.where((h) => h.tipo != 'mantenimiento').toList();
      final mantenimientos = rows.where((h) => h.tipo == 'mantenimiento').toList();

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Historial ${maquina.nombre}'),
          content: SizedBox(
            width: 680,
            height: 520,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.history), text: 'Estados / asignaciones'),
                      Tab(icon: Icon(Icons.build), text: 'Mantenimientos'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _historialList(historial, vacio: 'Sin historial para esta jornada y turno.'),
                        _historialList(mantenimientos, vacio: 'Sin mantenimientos registrados para este molino.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      _showError(e);
    }
  }

  Widget _historialList(List<MaquinaHistorialMolino> rows, {required String vacio}) {
    if (rows.isEmpty) return Center(child: Text(vacio));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final h = rows[index];
        return ListTile(
          dense: true,
          leading: Icon(
            h.tipo == 'estado'
                ? Icons.settings_suggest
                : h.tipo == 'mantenimiento'
                    ? Icons.build_circle_outlined
                    : Icons.person,
          ),
          title: Text(h.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text([
            '${h.fecha} ${h.hora}',
            if (h.turno?.isNotEmpty == true) h.turno!,
            if (h.subtitulo?.isNotEmpty == true) h.subtitulo!,
            if (h.observaciones?.isNotEmpty == true) h.observaciones!,
          ].join(' · ')),
        );
      },
    );
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  void _ok(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool _visiblePorTurno(EmpleadoMolinos e) {
    if (_turnoFiltro == 'TODOS') return true;
    return e.apareceEnTurno(_turnoFiltro);
  }

  bool _esLavador(EmpleadoMolinos e) => (e.puesto ?? '').toUpperCase().contains('LAVADOR');

  List<EmpleadoMolinos> _filtrarEmpleados(List<EmpleadoMolinos> empleados) {
    return empleados.where(_visiblePorTurno).toList();
  }

  Future<void> _cambiarFecha(int days) async {
    setState(() => _fecha = _fecha.add(Duration(days: days)));
    await _load();
  }

  void _detalle(EmpleadoMolinos e) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(e.nombre),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundImage: e.foto != null && e.foto!.isNotEmpty
                          ? NetworkImage(ApiService.fileUrl(e.foto!))
                          : null,
                      child: e.foto == null || e.foto!.isEmpty
                          ? const Icon(Icons.person, size: 38)
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _info('Nómina', e.numeroNomina),
                          _info('Puesto', e.puesto ?? 'Sin puesto'),
                          _info('Turno', e.turno ?? 'Sin turno'),
                          if (e.horarioTurno.isNotEmpty) _info('Horario', e.horarioTurno),
                          if (!e.turnoEnHorario) _info('Aviso', 'Aún no es su turno'),
                          if (e.turnoPorConcluir) _info('Alerta', 'Turno casi por concluir'),
                          _info('Máquina', e.maquinaNombre ?? 'En espera / afuera'),
                          if (e.horaEntrada != null) _info('Entrada', e.horaEntrada!),
                          if (e.horaSalidaComida != null) _info('Salida comida', e.horaSalidaComida!),
                          if (e.horaRegresoComida != null) _info('Regreso comida', e.horaRegresoComida!),
                          if (e.horaSalida != null) _info('Salida', e.horaSalida!),
                          if (e.horaInicioMaquina != null) _info('Desde en máquina', e.horaInicioMaquina!),
                          if (e.horaFinMaquina != null) _info('Hasta en máquina', e.horaFinMaquina!),
                        ],
                      ),
                    ),
                  ],
                ),
                if (e.acotacion != null) ...[
                  const SizedBox(height: 14),
                  _alertBox('${e.acotacion}: ${e.acotacionDescripcion ?? ''}'),
                ],
                const SizedBox(height: 16),
                const Text('Responsabilidades', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  e.responsabilidades?.isNotEmpty == true
                      ? e.responsabilidades!
                      : 'Sin responsabilidades registradas',
                ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 14),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _alertBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(text, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Column(
      children: [
        _topBar(auth.canEdit),
        _turnosBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : Column(
                      children: [
                        _supervisoresBar(),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(width: 350, child: _panelEmpleados(auth.canEdit)),
                              const VerticalDivider(width: 1),
                              Expanded(child: _panelMaquinas(auth.canEdit)),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _topBar(bool canEdit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          const Text('Molinos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          IconButton(onPressed: () => _cambiarFecha(-1), icon: const Icon(Icons.chevron_left)),
          Text(DateFormat('dd/MM/yyyy').format(_fecha), style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(onPressed: () => _cambiarFecha(1), icon: const Icon(Icons.chevron_right)),
          const Spacer(),
          IconButton(tooltip: 'Actualizar', onPressed: _load, icon: const Icon(Icons.refresh)),
          if (canEdit)
            FilledButton.icon(
              onPressed: _syncing ? null : _sincronizarTurnos,
              icon: _syncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: const Text('Sincronizar turnos'),
            ),
        ],
      ),
    );
  }

  (int, int)? _rangoTurno(String turno) {
    switch (turno) {
      case 'TURNO 1':
        return (6 * 60, 14 * 60);
      case 'TURNO 2':
        return (14 * 60, 21 * 60 + 30);
      case 'TURNO 3':
        return (21 * 60 + 30, 6 * 60);
      default:
        return null;
    }
  }

  String _fmtMin(int value) {
    final v = value % 1440;
    final h = (v ~/ 60).toString().padLeft(2, '0');
    final m = (v % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _relojJornada(String turno) {
    final rango = _rangoTurno(turno);
    if (rango == null) return 'Selecciona un turno para ver el reloj de jornada';
    final now = TimeOfDay.now();
    final actual = now.hour * 60 + now.minute;
    final inicio = rango.$1;
    final fin = rango.$2;
    final duracion = fin > inicio ? fin - inicio : (1440 - inicio) + fin;
    int transcurrido;
    if (inicio < fin) {
      transcurrido = (actual - inicio).clamp(0, duracion);
    } else {
      transcurrido = actual >= inicio ? actual - inicio : (1440 - inicio) + actual;
      transcurrido = transcurrido.clamp(0, duracion);
    }
    final restante = (duracion - transcurrido).clamp(0, duracion);
    return 'Jornada $turno · ${_fmtMin(inicio)} - ${_fmtMin(fin)} · Transcurrido ${_fmtMin(transcurrido)} · Restante ${_fmtMin(restante)}';
  }

  Widget _turnosBar() {
    return Container(
      width: double.infinity,
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _turnos.map((turno) {
              final selected = _turnoFiltro == turno;
              return ChoiceChip(
                selected: selected,
                label: Text(turno == 'TODOS' ? 'Todos' : turno),
                onSelected: (_) => setState(() => _turnoFiltro = turno),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          StreamBuilder<int>(
            stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
            builder: (_, __) => Row(
              children: [
                const Icon(Icons.access_time_filled, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _relojJornada(_turnoFiltro),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _supervisoresBar() {
    final supervisores = _filtrarEmpleados(_tablero?.supervisores ?? []);
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Encargados / Supervisores', Icons.supervisor_account),
          const SizedBox(height: 8),
          if (supervisores.isEmpty)
            Text('Sin encargados o supervisores para este turno.', style: TextStyle(color: Colors.grey.shade700))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: supervisores
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(width: 260, child: _EmpleadoChip(empleado: e, onTap: () => _detalle(e), destacado: true)),
                        ))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelEmpleados(bool canEdit) {
    final t = _tablero!;
    final empleadosDelTurno = _filtrarEmpleados(t.empleadosTurno);
    final espera = _filtrarEmpleados(t.espera);
    final lavadores = espera.where(_esLavador).toList();
    final otrosEspera = espera.where((e) => !_esLavador(e)).toList();
    final alertas = _filtrarEmpleados(t.alertas);
    final ausentes = _filtrarEmpleados(t.ausentes);

    return DragTarget<EmpleadoMolinos>(
      onWillAcceptWithDetails: (_) => canEdit,
      onAcceptWithDetails: (details) => _quitarDeMaquina(details.data),
      builder: (context, candidate, rejected) {
        return Container(
          color: candidate.isNotEmpty ? Colors.blue.shade50 : Colors.grey.shade100,
          padding: const EdgeInsets.all(12),
          child: ListView(
            children: [
              _sectionTitle(
                _turnoFiltro == 'TODOS' ? 'Lista de empleados' : 'Lista de empleados $_turnoFiltro',
                Icons.groups_rounded,
              ),
              const SizedBox(height: 10),
              if (empleadosDelTurno.isEmpty)
                Text('No hay empleados asignados a $_turnoFiltro.')
              else
                ...empleadosDelTurno.map((e) => _empleadoDraggable(e, canEdit)),
              const Divider(height: 30),
              _sectionTitle('Lavadores afuera de molinos', Icons.cleaning_services),
              const SizedBox(height: 10),
              if (lavadores.isEmpty) const Text('No hay lavadores en espera para este turno.'),
              ...lavadores.map((e) => _empleadoDraggable(e, canEdit)),
              const Divider(height: 30),
              _sectionTitle('Empleados en espera', Icons.hourglass_empty),
              const SizedBox(height: 10),
              if (otrosEspera.isEmpty) const Text('No hay empleados en espera para este turno.'),
              ...otrosEspera.map((e) => _empleadoDraggable(e, canEdit)),
              const Divider(height: 30),
              _sectionTitle('Alertas / Acotaciones', Icons.warning_amber_rounded),
              if (alertas.isEmpty) const Text('Sin alertas.'),
              ...alertas.map((e) => _alertTile(e)),
              const Divider(height: 30),
              _sectionTitle('No se presentaron', Icons.person_off),
              if (ausentes.isEmpty) const Text('Sin ausentes.'),
              ...ausentes.map((e) => _ausenteTile(e)),
              const SizedBox(height: 30),
              Text(
                'Arrastra aquí a un empleado para dejarlo afuera/en espera.',
                style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _empleadoDraggable(EmpleadoMolinos e, bool canEdit) {
    final card = EmpleadoMuneco(empleado: e, onTap: () => _detalle(e));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: canEdit
          ? Draggable<EmpleadoMolinos>(
              data: e,
              feedback: Material(
                color: Colors.transparent,
                child: EmpleadoMuneco(empleado: e, compacto: true),
              ),
              childWhenDragging: Opacity(opacity: .35, child: card),
              child: card,
            )
          : card,
    );
  }

  Widget _alertTile(EmpleadoMolinos e) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.warning, color: Colors.red),
      title: Text(e.nombre),
      subtitle: Text('${e.acotacion ?? ''} ${e.acotacionDescripcion ?? ''}'),
      onTap: () => _detalle(e),
    );
  }

  Widget _ausenteTile(EmpleadoMolinos e) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.person_off),
      title: Text(e.nombre),
      subtitle: Text('${e.puesto ?? ''} · ${e.turno ?? 'Sin turno'}'),
      onTap: () => _detalle(e),
    );
  }

  Widget _panelMaquinas(bool canEdit) {
    final maquinas = _tablero!.maquinas;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: maquinas.map((m) {
          final empleados = _filtrarEmpleados(m.empleados).toList();
          return _MaquinaMolinoCard(
            maquina: m,
            empleados: empleados,
            canEdit: canEdit,
            onDropEmpleado: (e) => _asignar(e, m.id),
            onEstado: (estado) => _estado(m, estado),
            onEmpleadoTap: _detalle,
            onHistorial: () => _verHistorial(m),
          );
        }).toList(),
      ),
    );
  }
}

class _EmpleadoChip extends StatelessWidget {
  final EmpleadoMolinos empleado;
  final VoidCallback onTap;
  final bool destacado;

  const _EmpleadoChip({required this.empleado, required this.onTap, this.destacado = false});

  Color _colorFromName(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'azul':
      case 'blue':
        return Colors.blue;
      case 'verde':
      case 'green':
        return Colors.green;
      case 'rojo':
      case 'red':
        return Colors.red;
      case 'amarillo':
      case 'yellow':
        return Colors.amber;
      case 'naranja':
      case 'orange':
        return Colors.orange;
      case 'morado':
      case 'purple':
        return Colors.purple;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final turnoColor = _colorFromName(empleado.turnoColor);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: destacado ? Colors.indigo.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: destacado ? Colors.indigo.shade200 : Colors.grey.shade300),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: empleado.foto != null && empleado.foto!.isNotEmpty
                  ? NetworkImage(ApiService.fileUrl(empleado.foto!))
                  : null,
              child: empleado.foto == null || empleado.foto!.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(empleado.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(empleado.puesto ?? 'Sin puesto', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                  Text(
                    empleado.maquinaNombre == null ? 'En espera / afuera' : 'Máquina: ${empleado.maquinaNombre}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                  if (empleado.turno != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: turnoColor.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        empleado.horarioTurno.isEmpty ? empleado.turno! : '${empleado.turno!} · ${empleado.horarioTurno}',
                        style: TextStyle(color: turnoColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  if (!empleado.turnoEnHorario)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange.shade200)),
                      child: const Text('Aún no es su turno', style: TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            if (empleado.acotacion != null) const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
          ],
        ),
      ),
    );
  }
}


class _EstadoAnimadoIcon extends StatefulWidget {
  final String estado;
  final Color color;

  const _EstadoAnimadoIcon({required this.estado, required this.color});

  @override
  State<_EstadoAnimadoIcon> createState() => _EstadoAnimadoIconState();
}

class _EstadoAnimadoIconState extends State<_EstadoAnimadoIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData get _icon {
    switch (widget.estado.toLowerCase()) {
      case 'trabajando':
        return Icons.settings;
      case 'mantenimiento':
        return Icons.handyman;
      case 'limpieza':
        return Icons.cleaning_services;
      case 'paro':
        return Icons.stop_circle;
      default:
        return Icons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado.toLowerCase();
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final t = _controller.value;
        Widget icon = Icon(_icon, size: 22, color: widget.color);
        if (estado == 'trabajando') {
          icon = Transform.rotate(angle: t * 2 * math.pi, child: icon);
        } else if (estado == 'mantenimiento') {
          icon = Opacity(opacity: .35 + (.65 * (math.sin(t * 2 * math.pi).abs())), child: icon);
        } else if (estado == 'limpieza') {
          icon = Transform.translate(offset: Offset(math.sin(t * 2 * math.pi) * 4, 0), child: icon);
        } else if (estado == 'paro') {
          icon = Transform.scale(scale: 1 + (.08 * math.sin(t * 2 * math.pi).abs()), child: icon);
        }
        return Tooltip(message: estado.toUpperCase(), child: icon);
      },
    );
  }
}


class _MaquinaMolinoCard extends StatelessWidget {
  final MaquinaMolinos maquina;
  final List<EmpleadoMolinos> empleados;
  final bool canEdit;
  final ValueChanged<EmpleadoMolinos> onDropEmpleado;
  final ValueChanged<String> onEstado;
  final ValueChanged<EmpleadoMolinos> onEmpleadoTap;
  final VoidCallback onHistorial;

  const _MaquinaMolinoCard({
    required this.maquina,
    required this.empleados,
    required this.canEdit,
    required this.onDropEmpleado,
    required this.onEstado,
    required this.onEmpleadoTap,
    required this.onHistorial,
  });

  Color _estadoColor(String value) {
    switch (value.toLowerCase()) {
      case 'verde':
      case 'trabajando':
        return Colors.green;
      case 'amarillo':
      case 'limpieza':
        return Colors.amber;
      case 'azul':
      case 'mantenimiento':
        return Colors.blue;
      case 'rojo':
      case 'paro':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String _estadoLabel(String estado) {
    switch (estado) {
      case 'trabajando':
        return 'TRABAJANDO';
      case 'limpieza':
        return 'LIMPIEZA';
      case 'mantenimiento':
        return 'MANTENIMIENTO';
      case 'paro':
        return 'PARO';
      default:
        return estado.toUpperCase();
    }
  }

  String _duracionEstado(DateTime? inicio) {
    if (inicio == null) return '--:--:--';
    final diff = DateTime.now().difference(inicio);
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Widget _estadoButton(String estado, Color color) {
    final selected = maquina.estado.toLowerCase() == estado;
    return OutlinedButton(
      onPressed: canEdit ? () => onEstado(estado) : null,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        side: BorderSide(color: selected ? color : Colors.grey.shade300, width: selected ? 2 : 1),
        backgroundColor: selected ? color.withOpacity(.10) : Colors.white,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(_estadoLabel(estado), style: TextStyle(fontSize: 11, color: selected ? color : Colors.black87, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(maquina.estadoColor.isNotEmpty ? maquina.estadoColor : maquina.estado);
    return DragTarget<EmpleadoMolinos>(
      onWillAcceptWithDetails: (_) => canEdit,
      onAcceptWithDetails: (details) => onDropEmpleado(details.data),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 340,
          constraints: const BoxConstraints(minHeight: 270),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: candidate.isNotEmpty ? color.withOpacity(.08) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x15000000), blurRadius: 12, offset: Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      maquina.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _EstadoAnimadoIcon(estado: maquina.estado, color: color),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: onHistorial,
                    icon: const Icon(Icons.history, size: 16),
                    label: const Text('Historial'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _estadoButton('trabajando', Colors.green),
                  _estadoButton('limpieza', Colors.amber),
                  _estadoButton('mantenimiento', Colors.blue),
                  _estadoButton('paro', Colors.red),
                ],
              ),
              if (maquina.descripcion?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(maquina.descripcion!, style: TextStyle(color: Colors.grey.shade700)),
                ),
              const Divider(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${_estadoLabel(maquina.estado)} desde ${maquina.estadoHoraInicio ?? '--:--'}',
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                        const Icon(Icons.timer_outlined, size: 18),
                        StreamBuilder<int>(
                          stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
                          builder: (_, __) => Text(
                            _duracionEstado(maquina.estadoInicioDateTime),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if (maquina.estadoObservaciones != null) Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(maquina.estadoObservaciones!, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              if (maquina.mantenimientoFechaProxima != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: maquina.mantenimientoAlerta ? Colors.orange.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: maquina.mantenimientoAlerta ? Colors.orange.shade300 : Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        maquina.mantenimientoAlerta ? Icons.notifications_active : Icons.notifications_none,
                        color: maquina.mantenimientoAlerta ? Colors.deepOrange : Colors.grey.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Próximo mantenimiento: ${maquina.mantenimientoFechaProxima}'
                          '${maquina.mantenimientoProximo == null ? '' : ' · ${maquina.mantenimientoProximo}'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: maquina.mantenimientoAlerta ? Colors.deepOrange : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('Lista de empleados (${empleados.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (empleados.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text('Arrastra empleados aquí. Si es LAVADOR, se queda en el molino y cambia a Limpieza.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                )
              else
                ...empleados.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: canEdit
                          ? Draggable<EmpleadoMolinos>(
                              data: e,
                              feedback: Material(
                                color: Colors.transparent,
                                child: EmpleadoMuneco(empleado: e, compacto: true),
                              ),
                              childWhenDragging: Opacity(opacity: .35, child: EmpleadoMuneco(empleado: e, onTap: () => onEmpleadoTap(e))),
                              child: EmpleadoMuneco(empleado: e, onTap: () => onEmpleadoTap(e)),
                            )
                          : EmpleadoMuneco(empleado: e, onTap: () => onEmpleadoTap(e)),
                    )),
            ],
          ),
        );
      },
    );
  }
}
