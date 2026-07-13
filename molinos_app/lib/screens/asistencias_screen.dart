import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

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

  final TextEditingController _buscarController = TextEditingController();
  final ScrollController _matrizHorizontalController = ScrollController();
  Timer? _buscarDebounce;

  bool _loading = true;
  bool _exportando = false;
  String? _error;

  DateTime _fecha = DateTime.now();
  int _mes = DateTime.now().month;
  int _anio = DateTime.now().year;

  String _q = '';
  int _pagina = 0;
  int _filasPorPagina = 500;

  List<dynamic> _presentes = [];
  List<dynamic> _ausentes = [];
  List<dynamic> _conAcotacion = [];
  List<dynamic> _empleadosMatriz = [];
  List<dynamic> _acotaciones = [];
  List<dynamic> _castigos = [];

  final List<int> _opcionesFilas = const [25, 50, 100, 200, 500];

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

    _buscarController.addListener(() {
      _buscarDebounce?.cancel();
      _buscarDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        setState(() {
          _q = _buscarController.text.trim().toLowerCase();
          _pagina = 0;
        });
      });
    });

    _cargarTodo();
  }

  @override
  void dispose() {
    _buscarDebounce?.cancel();
    _buscarController.dispose();
    _matrizHorizontalController.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Consulta optimizada: se evita llamar /checador/castigos en cada carga.
      // Si el backend manda castigos dentro del tablero, se usan; si no, queda vacío.
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
      ]);

      final tablero = Map<String, dynamic>.from(result[0] as Map);
      final matriz = Map<String, dynamic>.from(result[1] as Map);
      final acotaciones = List<dynamic>.from(result[2] as List);

      if (!mounted) return;

      setState(() {
        _presentes = List<dynamic>.from(tablero['presentes'] ?? []);
        _ausentes = List<dynamic>.from(tablero['ausentes'] ?? []);
        _conAcotacion = List<dynamic>.from(tablero['con_acotacion'] ?? []);
        _empleadosMatriz = List<dynamic>.from(matriz['empleados'] ?? []);
        _acotaciones = acotaciones;
        _castigos = List<dynamic>.from(tablero['castigos'] ?? []);
        _pagina = 0;
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

  String _fechaCortaDia(int dia) {
    final fecha = DateTime(_anio, _mes, dia);
    final yy = fecha.year.toString().substring(2);
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '$yy';
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
      _pagina = 0;
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

      final maxDias = DateUtils.getDaysInMonth(nuevoAnio, nuevoMes);
      final diaSeguro = _fecha.day > maxDias ? maxDias : _fecha.day;

      _fecha = DateTime(nuevoAnio, nuevoMes, diaSeguro);
      _pagina = 0;
    });

    await _cargarTodo();
  }

  Color _colorAcotacion(String? clave) {
    switch (clave) {
      case 'I':
        return Colors.purple;
      case 'NR':
      case 'F':
        return Colors.red;
      case 'FJ':
        return Colors.blue;
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
      case 'F':
        return Colors.red.shade100;
      case 'FJ':
        return Colors.blue.shade100;
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

  List<Map<String, dynamic>> get _empleadosFiltrados {
    final lista = _empleadosMatriz
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    lista.sort((a, b) {
      final ta = _turnoTexto(a);
      final tb = _turnoTexto(b);
      final pa = _ordenTurnos([ta, tb]).indexOf(ta);
      final pb = _ordenTurnos([ta, tb]).indexOf(tb);
      if (pa != pb) return pa.compareTo(pb);
      return (a['nombre'] ?? '')
          .toString()
          .compareTo((b['nombre'] ?? '').toString());
    });

    if (_q.isEmpty) return lista;

    return lista.where((emp) {
      final nomina = (emp['numero_nomina'] ?? emp['nomina'] ?? '').toString();
      final nombre = (emp['nombre'] ?? '').toString();
      final puesto = (emp['puesto'] ?? '').toString();
      final turno = _turnoTexto(emp);

      final texto = '$nomina $nombre $puesto $turno'.toLowerCase();
      return texto.contains(_q);
    }).toList();
  }

  List<Map<String, dynamic>> get _empleadosPagina {
    final filtrados = _empleadosFiltrados;
    if (filtrados.isEmpty) return [];

    var inicio = _pagina * _filasPorPagina;
    if (inicio < 0) inicio = 0;
    if (inicio > filtrados.length) inicio = filtrados.length;

    var fin = inicio + _filasPorPagina;
    if (fin > filtrados.length) fin = filtrados.length;

    return filtrados.sublist(inicio, fin);
  }

  int get _totalPaginas {
    final total = _empleadosFiltrados.length;
    if (total == 0) return 1;
    return (total / _filasPorPagina).ceil();
  }

  int get _inicioVista {
    final total = _empleadosFiltrados.length;
    if (total == 0) return 0;
    return (_pagina * _filasPorPagina) + 1;
  }

  int get _finVista {
    final total = _empleadosFiltrados.length;
    if (total == 0) return 0;
    final fin = (_pagina * _filasPorPagina) + _filasPorPagina;
    return fin > total ? total : fin;
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
                  _info('Nómina', emp['numero_nomina'] ?? emp['nomina']),
                  _info('Puesto', emp['puesto']),
                  _info('Departamento', emp['departamento']),
                  _info('Turno', _turnoTexto(emp)),
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
                              empleadoId: emp['empleado_id'] ?? emp['id'],
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

  String _turnoTexto(Map<String, dynamic> emp) {
    final raw = (emp['turno'] ??
            emp['turno_nombre'] ??
            emp['nombre_turno'] ??
            emp['turno_actual'] ??
            emp['turno_descripcion'] ??
            '')
        .toString()
        .trim();

    if (raw.isNotEmpty && raw.toLowerCase() != 'null') {
      return raw.toUpperCase();
    }

    final turnoId = emp['turno_id'] ?? emp['id_turno'];
    if (turnoId != null && turnoId.toString().trim().isNotEmpty) {
      return 'TURNO ${turnoId.toString().trim()}';
    }

    return 'SIN TURNO';
  }

  Color _colorTurno(String turno, {String? colorDb}) {
    final c = (colorDb ?? '').toLowerCase().trim();
    if (c.contains('verde')) return Colors.green;
    if (c.contains('naranja')) return Colors.orange;
    if (c.contains('azul')) return Colors.blue;
    if (c.contains('rosa')) return Colors.pink;
    if (c.contains('morado')) return Colors.deepPurple;
    if (c.contains('rojo')) return Colors.red;

    final t = turno.toUpperCase();
    if (t.contains('1')) return Colors.green;
    if (t.contains('2')) return Colors.orange;
    if (t.contains('3')) return Colors.blue;
    if (t.contains('MIX')) return Colors.pink;
    if (t.contains('MAT')) return Colors.green;
    if (t.contains('VES')) return Colors.orange;
    if (t.contains('NOC')) return Colors.blue;
    return Colors.blueGrey;
  }

  List<String> _ordenTurnos(Iterable<String> turnos) {
    final list = turnos.toList();
    int peso(String turno) {
      final t = turno.toUpperCase();
      if (t.contains('1')) return 1;
      if (t.contains('2')) return 2;
      if (t.contains('3')) return 3;
      if (t == 'SIN TURNO') return 99;
      return 50;
    }

    list.sort((a, b) {
      final pa = peso(a);
      final pb = peso(b);
      if (pa != pb) return pa.compareTo(pb);
      return a.compareTo(b);
    });
    return list;
  }

  Map<String, List<Map<String, dynamic>>> _agruparPorTurno(
      List<dynamic> empleados) {
    final grupos = <String, List<Map<String, dynamic>>>{};

    for (final item in empleados) {
      final emp = Map<String, dynamic>.from(item as Map);
      final turno = _turnoTexto(emp);
      grupos.putIfAbsent(turno, () => <Map<String, dynamic>>[]).add(emp);
    }

    return grupos;
  }

  Widget _empleadoCard(
    Map<String, dynamic> emp, {
    required bool alerta,
    bool compacto = false,
  }) {
    final acotacion = emp['acotacion']?.toString();
    final turno = _turnoTexto(emp);
    final turnoColor =
        _colorTurno(turno, colorDb: emp['turno_color']?.toString());
    final nombre = emp['nombre']?.toString() ?? '';
    final nomina = (emp['numero_nomina'] ?? emp['nomina'] ?? '-').toString();
    final puesto = (emp['puesto'] ?? '-').toString();
    final maquina = (emp['maquina_nombre'] ?? '').toString();

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: compacto ? 6 : 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: turnoColor.withOpacity(.35)),
      ),
      child: ListTile(
        dense: compacto,
        contentPadding: EdgeInsets.symmetric(
          horizontal: compacto ? 8 : 12,
          vertical: compacto ? 2 : 4,
        ),
        onTap: () => _mostrarDetalleEmpleado(emp),
        leading: CircleAvatar(
          radius: compacto ? 17 : 20,
          backgroundColor: acotacion != null
              ? _colorAcotacion(acotacion)
              : alerta
                  ? Colors.red
                  : turnoColor,
          child: acotacion != null
              ? Text(
                  acotacion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                )
              : Icon(
                  alerta ? Icons.warning : Icons.check,
                  color: Colors.white,
                  size: compacto ? 17 : 20,
                ),
        ),
        title: Text(
          nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: compacto ? 12 : 14,
          ),
        ),
        subtitle: compacto
            ? Text(
                '$nomina · $puesto',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Nómina: $nomina'),
                  Text('· $puesto'),
                  if (maquina.isNotEmpty) Text('· $maquina'),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: turnoColor.withOpacity(.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      turno,
                      style: TextStyle(
                        color: turnoColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Opciones',
          onSelected: (value) {
            if (value == 'detalle') {
              _mostrarDetalleEmpleado(emp);
            }

            if (value == 'acotacion') {
              _mostrarAcotacion(emp);
            }
          },
          itemBuilder: (_) => const [
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

  Widget _contadorCard({
    required String titulo,
    required String valor,
    required Color color,
    required IconData icon,
    bool compacto = false,
  }) {
    return Card(
      elevation: 1,
      child: Container(
        padding: EdgeInsets.all(compacto ? 10 : 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: compacto ? 16 : 20,
              backgroundColor: color,
              child: Icon(icon, color: Colors.white, size: compacto ? 17 : 20),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compacto ? 11 : 13,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: compacto ? 20 : 26,
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
        final isSmall = constraints.maxWidth < 900;

        final children = [
          _panelLista(
            titulo: 'Presentes / Con registros',
            color: Colors.green,
            empleados: _presentes,
            alerta: false,
            compacto: isSmall,
          ),
          _panelLista(
            titulo: 'Ausentes / No presentados',
            color: Colors.red,
            empleados: _ausentes,
            alerta: true,
            compacto: isSmall,
          ),
          _panelLista(
            titulo: 'Castigo martes, miércoles o jueves',
            color: Colors.deepOrange,
            empleados: _castigos,
            alerta: true,
            compacto: isSmall,
          ),
          _panelLista(
            titulo: 'Con acotación',
            color: Colors.orange,
            empleados: _conAcotacion,
            alerta: true,
            compacto: isSmall,
          ),
        ];

        if (isSmall) {
          return Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) const SizedBox(height: 12),
              ],
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
    bool compacto = false,
  }) {
    final grupos = _agruparPorTurno(empleados);
    final turnos = _ordenTurnos(grupos.keys);
    final altura = compacto ? 390.0 : 330.0;

    return Card(
      elevation: 1,
      child: Container(
        height: altura,
        padding: EdgeInsets.all(compacto ? 10 : 12),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: compacto ? 14 : 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    empleados.length.toString(),
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
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
                      itemCount: turnos.length,
                      itemBuilder: (_, index) {
                        final turno = turnos[index];
                        final rows = grupos[turno] ?? [];
                        final turnoColor = _colorTurno(turno);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: turnoColor, width: 4),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: turnoColor.withOpacity(.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$turno · ${rows.length}',
                                    style: TextStyle(
                                      color: turnoColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                ...rows.map((emp) => _empleadoCard(
                                      emp,
                                      alerta: alerta,
                                      compacto: compacto,
                                    )),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _esDomingo(int dia) {
    return DateTime(_anio, _mes, dia).weekday == DateTime.sunday;
  }

  Widget _celdaDia(String? valor, int dia) {
    final domingo = _esDomingo(dia);
    final baseColor = _colorValorDia(valor);

    return Tooltip(
      message: domingo
          ? 'Domingo · ${_tooltipValorDia(valor)}'
          : _tooltipValorDia(valor),
      child: Container(
        width: 42,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: domingo && (valor == null || valor.isEmpty)
              ? Colors.amber.shade100
              : baseColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: domingo ? Colors.amber.shade700 : Colors.black12,
            width: domingo ? 1.4 : 1,
          ),
        ),
        child: Text(
          _textoValorDia(valor),
          style: TextStyle(
            fontSize: valor == 'A' || valor == 'ENT' || valor == 'F' ? 18 : 11,
            fontWeight: FontWeight.bold,
            color: domingo && (valor == null || valor.isEmpty)
                ? Colors.amber.shade900
                : _colorTextoValorDia(valor),
          ),
        ),
      ),
    );
  }

  Widget _matrizAsistencia() {
    final diasMes = _diasDelMes();
    final filtrados = _empleadosFiltrados;
    final pagina = _empleadosPagina;

    if (_pagina >= _totalPaginas && _pagina > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pagina = _totalPaginas - 1;
        });
      });
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbarMatriz(filtrados.length),
            const SizedBox(height: 12),
            if (filtrados.isEmpty)
              const SizedBox(
                height: 180,
                child: Center(
                  child: Text('No se encontraron empleados'),
                ),
              )
            else
              Scrollbar(
                controller: _matrizHorizontalController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  controller: _matrizHorizontalController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 44,
                    dataRowMinHeight: 38,
                    dataRowMaxHeight: 44,
                    columnSpacing: 14,
                    horizontalMargin: 12,
                    columns: [
                      const DataColumn(label: Text('Turno')),
                      const DataColumn(label: Text('Nómina')),
                      const DataColumn(label: Text('Nombre')),
                      for (int d = 1; d <= diasMes; d++)
                        DataColumn(
                          label: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: _esDomingo(d)
                                  ? Colors.amber.shade100
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _fechaCortaDia(d),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _esDomingo(d)
                                    ? FontWeight.w800
                                    : FontWeight.normal,
                                color: _esDomingo(d)
                                    ? Colors.amber.shade900
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ),
                    ],
                    rows: pagina.map((emp) {
                      final dias = Map<String, dynamic>.from(emp['dias'] ?? {});
                      final turno = _turnoTexto(emp);
                      final turnoColor = _colorTurno(turno,
                          colorDb: emp['turno_color']?.toString());

                      return DataRow(
                        cells: [
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: turnoColor.withOpacity(.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: turnoColor.withOpacity(.35)),
                              ),
                              child: Text(
                                turno,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: turnoColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              (emp['numero_nomina'] ?? emp['nomina'] ?? '')
                                  .toString(),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 240,
                              child: Text(
                                emp['nombre']?.toString() ?? '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          for (int d = 1; d <= diasMes; d++)
                            DataCell(
                              _celdaDia(dias[d.toString()]?.toString(), d),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _paginacionMatriz(filtrados.length),
          ],
        ),
      ),
    );
  }

  Widget _toolbarMatriz(int totalFiltrado) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 720;
        final searchWidth = isSmall ? constraints.maxWidth : 320.0;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Matriz mensual de asistencia',
              style: TextStyle(
                fontSize: isSmall ? 15 : 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Chip(
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text('${_meses[_mes - 1]} $_anio'),
            ),
            SizedBox(
              width: searchWidth,
              child: TextField(
                controller: _buscarController,
                decoration: InputDecoration(
                  labelText: 'Buscar turno, nómina o nombre',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscarController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _buscarController.clear();
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Chip(
              label: Text(
                  '$totalFiltrado de ${_empleadosMatriz.length} empleados'),
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
        );
      },
    );
  }

  Widget _paginacionMatriz(int totalFiltrado) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 720;

        final controls = [
          const Text('Filas:'),
          DropdownButton<int>(
            value: _filasPorPagina,
            items: _opcionesFilas.map((value) {
              return DropdownMenuItem<int>(
                value: value,
                child: Text(value.toString()),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _filasPorPagina = value;
                _pagina = 0;
              });
            },
          ),
          IconButton(
            tooltip: 'Primera página',
            visualDensity: VisualDensity.compact,
            onPressed: _pagina <= 0
                ? null
                : () {
                    setState(() {
                      _pagina = 0;
                    });
                  },
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            tooltip: 'Página anterior',
            visualDensity: VisualDensity.compact,
            onPressed: _pagina <= 0
                ? null
                : () {
                    setState(() {
                      _pagina--;
                    });
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Página ${_pagina + 1} de $_totalPaginas'),
          IconButton(
            tooltip: 'Página siguiente',
            visualDensity: VisualDensity.compact,
            onPressed: _pagina >= _totalPaginas - 1
                ? null
                : () {
                    setState(() {
                      _pagina++;
                    });
                  },
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Última página',
            visualDensity: VisualDensity.compact,
            onPressed: _pagina >= _totalPaginas - 1
                ? null
                : () {
                    setState(() {
                      _pagina = _totalPaginas - 1;
                    });
                  },
            icon: const Icon(Icons.last_page),
          ),
        ];

        if (isSmall) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mostrando $_inicioVista-$_finVista de $totalFiltrado',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: controls,
              ),
            ],
          );
        }

        return Row(
          children: [
            Text(
              'Mostrando $_inicioVista-$_finVista de $totalFiltrado',
              style: const TextStyle(color: Colors.black54),
            ),
            const Spacer(),
            ...controls,
          ],
        );
      },
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
      'DOM': 'Domingo',
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
                  : e.key == 'DOM'
                      ? Colors.amber.shade100
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 720;
        final mesWidth = isSmall ? (constraints.maxWidth - 10) / 2 : 180.0;
        final anioWidth = isSmall ? (constraints.maxWidth - 10) / 2 : 130.0;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.fact_check, size: isSmall ? 24 : 30),
            Text(
              'Asistencias - Molinos',
              style: TextStyle(
                fontSize: isSmall ? 20 : 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _seleccionarFecha,
              icon: const Icon(Icons.calendar_today),
              label: Text('Día: ${_fechaTexto(_fecha)}'),
            ),
            SizedBox(
              width: mesWidth,
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
              width: anioWidth,
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
              label: Text(isSmall ? 'Actualizar' : 'Actualizar'),
            ),
            OutlinedButton.icon(
              onPressed: _exportando ? null : _exportarExcel,
              icon: const Icon(Icons.table_view),
              label: Text(isSmall ? 'Excel' : 'Exportar Excel'),
            ),
          ],
        );
      },
    );
  }

  String _csvValue(dynamic value) {
    final text = value?.toString() ?? '';
    final safe = text.replaceAll('"', '""');
    return '"$safe"';
  }

  Future<void> _exportarExcel() async {
    final empleados = _empleadosFiltrados;

    if (empleados.isEmpty) {
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
        'Turno',
        'Nómina',
        'Nombre',
        for (int d = 1; d <= diasMes; d++) _fechaCortaDia(d),
      ]);

      for (final emp in empleados) {
        final dias = Map<String, dynamic>.from(emp['dias'] ?? {});

        rows.add([
          _turnoTexto(emp),
          emp['numero_nomina'] ?? emp['nomina'] ?? '',
          emp['nombre'] ?? '',
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 720;

        return Scaffold(
          backgroundColor: const Color(0xfff4f6f8),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _cargarTodo,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(isSmall ? 10 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(),
                    SizedBox(height: isSmall ? 10 : 16),
                    _listasAsistencia(),
                    SizedBox(height: isSmall ? 10 : 16),
                    _leyenda(),
                    SizedBox(height: isSmall ? 10 : 16),
                    _matrizAsistencia(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
