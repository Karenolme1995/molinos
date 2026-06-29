import 'package:flutter/material.dart';
import '../models/empleado_molinos.dart';

class EmpleadoMuneco extends StatelessWidget {
  final EmpleadoMolinos empleado;
  final VoidCallback? onTap;

  const EmpleadoMuneco({super.key, required this.empleado, this.onTap});

  Color _turnoColor(String? color) {
    switch (color) {
      case 'verde': return Colors.green;
      case 'naranja': return Colors.orange;
      case 'azul': return Colors.blue;
      case 'rosa': return Colors.pink;
      case 'amarillo': return Colors.amber;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _turnoColor(empleado.turnoColor), width: 2),
          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: (empleado.foto != null && empleado.foto!.isNotEmpty) ? NetworkImage(empleado.foto!) : null,
              child: empleado.foto == null || empleado.foto!.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(empleado.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      if (empleado.acotacion != null) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Text(empleado.acotacion!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                      ),
                    ],
                  ),
                  Text('Nómina: ${empleado.numeroNomina}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  if (empleado.puesto != null) Text(empleado.puesto!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
