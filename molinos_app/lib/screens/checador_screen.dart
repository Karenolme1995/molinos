import 'dart:async';

import 'package:flutter/material.dart';

import '../services/asistencias_service.dart';

class ChecadorScreen extends StatefulWidget {
  final Future<String?> Function() getToken;

  const ChecadorScreen({
    super.key,
    required this.getToken,
  });

  @override
  State<ChecadorScreen> createState() => _ChecadorScreenState();
}

class _ChecadorScreenState extends State<ChecadorScreen> {
  late final AsistenciasService _service;

  final TextEditingController _nominaController = TextEditingController();
  final FocusNode _nominaFocus = FocusNode();

  Timer? _timerHora;
  Timer? _timerLimpiar;

  DateTime _horaMexico = DateTime.now();

  bool _loadingHora = true;
  bool _checando = false;

  String? _error;
  Map<String, dynamic>? _resultado;

  @override
  void initState() {
    super.initState();
    _service = AsistenciasService(getToken: widget.getToken);
    _iniciarHora();
  }

  @override
  void dispose() {
    _timerHora?.cancel();
    _timerLimpiar?.cancel();
    _nominaController.dispose();
    _nominaFocus.dispose();
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

    if (!mounted) return;

    setState(() {
      _loadingHora = false;
    });

    _timerHora?.cancel();
    _timerHora = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      setState(() {
        _horaMexico = _horaMexico.add(const Duration(seconds: 1));
      });
    });
  }

  void _programarLimpieza() {
    _timerLimpiar?.cancel();

    _timerLimpiar = Timer(const Duration(minutes: 1), () {
      if (!mounted) return;

      setState(() {
        _resultado = null;
        _error = null;
      });

      _nominaController.clear();
      _nominaFocus.requestFocus();
    });
  }

  void _limpiarAhora() {
    _timerLimpiar?.cancel();

    setState(() {
      _resultado = null;
      _error = null;
    });

    _nominaController.clear();
    _nominaFocus.requestFocus();
  }

  String _fechaTexto(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/'
        '${fecha.year}';
  }

  String _horaTexto(DateTime fecha) {
    return '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}:'
        '${fecha.second.toString().padLeft(2, '0')}';
  }

  Future<void> _checar() async {
    final numeroNomina = _nominaController.text.trim();

    if (numeroNomina.isEmpty) {
      setState(() {
        _error = 'Ingresa tu número de nómina';
        _resultado = null;
      });

      _programarLimpieza();
      return;
    }

    setState(() {
      _checando = true;
      _error = null;
      _resultado = null;
    });

    try {
      final data = await _service.checarPorNomina(
        numeroNomina: numeroNomina,
      );

      if (!mounted) return;

      setState(() {
        _resultado = data;
        _error = null;
      });

      _nominaController.clear();
      _nominaFocus.requestFocus();
      _programarLimpieza();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _resultado = null;
      });

      _nominaFocus.requestFocus();
      _programarLimpieza();
    } finally {
      if (!mounted) return;

      setState(() {
        _checando = false;
      });
    }
  }

  Widget _relojCard() {
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Text(
              'Hora México',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _loadingHora ? '--:--:--' : _horaTexto(_horaMexico),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 58,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _fechaTexto(_horaMexico),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checadorCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.fingerprint,
              size: 70,
              color: Colors.blue,
            ),
            const SizedBox(height: 12),
            const Text(
              'Checador de asistencia',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ingresa tu número de nómina para registrar tu siguiente checada.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 26),
            TextField(
              controller: _nominaController,
              focusNode: _nominaFocus,
              autofocus: true,
              enabled: !_checando,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
              decoration: const InputDecoration(
                labelText: 'Número de nómina',
                prefixIcon: Icon(Icons.badge),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _checar(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _checando ? null : _checar,
                icon: _checando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  _checando ? 'Registrando...' : 'Registrar checada',
                  style: const TextStyle(fontSize: 17),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelIzquierdo() {
    return Column(
      children: [
        _relojCard(),
        const SizedBox(height: 18),
        _checadorCard(),
      ],
    );
  }

  Widget _panelDerecho() {
    if (_error != null) {
      return _errorCard();
    }

    if (_resultado != null) {
      return _resultadoCard();
    }

    return _esperaCard();
  }

  Widget _esperaCard() {
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(30),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.badge_outlined,
              size: 80,
              color: Colors.black26,
            ),
            SizedBox(height: 16),
            Text(
              'Información del empleado',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Aquí se mostrará la información después de registrar la checada.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard() {
    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.error,
              size: 70,
              color: Colors.red,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se pudo registrar',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _limpiarAhora,
              icon: const Icon(Icons.cleaning_services),
              label: const Text('Limpiar'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta información se limpiará automáticamente en 1 minuto.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultadoCard() {
    final data = _resultado;

    if (data == null) {
      return const SizedBox.shrink();
    }

    final empleado = Map<String, dynamic>.from(data['empleado'] ?? {});
    final checadas = List<dynamic>.from(data['checadas'] ?? []);
    final tiempoExtra = Map<String, dynamic>.from(data['tiempo_extra'] ?? {});

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green.shade600,
                  child: const Icon(Icons.check, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data['message']?.toString() ?? 'Checada registrada',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            _info('Empleado', empleado['nombre']),
            _info('Nómina', empleado['numero_nomina']),
            _info('Puesto', empleado['puesto']),
            _info('Departamento', empleado['departamento']),
            _info('Checada registrada', data['tipo_label']),
            _info('Hora', data['hora']),
            const SizedBox(height: 12),
            const Text(
              'Checadas del día',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: checadas.map((raw) {
                final c = Map<String, dynamic>.from(raw);

                return Chip(
                  avatar: const Icon(Icons.access_time, size: 18),
                  label: Text(
                    '${c['tipo_label'] ?? c['tipo']}: ${c['hora'] ?? '-'}',
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tiempoExtra['tiempo_extra_pagable'] == true
                    ? Colors.green.shade50
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: tiempoExtra['tiempo_extra_pagable'] == true
                      ? Colors.green.shade300
                      : Colors.black12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tiempo extra: ${tiempoExtra['tiempo_extra'] ?? '00:00:00'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: tiempoExtra['tiempo_extra_pagable'] == true
                          ? Colors.green.shade800
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tiempoExtra['mensaje']?.toString() ??
                        'Solo se paga si pasa de 30 minutos.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Siguiente: ${data['siguiente_label'] ?? 'Completo'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _limpiarAhora,
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Limpiar'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Esta información se limpiará automáticamente en 1 minuto.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 15),
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

  Widget _contenido() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmall = constraints.maxWidth < 980;

        if (isSmall) {
          return Column(
            children: [
              _panelIzquierdo(),
              const SizedBox(height: 18),
              _panelDerecho(),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: _panelIzquierdo(),
            ),
            const SizedBox(width: 18),
            Expanded(
              flex: 5,
              child: _panelDerecho(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6f8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _contenido(),
        ),
      ),
    );
  }
}