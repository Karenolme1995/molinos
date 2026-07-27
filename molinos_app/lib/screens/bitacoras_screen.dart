import 'package:flutter/material.dart';

import '../services/bitacoras_service.dart';

class BitacorasScreen extends StatefulWidget {
  final Future<String?> Function() getToken;

  const BitacorasScreen({
    super.key,
    required this.getToken,
  });

  @override
  State<BitacorasScreen> createState() => _BitacorasScreenState();
}
// --- IGNORE ---          
class _BitacorasScreenState extends State<BitacorasScreen> {
  late final BitacorasService _service;

  bool _loading = true;
  String? _error;
  int? _areaId;
  String _status = 'TODOS';
  int _pagina = 0;
  int _filasPorPagina = 10;

  List<dynamic> _areas = [];
  List<dynamic> _maquinas = [];
  List<dynamic> _mantenimientos = [];
  List<dynamic> _bitacoras = [];
  List<dynamic> _alertasProximas = [];
  List<dynamic> _alertasHoy = [];
  Map<String, dynamic> _conteos = {};
// --- IGNORE ---
  final TextEditingController _buscarMaquinaCtrl = TextEditingController();
  final ScrollController _tablaHorizontalCtrl = ScrollController();
  final ScrollController _tablaVerticalCtrl = ScrollController();
// --- IGNORE ---
  static const _statusItems = [
    _StatusItem('TODOS', 'Todos', Icons.list_alt, Colors.blueGrey),
    _StatusItem('a_tiempo', 'A tiempo', Icons.circle, Colors.green),
    _StatusItem('6_10', '6 a 10 días', Icons.circle, Colors.deepOrange),
    _StatusItem('1_5', '1 a 5 días', Icons.circle, Colors.red),
    _StatusItem('hoy', 'Hoy', Icons.warning_amber, Colors.orange),
    _StatusItem('vencido', 'Vencido', Icons.remove_circle, Colors.pink),
    _StatusItem(
        'en_espera', 'En espera', Icons.hourglass_empty, Colors.blueGrey),
    _StatusItem('cerrado', 'Cerrado', Icons.check_box, Colors.green),
  ];

  @override
  void initState() {
    super.initState();
    _service = BitacorasService(getToken: widget.getToken);
    _cargarInicial();
  }

  @override
  void dispose() {
    _buscarMaquinaCtrl.dispose();
    _tablaHorizontalCtrl.dispose();
    _tablaVerticalCtrl.dispose();
    super.dispose();
  }
// --- IGNORE ---
  Future<void> _cargarInicial() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final areas = await _service.areas();
      final firstArea = areas.isNotEmpty ? _asInt(areas.first['id']) : null;
      _areaId ??= firstArea;

      if (!mounted) return;
      setState(() => _areas = areas);

