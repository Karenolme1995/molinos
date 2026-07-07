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
  String _vistaHistorial = 'dia';
  Timer? _turnoAutoTimer;
  TableroMolinos? _tablero;
  bool _vistaTabla = false;
  bool _mostrarListaEmpleados = true;

  final List<String> _turnos = const ['TURNO 1', 'TURNO 2', 'TURNO 3'];
  static const List<String> _puestos = [
    'AYUD.GENERAL',
    'LAVADOR',
    'MANGAS',
    'MONTACARGUISTA',
    'OP.MOLINOS',
    'SUPERVISOR',
    'OTRO',
  ];

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
    _turnoAutoTimer = Timer.periodic(const Duration(minutes: 1), (_) => _verificarCambioAutomaticoTurno());
  }

  @override
  void dispose() {
    _turnoAutoTimer?.cancel();
    super.dispose();
  }

  Future<void> _verificarCambioAutomaticoTurno() async {
    final automatico = _turnoAutomaticoInicial();
    if (!mounted || automatico == _turnoFiltro) return;
    setState(() => _turnoFiltro = automatico);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ya comenzó $automatico · TURNO ACTUAL')),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = context.read<AuthService>().token!;
      final data = await MolinosService(token).tablero(_fecha, turno: _turnoFiltro, vista: 'dia');
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
    String buscarMantenimiento = '';

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
                      final qMant = buscarMantenimiento.trim().toLowerCase();
                      final List<MantenimientoMolino> filtrados = qMant.isEmpty
                          ? mantenimientos
                          : mantenimientos.where((m) {
                              return m.tipoMant.toLowerCase().contains(qMant) ||
                                  m.tiempoMant.toLowerCase().contains(qMant);
                            }).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (value) {
                                    setDialogState(() => buscarMantenimiento = value);
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Buscar mantenimiento',
                                    prefixIcon: const Icon(Icons.search),
                                    helperText: mantenimientos.isEmpty
                                        ? 'No hay mantenimientos activos para el área MOLINOS'
                                        : 'Se carga desde la tabla mantenimientos',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filled(
                                tooltip: 'Agregar mantenimiento al catálogo',
                                icon: const Icon(Icons.add),
                                onPressed: () async {
                                  final tipoCtrl = TextEditingController();
                                  final tiempoCtrl = TextEditingController();
                                  try {
                                    final ok = await showDialog<bool>(
                                      context: dialogContext,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Nuevo mantenimiento MOLINOS'),
                                        content: SizedBox(
                                          width: 420,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextField(
                                                controller: tipoCtrl,
                                                decoration: const InputDecoration(labelText: 'Tipo mantenimiento'),
                                              ),
                                              TextField(
                                                controller: tiempoCtrl,
                                                decoration: const InputDecoration(
                                                  labelText: 'Tiempo / frecuencia en días',
                                                  hintText: 'Ejemplo: 7, 15, 30',
                                                ),
                                                keyboardType: TextInputType.number,
                                              ),
                                            ],
                                          ),
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      final tipo = tipoCtrl.text.trim();
                                      final tiempo = tiempoCtrl.text.trim();
                                      if (tipo.isEmpty || tiempo.isEmpty) {
                                        _showError('Tipo y tiempo son obligatorios');
                                        return;
                                      }
                                      final token = this.context.read<AuthService>().token!;
                                      final service = MolinosService(token);
                                      final nuevoMant = await service.crearMantenimientoMolinos(tipoMant: tipo, tiempoMant: tiempo);
                                      final actualizados = await service.mantenimientosMolinos();
                                      setDialogState(() {
                                        mantenimientos = actualizados;
                                        mantenimientoId = nuevoMant.id;
                                        mantenimiento = tipo;
                                        diasAuto = diasDesdeTiempoMant(tiempo);
                                        fechaProximaAuto = diasAuto == null ? '' : fechaProximaDesdeDias(diasAuto!);
                                      });
                                      _ok('Mantenimiento agregado al catálogo.');
                                    }
                                  } finally {
                                    tipoCtrl.dispose();
                                    tiempoCtrl.dispose();
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 190),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtrados.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final m = filtrados[index];
                                final seleccionado = mantenimientoId == m.id;
                                return ListTile(
                                  dense: true,
                                  selected: seleccionado,
                                  leading: Icon(seleccionado ? Icons.check_circle : Icons.build_outlined),
                                  title: Text(m.tipoMant, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text('Frecuencia: ${m.tiempoMant}'),
                                  onTap: () {
                                    setDialogState(() {
                                      mantenimientoId = m.id;
                                      mantenimiento = m.tipoMant;
                                      diasAuto = diasDesdeTiempoMant(m.tiempoMant);
                                      fechaProximaAuto = diasAuto == null ? '' : fechaProximaDesdeDias(diasAuto!);
                                    });
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      fechaProximaAuto.isEmpty
                          ? 'Fecha próxima: se calculará con los días del mantenimiento'
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
      final data = await MolinosService(token).historialMaquinaDetalle(
        maquinaId: maquina.id,
        fecha: _fecha,
        turno: _turnoFiltro,
        vista: _vistaHistorial,
      );
      final rows = List<MaquinaHistorialMolino>.from(data['historial'] as List);
      final conteos = Map<String, dynamic>.from(data['conteos'] ?? {});
      final fichaTecnica = Map<String, dynamic>.from(data['ficha_tecnica'] ?? {});
      if (!mounted) return;

      final historial = rows.where((h) => h.tipo != 'mantenimiento').toList();
      final mantenimientos = rows.where((h) => h.tipo == 'mantenimiento').toList();
      final asignaciones = rows.where((h) => h.tipo == 'asignacion').toList();

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Historial ${maquina.nombre}'),
          content: SizedBox(
            width: 680,
            height: 520,
            child: DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  StatefulBuilder(
                    builder: (context, setDialogState) => Wrap(
                      spacing: 8,
                      children: ['dia', 'semana', 'mes'].map((v) {
                        return ChoiceChip(
                          selected: _vistaHistorial == v,
                          label: Text(v.toUpperCase()),
                          onSelected: (_) {
                            setDialogState(() => _vistaHistorial = v);
                            Navigator.pop(context);
                            _verHistorial(maquina);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TabBar(
                    tabs: [
                      Tab(icon: const Icon(Icons.history), text: 'Estados/asig. (${conteos['estados_asignaciones'] ?? historial.length})'),
                      Tab(icon: const Icon(Icons.build), text: 'Mantenimientos (${conteos['mantenimientos'] ?? mantenimientos.length})'),
                      const Tab(icon: Icon(Icons.description), text: 'Ficha técnica'),
                      const Tab(icon: Icon(Icons.people), text: 'Personas por turno'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _historialList(historial, vacio: 'Sin historial para esta vista y turno.', maquina: maquina),
                        _historialList(mantenimientos, vacio: 'Sin mantenimientos registrados para este molino.', maquina: maquina),
                        _fichaTecnicaMaquina(maquina, fichaTecnica),
                        _personasAsignadasPorTurno(asignaciones),
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

  Widget _historialList(List<MaquinaHistorialMolino> rows, {required String vacio, MaquinaMolinos? maquina}) {
    if (rows.isEmpty) return Center(child: Text(vacio));
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final h = rows[index];
        if (h.tipo == 'mantenimiento') {
          final color = _colorSemaforo(h.semaforo);
          final restante = h.diasRestantes == null
              ? ''
              : h.diasRestantes! <= 0
                  ? 'vence hoy'
                  : 'faltan ${h.diasRestantes} días';
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: color.withOpacity(.08),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: color.withOpacity(.75), width: h.semaforo == null ? 1 : 2),
            ),
            child: ListTile(
              leading: Icon(Icons.build_circle_outlined, color: color),
              title: Text(h.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text([
                'Inicio: ${h.fecha} ${h.hora}',
                if (h.fechaProxima?.isNotEmpty == true) 'Próximo: ${h.fechaProxima} $restante',
                if (h.dias != null) 'Frecuencia: ${h.dias} días',
                if (h.statusManto?.isNotEmpty == true) 'Estatus: ${h.statusManto}',
                if (h.tiempoMuerto?.isNotEmpty == true) 'Tiempo muerto: ${h.tiempoMuerto}',
              ].join(' · ')),
              onTap: () => _verBitacoraFormato(h),
              trailing: Wrap(
                spacing: 6,
                children: [
                  IconButton(
                    tooltip: 'Ver formato',
                    icon: const Icon(Icons.description_outlined),
                    onPressed: () => _verBitacoraFormato(h),
                  ),
                  if (maquina != null && h.mantenimientoActivo)
                    IconButton(
                      tooltip: 'Cerrar mantenimiento',
                      icon: const Icon(Icons.task_alt, color: Colors.green),
                      onPressed: () => _cerrarMantenimientoDialog(maquina, h),
                    ),
                ],
              ),
            ),
          );
        }
        return ListTile(
          dense: true,
          leading: Icon(h.tipo == 'estado' ? Icons.settings_suggest : Icons.person),
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


  Widget _fichaTecnicaMaquina(MaquinaMolinos maquina, Map<String, dynamic> ficha) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Máquina', (ficha['nombre'] ?? maquina.nombre).toString()),
      MapEntry('Área', (ficha['area'] ?? 'MOLINOS').toString()),
      MapEntry('Descripción', (ficha['descripcion'] ?? maquina.descripcion ?? 'Sin descripción').toString()),
      MapEntry('Código interno', (ficha['codigo'] ?? 'Sin capturar').toString()),
      MapEntry('Marca', (ficha['marca'] ?? 'Sin capturar').toString()),
      MapEntry('Modelo', (ficha['modelo'] ?? 'Sin capturar').toString()),
      MapEntry('Serie', (ficha['serie'] ?? 'Sin capturar').toString()),
      MapEntry('Ubicación', (ficha['ubicacion'] ?? 'Sin capturar').toString()),
      MapEntry('Capacidad', (ficha['capacidad'] ?? 'Sin capturar').toString()),
      MapEntry('Voltaje', (ficha['voltaje'] ?? 'Sin capturar').toString()),
      MapEntry('Potencia', (ficha['potencia'] ?? 'Sin capturar').toString()),
      MapEntry('Proveedor', (ficha['proveedor'] ?? 'Sin capturar').toString()),
      MapEntry('Fecha instalación', (ficha['fecha_instalacion'] ?? 'Sin capturar').toString()),
      MapEntry('Fecha alta', (ficha['fecha_alta'] ?? 'Sin dato').toString()),
      MapEntry('Última actualización', (ficha['actualizado'] ?? 'Sin dato').toString()),
      MapEntry('Estado actual', maquina.estadoNombre),
      MapEntry('Inicio estado', '${maquina.estadoFechaInicio ?? '-'} ${maquina.estadoHoraInicio ?? ''}'.trim()),
      MapEntry('Observaciones estado', maquina.estadoObservaciones ?? 'Sin observaciones'),
      MapEntry('Próximo mantenimiento', maquina.mantenimientoProximo ?? 'Sin mantenimiento próximo'),
      MapEntry('Fecha próxima', maquina.mantenimientoFechaProxima ?? 'Sin fecha'),
      MapEntry('Días restantes', maquina.mantenimientoDiasRestantes == null ? 'Sin dato' : '${maquina.mantenimientoDiasRestantes}'),
      MapEntry('Notas', (ficha['notas'] ?? 'Sin notas').toString()),
    ];

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.precision_manufacturing_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ficha técnica de ${maquina.nombre}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Table(
                  columnWidths: const {0: FixedColumnWidth(170), 1: FlexColumnWidth()},
                  border: TableBorder.all(color: Colors.black12),
                  children: rows.map((r) {
                    return TableRow(
                      children: [
                        Container(
                          color: Colors.grey.shade100,
                          padding: const EdgeInsets.all(9),
                          child: Text(r.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(9),
                          child: Text(r.value.isEmpty ? '-' : r.value),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Para editar estos datos llena la tabla maquina_ficha_tecnica. Si no hay datos, se muestra la información básica de maquinas.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }


  Widget _personasAsignadasPorTurno(List<MaquinaHistorialMolino> asignaciones) {
    if (asignaciones.isEmpty) {
      return const Center(child: Text('Sin personas asignadas para esta vista.'));
    }

    final Map<String, List<MaquinaHistorialMolino>> grupos = {};
    for (final a in asignaciones) {
      final turno = (a.turno == null || a.turno!.trim().isEmpty) ? 'SIN TURNO' : a.turno!.trim().toUpperCase();
      grupos.putIfAbsent(turno, () => []).add(a);
    }

    final turnos = grupos.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: turnos.length,
      itemBuilder: (_, index) {
        final turno = turnos[index];
        final rows = grupos[turno]!;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: const Icon(Icons.groups),
            title: Text('$turno (${rows.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            children: rows.map((h) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(h.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  '${h.fecha} ${h.hora}',
                  if (h.subtitulo?.isNotEmpty == true) h.subtitulo!,
                  if (h.observaciones?.isNotEmpty == true) h.observaciones!,
                ].join(' · ')),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Color _colorSemaforo(String? semaforo) {
    switch ((semaforo ?? '').toLowerCase()) {
      case 'rojo':
        return Colors.red;
      case 'amarillo':
        return Colors.amber;
      case 'verde':
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _cerrarMantenimientoDialog(MaquinaMolinos maquina, MaquinaHistorialMolino bitacora) async {
    String descripcion = '';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cerrar mantenimiento ${maquina.nombre}'),
        content: TextField(
          maxLines: 4,
          onChanged: (value) => descripcion = value,
          decoration: InputDecoration(
            labelText: 'Descripción correctiva / término',
            hintText: 'Qué se corrigió y cómo terminó el mantenimiento',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar mantenimiento')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).cerrarMantenimiento(
        maquinaId: maquina.id,
        bitacoraId: bitacora.bitacoraId,
        descripcionCorrec: _clean(descripcion),
      );
      await _load();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _ok('Mantenimiento cerrado. Se calculó el tiempo muerto.');
    } catch (e) {
      _showError(e);
    }
  }

  void _verBitacoraFormato(MaquinaHistorialMolino h) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Bitácora ${h.numero ?? ''}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _info('Mantenimiento', h.titulo),
                _info('Fecha inicio', '${h.fecha} ${h.hora}'),
                _info('Fecha próxima', h.fechaProxima ?? 'Sin fecha'),
                _info('Días / frecuencia', h.dias == null ? 'Sin días' : '${h.dias} días'),
                _info('Días restantes', h.diasRestantes == null ? 'Sin dato' : '${h.diasRestantes}'),
                _info('Estatus', h.statusManto ?? 'Sin estatus'),
                _info('Operador', h.operador ?? ''),
                _info('Supervisor', h.supervisor ?? ''),
                _info('Usuario', h.usuario ?? ''),
                const Divider(height: 24),
                const Text('Descripción preventiva', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(h.descripcionPreven?.isNotEmpty == true ? h.descripcionPreven! : 'Sin descripción preventiva'),
                const SizedBox(height: 12),
                const Text('Descripción correctiva', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(h.descripcionCorrec?.isNotEmpty == true ? h.descripcionCorrec! : 'Sin descripción correctiva'),
                const Divider(height: 24),
                _info('Fecha término', h.fechaTermino == null ? 'Abierto' : '${h.fechaTermino} ${h.horaTermino ?? ''}'),
                _info('Tiempo muerto', h.tiempoMuerto ?? 'En curso'),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
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
    // Filtro estricto por turno actual configurado en empleados_turnos_rotacion.
    return (e.turno ?? '').toUpperCase().trim() == _turnoFiltro.toUpperCase().trim();
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
        actions: [
          if (context.read<AuthService>().canEdit)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _editarEmpleadoDialog(e);
              },
              child: const Text('Editar empleado / rotación'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
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

  int? _valorDropdownValido(int? value, List<TurnoMolino> turnos) {
    if (value == null || value == 0) return null;
    return turnos.any((t) => t.id == value) ? value : null;
  }

  Future<void> _editarEmpleadoDialog(EmpleadoMolinos e) async {
    final token = context.read<AuthService>().token!;
    final service = MolinosService(token);
    final numeroCtrl = TextEditingController(text: e.numeroNomina);
    final nombreCtrl = TextEditingController(text: e.nombre);
    String puestoSeleccionado = _puestos.contains((e.puesto ?? '').toUpperCase().trim())
        ? (e.puesto ?? '').toUpperCase().trim()
        : 'OTRO';
    final respCtrl = TextEditingController(text: e.responsabilidades ?? '');
    final telefonoCtrl = TextEditingController(text: e.telefono ?? '');
    final direccionCtrl = TextEditingController(text: e.direccion ?? '');
    int activoSeleccionado = e.activo == 0 ? 0 : 1;
    int? turnoId;
    List<TurnoMolino> turnos = const [];

    try {
      turnos = _turnosUnicos(await service.turnos());
      final actual = turnos.where((t) => t.nombre.toUpperCase() == (e.turno ?? '').toUpperCase()).toList();
      if (actual.isNotEmpty) turnoId = actual.first.id;
      turnoId = _valorDropdownValido(turnoId, turnos);
    } catch (_) {}

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Editar ${e.nombre}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: numeroCtrl, decoration: const InputDecoration(labelText: 'Nómina')),
                    TextField(controller: nombreCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                    DropdownButtonFormField<String>(
                      value: puestoSeleccionado,
                      items: _puestos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                      onChanged: (value) => setDialogState(() => puestoSeleccionado = value ?? 'OTRO'),
                      decoration: const InputDecoration(labelText: 'Puesto'),
                    ),
                    TextField(
                      controller: respCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Responsabilidades'),
                    ),
                    TextField(controller: telefonoCtrl, decoration: const InputDecoration(labelText: 'Teléfono')),
                    TextField(controller: direccionCtrl, decoration: const InputDecoration(labelText: 'Dirección')),
                    DropdownButtonFormField<int>(
                      value: activoSeleccionado,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Activo')),
                        DropdownMenuItem(value: 0, child: Text('Inactivo')),
                      ],
                      onChanged: (value) => setDialogState(() => activoSeleccionado = value ?? 1),
                      decoration: const InputDecoration(labelText: 'Status'),
                    ),
                    const SizedBox(height: 14),
                    const Text('Turno actual', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButtonFormField<int>(
                      value: _valorDropdownValido(turnoId, turnos),
                      items: turnos.map<DropdownMenuItem<int>>((t) {
                        final horario = [t.horaInicio, t.horaFin].whereType<String>().join(' - ');
                        return DropdownMenuItem(value: t.id, child: Text('${t.nombre}${horario.isEmpty ? '' : ' ($horario)'}'));
                      }).toList(),
                      onChanged: (value) => setDialogState(() => turnoId = value),
                      decoration: const InputDecoration(labelText: 'Selecciona turno'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _rotacionSemanalDialog(e, turnos),
                      icon: const Icon(Icons.calendar_view_week),
                      label: const Text('Editar rotación semanal'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await service.actualizarEmpleado(
                      empleadoId: e.id,
                      numeroNomina: numeroCtrl.text.trim(),
                      nombre: nombreCtrl.text.trim(),
                      puesto: puestoSeleccionado,
                      responsabilidades: respCtrl.text.trim(),
                      departamento: 'MOLINOS',
                      telefono: telefonoCtrl.text.trim(),
                      direccion: direccionCtrl.text.trim(),
                      status: activoSeleccionado == 1 ? 'ACTIVO' : 'INACTIVO',
                      activo: activoSeleccionado,
                    );
                    if (turnoId != null) {
                      await service.guardarRotacionEmpleado(
                        empleadoId: e.id,
                        rotacion: [
                          RotacionTurnoMolino(
                            semanaOrden: _semanaDelAnio(_fecha),
                            turnoId: turnoId!,
                            fechaInicio: DateFormat('yyyy-MM-dd').format(_fecha),
                          ),
                        ],
                      );
                    }
                    if (mounted) Navigator.pop(context);
                    await _load();
                    _ok('Empleado actualizado');
                  } catch (err) {
                    _showError(err);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    numeroCtrl.dispose();
    nombreCtrl.dispose();
    respCtrl.dispose();
    telefonoCtrl.dispose();
    direccionCtrl.dispose();
  }

  Future<void> _rotacionSemanalDialog(EmpleadoMolinos e, List<TurnoMolino> turnosIniciales) async {
    final token = context.read<AuthService>().token!;
    final service = MolinosService(token);
    var turnos = _turnosUnicos(turnosIniciales);
    if (turnos.isEmpty) turnos = _turnosUnicos(await service.turnos());
    var rotacion = await service.rotacionEmpleado(e.id);
    if (rotacion.isEmpty && turnos.isNotEmpty) {
      rotacion = [
        RotacionTurnoMolino(semanaOrden: _semanaDelAnio(_fecha), turnoId: turnos.first.id, fechaInicio: DateFormat('yyyy-MM-dd').format(_fecha)),
      ];
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Rotación semanal - ${e.nombre}'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Define desde la semana actual del año en adelante y el turno que tendrá el empleado.', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 10),
                    ...rotacion.asMap().entries.map((entry) {
                      final i = entry.key;
                      final r = entry.value;
                      final semanaActual = _semanaDelAnio(_fecha);
                      final maxSemana = math.max(53, rotacion.isEmpty ? semanaActual : rotacion.map((x) => x.semanaOrden).reduce(math.max));
                      final semanaValue = r.semanaOrden <= 0 ? _semanaDelAnio(_fecha) : r.semanaOrden;
                      final turnoValue = _valorDropdownValido(r.turnoId, turnos);
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 82,
                                child: DropdownButtonFormField<int>(
                                  value: semanaValue,
                                  items: List.generate((maxSemana - semanaActual) + 1, (idx) => semanaActual + idx)
                                      .map((w) => DropdownMenuItem<int>(value: w, child: Text('Semana del año $w')))
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() => rotacion[i] = RotacionTurnoMolino(
                                      semanaOrden: value,
                                      turnoId: r.turnoId,
                                      fechaInicio: r.fechaInicio ?? DateFormat('yyyy-MM-dd').format(_fecha),
                                      fechaFin: r.fechaFin,
                                    ));
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: turnoValue,
                                  items: turnos.map<DropdownMenuItem<int>>((t) => DropdownMenuItem<int>(value: t.id, child: Text('${t.nombre} ${t.horaInicio ?? ''}-${t.horaFin ?? ''}'))).toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() => rotacion[i] = RotacionTurnoMolino(
                                      semanaOrden: r.semanaOrden,
                                      turnoId: value,
                                      fechaInicio: r.fechaInicio ?? DateFormat('yyyy-MM-dd').format(_fecha),
                                      fechaFin: r.fechaFin,
                                    ));
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
                        onPressed: turnos.isEmpty ? null : () => setDialogState(() {
                          final nextWeek = rotacion.isEmpty ? _semanaDelAnio(_fecha) : (rotacion.map((r) => r.semanaOrden).reduce(math.max) + 1);
                          rotacion.add(RotacionTurnoMolino(
                            semanaOrden: nextWeek,
                            turnoId: turnos.first.id,
                            fechaInicio: DateFormat('yyyy-MM-dd').format(_fecha),
                          ));
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await service.guardarRotacionEmpleado(empleadoId: e.id, rotacion: rotacion);
                    if (mounted) Navigator.pop(context);
                    _ok('Rotación semanal actualizada');
                  } catch (err) {
                    _showError(err);
                  }
                },
                child: const Text('Guardar rotación'),
              ),
            ],
          );
        },
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

  int _semanaDelAnio(DateTime date) {
    final thursday = date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 + ((thursday.difference(firstThursday).inDays + (firstThursday.weekday == 7 ? 7 : firstThursday.weekday) - 1) ~/ 7);
    return week.clamp(1, 53);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final pantallaChica = ancho < 760;
        final mostrarPanelEmpleados = !_vistaTabla && _mostrarListaEmpleados && !pantallaChica;
        final panelWidth = ancho < 980 ? 300.0 : 350.0;
        final usarCompacto = _vistaTabla || pantallaChica;

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
                              child: pantallaChica
                                  ? _panelMaquinas(
                                      auth.canEdit,
                                      compacto: true,
                                    )
                                  : Row(
                                      children: [
                                        if (mostrarPanelEmpleados) ...[
                                          SizedBox(width: panelWidth, child: _panelEmpleados(auth.canEdit)),
                                          const VerticalDivider(width: 1),
                                        ] else if (!_vistaTabla) ...[
                                          Container(
                                            width: 42,
                                            color: Colors.grey.shade100,
                                            child: Center(
                                              child: IconButton.filledTonal(
                                                tooltip: 'Mostrar lista de empleados',
                                                onPressed: () {
                                                  setState(() => _mostrarListaEmpleados = true);
                                                },
                                                icon: const Icon(Icons.keyboard_double_arrow_right),
                                              ),
                                            ),
                                          ),
                                          const VerticalDivider(width: 1),
                                        ],
                                        Expanded(
                                          child: _panelMaquinas(
                                            auth.canEdit,
                                            compacto: usarCompacto,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _topBar(bool canEdit) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pantallaChica = constraints.maxWidth < 760;

        Widget fechaSelector() {
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Día anterior',
                visualDensity: VisualDensity.compact,
                onPressed: () => _cambiarFecha(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  DateFormat('dd/MM/yyyy').format(_fecha),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Día siguiente',
                visualDensity: VisualDensity.compact,
                onPressed: () => _cambiarFecha(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
        }

        Widget controles() {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.view_agenda_outlined),
                    label: Text(pantallaChica ? 'Cards' : 'Tarjetas'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.table_rows_outlined),
                    label: const Text('Tabla'),
                  ),
                ],
                selected: {_vistaTabla},
                onSelectionChanged: (values) {
                  setState(() {
                    _vistaTabla = values.first;
                    _mostrarListaEmpleados = !_vistaTabla;
                  });
                },
              ),
              if (!_vistaTabla)
                IconButton.filledTonal(
                  tooltip: _mostrarListaEmpleados ? 'Ocultar lista de empleados' : 'Mostrar lista de empleados',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => _mostrarListaEmpleados = !_mostrarListaEmpleados);
                  },
                  icon: Icon(_mostrarListaEmpleados ? Icons.visibility_off : Icons.visibility),
                ),
              IconButton.filledTonal(
                tooltip: 'Actualizar',
                visualDensity: VisualDensity.compact,
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
              if (canEdit)
                FilledButton.icon(
                  onPressed: _syncing ? null : _sincronizarTurnos,
                  icon: _syncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(pantallaChica ? 'Sync' : 'Sincronizar turnos'),
                ),
            ],
          );
        }

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: pantallaChica ? 10 : 14,
            vertical: pantallaChica ? 8 : 10,
          ),
          color: Colors.white,
          child: pantallaChica
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Molinos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        fechaSelector(),
                      ],
                    ),
                    const SizedBox(height: 6),
                    controles(),
                  ],
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const SizedBox(
                      width: 120,
                      child: Text(
                        'Molinos',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                    ),
                    fechaSelector(),
                    controles(),
                  ],
                ),
        );
      },
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
                label: Text(turno),
                onSelected: (_) async {
                  setState(() => _turnoFiltro = turno);
                  await _load();
                },
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
                    '${_turnoFiltro == _turnoAutomaticoInicial() ? 'TURNO ACTUAL · Ya comenzó $_turnoFiltro · ' : ''}${_relojJornada(_turnoFiltro)}',
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final pantallaChica = constraints.maxWidth < 760;
        final compacto = pantallaChica || _vistaTabla;

        return Container(
          width: double.infinity,
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(12, compacto ? 6 : 10, 12, compacto ? 6 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _sectionTitle(
                      compacto ? 'Supervisores' : 'Encargados / Supervisores',
                      Icons.supervisor_account,
                      compacto: compacto,
                    ),
                  ),
                  if (compacto && supervisores.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Text(
                        '${supervisores.length}',
                        style: TextStyle(
                          color: Colors.indigo.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: compacto ? 4 : 8),
              if (supervisores.isEmpty)
                Text(
                  'Sin encargados o supervisores para este turno.',
                  maxLines: compacto ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: compacto ? 11 : 13),
                )
              else
                SizedBox(
                  height: compacto ? 48 : 78,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: supervisores.length,
                    separatorBuilder: (_, __) => SizedBox(width: compacto ? 6 : 8),
                    itemBuilder: (_, index) {
                      final e = supervisores[index];
                      return SizedBox(
                        width: compacto ? 185 : 260,
                        child: _EmpleadoChip(
                          empleado: e,
                          onTap: () => _detalle(e),
                          destacado: true,
                          compacto: compacto,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _panelEmpleados(bool canEdit) {
    final t = _tablero!;
    final empleadosDelTurno = _filtrarEmpleados(t.empleadosTurno)
        .where((e) => e.maquinaId == null)
        .toList();
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
              Row(
                children: [
                  Expanded(
                    child: _sectionTitle(
                      'Lista de empleados $_turnoFiltro',
                      Icons.groups_rounded,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Ocultar lista de empleados',
                    onPressed: () {
                      setState(() => _mostrarListaEmpleados = false);
                    },
                    icon: const Icon(Icons.keyboard_double_arrow_left),
                  ),
                ],
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

  Widget _sectionTitle(String title, IconData icon, {bool compacto = false}) {
    return Row(
      children: [
        Icon(icon, size: compacto ? 16 : 20),
        SizedBox(width: compacto ? 6 : 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compacto ? 14 : 18, fontWeight: FontWeight.bold),
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

  Widget _panelMaquinas(bool canEdit, {bool compacto = false}) {
    final maquinas = _tablero!.maquinas;

    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        final pantallaMuyChica = ancho < 520;
        final anchoTarjeta = pantallaMuyChica
            ? (ancho - 16).clamp(220.0, 420.0)
            : compacto
                ? 240.0
                : 340.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(compacto ? 8 : 12),
          child: Wrap(
            spacing: compacto ? 8 : 12,
            runSpacing: compacto ? 8 : 12,
            children: maquinas.map((m) {
              final empleados = _filtrarEmpleados(m.empleados).toList();

              return _MaquinaMolinoCard(
                maquina: m,
                empleados: empleados,
                canEdit: canEdit,
                compacto: compacto || pantallaMuyChica,
                ancho: anchoTarjeta,
                onDropEmpleado: (e) => _asignar(e, m.id),
                onEstado: (estado) => _estado(m, estado),
                onEmpleadoTap: _detalle,
                onHistorial: () => _verHistorial(m),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _EmpleadoChip extends StatelessWidget {
  final EmpleadoMolinos empleado;
  final VoidCallback onTap;
  final bool destacado;
  final bool compacto;

  const _EmpleadoChip({
    required this.empleado,
    required this.onTap,
    this.destacado = false,
    this.compacto = false,
  });

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

  int _semanaDelAnio(DateTime date) {
    final thursday = date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 + ((thursday.difference(firstThursday).inDays + (firstThursday.weekday == 7 ? 7 : firstThursday.weekday) - 1) ~/ 7);
    return week.clamp(1, 53);
  }

  @override
  Widget build(BuildContext context) {
    final turnoColor = _colorFromName(empleado.turnoColor);

    if (compacto) {
      final subtitulo = empleado.puesto ?? empleado.turno ?? 'Sin puesto';

      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: destacado ? Colors.indigo.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: destacado ? Colors.indigo.shade200 : Colors.grey.shade300),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundImage: empleado.foto != null && empleado.foto!.isNotEmpty
                    ? NetworkImage(ApiService.fileUrl(empleado.foto!))
                    : null,
                child: empleado.foto == null || empleado.foto!.isEmpty ? const Icon(Icons.person, size: 15) : null,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${empleado.nombre} · $subtitulo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                ),
              ),
              if (empleado.acotacion != null) const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 15),
            ],
          ),
        ),
      );
    }

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
              child: Text(
                [
                  empleado.nombre,
                  empleado.puesto ?? 'Sin puesto',
                  empleado.maquinaNombre == null ? 'En espera / afuera' : 'Máquina: ${empleado.maquinaNombre}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: destacado ? 12 : 13,
                  color: Colors.black87,
                ),
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

  int _semanaDelAnio(DateTime date) {
    final thursday = date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 + ((thursday.difference(firstThursday).inDays + (firstThursday.weekday == 7 ? 7 : firstThursday.weekday) - 1) ~/ 7);
    return week.clamp(1, 53);
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
  final bool compacto;
  final double? ancho;
  final ValueChanged<EmpleadoMolinos> onDropEmpleado;
  final ValueChanged<String> onEstado;
  final ValueChanged<EmpleadoMolinos> onEmpleadoTap;
  final VoidCallback onHistorial;

  const _MaquinaMolinoCard({
    required this.maquina,
    required this.empleados,
    required this.canEdit,
    this.compacto = false,
    this.ancho,
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


  Color _colorSemaforo(String? semaforo) {
    switch ((semaforo ?? '').toLowerCase()) {
      case 'rojo':
        return Colors.red;
      case 'amarillo':
        return Colors.amber;
      case 'verde':
        return Colors.green;
      default:
        return Colors.blueGrey;
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

  int _semanaDelAnio(DateTime date) {
    final thursday = date.add(Duration(days: 4 - (date.weekday == 7 ? 7 : date.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    final week = 1 + ((thursday.difference(firstThursday).inDays + (firstThursday.weekday == 7 ? 7 : firstThursday.weekday) - 1) ~/ 7);
    return week.clamp(1, 53);
  }


  Widget _empleadoEnMaquina(EmpleadoMolinos e, ValueChanged<EmpleadoMolinos> onTap) {
    final noCheco = !e.presente;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EmpleadoMuneco(empleado: e, onTap: () => onTap(e)),
        if (noCheco)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_off, size: 16, color: Colors.red),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No está presente / no checó entrada',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }


  Widget _empleadoEnMaquinaCompacto(EmpleadoMolinos e, ValueChanged<EmpleadoMolinos> onTap) {
    final noCheco = !e.presente;

    return InkWell(
      onTap: () => onTap(e),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: noCheco ? Colors.red.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: noCheco ? Colors.red.shade200 : Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(
              noCheco ? Icons.person_off : Icons.person,
              size: 16,
              color: noCheco ? Colors.red : Colors.blueGrey,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                e.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: noCheco ? Colors.red.shade800 : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(maquina.estadoColor.isNotEmpty ? maquina.estadoColor : maquina.estado);

    final cardWidth = ancho ?? (compacto ? 240.0 : 340.0);
    final minHeight = compacto ? 170.0 : 270.0;
    final padding = compacto ? 8.0 : 12.0;
    final titleSize = compacto ? 14.0 : 18.0;

    return DragTarget<EmpleadoMolinos>(
      onWillAcceptWithDetails: (_) => canEdit,
      onAcceptWithDetails: (details) => onDropEmpleado(details.data),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: cardWidth,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: candidate.isNotEmpty ? color.withOpacity(.08) : Colors.white,
            borderRadius: BorderRadius.circular(compacto ? 14 : 18),
            border: Border.all(color: color, width: compacto ? 2 : 3),
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
                      style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _EstadoAnimadoIcon(estado: maquina.estado, color: color),
                  if (!compacto) ...[
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
                  ] else
                    IconButton(
                      tooltip: 'Historial',
                      onPressed: onHistorial,
                      icon: const Icon(Icons.history, size: 18),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              SizedBox(height: compacto ? 4 : 6),
              Wrap(
                spacing: compacto ? 4 : 6,
                runSpacing: compacto ? 4 : 6,
                children: [
                  _estadoButton('trabajando', Colors.green),
                  _estadoButton('limpieza', Colors.amber),
                  _estadoButton('mantenimiento', Colors.blue),
                  _estadoButton('paro', Colors.red),
                ],
              ),
              if (!compacto && maquina.descripcion?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(maquina.descripcion!, style: TextStyle(color: Colors.grey.shade700)),
                ),
              Divider(height: compacto ? 12 : 18),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(compacto ? 7 : 10),
                decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          compacto
                              ? _estadoLabel(maquina.estado)
                              : '${_estadoLabel(maquina.estado)} desde ${maquina.estadoHoraInicio ?? '--:--'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: compacto ? 11 : 14),
                        ),
                        const Icon(Icons.timer_outlined, size: 16),
                        StreamBuilder<int>(
                          stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
                          builder: (_, __) => Text(
                            _duracionEstado(maquina.estadoInicioDateTime),
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: compacto ? 11 : 14),
                          ),
                        ),
                      ],
                    ),
                    if (!compacto && maquina.estadoObservaciones != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(maquina.estadoObservaciones!, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
              ),
              if (!compacto && maquina.mantenimientoFechaProxima != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _colorSemaforo(maquina.mantenimientoSemaforo).withOpacity(.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _colorSemaforo(maquina.mantenimientoSemaforo), width: maquina.mantenimientoAlerta ? 2 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        maquina.mantenimientoAlerta ? Icons.notifications_active : Icons.notifications_none,
                        color: _colorSemaforo(maquina.mantenimientoSemaforo),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Próximo mantenimiento: ${maquina.mantenimientoFechaProxima}'
                          '${maquina.mantenimientoDiasRestantes == null ? '' : ' · faltan ${maquina.mantenimientoDiasRestantes} días'}'
                          '${maquina.mantenimientoProximo == null ? '' : ' · ${maquina.mantenimientoProximo}'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, color: _colorSemaforo(maquina.mantenimientoSemaforo)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: compacto ? 8 : 12),
              Text(
                compacto ? 'Emp. (${empleados.length})' : 'Lista de empleados (${empleados.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: compacto ? 12 : 14),
              ),
              SizedBox(height: compacto ? 5 : 8),
              if (empleados.isEmpty)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(compacto ? 8 : 16),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    compacto ? 'Vacío' : 'Arrastra empleados aquí. Si es LAVADOR, se queda en el molino y cambia a Limpieza.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: compacto ? 11 : 13),
                  ),
                )
              else
                ...empleados.map((e) {
                  final child = compacto
                      ? _empleadoEnMaquinaCompacto(e, onEmpleadoTap)
                      : _empleadoEnMaquina(e, onEmpleadoTap);

                  return Padding(
                    padding: EdgeInsets.only(bottom: compacto ? 5 : 8),
                    child: canEdit
                        ? Draggable<EmpleadoMolinos>(
                            data: e,
                            feedback: Material(
                              color: Colors.transparent,
                              child: EmpleadoMuneco(empleado: e, compacto: true),
                            ),
                            childWhenDragging: Opacity(opacity: .35, child: child),
                            child: child,
                          )
                        : child,
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
