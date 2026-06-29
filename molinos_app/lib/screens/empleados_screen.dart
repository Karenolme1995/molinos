import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class EmpleadosScreen extends StatefulWidget {
  const EmpleadosScreen({super.key});

  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen>
    with TickerProviderStateMixin {
  bool loading = true;
  bool saving = false;

  String? error;

  List<dynamic> turnos = [];
  List<dynamic> grupos = [];
  List<dynamic> sinTurno = [];
  List<dynamic> areas = [];

  String q = '';
  final TextEditingController _buscarCtrl = TextEditingController();

  TabController? _tabController;

  final String departamentoDefault = 'MOLINOS';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _headers() async {
    final auth = context.read<AuthService>();
    final token = await auth.getToken();

    return ApiService.headers(token: token);
  }

  dynamic _decode(http.Response res) {
    return ApiService.decode(res);
  }

  Future<dynamic> _get(String path) async {
    final res = await http
        .get(
          Uri.parse('${ApiService.baseUrl}$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 6));

    return _decode(res);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse('${ApiService.baseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));

    return _decode(res);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final res = await http
        .put(
          Uri.parse('${ApiService.baseUrl}$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));

    return _decode(res);
  }

  Future<dynamic> _delete(String path) async {
    final res = await http
        .delete(
          Uri.parse('${ApiService.baseUrl}$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 6));

    return _decode(res);
  }

  List<dynamic> _areasUnicas(List<dynamic> data) {
    final vistos = <String>{};
    final resultado = <dynamic>[];

    for (final raw in data) {
      final item = Map<String, dynamic>.from(raw);
      final nombre = item['nombre']?.toString().trim() ?? '';

      if (nombre.isEmpty) continue;

      final key = nombre.toLowerCase();

      if (vistos.contains(key)) continue;

      vistos.add(key);
      item['nombre'] = nombre;
      resultado.add(item);
    }

    return resultado;
  }

  Future<void> load() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final data = await _get(
        '/empleados/por-turno?departamento=$departamentoDefault',
      );

      final areasData = await _get('/empleados/areas');

      final nuevosGrupos = List<dynamic>.from(data['turnos'] ?? []);
      final nuevosTurnos = nuevosGrupos.map((g) => g['turno']).toList();
      final nuevosSinTurno = List<dynamic>.from(data['sin_turno'] ?? []);

      _tabController?.dispose();
      _tabController = TabController(
        length: nuevosGrupos.length + 1,
        vsync: this,
      );

      if (!mounted) return;

      setState(() {
        grupos = nuevosGrupos;
        turnos = nuevosTurnos;
        sinTurno = nuevosSinTurno;
        areas = _areasUnicas(List<dynamic>.from(areasData));
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  String _dateToText(dynamic value) {
    if (value == null) return '';

    final text = value.toString();

    if (text.length >= 10) {
      return text.substring(0, 10);
    }

    return text;
  }

  String? _emptyToNull(String text) {
    final value = text.trim();
    return value.isEmpty ? null : value;
  }

  int? _intOrNull(dynamic value) {
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  Widget _avatarEmpleado({
    required String foto,
    required String inicial,
    double size = 44,
  }) {
    Widget fallback() {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          inicial,
          style: TextStyle(
            color: Colors.blue.shade900,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (foto.trim().isEmpty) {
      return fallback();
    }

    return ClipOval(
      child: Image.network(
        ApiService.fileUrl(foto),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return fallback();
        },
      ),
    );
  }

  Widget _avatarFormulario({
    required String? foto,
  }) {
    Widget fallback() {
      return Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.person,
          size: 42,
          color: Colors.blue.shade900,
        ),
      );
    }

    if (foto == null || foto.trim().isEmpty) {
      return fallback();
    }

    return ClipOval(
      child: Image.network(
        ApiService.fileUrl(foto),
        width: 84,
        height: 84,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return fallback();
        },
      ),
    );
  }

  Future<void> _nuevoEmpleado() async {
    await _abrirFormulario();
  }

  Future<void> _editarEmpleado(Map<String, dynamic> empleado) async {
    await _abrirFormulario(empleado: empleado);
  }

  Future<String?> _subirFotoEmpleado({
    required int empleadoId,
    required ImageSource source,
  }) async {
    final picker = ImagePicker();

    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );

    if (picked == null) return null;

    final auth = context.read<AuthService>();
    final token = await auth.getToken();

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${ApiService.baseUrl}/empleados/$empleadoId/foto'),
    );

    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final bytes = await picked.readAsBytes();

    request.files.add(
      http.MultipartFile.fromBytes(
        'foto',
        bytes,
        filename: picked.name,
      ),
    );

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    final data = _decode(res);

    return data['foto']?.toString();
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? empleado}) async {
    final rootContext = context;

    final numeroNominaCtrl = TextEditingController(
      text: empleado?['numero_nomina']?.toString() ?? '',
    );
    final nombreCtrl = TextEditingController(
      text: empleado?['nombre']?.toString() ?? '',
    );
    final fotoCtrl = TextEditingController(
      text: empleado?['foto']?.toString() ?? '',
    );
    final puestoCtrl = TextEditingController(
      text: empleado?['puesto']?.toString() ?? '',
    );
    final responsabilidadesCtrl = TextEditingController(
      text: empleado?['responsabilidades']?.toString() ?? '',
    );
    final fechaNacimientoCtrl = TextEditingController(
      text: _dateToText(empleado?['fecha_nacimiento']),
    );
    final telefonoCtrl = TextEditingController(
      text: empleado?['telefono']?.toString() ?? '',
    );
    final direccionCtrl = TextEditingController(
      text: empleado?['direccion']?.toString() ?? '',
    );
    final statusCtrl = TextEditingController(
      text: empleado?['status']?.toString() ?? 'ACTIVO',
    );
    final departamentoCtrl = TextEditingController(
      text: empleado?['departamento']?.toString() ?? departamentoDefault,
    );

    int activo = _intOrNull(empleado?['activo']) ?? 1;
    int? turnoSeleccionado = _intOrNull(empleado?['turno_id']);
    String? fotoPreview = empleado?['foto']?.toString();

    final fechaInicioTurnoCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );

    bool dialogAbierto = true;

    await showDialog(
      context: rootContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool guardandoFormulario = false;

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            Future<void> guardar() async {
              final nombre = nombreCtrl.text.trim();

              if (nombre.isEmpty) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(content: Text('El nombre es obligatorio')),
                );
                return;
              }

              final turnoOriginal = _intOrNull(empleado?['turno_id']);
              final turnoCambio = turnoSeleccionado != turnoOriginal;

              final body = {
                'numero_nomina': _emptyToNull(numeroNominaCtrl.text),
                'nombre': _emptyToNull(nombreCtrl.text),
                'foto': _emptyToNull(fotoCtrl.text),
                'puesto': _emptyToNull(puestoCtrl.text),
                'responsabilidades': _emptyToNull(responsabilidadesCtrl.text),
                'fecha_nacimiento': _emptyToNull(fechaNacimientoCtrl.text),
                'telefono': _emptyToNull(telefonoCtrl.text),
                'direccion': _emptyToNull(direccionCtrl.text),
                'status': _emptyToNull(statusCtrl.text) ?? 'ACTIVO',
                'departamento':
                    _emptyToNull(departamentoCtrl.text) ?? departamentoDefault,
                'activo': activo,
                'turno_id': empleado == null || turnoCambio
                    ? turnoSeleccionado
                    : null,
                'fecha_inicio_turno': empleado == null || turnoCambio
                    ? _emptyToNull(fechaInicioTurnoCtrl.text)
                    : null,
              };

              setModalState(() {
                guardandoFormulario = true;
              });

              try {
                dynamic result;

                if (empleado == null) {
                  result = await _post('/empleados', body);
                } else {
                  result = await _put('/empleados/${empleado['id']}', body);
                }

                if (!mounted) return;

                setModalState(() {
                  guardandoFormulario = false;
                });

                dialogAbierto = false;
                Navigator.of(dialogContext, rootNavigator: true).pop();

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      empleado == null
                          ? 'Empleado creado correctamente'
                          : 'Empleado actualizado correctamente',
                    ),
                  ),
                );

                Future.microtask(() {
                  if (mounted) {
                    load();
                  }
                });

                if (empleado == null && result is Map && result['id'] != null) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Empleado creado. Para agregar foto, abre editar empleado.',
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              } finally {
                if (dialogAbierto) {
                  setModalState(() {
                    guardandoFormulario = false;
                  });
                }
              }
            }

            final departamentoActual = departamentoCtrl.text.trim();

            return AlertDialog(
              title: Text(
                empleado == null ? 'Nuevo empleado' : 'Editar empleado',
              ),
              content: SizedBox(
                width: 820,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _avatarFormulario(foto: fotoPreview),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: empleado == null
                                      ? null
                                      : () async {
                                          final url = await _subirFotoEmpleado(
                                            empleadoId: int.parse(
                                              empleado['id'].toString(),
                                            ),
                                            source: ImageSource.gallery,
                                          );

                                          if (url == null) return;
                                          if (!dialogAbierto) return;

                                          setModalState(() {
                                            fotoPreview = url;
                                            fotoCtrl.text = url;
                                          });
                                        },
                                  icon: const Icon(Icons.upload_file),
                                  label: const Text('Seleccionar foto'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: empleado == null
                                      ? null
                                      : () async {
                                          final url = await _subirFotoEmpleado(
                                            empleadoId: int.parse(
                                              empleado['id'].toString(),
                                            ),
                                            source: ImageSource.camera,
                                          );

                                          if (url == null) return;
                                          if (!dialogAbierto) return;

                                          setModalState(() {
                                            fotoPreview = url;
                                            fotoCtrl.text = url;
                                          });
                                        },
                                  icon: const Icon(Icons.photo_camera),
                                  label: const Text('Tomar foto'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (empleado == null) ...[
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Primero guarda el empleado para poder cargar foto.',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              controller: numeroNominaCtrl,
                              label: 'Número de nómina',
                              icon: Icons.badge,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _campo(
                              controller: nombreCtrl,
                              label: 'Nombre completo',
                              icon: Icons.person,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              controller: puestoCtrl,
                              label: 'Puesto',
                              icon: Icons.work,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: areas.any(
                                (a) =>
                                    (a['nombre']?.toString().trim() ?? '') ==
                                    departamentoActual,
                              )
                                  ? departamentoActual
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Departamento / Área',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.apartment),
                              ),
                              items: areas.map((a) {
                                final nombre =
                                    a['nombre']?.toString().trim() ?? '';

                                return DropdownMenuItem<String>(
                                  value: nombre,
                                  child: Text(nombre),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value == null) return;

                                setModalState(() {
                                  departamentoCtrl.text = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        controller: fotoCtrl,
                        label: 'Foto URL',
                        icon: Icons.image,
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        controller: responsabilidadesCtrl,
                        label: 'Responsabilidades',
                        icon: Icons.assignment,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              controller: fechaNacimientoCtrl,
                              label: 'Fecha nacimiento YYYY-MM-DD',
                              icon: Icons.calendar_today,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _campo(
                              controller: telefonoCtrl,
                              label: 'Teléfono',
                              icon: Icons.phone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _campo(
                        controller: direccionCtrl,
                        label: 'Dirección',
                        icon: Icons.home,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _campo(
                              controller: statusCtrl,
                              label: 'Status',
                              icon: Icons.info,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: activo,
                              decoration: const InputDecoration(
                                labelText: 'Activo',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.toggle_on),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('Activo'),
                                ),
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Inactivo'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;

                                setModalState(() {
                                  activo = value;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: turnoSeleccionado,
                              decoration: const InputDecoration(
                                labelText: 'Turno',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.schedule),
                              ),
                              items: [
                                const DropdownMenuItem<int>(
                                  value: null,
                                  child: Text('Sin turno'),
                                ),
                                ...turnos.map((t) {
                                  return DropdownMenuItem<int>(
                                    value: _intOrNull(t['id']),
                                    child: Text(
                                      '${t['nombre']} (${t['hora_inicio'] ?? ''} - ${t['hora_fin'] ?? ''})',
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  turnoSeleccionado = value;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _campo(
                              controller: fechaInicioTurnoCtrl,
                              label: 'Inicio turno YYYY-MM-DD',
                              icon: Icons.event_available,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (empleado != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => _abrirRotacionEmpleado(
                              empleadoId: int.parse(empleado['id'].toString()),
                              nombreEmpleado:
                                  empleado['nombre']?.toString() ?? '',
                            ),
                            icon: const Icon(Icons.autorenew),
                            label: const Text('Configurar rotación semanal'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: guardandoFormulario
                      ? null
                      : () {
                          dialogAbierto = false;
                          Navigator.of(dialogContext, rootNavigator: true).pop();
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: guardandoFormulario ? null : guardar,
                  icon: guardandoFormulario
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(guardandoFormulario ? 'Guardando...' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
    );
  }

  Future<void> _eliminarEmpleado(Map<String, dynamic> empleado) async {
    final rootContext = context;

    final ok = await showDialog<bool>(
      context: rootContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Desactivar empleado'),
          content: Text(
            '¿Seguro que deseas desactivar a ${empleado['nombre']}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Desactivar'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await _delete('/empleados/${empleado['id']}');
      await load();

      if (!mounted) return;

      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(content: Text('Empleado desactivado')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _cambiarGrupoTurno(Map<String, dynamic> grupoActual) async {
    final rootContext = context;

    final turnoActual = Map<String, dynamic>.from(grupoActual['turno']);
    final origenId = _intOrNull(turnoActual['id']);

    if (origenId == null) return;

    int? destinoId;
    final fechaCtrl = TextEditingController(
      text: DateTime.now().toIso8601String().substring(0, 10),
    );

    final empleados = List<dynamic>.from(grupoActual['empleados'] ?? []);

    if (empleados.isEmpty) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        const SnackBar(content: Text('No hay empleados en este turno')),
      );
      return;
    }

    await showDialog(
      context: rootContext,
      builder: (dialogContext) {
        bool dialogGrupoAbierto = true;
        bool guardandoGrupo = false;

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            Future<void> guardar() async {
              if (destinoId == null) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(content: Text('Selecciona el turno destino')),
                );
                return;
              }

              final ok = await showDialog<bool>(
                context: rootContext,
                builder: (confirmContext) {
                  return AlertDialog(
                    title: const Text('Confirmar cambio masivo'),
                    content: Text(
                      'Se cambiarán ${empleados.length} empleados de ${turnoActual['nombre']} al turno seleccionado. ¿Continuar?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(confirmContext, true),
                        child: const Text('Cambiar grupo'),
                      ),
                    ],
                  );
                },
              );

              if (ok != true) return;

              setModalState(() {
                guardandoGrupo = true;
              });

              try {
                final result = await _put('/empleados/grupo-turno', {
                  'origen_turno_id': origenId,
                  'destino_turno_id': destinoId,
                  'departamento': departamentoDefault,
                  'fecha_inicio': _emptyToNull(fechaCtrl.text),
                });

                if (!mounted) return;

                dialogGrupoAbierto = false;
                Navigator.of(dialogContext, rootNavigator: true).pop();

                if (!mounted) return;

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      result['message']?.toString() ??
                          'Grupo actualizado correctamente',
                    ),
                  ),
                );

                load();
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text(e.toString().replaceFirst('Exception: ', '')),
                  ),
                );
              } finally {
                if (dialogGrupoAbierto) {
                  setModalState(() {
                    guardandoGrupo = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: Text('Cambiar grupo: ${turnoActual['nombre']}'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Empleados en este turno: ${empleados.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      value: destinoId,
                      decoration: const InputDecoration(
                        labelText: 'Turno destino',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.compare_arrows),
                      ),
                      items: turnos
                          .where((t) => _intOrNull(t['id']) != origenId)
                          .map((t) {
                        return DropdownMenuItem<int>(
                          value: _intOrNull(t['id']),
                          child: Text(
                            '${t['nombre']} (${t['hora_inicio'] ?? ''} - ${t['hora_fin'] ?? ''})',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setModalState(() {
                          destinoId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _campo(
                      controller: fechaCtrl,
                      label: 'Fecha inicio YYYY-MM-DD',
                      icon: Icons.event,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: guardandoGrupo
                      ? null
                      : () {
                          dialogGrupoAbierto = false;
                          Navigator.of(dialogContext, rootNavigator: true).pop();
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: guardandoGrupo ? null : guardar,
                  icon: guardandoGrupo
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.swap_horiz),
                  label: Text(
                    guardandoGrupo ? 'Cambiando...' : 'Cambiar todo el grupo',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    fechaCtrl.dispose();
  }

  Future<void> _abrirRotacionEmpleado({
    required int empleadoId,
    required String nombreEmpleado,
  }) async {
    final rootContext = context;

    String fechaHoy() => DateTime.now().toIso8601String().substring(0, 10);

    List<Map<String, dynamic>> rotacion = [
      {
        'semana_orden': 1,
        'turno_id': null,
        'fecha_inicio': fechaHoy(),
        'fecha_fin': '',
      },
      {
        'semana_orden': 2,
        'turno_id': null,
        'fecha_inicio': '',
        'fecha_fin': '',
      },
      {
        'semana_orden': 3,
        'turno_id': null,
        'fecha_inicio': '',
        'fecha_fin': '',
      },
    ];

    try {
      final data = await _get('/empleados/rotacion/$empleadoId');
      final actual = List<dynamic>.from(data['rotacion'] ?? []);

      if (actual.isNotEmpty) {
        rotacion = actual.map((r) {
          return {
            'semana_orden': _intOrNull(r['semana_orden']) ?? 1,
            'turno_id': _intOrNull(r['turno_id']),
            'fecha_inicio': _dateToText(r['fecha_inicio']),
            'fecha_fin': _dateToText(r['fecha_fin']),
          };
        }).toList();
      }
    } catch (_) {}

    if (!mounted) return;

    await showDialog(
      context: rootContext,
      builder: (dialogContext) {
        bool guardandoRotacion = false;
        bool dialogRotacionAbierto = true;

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            Future<void> guardarRotacion() async {
              final limpia = rotacion
                  .where((r) => r['turno_id'] != null)
                  .map((r) {
                final fechaInicio = r['fecha_inicio']?.toString().trim() ?? '';
                final fechaFin = r['fecha_fin']?.toString().trim() ?? '';

                return {
                  'semana_orden': r['semana_orden'],
                  'turno_id': r['turno_id'],
                  'fecha_inicio': fechaInicio.isEmpty ? null : fechaInicio,
                  'fecha_fin': fechaFin.isEmpty ? null : fechaFin,
                };
              }).toList();

              if (limpia.isEmpty) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(
                    content: Text('Agrega al menos una semana de rotación'),
                  ),
                );
                return;
              }

              for (final item in limpia) {
                final inicio = item['fecha_inicio']?.toString() ?? '';
                final fin = item['fecha_fin']?.toString() ?? '';

                if (inicio.isNotEmpty && fin.isNotEmpty) {
                  final fechaInicio = DateTime.tryParse(inicio);
                  final fechaFin = DateTime.tryParse(fin);

                  if (fechaInicio == null || fechaFin == null) {
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(
                        content: Text('Usa fechas válidas en formato YYYY-MM-DD'),
                      ),
                    );
                    return;
                  }

                  if (fechaFin.isBefore(fechaInicio)) {
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'La fecha fin no puede ser menor a la fecha inicio en la semana ${item['semana_orden']}',
                        ),
                      ),
                    );
                    return;
                  }
                }
              }

              setModalState(() {
                guardandoRotacion = true;
              });

              try {
                await _post('/empleados/rotacion', {
                  'empleado_id': empleadoId,
                  'rotacion': limpia,
                });

                if (!mounted) return;

                dialogRotacionAbierto = false;
                Navigator.of(dialogContext, rootNavigator: true).pop();

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(
                    content: Text('Rotación guardada correctamente'),
                  ),
                );

                load();
              } catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      e.toString().replaceFirst('Exception: ', ''),
                    ),
                  ),
                );
              } finally {
                if (dialogRotacionAbierto) {
                  setModalState(() {
                    guardandoRotacion = false;
                  });
                }
              }
            }

            return AlertDialog(
              title: Text('Rotación semanal: $nombreEmpleado'),
              content: SizedBox(
                width: 860,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Configura el turno y el rango de fechas. Si dejas las fechas vacías, la semana queda sin límite de fecha.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...rotacion.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  'Semana ${item['semana_orden']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<int>(
                                  value: item['turno_id'],
                                  decoration: const InputDecoration(
                                    labelText: 'Turno',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.schedule),
                                  ),
                                  items: turnos.map((t) {
                                    return DropdownMenuItem<int>(
                                      value: _intOrNull(t['id']),
                                      child: Text(
                                        '${t['nombre']} (${t['hora_inicio'] ?? ''} - ${t['hora_fin'] ?? ''})',
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setModalState(() {
                                      rotacion[index]['turno_id'] = value;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: item['fecha_inicio']?.toString() ?? '',
                                  decoration: const InputDecoration(
                                    labelText: 'De día',
                                    hintText: 'YYYY-MM-DD',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.date_range),
                                  ),
                                  onChanged: (value) {
                                    rotacion[index]['fecha_inicio'] = value.trim();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: item['fecha_fin']?.toString() ?? '',
                                  decoration: const InputDecoration(
                                    labelText: 'A día',
                                    hintText: 'YYYY-MM-DD',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.event_available),
                                  ),
                                  onChanged: (value) {
                                    rotacion[index]['fecha_fin'] = value.trim();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Eliminar semana',
                                onPressed: rotacion.length <= 1
                                    ? null
                                    : () {
                                        setModalState(() {
                                          rotacion.removeAt(index);
                                          for (int i = 0;
                                              i < rotacion.length;
                                              i++) {
                                            rotacion[i]['semana_orden'] = i + 1;
                                          }
                                        });
                                      },
                                icon: const Icon(Icons.delete),
                              ),
                            ],
                          ),
                        );
                      }),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setModalState(() {
                              rotacion.add({
                                'semana_orden': rotacion.length + 1,
                                'turno_id': null,
                                'fecha_inicio': '',
                                'fecha_fin': '',
                              });
                            });
                          },
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
                  onPressed: guardandoRotacion
                      ? null
                      : () {
                          dialogRotacionAbierto = false;
                          Navigator.of(dialogContext, rootNavigator: true).pop();
                        },
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: guardandoRotacion ? null : guardarRotacion,
                  icon: guardandoRotacion
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    guardandoRotacion ? 'Guardando...' : 'Guardar rotación',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }


  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.badge, size: 30),
          const SizedBox(width: 10),
          const Text(
            'Empleados Molinos',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 20),
          SizedBox(
            width: 320,
            child: TextField(
              controller: _buscarCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar empleado, nómina o puesto',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            q = '';
                            _buscarCtrl.clear();
                          });
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                setState(() {
                  q = value.trim().toLowerCase();
                });
              },
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _nuevoEmpleado,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo empleado'),
          ),
        ],
      ),
    );
  }

  List<Tab> _tabs() {
    return [
      ...grupos.map((g) {
        final turno = Map<String, dynamic>.from(g['turno']);
        final empleados = List<dynamic>.from(g['empleados'] ?? []);

        return Tab(
          text: '${turno['nombre']} (${empleados.length})',
        );
      }),
      Tab(text: 'Sin turno (${sinTurno.length})'),
    ];
  }

  List<Widget> _tabViews() {
    return [
      ...grupos.map((g) {
        return _grupoTurnoView(Map<String, dynamic>.from(g));
      }),
      _listaEmpleados(
        titulo: 'Empleados sin turno',
        empleados: sinTurno,
      ),
    ];
  }

  Widget _grupoTurnoView(Map<String, dynamic> grupo) {
    final turno = Map<String, dynamic>.from(grupo['turno']);
    final empleados = List<dynamic>.from(grupo['empleados'] ?? []);

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.schedule,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${turno['nombre']} · ${turno['hora_inicio'] ?? ''} - ${turno['hora_fin'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _cambiarGrupoTurno(grupo),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Cambiar todo el grupo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _listaEmpleados(
            titulo: turno['nombre']?.toString() ?? 'Turno',
            empleados: empleados,
          ),
        ),
      ],
    );
  }

  Widget _listaEmpleados({
    required String titulo,
    required List<dynamic> empleados,
  }) {
    final filtrados = empleados.where((raw) {
      final e = Map<String, dynamic>.from(raw);

      if (q.isEmpty) return true;

      final texto = [
        e['nombre'],
        e['numero_nomina'],
        e['puesto'],
        e['departamento'],
        e['turno_nombre'],
      ].where((x) => x != null).join(' ').toLowerCase();

      return texto.contains(q);
    }).toList();

    if (filtrados.isEmpty) {
      return const Center(
        child: Text('Sin empleados'),
      );
    }

    return ListView.separated(
      itemCount: filtrados.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = Map<String, dynamic>.from(filtrados[i]);
        final nombre = e['nombre']?.toString() ?? '';
        final inicial = nombre.isNotEmpty ? nombre.substring(0, 1) : '?';
        final foto = e['foto']?.toString() ?? '';

        return ListTile(
          leading: _avatarEmpleado(
            foto: foto,
            inicial: inicial,
            size: 44,
          ),
          title: Text(
            nombre,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'Nómina: ${e['numero_nomina'] ?? '-'} · ${e['puesto'] ?? '-'} · ${e['departamento'] ?? '-'} · ${e['turno_nombre'] ?? 'Sin turno'}',
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'editar') {
                _editarEmpleado(e);
              }

              if (value == 'eliminar') {
                _eliminarEmpleado(e);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'editar',
                child: Row(
                  children: [
                    Icon(Icons.edit),
                    SizedBox(width: 8),
                    Text('Editar'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'eliminar',
                child: Row(
                  children: [
                    Icon(Icons.delete),
                    SizedBox(width: 8),
                    Text('Desactivar'),
                  ],
                ),
              ),
            ],
          ),
          onTap: () => _editarEmpleado(e),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Column(
        children: [
          _header(),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return Column(
        children: [
          _header(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_tabController == null) {
      return Column(
        children: [
          _header(),
          const Expanded(
            child: Center(
              child: Text('Sin datos'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _header(),
        Material(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.black54,
            tabs: _tabs(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _tabViews(),
          ),
        ),
      ],
    );
  }
}