      await _cargarArea();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
// --- IGNORE ---
  Future<void> _cargarArea() async {
    if (_areaId == null) {
      setState(() {
        _maquinas = [];
        _mantenimientos = [];
        _bitacoras = [];
        _alertasProximas = [];
        _alertasHoy = [];
        _conteos = {};
      });
      return;
    }

    try {
      final result = await Future.wait([
        _service.maquinas(areaId: _areaId),
        _service.mantenimientos(areaId: _areaId),
        _service.bitacoras(
          areaId: _areaId,
          maquina: _buscarMaquinaCtrl.text.trim(),
          status: _status,
        ),
      ]);

      final bitData = Map<String, dynamic>.from(result[2] as Map);

      if (!mounted) return;
      setState(() {
        _maquinas = List<dynamic>.from(result[0] as List);
        _mantenimientos = List<dynamic>.from(result[1] as List);
        _bitacoras = List<dynamic>.from(bitData['bitacoras'] ?? []);
        _alertasProximas =
            List<dynamic>.from(bitData['alertas_proximas'] ?? []);
        _alertasHoy = List<dynamic>.from(bitData['alertas_hoy'] ?? []);
        _conteos = Map<String, dynamic>.from(bitData['conteos'] ?? {});
        _pagina = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }
// --- IGNORE ---
  Future<void> _recargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _cargarArea();
    if (mounted) setState(() => _loading = false);
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _text(dynamic value) => value?.toString() ?? '';

  String _fechaDMY(dynamic value) {
    final raw = _text(value).trim();
    if (raw.isEmpty || raw == 'null') return '-';
    final fecha = raw.length >= 10 ? raw.substring(0, 10) : raw;
    final parts = fecha.split('-');
    if (parts.length == 3) {
      return '${parts[2].padLeft(2, '0')}/${parts[1].padLeft(2, '0')}/${parts[0]}';
    }
    return raw;
  }

  String _hora(dynamic value) {
    final raw = _text(value).trim();
    if (raw.isEmpty || raw == 'null') return '-';
    return raw.length >= 5 ? raw.substring(0, 5) : raw;
  }

  int _diasInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _diasMantenimiento(dynamic value) {
    final dias = _diasInt(value);
    if (dias <= 0) return '-';
    return '$dias días';
  }

  List<dynamic> get _bitacorasPagina {
    final inicio = _pagina * _filasPorPagina;
    if (inicio >= _bitacoras.length) return const [];
    final fin = (inicio + _filasPorPagina).clamp(0, _bitacoras.length);
    return _bitacoras.sublist(inicio, fin);
  }

  int get _totalPaginas {
    if (_bitacoras.isEmpty) return 1;
    return ((_bitacoras.length - 1) ~/ _filasPorPagina) + 1;
  }

  String _rangoPaginaTexto() {
    if (_bitacoras.isEmpty) return '0 de 0';
    final inicio = (_pagina * _filasPorPagina) + 1;
    final fin = ((_pagina + 1) * _filasPorPagina).clamp(0, _bitacoras.length);
    return '$inicio-$fin de ${_bitacoras.length}';
  }

  String _tiempoMuerto(Map<String, dynamic> b) {
    final minutosRaw = b['tiempo_muerto_minutos'];
    final minutos = _diasInt(minutosRaw);
    if (minutos > 0) return '$minutos min';

    final actual = _text(b['tiempo_muerto_actual']);
    final guardado = _text(b['tiempo_muerto']);
    final valor = actual.isNotEmpty ? actual : guardado;
    if (valor.isEmpty || valor == 'null' || valor == '-') return '-';

    final partes = valor.split(':');
    if (partes.length >= 2) {
      final h = int.tryParse(partes[0]) ?? 0;
      final m = int.tryParse(partes[1]) ?? 0;
      final total = h * 60 + m;
      if (total > 0) return '$total min';
    }

    return valor;
  }

  String _statusTexto(String status) {
    final item = _statusItems.firstWhere(
      (e) => e.id == status,
      orElse: () => const _StatusItem(
          'en_espera', 'En espera', Icons.hourglass_empty, Colors.blueGrey),
    );
    return item.label;
  }

  String _mensajeAlerta(Map<String, dynamic> b) {
    final diasRestantes = _text(b['dias_restantes']);
    final maquina = _text(b['maquina']);
    final mantenimiento = _text(b['mantenimiento']);
    final proxima = _fechaDMY(b['fecha_proxima']);
    if (diasRestantes == '0') {
      return '$maquina - $mantenimiento vence hoy ($proxima)';
    }
    return '$maquina - $mantenimiento faltan $diasRestantes días ($proxima)';
  }

  String _areaNombreActual() {
    for (final raw in _areas) {
      final a = Map<String, dynamic>.from(raw as Map);
      if (_asInt(a['id']) == _areaId) return _text(a['nombre']);
    }
    return '';
  }
// --- IGNORE ---
  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _ok(String msg) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6f9),
      body: Column(
        children: [
          _header(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _errorView()
                    : _content(),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 800 || size.width < 760;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        elevation: 1,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 22,
            compact ? 8 : 14,
            compact ? 12 : 22,
            compact ? 5 : 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bitácoras',
                style: TextStyle(
                  fontSize: compact ? 21 : 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 2),
                Text(
                  'Consulta por departamento, máquina, fallas y mantenimientos',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              SizedBox(height: compact ? 6 : 14),
              Wrap(
                spacing: compact ? 6 : 10,
                runSpacing: compact ? 5 : 10,
                children: [
                  FilledButton.icon(
                    onPressed: _mostrarDialogBitacora,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Nueva bitácora'),
                  ),
                  FilledButton.icon(
                    onPressed: _mostrarDialogMantenimientos,
                    icon: const Icon(Icons.build),
                    label: const Text('+ Mantenimiento'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700),
                  ),
                  OutlinedButton.icon(
                    onPressed: _mostrarDialogMaquinas,
                    icon: const Icon(Icons.precision_manufacturing),
                    label: const Text('Máquinas'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _mostrarDialogAreas,
                    icon: const Icon(Icons.add_business),
                    label: const Text('Áreas'),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _recargar,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 14),
              _areasTabs(),
              SizedBox(height: compact ? 4 : 10),
              _statusChips(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _areasTabs() {
    if (_areas.isEmpty) {
      return Row(
        children: [
          const Text('No hay áreas registradas'),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _mostrarDialogAreas,
            icon: const Icon(Icons.add),
            label: const Text('Agregar área'),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _areas.map((raw) {
            final area = Map<String, dynamic>.from(raw as Map);
            final id = _asInt(area['id']);
            final selected = id == _areaId;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_text(area['nombre'])),
                selected: selected,
                onSelected: (_) async {
                  setState(() {
                    _areaId = id;
                    _status = 'TODOS';
                    _pagina = 0;
                  });
                  await _recargar();
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _statusChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _statusItems.map((item) {
          final selected = _status == item.id;
          final count =
              item.id == 'TODOS' ? _bitacoras.length : (_conteos[item.id] ?? 0);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: selected,
              avatar: Icon(item.icon, size: 18, color: item.color),
              label:
                  Text('${item.label}${item.id == 'TODOS' ? '' : ' ($count)'}'),
              onSelected: (_) async {
                setState(() {
                  _status = item.id;
                  _pagina = 0;
                });
                await _recargar();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error ?? 'Error'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _recargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 520;

        return Padding(
          padding: EdgeInsets.all(compactHeight ? 8 : 18),
          child: Column(
            children: [
              // En ventanas con poca altura ocultamos las alertas para que
              // la tabla conserve suficiente espacio y muestre más filas.
              if (!compactHeight) ...[
                _alertasCard(),
                const SizedBox(height: 12),
              ],
              _filtros(),
              SizedBox(height: compactHeight ? 6 : 14),
              Expanded(child: _tablaBitacoras()),
            ],
          ),
        );
      },
    );
  }

  Widget _alertasCard() {
    final total = _alertasProximas.length + _alertasHoy.length;
    if (total == 0) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Alertas de mantenimiento: no hay mantenimientos venciendo hoy ni dentro de 1 a 5 días.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active, color: Colors.orange.shade800),
                const SizedBox(width: 10),
                Text(
                  'Alertas de mantenimiento ($total)',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Chip(
                  avatar: const Icon(Icons.warning_amber, size: 18),
                  label: Text('Hoy: ${_alertasHoy.length}'),
                  backgroundColor: Colors.orange.shade50,
                ),
                const SizedBox(width: 8),
                Chip(
                  avatar: const Icon(Icons.circle, size: 14),
                  label: Text('1 a 5 días: ${_alertasProximas.length}'),
                  backgroundColor: Colors.red.shade50,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                ..._alertasHoy.take(8).map((raw) {
                  final b = Map<String, dynamic>.from(raw as Map);
                  return _alertaItem(b, Colors.orange, Icons.warning_amber);
                }),
                ..._alertasProximas.take(8).map((raw) {
                  final b = Map<String, dynamic>.from(raw as Map);
                  return _alertaItem(b, Colors.red, Icons.notifications);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertaItem(
      Map<String, dynamic> b, MaterialColor color, IconData icon) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color.shade700, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _mensajeAlerta(b),
              style:
                  TextStyle(color: color.shade900, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;

        final buscador = TextField(
          controller: _buscarMaquinaCtrl,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar por máquina',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) {
            setState(() => _pagina = 0);
            _recargar();
          },
        );

        final boton = FilledButton(
          onPressed: () {
            setState(() => _pagina = 0);
            _recargar();
          },
          child: const Text('Filtrar'),
        );

        final resumen = Wrap(
          spacing: 20,
          runSpacing: 6,
          children: [
            Text('Área: ${_areaNombreActual()}'),
            Text(
              'Total: ${_bitacoras.length}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buscador,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: boton),
              const SizedBox(height: 10),
              resumen,
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: 330, child: buscador),
            const SizedBox(width: 12),
            boton,
            const Spacer(),
            resumen,
          ],
        );
      },
    );
  }

  Widget _tablaBitacoras() {
    if (_bitacoras.isEmpty) {
      return const Center(
          child: Text('No hay bitácoras con los filtros seleccionados.'));
    }

    if (_pagina >= _totalPaginas) {
      _pagina = _totalPaginas - 1;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _tablaVerticalCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _tablaVerticalCtrl,
                child: Scrollbar(
                  controller: _tablaHorizontalCtrl,
                  thumbVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.depth == 1,
                  child: SingleChildScrollView(
                    controller: _tablaHorizontalCtrl,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      // La tabla conserva un ancho cómodo y se desplaza
                      // horizontalmente en pantallas pequeñas.
                      constraints: const BoxConstraints(minWidth: 1450),
                      child: DataTable(
                          columnSpacing: 24,
                          horizontalMargin: 18,
                          headingRowColor:
                              MaterialStateProperty.all(Colors.blue.shade800),
                      headingTextStyle: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                      columns: const [
                        DataColumn(label: Text('MÁQUINA')),
                        DataColumn(label: Text('MANTENIMIENTO / FALLA')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('DÍAS')),
                        DataColumn(label: Text('FECHA INICIO')),
                        DataColumn(label: Text('HORA INICIO')),
                        DataColumn(label: Text('FECHA FIN')),
                        DataColumn(label: Text('HORA FIN')),
                        DataColumn(label: Text('TIEMPO MUERTO')),
                        DataColumn(label: Text('PRÓXIMA')),
                        DataColumn(label: Text('STATUS MANTTO')),
                        DataColumn(label: Text('ACCIONES')),
                      ],
                      rows: _bitacorasPagina.map((raw) {
                        final b = Map<String, dynamic>.from(raw as Map);
                        final semaforo = _text(b['semaforo']);
                        return DataRow(
                          cells: [
                            DataCell(_cellTitle(
                                _text(b['maquina']), _text(b['area']))),
                            DataCell(SizedBox(
                                width: 230,
                                child: Text(_text(b['mantenimiento'])))),
                            DataCell(_statusIcon(semaforo)),
                            DataCell(_diasChip(semaforo, b['Dias'])),
                            DataCell(Text(_fechaDMY(b['fecha_inicio']))),
                            DataCell(Text(_hora(b['hora_inicio']))),
                            DataCell(Text(_fechaDMY(b['fecha_termino']))),
                            DataCell(Text(_hora(b['Hora_termino']))),
                            DataCell(Text(_tiempoMuerto(b))),
                            DataCell(Text(_fechaDMY(b['fecha_proxima']))),
                            DataCell(Text(_text(b['status_manto']).isEmpty
                                ? '-'
                                : _text(b['status_manto']))),
                            DataCell(
                              IconButton(
                                tooltip: 'Editar / cerrar',
                                onPressed: () =>
                                    _mostrarDialogEditarBitacora(b),
                                icon: const Icon(Icons.settings),
                              ),
                            ),
                          ],
                        );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _paginacion(),
        ],
      ),
    );
  }

  Widget _paginacion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Filas por página:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _filasPorPagina,
                items: const [10, 20, 30, 50].map((v) {
                  return DropdownMenuItem(value: v, child: Text('$v'));
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _filasPorPagina = v;
                    _pagina = 0;
                  });
                },
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _rangoPaginaTexto(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Primera página',
                onPressed:
                    _pagina == 0 ? null : () => setState(() => _pagina = 0),
                icon: const Icon(Icons.first_page),
              ),
              IconButton(
                tooltip: 'Anterior',
                onPressed:
                    _pagina == 0 ? null : () => setState(() => _pagina--),
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Página ${_pagina + 1} de $_totalPaginas'),
              IconButton(
                tooltip: 'Siguiente',
                onPressed: _pagina >= _totalPaginas - 1
                    ? null
                    : () => setState(() => _pagina++),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: 'Última página',
                onPressed: _pagina >= _totalPaginas - 1
                    ? null
                    : () => setState(() => _pagina = _totalPaginas - 1),
                icon: const Icon(Icons.last_page),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cellTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (subtitle.isNotEmpty)
          Text(subtitle,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
      ],
    );
  }

  Widget _statusIcon(String status) {
    final item = _statusItems.firstWhere(
      (e) => e.id == status,
      orElse: () => const _StatusItem(
          'en_espera', 'En espera', Icons.hourglass_empty, Colors.blueGrey),
    );
    return Tooltip(
      message: item.label,
      child: Icon(item.icon, color: item.color),
    );
  }

  Widget _diasChip(String status, dynamic dias) {
    final item = _statusItems.firstWhere(
      (e) => e.id == status,
      orElse: () => const _StatusItem(
          'en_espera', 'En espera', Icons.hourglass_empty, Colors.blueGrey),
    );
    final label = status == 'cerrado' ? 'Cerrado' : _diasMantenimiento(dias);
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: item.color.withOpacity(0.14),
      labelStyle: TextStyle(color: item.color, fontWeight: FontWeight.bold),
    );
  }

  Future<void> _mostrarDialogAreas() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Áreas'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        decoration:
                            const InputDecoration(labelText: 'Nueva área'),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        try {
                          await _service.crearArea(ctrl.text.trim());
                          ctrl.clear();
                          final areas = await _service.areas();
                          setLocal(() => _areas = areas);
                          if (mounted) setState(() => _areas = areas);
                        } catch (e) {
                          _showError(e);
                        }
                      },
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _areas.length,
                    itemBuilder: (_, i) {
                      final a = Map<String, dynamic>.from(_areas[i] as Map);
                      return ListTile(
                        title: Text(_text(a['nombre'])),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _mostrarEditarTexto(
                            title: 'Editar área',
                            initial: _text(a['nombre']),
                            onSave: (v) async {
                              await _service.editarArea(_asInt(a['id'])!, v);
                              await _cargarInicial();
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'))
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogMaquinas() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Máquinas - ${_areaNombreActual()}'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _mostrarAgregarMaquina(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar máquina'),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _maquinas.length,
                  itemBuilder: (_, i) {
                    final m = Map<String, dynamic>.from(_maquinas[i] as Map);
                    return ListTile(
                      leading: const Icon(Icons.precision_manufacturing),
                      title: Text(_text(m['nombre'])),
                      subtitle: Text(_text(m['descripcion'])),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'))
        ],
      ),
    );
  }

  Future<void> _mostrarDialogMantenimientos() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Mantenimientos - ${_areaNombreActual()}'),
        content: SizedBox(
          width: 580,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _mostrarAgregarMantenimiento(),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar mantenimiento'),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _mantenimientos.length,
                  itemBuilder: (_, i) {
                    final m =
                        Map<String, dynamic>.from(_mantenimientos[i] as Map);
                    return ListTile(
                      leading: const Icon(Icons.build),
                      title: Text(_text(m['tipo_mant'])),
                      subtitle: Text('Tiempo: ${_text(m['tiempo_mant'])}'),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () =>
                                _mostrarAgregarMantenimiento(edit: m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              try {
                                await _service
                                    .eliminarMantenimiento(_asInt(m['id'])!);
                                await _recargar();
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                _showError(e);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'))
        ],
      ),
    );
  }

  Future<void> _mostrarAgregarMaquina() async {
    final nombreCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Agregar máquina'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Máquina')),
            TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              try {
                await _service.crearMaquina(
                    nombre: nombreCtrl.text.trim(),
                    descripcion: descCtrl.text.trim(),
                    areaId: _areaId!);
                if (mounted) Navigator.pop(context);
                await _recargar();
              } catch (e) {
                _showError(e);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarAgregarMantenimiento(
      {Map<String, dynamic>? edit}) async {
    final tipoCtrl = TextEditingController(text: _text(edit?['tipo_mant']));
    final tiempoCtrl = TextEditingController(text: _text(edit?['tiempo_mant']));
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
            edit == null ? 'Agregar mantenimiento' : 'Editar mantenimiento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: tipoCtrl,
                decoration:
                    const InputDecoration(labelText: 'Tipo de mantenimiento')),
            TextField(
                controller: tiempoCtrl,
                decoration: const InputDecoration(labelText: 'Tiempo / días')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              try {
                if (edit == null) {
                  await _service.crearMantenimiento(
                      tipoMant: tipoCtrl.text.trim(),
                      tiempoMant: tiempoCtrl.text.trim(),
                      areaId: _areaId!);
                } else {
                  await _service.editarMantenimiento(
                      id: _asInt(edit['id'])!,
                      tipoMant: tipoCtrl.text.trim(),
                      tiempoMant: tiempoCtrl.text.trim(),
                      areaId: _areaId!);
                }
                if (mounted) Navigator.pop(context);
                await _recargar();
              } catch (e) {
                _showError(e);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogBitacora() async {
    if (_areaId == null) {
      _showError('Primero agrega un área');
      return;
    }

    int? maquinaId =
        _maquinas.isNotEmpty ? _asInt(_maquinas.first['id']) : null;
    int? mantenimientoId =
        _mantenimientos.isNotEmpty ? _asInt(_mantenimientos.first['id']) : null;
    final operadorCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nueva bitácora'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: maquinaId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Máquina'),
                        selectedItemBuilder: (context) => _maquinas.map((raw) {
                          final m = Map<String, dynamic>.from(raw as Map);
                          return Text(_text(m['nombre']),
                              overflow: TextOverflow.ellipsis, maxLines: 1);
                        }).toList(),
                        items: _maquinas.map((raw) {
                          final m = Map<String, dynamic>.from(raw as Map);
                          return DropdownMenuItem(
                            value: _asInt(m['id']),
                            child: Text(_text(m['nombre']),
                                overflow: TextOverflow.ellipsis, maxLines: 1),
                          );
                        }).toList(),
                        onChanged: (v) => setLocal(() => maquinaId = v),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Agregar máquina',
                      onPressed: () async {
                        await _mostrarAgregarMaquina();
                        setLocal(() {
                          maquinaId = _maquinas.isNotEmpty
                              ? _asInt(_maquinas.last['id'])
                              : maquinaId;
                        });
                      },
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: mantenimientoId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Mantenimiento / falla'),
                        selectedItemBuilder: (context) =>
                            _mantenimientos.map((raw) {
                          final m = Map<String, dynamic>.from(raw as Map);
                          return Text(
                            '${_text(m['tipo_mant'])} (${_text(m['tiempo_mant'])})',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          );
                        }).toList(),
                        items: _mantenimientos.map((raw) {
                          final m = Map<String, dynamic>.from(raw as Map);
                          return DropdownMenuItem(
                            value: _asInt(m['id']),
                            child: Text(
                              '${_text(m['tipo_mant'])} (${_text(m['tiempo_mant'])})',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setLocal(() => mantenimientoId = v),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Agregar mantenimiento',
                      onPressed: () async {
                        await _mostrarAgregarMantenimiento();
                        setLocal(() {
                          mantenimientoId = _mantenimientos.isNotEmpty
                              ? _asInt(_mantenimientos.last['id'])
                              : mantenimientoId;
                        });
                      },
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
                TextField(
                    controller: operadorCtrl,
                    decoration: const InputDecoration(labelText: 'Operador')),
                TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Descripción preventiva')),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Fecha inicio y hora inicio se guardan en automático.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await _service.crearBitacora(
                    areaId: _areaId!,
                    maquinaId: maquinaId,
                    mantenimientoId: mantenimientoId,
                    operador: operadorCtrl.text.trim(),
                    descripcionPreven: descCtrl.text.trim(),
                  );
                  if (mounted) Navigator.pop(context);
                  await _recargar();
                  await _ok('Bitácora creada');
                } catch (e) {
                  _showError(e);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarDialogEditarBitacora(Map<String, dynamic> b) async {
    final supervisor2Ctrl =
        TextEditingController(text: _text(b['Supervisor2']));
    final descCorrecCtrl =
        TextEditingController(text: _text(b['descripcionCorrec']));
    // El Dropdown solo admite estos dos valores. Algunos registros pueden
    // venir como EN ESPERA, ABIERTO, TERMINADO, etc.; los normalizamos para
    // evitar el error: "There should be exactly one item with value...".
    final statusRaw = _text(b['status_manto']).trim().toUpperCase();
    var status = const {
      'CERRADO',
      'CERRADA',
      'TERMINO',
      'TERMINADO',
      'FINALIZADO',
    }.contains(statusRaw)
        ? 'CERRADO'
        : 'TRABAJANDO';
    var cerrar = status == 'CERRADO';

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Editar bitácora #${b['id']}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Máquina: ${_text(b['maquina'])}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                    'Inicio: ${_fechaDMY(b['fecha_inicio'])} ${_hora(b['hora_inicio'])}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration:
                      const InputDecoration(labelText: 'Status mantenimiento'),
                  items: const [
                    DropdownMenuItem(
                        value: 'TRABAJANDO', child: Text('Trabajando')),
                    DropdownMenuItem(value: 'CERRADO', child: Text('Cerrado')),
                  ],
                  onChanged: (v) => setLocal(() {
                    status = v ?? 'TRABAJANDO';
                    cerrar = status == 'CERRADO';
                  }),
                ),
                TextField(
                    controller: supervisor2Ctrl,
                    decoration:
                        const InputDecoration(labelText: 'Supervisor2')),
                TextField(
                    controller: descCorrecCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Descripción correctiva')),
                CheckboxListTile(
                  value: cerrar,
                  onChanged: (v) => setLocal(() {
                    cerrar = v ?? false;
                    status = cerrar ? 'CERRADO' : 'TRABAJANDO';
                  }),
                  title: const Text(
                      'Capturar fecha término y hora término automáticamente'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              onPressed: () async {
                try {
                  if (cerrar || status == 'CERRADO') {
                    await _service.cerrarBitacora(
                      id: _asInt(b['id'])!,
                      supervisor2: supervisor2Ctrl.text.trim(),
                      descripcionCorrec: descCorrecCtrl.text.trim(),
                      statusManto: 'CERRADO',
                    );
                  } else {
                    await _service.editarBitacora(
                      id: _asInt(b['id'])!,
                      supervisor2: supervisor2Ctrl.text.trim(),
                      descripcionCorrec: descCorrecCtrl.text.trim(),
                      statusManto: status,
                    );
                  }
                  if (mounted) Navigator.pop(context);
                  await _recargar();
                  await _ok('Bitácora actualizada');
                } catch (e) {
                  _showError(e);
                }
              },
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarEditarTexto({
    required String title,
    required String initial,
    required Future<void> Function(String value) onSave,
  }) async {
    final ctrl = TextEditingController(text: initial);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              try {
                await onSave(ctrl.text.trim());
                if (mounted) Navigator.pop(context);
              } catch (e) {
                _showError(e);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

class _StatusItem {
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  const _StatusItem(this.id, this.label, this.icon, this.color);
}

