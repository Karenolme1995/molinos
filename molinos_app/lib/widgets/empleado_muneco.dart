import 'package:flutter/material.dart';
import '../models/empleado_molinos.dart';
import '../services/api_service.dart';

class EmpleadoMuneco extends StatelessWidget {
  final EmpleadoMolinos empleado;
  final VoidCallback? onTap;
  final bool compacto;

  const EmpleadoMuneco({
    super.key,
    required this.empleado,
    this.onTap,
    this.compacto = false,
  });

  Color _turnoColor(String? color) {
    switch ((color ?? '').toLowerCase()) {
      case 'verde':
      case 'green':
        return Colors.green;
      case 'naranja':
      case 'orange':
        return Colors.orange;
      case 'azul':
      case 'blue':
        return Colors.blue;
      case 'rosa':
      case 'pink':
        return Colors.pink;
      case 'amarillo':
      case 'yellow':
        return Colors.amber;
      case 'rojo':
      case 'red':
        return Colors.red;
      case 'morado':
      case 'purple':
        return Colors.purple;
      default:
        return Colors.blueGrey;
    }
  }

  String? get _fotoUrl {
    final foto = empleado.foto?.trim();
    if (foto == null || foto.isEmpty) return null;
    if (foto.startsWith('http://') || foto.startsWith('https://')) return foto;
    return ApiService.fileUrl(foto);
  }

  @override
  Widget build(BuildContext context) {
    final color = _turnoColor(empleado.turnoColor);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: compacto ? _muneco3D(color, size: 74, soloMuneco: true) : _tarjetaMuneco(color),
    );
  }

  Widget _tarjetaMuneco(Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 2),
        boxShadow: const [
          BoxShadow(blurRadius: 8, offset: Offset(0, 3), color: Color(0x22000000)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _muneco3D(color, size: 76),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _turnoPill(color),
                    if (!empleado.turnoEnHorario) _avisoPill('Aún no es su turno'),
                    if (empleado.turnoPorConcluir) _avisoPill('Turno por concluir', warning: true),
                    if (empleado.acotacion != null && empleado.acotacion!.trim().isNotEmpty) _acotacionPill(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  empleado.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nómina: ${empleado.numeroNomina}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
                if (empleado.puesto != null && empleado.puesto!.trim().isNotEmpty)
                  Text(
                    empleado.puesto!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 3),
                Text(
                  empleado.maquinaNombre == null
                      ? 'En espera / afuera'
                      : 'Máquina: ${empleado.maquinaNombre} · desde ${empleado.horaInicioMaquina ?? '--:--'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _turnoPill(Color color) {
    final turno = empleado.turno?.trim().isNotEmpty == true ? empleado.turno!.trim() : 'SIN TURNO';
    final horario = empleado.horarioTurno;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Text(
        horario.isEmpty ? turno : '$turno · $horario',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _avisoPill(String text, {bool warning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: warning ? Colors.red.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warning ? Colors.red.shade200 : Colors.orange.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: warning ? Colors.red : Colors.deepOrange,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _acotacionPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Text(
        empleado.acotacion!,
        style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _muneco3D(Color color, {double size = 76, bool soloMuneco = false}) {
    final foto = _fotoUrl;
    final scale = size / 76.0;
    final headSize = 29.0 * scale;

    return SizedBox(
      width: size,
      height: soloMuneco ? size + 10 : size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 1 * scale,
            child: Container(
              width: 42 * scale,
              height: 8 * scale,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.12),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          CustomPaint(
            size: Size(size, size),
            painter: _Muneco3DPainter(color),
          ),
          Positioned(
            top: 7 * scale,
            child: Container(
              width: headSize,
              height: headSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-.35, -.45),
                  radius: .95,
                  colors: [Colors.white, Color(0xFFE7E7E7), Color(0xFFCFCFCF)],
                ),
                boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 5, offset: Offset(0, 3))],
              ),
              child: foto == null
                  ? null
                  : ClipOval(
                      child: Image.network(
                        foto,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
            ),
          ),
          if (soloMuneco)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 4)],
                ),
                child: Text(
                  empleado.turno ?? 'Turno',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Muneco3DPainter extends CustomPainter {
  final Color accent;
  _Muneco3DPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 76.0;
    final white = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFE9E9E9), Color(0xFFCFCFCF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final shadow = Paint()
      ..color = Colors.black.withOpacity(.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final accentPaint = Paint()..color = accent.withOpacity(.90);

    void capsule(Rect rect, double radius, Paint paint) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    }

    // sombra del cuerpo
    capsule(Rect.fromLTWH(27 * s, 33 * s, 23 * s, 31 * s).translate(1.5 * s, 2 * s), 12 * s, shadow);

    // piernas
    capsule(Rect.fromLTWH(26 * s, 56 * s, 11 * s, 17 * s), 7 * s, white);
    capsule(Rect.fromLTWH(39 * s, 56 * s, 11 * s, 17 * s), 7 * s, white);

    // pies
    capsule(Rect.fromLTWH(20 * s, 68 * s, 18 * s, 8 * s), 8 * s, white);
    capsule(Rect.fromLTWH(38 * s, 68 * s, 18 * s, 8 * s), 8 * s, white);

    // brazos tipo imagen, manos en cintura
    final leftArm = Path()
      ..moveTo(27 * s, 38 * s)
      ..cubicTo(17 * s, 41 * s, 15 * s, 50 * s, 20 * s, 57 * s)
      ..cubicTo(22 * s, 60 * s, 26 * s, 58 * s, 24 * s, 54 * s)
      ..cubicTo(22 * s, 49 * s, 25 * s, 45 * s, 31 * s, 43 * s)
      ..close();
    final rightArm = Path()
      ..moveTo(49 * s, 38 * s)
      ..cubicTo(59 * s, 41 * s, 61 * s, 50 * s, 56 * s, 57 * s)
      ..cubicTo(54 * s, 60 * s, 50 * s, 58 * s, 52 * s, 54 * s)
      ..cubicTo(54 * s, 49 * s, 51 * s, 45 * s, 45 * s, 43 * s)
      ..close();
    canvas.drawPath(leftArm.shift(Offset(1.5 * s, 2 * s)), shadow);
    canvas.drawPath(rightArm.shift(Offset(1.5 * s, 2 * s)), shadow);
    canvas.drawPath(leftArm, white);
    canvas.drawPath(rightArm, white);

    // cuerpo
    capsule(Rect.fromLTWH(26 * s, 32 * s, 24 * s, 32 * s), 12 * s, white);

    // cuello
    capsule(Rect.fromLTWH(34 * s, 29 * s, 8 * s, 8 * s), 5 * s, white);

    // pequeño distintivo de color para turno
    canvas.drawCircle(Offset(50 * s, 43 * s), 4.2 * s, accentPaint);
    canvas.drawCircle(Offset(50 * s, 43 * s), 2.1 * s, Paint()..color = Colors.white.withOpacity(.85));
  }

  @override
  bool shouldRepaint(covariant _Muneco3DPainter oldDelegate) => oldDelegate.accent != accent;
}
