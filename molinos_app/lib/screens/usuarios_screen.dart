import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/crud_service.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  bool loading = true;

  List<dynamic> rows = [];
  List<dynamic> areas = [];

  String q = '';

  final TextEditingController _buscarCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => load());
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  CrudService get _crud {
    final token = context.read<AuthService>().token!;
    return CrudService(token);
  }

  Future<void> load() async {
    final crud = _crud;

    if (mounted) {
      setState(() => loading = true);
    }

    try {
      final usuarios = await crud.get('/usuarios?q=$q');

      List<dynamic> areasData = [];

      try {
        areasData = await crud.get('/areas');
      } catch (_) {
        areasData = [];
      }

      if (!mounted) return;

      setState(() {
        rows = usuarios;
        areas = _limpiarAreasDuplicadas(areasData);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar usuarios: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<dynamic> _limpiarAreasDuplicadas(List<dynamic> data) {
    final Set<int> usados = {};
    final List<dynamic> limpias = [];

    for (final item in data) {
      if (item == null) continue;

      final rawId = item['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId.toString());

      if (id == null) continue;
      if (usados.contains(id)) continue;

      usados.add(id);
      limpias.add(item);
    }

    return limpias;
  }

  Future<void> _buscar() async {
    q = _buscarCtrl.text.trim();
    await load();
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? usuario}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return _UsuarioFormDialog(
          usuario: usuario,
          areas: areas,
        );
      },
    );

    if (result == true) {
      await load();
    }
  }

  Future<void> _desactivarUsuario(Map<String, dynamic> usuario) async {
    final id = usuario['id'];
    final nombre = usuario['nombre'] ?? '';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Desactivar usuario'),
          content: Text('¿Seguro que deseas desactivar a "$nombre"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.block),
              label: const Text('Desactivar'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) return;

    try {
      await _crud.delete('/usuarios/$id');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usuario desactivado'),
        ),
      );

      await load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al desactivar usuario: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _statusColor(dynamic activo) {
    final isActivo = activo == 1 || activo == true || activo == '1';
    return isActivo ? Colors.green : Colors.red;
  }

  String _statusText(dynamic activo) {
    final isActivo = activo == 1 || activo == true || activo == '1';
    return isActivo ? 'Activo' : 'Inactivo';
  }

  bool _isActivo(dynamic activo) {
    return activo == 1 || activo == true || activo == '1';
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
              const Text(
                'Usuarios',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: TextField(
                  controller: _buscarCtrl,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, usuario o correo',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscarCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              _buscarCtrl.clear();
                              q = '';
                              await load();
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _buscar(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Buscar',
                onPressed: _buscar,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: load,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _abrirFormulario(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : rows.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay usuarios registrados',
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final u = rows[i];

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _statusColor(u['activo']),
                            child: const Icon(
                              Icons.manage_accounts,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            u['nombre']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${u['usuario']?.toString() ?? ''} · ${u['tipo']?.toString() ?? ''} · ${u['area']?.toString() ?? 'Sin área'}'
                              '${u['correo'] != null && '${u['correo']}'.isNotEmpty ? '\n${u['correo']}' : ''}',
                            ),
                          ),
                          trailing: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Chip(
                                label: Text(_statusText(u['activo'])),
                                labelStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                                backgroundColor: _statusColor(u['activo']),
                              ),
                              IconButton(
                                tooltip: 'Editar',
                                icon: const Icon(Icons.edit),
                                onPressed: () => _abrirFormulario(usuario: u),
                              ),
                              IconButton(
                                tooltip: 'Desactivar',
                                icon: const Icon(Icons.block),
                                color: Colors.red,
                                onPressed: _isActivo(u['activo'])
                                    ? () => _desactivarUsuario(u)
                                    : null,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _UsuarioFormDialog extends StatefulWidget {
  final Map<String, dynamic>? usuario;
  final List<dynamic> areas;

  const _UsuarioFormDialog({
    required this.usuario,
    required this.areas,
  });

  @override
  State<_UsuarioFormDialog> createState() => _UsuarioFormDialogState();
}

class _UsuarioFormDialogState extends State<_UsuarioFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nombreCtrl;
  late TextEditingController usuarioCtrl;
  late TextEditingController passwordCtrl;
  late TextEditingController correoCtrl;

  String tipo = 'Usuario';
  int? areaId;
  bool activo = true;
  bool saving = false;

  bool get isEdit => widget.usuario != null;

  @override
  void initState() {
    super.initState();

    final u = widget.usuario;

    nombreCtrl = TextEditingController(
      text: u?['nombre']?.toString() ?? '',
    );

    usuarioCtrl = TextEditingController(
      text: u?['usuario']?.toString() ?? '',
    );

    passwordCtrl = TextEditingController();

    correoCtrl = TextEditingController(
      text: u?['correo']?.toString() ?? '',
    );

    tipo = _normalizarTipo(
      u?['tipo']?.toString() ?? 'Usuario',
    );

    areaId = _toIntOrNull(u?['area_id']);

    activo = u?['activo'] == null
        ? true
        : u?['activo'] == 1 || u?['activo'] == true || u?['activo'] == '1';
  }

  @override
  void dispose() {
    nombreCtrl.dispose();
    usuarioCtrl.dispose();
    passwordCtrl.dispose();
    correoCtrl.dispose();
    super.dispose();
  }

  String _normalizarTipo(String value) {
    final v = value.trim().toLowerCase();

    if (v == 'administrador') return 'Administrador';
    if (v == 'supervisor') return 'Supervisor';
    if (v == 'usuario') return 'Usuario';

    return 'Usuario';
  }

  int? _toIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  bool _isActivo(dynamic value) {
    return value == 1 || value == true || value == '1';
  }

  List<DropdownMenuItem<int?>> _buildAreaItems() {
    final List<DropdownMenuItem<int?>> items = [
      const DropdownMenuItem<int?>(
        value: null,
        child: Text('Sin área'),
      ),
    ];

    final Set<int> usedAreaIds = {};

    for (final a in widget.areas) {
      if (a == null) continue;

      final id = _toIntOrNull(a['id']);

      if (id == null) continue;
      if (usedAreaIds.contains(id)) continue;

      usedAreaIds.add(id);

      final nombre = a['nombre']?.toString() ?? 'Área';

      items.add(
        DropdownMenuItem<int?>(
          value: id,
          child: Text(nombre),
        ),
      );
    }

    return items;
  }

  int? _safeAreaId() {
    if (areaId == null) return null;

    final Set<int> usedAreaIds = {};

    for (final a in widget.areas) {
      if (a == null) continue;

      final id = _toIntOrNull(a['id']);

      if (id == null) continue;
      usedAreaIds.add(id);
    }

    if (usedAreaIds.contains(areaId)) {
      return areaId;
    }

    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final token = context.read<AuthService>().token!;
    final crud = CrudService(token);

    final password = passwordCtrl.text.trim();

    final payload = {
      'nombre': nombreCtrl.text.trim(),
      'usuario': usuarioCtrl.text.trim(),
      'password': password.isEmpty ? null : password,
      'tipo': tipo,
      'area_id': areaId,
      'correo': correoCtrl.text.trim().isEmpty ? null : correoCtrl.text.trim(),
      'activo': activo ? 1 : 0,
    };

    setState(() => saving = true);

    try {
      if (isEdit) {
        await crud.put('/usuarios/${widget.usuario!['id']}', payload);
      } else {
        await crud.post('/usuarios', payload);
      }

      if (!mounted) return;

      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEdit ? 'Usuario actualizado' : 'Usuario creado',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar usuario: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  InputDecoration _decoracion(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final areaItems = _buildAreaItems();
    final safeAreaId = _safeAreaId();

    if (safeAreaId != areaId) {
      areaId = safeAreaId;
    }

    return AlertDialog(
      title: Text(isEdit ? 'Editar usuario' : 'Nuevo usuario'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: nombreCtrl,
                  decoration: _decoracion(
                    'Nombre completo',
                    Icons.person,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: usuarioCtrl,
                  decoration: _decoracion(
                    'Usuario',
                    Icons.account_circle,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'El usuario es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: _decoracion(
                    isEdit
                        ? 'Contraseña nueva, dejar vacío para no cambiar'
                        : 'Contraseña',
                    Icons.lock,
                  ),
                  validator: (v) {
                    if (!isEdit && (v == null || v.trim().isEmpty)) {
                      return 'La contraseña es obligatoria';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tipo,
                  decoration: _decoracion(
                    'Tipo',
                    Icons.admin_panel_settings,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Administrador',
                      child: Text('Administrador'),
                    ),
                    DropdownMenuItem(
                      value: 'Supervisor',
                      child: Text('Supervisor'),
                    ),
                    DropdownMenuItem(
                      value: 'Usuario',
                      child: Text('Usuario'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => tipo = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  value: safeAreaId,
                  decoration: _decoracion(
                    'Área',
                    Icons.business,
                  ),
                  items: areaItems,
                  onChanged: (value) {
                    setState(() => areaId = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: correoCtrl,
                  decoration: _decoracion(
                    'Correo',
                    Icons.email,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: activo,
                  title: const Text('Usuario activo'),
                  subtitle: Text(activo ? 'Activo' : 'Inactivo'),
                  onChanged: (value) {
                    setState(() => activo = value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: saving ? null : _guardar,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.save),
          label: Text(
            saving ? 'Guardando...' : 'Guardar',
          ),
        ),
      ],
    );
  }
}
