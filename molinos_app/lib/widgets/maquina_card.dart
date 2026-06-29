import 'package:flutter/material.dart';
import '../models/empleado_molinos.dart';
import '../models/maquina_molinos.dart';
import 'empleado_muneco.dart';

class MaquinaCard extends StatelessWidget {
  final MaquinaMolinos maquina;
  final bool canEdit;
  final Function(EmpleadoMolinos empleado) onDropEmpleado;
  final Function(String estado) onEstado;
  final Function(EmpleadoMolinos empleado) onEmpleadoTap;

  const MaquinaCard({
    super.key,
    required this.maquina,
    required this.canEdit,
    required this.onDropEmpleado,
    required this.onEstado,
    required this.onEmpleadoTap,
  });

  Color _estadoColor(String estado) {
    switch (estado) {
      case 'trabajando': return Colors.green;
      case 'paro': return Colors.red;
      case 'mantenimiento': return Colors.orange;
      case 'limpieza': return Colors.blue;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(maquina.estado);
    return DragTarget<EmpleadoMolinos>(
      onWillAcceptWithDetails: (_) => canEdit,
      onAcceptWithDetails: (details) => onDropEmpleado(details.data),
      builder: (context, candidate, rejected) {
        return Container(
          width: 360,
          constraints: const BoxConstraints(minHeight: 280),
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: candidate.isNotEmpty ? Colors.indigo.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 3),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black12)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(maquina.nombre, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(maquina.estadoNombre, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _EstadoButton(label: 'Trabajando', color: Colors.green, enabled: canEdit, onTap: () => onEstado('trabajando')),
                  _EstadoButton(label: 'Paro', color: Colors.red, enabled: canEdit, onTap: () => onEstado('paro')),
                  _EstadoButton(label: 'Manto', color: Colors.orange, enabled: canEdit, onTap: () => onEstado('mantenimiento')),
                  _EstadoButton(label: 'Limpieza', color: Colors.blue, enabled: canEdit, onTap: () => onEstado('limpieza')),
                ],
              ),
              const Divider(height: 24),
              if (maquina.empleados.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Arrastra empleados aquí', style: TextStyle(color: Colors.grey))),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: maquina.empleados.map((e) => EmpleadoMuneco(empleado: e, onTap: () => onEmpleadoTap(e))).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EstadoButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _EstadoButton({required this.label, required this.color, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: enabled ? onTap : null,
      style: FilledButton.styleFrom(foregroundColor: color),
      child: Text(label),
    );
  }
}
