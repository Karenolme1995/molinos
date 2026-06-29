// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/asistencias_service.dart';

class AsistenciasScreen extends StatefulWidget {
  final Future<String?> Function() getToken;

  const AsistenciasScreen({
    super.key,
    required this.getToken,
  });

  @override
  State<AsistenciasScreen> createState() => _AsistenciasScreenState();
}

class _AsistenciasScreenState extends State<AsistenciasScreen> {
  late final AsistenciasService _service;

  bool _loading = true;
  bool _checando = false;
  bool _exportando = false;
  String? _error;

  Timer? _timer;
  DateTime _horaMexico = DateTime.now();

  DateTime _fecha = DateTime.now();
  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;

  List<dynamic> _presentes = [];
  List<dynamic> _ausentes = [];
  List<dynamic> _conAcotacion = [];
  List<dynamic> _empleadosMatriz = [];
  List<dynamic> _acotaciones = [];
  List<dynamic> _castigos = [];

  Map<String, dynamic>? _empleadoSeleccionado;
  Map<String, dynamic>? _estadoChecador;

  final List<String> _meses = const [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _service = AsistenciasService(getToken: widget.getToken);
    _iniciarHora();
    _cargarTodo();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _iniciarHora() async {
    try {
      final data = await _service.getHoraMexico();
      final fecha = data['fecha']?.toString();
      final hora = data['hora']?.toString();

      if (fecha != null && hora != null) {
        _horaMexico = DateTime.parse('${fecha}T$hora');
      }
    } catch (_) {
      _horaMexico = DateTime.now();
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        _horaMexico = _horaMexico.add(const Duration(seconds: 1));
      });
    });
  }

  Future<void> _cargarTodo() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await Future.wait([
        _service.getTablero(
          fecha: _fecha,
          departamento: 'MOLINOS',
        ),
        _service.getMatriz(
          mes: _mes,
          anio: _anio,
          departamento: 'MOLINOS',
        ),
        _service.getAcotaciones(),
        _service.getCastigos(),
      ]);

      final tablero = Map<String, dynamic>.from(result[0] as Map);
      final matriz = Map<String, dynamic>.from(result[1] as Map);
      final acotaciones = List<dynamic>.from(result[2] as List);
      final castigos = Map<String, dynamic>.from(result[3] as Map);

      if (!mounted) return;

      setState(() {
        _presentes = List<dynamic>.from(tablero['presentes'] ?? []);
        _ausentes = List<dynamic>.from(tablero['ausentes'] ?? []);
        _conAcotacion = List<dynamic>.from(tablero['con_acotacion'] ?? []);
        _empleadosMatriz = List<dynamic>.from(matriz['empleados'] ?? []);
        _acotaciones = acotaciones;
        _castigos = List<dynamic>.from(castigos['empleados'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _fechaTexto(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  String _fechaIso(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}-'
        '${fecha.month.toString().padLeft(2, '0')}-'
        '${fecha.day.toString().padLeft(2, '0')}';
  }

  String _horaTexto(DateTime fecha) {
    return '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}:'
        '${fecha.second.toString().padLeft(2, '0')}';
  }

  Color _colorAcotacion(String? clave) {
    switch (clave) {
      case 'I':
        return Colors.purple;
      case 'NR':
        return Colors.red;
      case 'FJ':
        return Colors.blue;
      case 'F':
        return Colors.red;
      case 'V':
        return Colors.cyan;
      case 'NL':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Color _colorValorDia(String? valor) {
    switch (valor) {
      case 'A':
        return Colors.green.shade100;
      case 'ENT':
        return Colors.orange.shade100;
      case 'I':
        return Colors.purple.shade100;
      case 'NR':
        return Colors.red.shade100;
      case 'FJ':
        return Colors.blue.shade100;
      case 'F':
        return Colors.red.shade100;
      case 'V':
        return Colors.cyan.shade100;
      case 'NL':
        return Colors.grey.shade300;
      default:
        return Colors.white;
    }
  }

  Color _colorTextoValorDia(String? valor) {
    switch (valor) {
      case 'A':
        return Colors.green.shade800;
      case 'ENT':
        return Colors.deepOrange.shade800;
      case 'F':
      case 'NR':
        return Colors.red.shade800;
      default:
        return Colors.black87;
    }
  }

  String _textoValorDia(String? valor) {
    switch (valor) {
      case 'A':
        return '✓';
      case 'ENT':
        return '✕';
      case 'F':
        return '✕';
      default:
        return valor ?? '';
    }
  }

  String _tooltipValorDia(String? valor) {
    switch (valor) {
      case 'A':
        return 'Asistencia completa';
      case 'ENT':
        return 'Registros incompletos';
      case 'F':
        return 'Sin registros completos';
      case 'I':
        return 'Incapacidad';
      case 'NR':
        return 'No regresó';
      case 'FJ':
        return 'Falta justificada';
      case 'V':
        return 'Vacaciones';
      case 'NL':
        return 'No labora';
      default:
        return 'Sin dato';
    }
  }

  int _diasDelMes() {
    return DateUtils.getDaysInMonth(_anio, _mes);
  }

  Future<void> _seleccionarFecha() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (selected == null) return;

    setState(() {
      _fecha = selected;
      _mes = selected.month;
      _anio = selected.year;
    });

    await _cargarTodo();
  }

  Future<void> _cambiarMesAnio({
    int? mes,
    int? anio,
  }) async {
    final nuevoMes = mes ?? _mes;
    final nuevoAnio = anio ?? _anio;

    setState(() {
      _mes = nuevoMes;
      _anio = nuevoAnio;

      final diaSeguro = _fecha.day.clamp(
        1,
        DateUtils.getDaysInMonth(nuevoAnio, nuevoMes),
      );

      _fecha = DateTime(nuevoAnio, nuevoMes, diaSeguro);
    });

    await _cargarTodo();
  }

  Future<void> _seleccionarEmpleado(Map<String, dynamic> emp) async {
    final empleadoId = emp['empleado_id'] ?? emp['id'];

    if (empleadoId == null) return;

    try {
      final estado = await _service.getEstadoChecador(
        empleadoId: int.parse(empleadoId.toString()),
      );

      if (!mounted) return;

      setState(() {
        _empleadoSeleccionado = emp;
        _estadoChecador = estado;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _checarEmpleado() async {
    final emp = _empleadoSeleccionado;

    if (emp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un empleado primero')),
      );
      return;
    }

    final empleadoId = emp['empleado_id'] ?? emp['id'];

    if (empleadoId == null) return;

    setState(() {
      _checando = true;
    });

    try {
      final id = int.parse(empleadoId.toString());

      final result = await _service.checar(
        empleadoId: id,
      );

      final estado = await _service.getEstadoChecador(
        empleadoId: id,
      );

      if (!mounted) return;

      setState(() {
        _estadoChecador = estado;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Checada registrada'),
        ),
      );

      await _cargarTodo();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _checando = false;
      });
    }
  }

  Future<void> _mostrarDetalleEmpleado(Map<String, dynamic> emp) async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        final foto = emp['foto']?.toString() ?? '';

        return AlertDialog(
          title: Text(emp['nombre']?.toString() ?? 'Empleado'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ClipOval(
                      child: foto.isNotEmpty
                          ? Image.network(
                              ApiService.fileUrl(foto),
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Container(
                                  width: 84,
                                  height: 84,
                                  color: Colors.blue.shade100,
                                  child: const Icon(Icons.person, size: 42),
                                );
                              },
                            )
                          : Container(
                              width: 84,
                              height: 84,
                              color: Colors.blue.shade100,
                              child: const Icon(Icons.person, size: 42),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _info('Nómina', emp['numero_nomina']),
                  _info('Puesto', emp['puesto']),
                  _info('Departamento', emp['departamento']),
                  _info('Turno', emp['turno']),
                  _info('Máquina', emp['maquina_nombre']),
                  _info('Entrada', emp['entrada']),
                  _info('Salida comida', emp['salida_comida']),
                  _info('Entrada comida', emp['entrada_comida']),
                  _info('Salida', emp['salida']),
                  _info(
                    'Asistencia completa',
                    emp['asistencia_completa'] == true ? 'Sí' : 'No',
                  ),
                  if (emp['acotacion'] != null)
                    _info(
                      'Acotación',
                      '${emp['acotacion']} - ${emp['acotacion_descripcion'] ?? ''}',
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Responsabilidades',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    emp['responsabilidades']?.toString().isNotEmpty == true
                        ? emp['responsabilidades'].toString()
                        : 'Sin responsabilidades capturadas',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Widget _info(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value?.toString() ?? '-'),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarAcotacion(Map<String, dynamic> emp) async {
    String? claveSeleccionada;
    final observacionesController = TextEditingController();
    bool guardando = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return AlertDialog(
              title: Text('Acotación - ${emp['nombre']}'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: claveSeleccionada,
                      decoration: const InputDecoration(
                        labelText: 'Acotación',
                        border: OutlineInputBorder(),
                      ),
                      items: _acotaciones.map((a) {
                        return DropdownMenuItem<String>(
                          value: a['clave'].toString(),
                          child: Text(
                            '${a['clave']} - ${a['descripcion']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setModalState(() {
                          claveSeleccionada = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: observacionesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Observaciones',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: guardando
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: guardando
                      ? null
                      : () async {
                          if (claveSeleccionada == null) return;

                          setModalState(() {
                            guardando = true;
                          });

                          try {
                            await _service.registrarAcotacion(
                              empleadoId: emp['empleado_id'],
                              clave: claveSeleccionada!,
                              fecha: _fecha,
                              observaciones: observacionesController.text,
                            );

                            if (!mounted) return;

                            Navigator.of(dialogContext).pop();
                            await _cargarTodo();
                          } catch (e) {
                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          } finally {
                            if (mounted && guardando) {
                              setModalState(() {
                                guardando = false;
                              });
                            }
                          }
                        },
                  icon: guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(guardando ? 'Guardando...' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _checadorPanel() {
    final emp = _empleadoSeleccionado;
    final estado = _estadoChecador;
    final checadas = List<dynamic>.from(estado?['checadas'] ?? []);
    final tiempoExtra = Map<String, dynamic>.from(estado?['tiempo_extra'] ?? {});
    final siguienteLabel =
        estado?['siguiente_label']?.toString() ?? 'Selecciona empleado';

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final small = constraints.maxWidth < 850;

            final reloj = Container(
              width: small ? double.infinity : 280,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Hora México',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _horaTexto(_horaMexico),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fechaTexto(_horaMexico),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );

            final detalle = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Checador',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    emp == null
                        ? 'Selecciona un empleado de las listas para checar.'
                        : '${emp['nombre'] ?? '-'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('Siguiente: $siguienteLabel'),
                    avatar: const Icon(Icons.touch_app, size: 18),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: checadas.map((c) {
                      return Chip(
                        label: Text(
                          '${c['tipo_label'] ?? c['tipo']}: ${c['hora'] ?? '-'}',
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tiempo extra: ${tiempoExtra['tiempo_extra'] ?? '00:00:00'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: tiempoExtra['tiempo_extra_pagable'] == true
                          ? Colors.green
                          : Colors.black87,
                    ),
                  ),
                  Text(
                    tiempoExtra['mensaje']?.toString() ??
                        'Solo se paga si pasa de 30 minutos.',
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _checando ? null : _checarEmpleado,
                    icon: _checando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fingerprint),
                    label: Text(_checando ? 'Checando...' : 'Checar ahora'),
                  ),
                ],
              ),
            );

            if (small) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  reloj,
                  const SizedBox(height: 16),
                  detalle,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                reloj,
                const SizedBox(width: 18),
                detalle,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empleadoCard(
    Map<String, dynamic> emp, {
    required bool alerta,
  }) {
    final acotacion = emp['acotacion']?.toString();
    final seleccionado = _empleadoSeleccionado != null &&
        (_empleadoSeleccionado!['empleado_id'] ?? _empleadoSeleccionado!['id'])
                ?.toString() ==
            (emp['empleado_id'] ?? emp['id'])?.toString();

    return Card(
      elevation: seleccionado ? 3 : 1,
      color: seleccionado ? Colors.blue.shade50 : null,
      child: ListTile(
        onTap: () => _seleccionarEmpleado(emp),
        leading: CircleAvatar(
          backgroundColor: acotacion != null
              ? _colorAcotacion(acotacion)
              : alerta
                  ? Colors.red
                  : Colors.green,
          child: acotacion != null
              ? Text(
                  acotacion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                )
              : Icon(
                  alerta ? Icons.warning : Icons.check,
                  color: Colors.white,
                ),
        ),
        title: Text(
          emp['nombre']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Nómina: ${emp['numero_nomina'] ?? '-'} | ${emp['puesto'] ?? '-'}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'seleccionar') {
              _seleccionarEmpleado(emp);
            }

            if (value == 'detalle') {
              _mostrarDetalleEmpleado(emp);
            }

            if (value == 'acotacion') {
              _mostrarAcotacion(emp);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'seleccionar',
              child: Text('Usar en checador'),
            ),
            PopupMenuItem(
              value: 'detalle',
              child: Text('Ver detalle'),
            ),
            PopupMenuItem(
              value: 'acotacion',
              child: Text('Agregar acotación'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenCards() {
    return Row(
      children: [
        Expanded(
          child: _contadorCard(
            titulo: 'Presentes',
            valor: _presentes.length.toString(),
            color: Colors.green,
            icon: Icons.check_circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _contadorCard(
            titulo: 'Ausentes',
            valor: _ausentes.length.toString(),
            color: Colors.red,
            icon: Icons.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _contadorCard(
            titulo: 'Castigos',
            valor: _castigos.length.toString(),
            color: Colors.deepOrange,
            icon: Icons.gavel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _contadorCard(
            titulo: 'Acotaciones',
            valor: _conAcotacion.length.toString(),
            color: Colors.orange,
            icon: Icons.info,
          ),
        ),
      ],
    );
  }

  Widget _contadorCard({
    required String titulo,
    required String valor,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 1,
      child: Container(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color,
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listasAsistencia() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 1100;

        final children = [
          _panelLista(
            titulo: 'Presentes / Con registros',
            color: Colors.green,
            empleados: _presentes,
            alerta: false,
          ),
          _panelLista(
            titulo: 'Ausentes / No presentados',
            color: Colors.red,
            empleados: _ausentes,
            alerta: true,
          ),
          _panelLista(
            titulo: 'Castigo martes, miércoles o jueves',
            color: Colors.deepOrange,
            empleados: _castigos,
            alerta: true,
          ),
          _panelLista(
            titulo: 'Con acotación',
            color: Colors.orange,
            empleados: _conAcotacion,
            alerta: true,
          ),
        ];

        if (isSmall) {
          return Column(
            children: [
              children[0],
              const SizedBox(height: 12),
              children[1],
              const SizedBox(height: 12),
              children[2],
              const SizedBox(height: 12),
              children[3],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
            const SizedBox(width: 12),
            Expanded(child: children[2]),
            const SizedBox(width: 12),
            Expanded(child: children[3]),
          ],
        );
      },
    );
  }

  Widget _panelLista({
    required String titulo,
    required Color color,
    required List<dynamic> empleados,
    required bool alerta,
  }) {
    return Card(
      elevation: 1,
      child: Container(
        height: 360,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.circle, color: color, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: empleados.isEmpty
                  ? const Center(
                      child: Text('Sin registros'),
                    )
                  : ListView.builder(
                      itemCount: empleados.length,
                      itemBuilder: (_, index) {
                        return _empleadoCard(
                          Map<String, dynamic>.from(empleados[index]),
                          alerta: alerta,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _celdaDia(String? valor) {
    return Tooltip(
      message: _tooltipValorDia(valor),
      child: Container(
        width: 38,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _colorValorDia(valor),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.black12,
          ),
        ),
        child: Text(
          _textoValorDia(valor),
          style: TextStyle(
            fontSize: valor == 'A' || valor == 'ENT' || valor == 'F' ? 18 : 11,
            fontWeight: FontWeight.bold,
            color: _colorTextoValorDia(valor),
          ),
        ),
      ),
    );
  }

  Widget _matrizAsistencia() {
    final diasMes = _diasDelMes();

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Matriz mensual de asistencia',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  label: Text('${_meses[_mes - 1]} $_anio'),
                ),
                OutlinedButton.icon(
                  onPressed: _exportando ? null : _exportarExcel,
                  icon: _exportando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_exportando ? 'Exportando...' : 'Exportar Excel'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 46,
                columns: [
                  const DataColumn(label: Text('Nómina')),
                  const DataColumn(label: Text('Nombre')),
                  const DataColumn(label: Text('Puesto')),
                  for (int d = 1; d <= diasMes; d++)
                    DataColumn(
                      label: Text(
                        d.toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                rows: _empleadosMatriz.map((empRaw) {
                  final emp = Map<String, dynamic>.from(empRaw);
                  final dias = Map<String, dynamic>.from(emp['dias'] ?? {});

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(emp['numero_nomina']?.toString() ?? ''),
                      ),
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: Text(
                            emp['nombre']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 140,
                          child: Text(
                            emp['puesto']?.toString() ?? '',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      for (int d = 1; d <= diasMes; d++)
                        DataCell(
                          _celdaDia(dias[d.toString()]?.toString()),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leyenda() {
    final items = {
      '✓': 'Asistencia completa',
      '✕': 'Sin registros completos',
      'ENT': 'Registros incompletos',
      'I': 'Incapacidad',
      'NL': 'No labora',
      'NR': 'No regresó',
      'FJ': 'Falta justificada',
      'V': 'Vacaciones',
    };

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: items.entries.map((e) {
        return Chip(
          label: Text('${e.key} - ${e.value}'),
          backgroundColor: e.key == '✓'
              ? Colors.green.shade100
              : e.key == '✕'
                  ? Colors.red.shade100
                  : _colorValorDia(e.key),
        );
      }).toList(),
    );
  }

  List<int> _aniosDisponibles() {
    final actual = DateTime.now().year;
    return List.generate(7, (i) => actual - 3 + i);
  }

  Widget _header() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.fact_check, size: 30),
        const Text(
          'Asistencias y Checador - Molinos',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _seleccionarFecha,
          icon: const Icon(Icons.calendar_today),
          label: Text('Día: ${_fechaTexto(_fecha)}'),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<int>(
            value: _mes,
            decoration: const InputDecoration(
              labelText: 'Mes',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: List.generate(12, (index) {
              final value = index + 1;
              return DropdownMenuItem<int>(
                value: value,
                child: Text(_meses[index]),
              );
            }),
            onChanged: (value) {
              if (value == null) return;
              _cambiarMesAnio(mes: value);
            },
          ),
        ),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<int>(
            value: _anio,
            decoration: const InputDecoration(
              labelText: 'Año',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _aniosDisponibles().map((anio) {
              return DropdownMenuItem<int>(
                value: anio,
                child: Text(anio.toString()),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              _cambiarMesAnio(anio: value);
            },
          ),
        ),
        ElevatedButton.icon(
          onPressed: _cargarTodo,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar'),
        ),
        OutlinedButton.icon(
          onPressed: _exportando ? null : _exportarExcel,
          icon: const Icon(Icons.table_view),
          label: const Text('Exportar Excel'),
        ),
      ],
    );
  }

  String _csvValue(dynamic value) {
    final text = value?.toString() ?? '';
    final safe = text.replaceAll('"', '""');
    return '"$safe"';
  }

  Future<void> _exportarExcel() async {
    if (_empleadosMatriz.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay datos para exportar')),
      );
      return;
    }

    setState(() {
      _exportando = true;
    });

    try {
      final diasMes = _diasDelMes();
      final rows = <List<dynamic>>[];

      rows.add([
        'Nómina',
        'Nombre',
        'Puesto',
        for (int d = 1; d <= diasMes; d++) d.toString(),
      ]);

      for (final empRaw in _empleadosMatriz) {
        final emp = Map<String, dynamic>.from(empRaw);
        final dias = Map<String, dynamic>.from(emp['dias'] ?? {});

        rows.add([
          emp['numero_nomina'] ?? '',
          emp['nombre'] ?? '',
          emp['puesto'] ?? '',
          for (int d = 1; d <= diasMes; d++)
            _textoExcel(dias[d.toString()]?.toString()),
        ]);
      }

      final csv = rows.map((row) {
        return row.map(_csvValue).join(',');
      }).join('\n');

      final bytes = utf8.encode('\uFEFF$csv');
      final blob = html.Blob(
        [bytes],
        'text/csv;charset=utf-8',
      );

      final url = html.Url.createObjectUrlFromBlob(blob);
      final fileName =
          'asistencias_molinos_${_anio}_${_mes.toString().padLeft(2, '0')}.csv';

      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();

      html.Url.revokeObjectUrl(url);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Archivo exportado para Excel')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _exportando = false;
      });
    }
  }

  String _textoExcel(String? valor) {
    switch (valor) {
      case 'A':
        return '✓';
      case 'ENT':
        return '✕ INCOMPLETO';
      case 'F':
        return '✕';
      default:
        return valor ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xfff4f6f8),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _cargarTodo,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 16),
                _resumenCards(),
                const SizedBox(height: 16),
                _checadorPanel(),
                const SizedBox(height: 16),
                _listasAsistencia(),
                const SizedBox(height: 16),
                _leyenda(),
                const SizedBox(height: 16),
                _matrizAsistencia(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
