import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/empleado_molinos.dart';
import '../services/auth_service.dart';
import '../services/molinos_service.dart';
import '../widgets/empleado_muneco.dart';
import '../widgets/maquina_card.dart';
import '../services/api_service.dart';

class MolinosScreen extends StatefulWidget {
  const MolinosScreen({super.key});

  @override
  State<MolinosScreen> createState() => _MolinosScreenState();
}

class _MolinosScreenState extends State<MolinosScreen> {
  DateTime _fecha = DateTime.now();
  bool _loading = true;
  String? _error;
  TableroMolinos? _tablero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = context.read<AuthService>().token!;
      _tablero = await MolinosService(token).tablero(_fecha);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _asignar(EmpleadoMolinos empleado, int maquinaId) async {
    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).asignar(empleadoId: empleado.id, maquinaId: maquinaId, fecha: _fecha);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _estado(int maquinaId, String estado) async {
    try {
      final token = context.read<AuthService>().token!;
      await MolinosService(token).cambiarEstado(maquinaId: maquinaId, estado: estado);
      await _load();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  void _detalle(EmpleadoMolinos e) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(e.nombre),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundImage: e.foto != null && e.foto!.isNotEmpty
                        ? NetworkImage(ApiService.fileUrl(e.foto!))
                        : null,
                    child: e.foto == null || e.foto!.isEmpty
                        ? const Icon(Icons.person, size: 36)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nómina: ${e.numeroNomina}'),
                    Text('Puesto: ${e.puesto ?? ''}'),
                    Text('Turno: ${e.turno ?? ''}'),
                    if (e.acotacion != null) Text('${e.acotacion}: ${e.acotacionDescripcion ?? ''}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ])),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Responsabilidades', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(e.responsabilidades?.isNotEmpty == true ? e.responsabilidades! : 'Sin responsabilidades registradas'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              const Text('Molinos', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              Text(DateFormat('dd/MM/yyyy').format(_fecha)),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                  : Row(
                      children: [
                        SizedBox(width: 330, child: _panelEmpleados(auth.canEdit)),
                        const VerticalDivider(width: 1),
                        Expanded(child: _panelMaquinas(auth.canEdit)),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _panelEmpleados(bool canEdit) {
    final t = _tablero!;
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          const Text('Empleados en espera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (t.espera.isEmpty) const Text('No hay empleados en espera.'),
          ...t.espera.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: canEdit
                ? Draggable<EmpleadoMolinos>(
                    data: e,
                    feedback: Material(color: Colors.transparent, child: EmpleadoMuneco(empleado: e)),
                    childWhenDragging: Opacity(opacity: .4, child: EmpleadoMuneco(empleado: e, onTap: () => _detalle(e))),
                    child: EmpleadoMuneco(empleado: e, onTap: () => _detalle(e)),
                  )
                : EmpleadoMuneco(empleado: e, onTap: () => _detalle(e)),
          )),
          const Divider(height: 30),
          const Text('Alertas / Acotaciones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...t.alertas.map((e) => ListTile(
            dense: true,
            leading: const Icon(Icons.warning, color: Colors.red),
            title: Text(e.nombre),
            subtitle: Text('${e.acotacion ?? ''} ${e.acotacionDescripcion ?? ''}'),
            onTap: () => _detalle(e),
          )),
          const Divider(height: 30),
          const Text('No se presentaron', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ...t.ausentes.map((e) => ListTile(
            dense: true,
            leading: const Icon(Icons.person_off),
            title: Text(e.nombre),
            subtitle: Text(e.puesto ?? ''),
            onTap: () => _detalle(e),
          )),
        ],
      ),
    );
  }

  Widget _panelMaquinas(bool canEdit) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        children: _tablero!.maquinas.map((m) {
          return MaquinaCard(
            maquina: m,
            canEdit: canEdit,
            onDropEmpleado: (e) => _asignar(e, m.id),
            onEstado: (estado) => _estado(m.id, estado),
            onEmpleadoTap: _detalle,
          );
        }).toList(),
      ),
    );
  }
}
