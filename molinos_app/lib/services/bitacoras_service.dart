import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

class BitacorasService {
  final Future<String?> Function() getToken;

  BitacorasService({required this.getToken});

  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  dynamic _decode(http.Response res) {
    final decodedBody = utf8.decode(res.bodyBytes);
    final body = decodedBody.isNotEmpty ? jsonDecode(decodedBody) : null;
    if (res.statusCode >= 200 && res.statusCode < 300) return body;

    var message = 'Error ${res.statusCode}';
    if (body is Map && body['detail'] != null)
      message = body['detail'].toString();
    throw Exception(message);
  }

  Uri _uri(String path, [Map<String, String?>? query]) {
    return Uri.parse('${ApiService.baseUrl}/bitacoras$path').replace(
      queryParameters: query == null
          ? null
          : Map<String, String>.fromEntries(
              query.entries
                  .where((e) => e.value != null && e.value!.isNotEmpty)
                  .map(
                    (e) => MapEntry(e.key, e.value!),
                  ),
            ),
    );
  }

  Future<List<dynamic>> areas() async {
    final res = await http
        .get(_uri('/areas'), headers: await _headers())
        .timeout(_timeout);
    final data = Map<String, dynamic>.from(_decode(res));
    return List<dynamic>.from(data['areas'] ?? []);
  }

  Future<void> crearArea(String nombre) async {
    final res = await http
        .post(
          _uri('/areas'),
          headers: await _headers(),
          body: jsonEncode({'nombre': nombre}),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> editarArea(int id, String nombre) async {
    final res = await http
        .put(
          _uri('/areas/$id'),
          headers: await _headers(),
          body: jsonEncode({'nombre': nombre}),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> eliminarArea(int id) async {
    final res = await http
        .delete(_uri('/areas/$id'), headers: await _headers())
        .timeout(_timeout);
    _decode(res);
  }

  Future<List<dynamic>> maquinas({int? areaId}) async {
    final res = await http
        .get(
          _uri('/maquinas', {'area_id': areaId?.toString()}),
          headers: await _headers(),
        )
        .timeout(_timeout);
    final data = Map<String, dynamic>.from(_decode(res));
    return List<dynamic>.from(data['maquinas'] ?? []);
  }

  Future<void> crearMaquina({
    required String nombre,
    String? descripcion,
    required int areaId,
  }) async {
    final res = await http
        .post(
          _uri('/maquinas'),
          headers: await _headers(),
          body: jsonEncode({
            'nombre': nombre,
            'descripcion': descripcion,
            'id_area': areaId,
            'activo': 1,
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> editarMaquina({
    required int id,
    required String nombre,
    String? descripcion,
    required int areaId,
    int activo = 1,
  }) async {
    final res = await http
        .put(
          _uri('/maquinas/$id'),
          headers: await _headers(),
          body: jsonEncode({
            'nombre': nombre,
            'descripcion': descripcion,
            'id_area': areaId,
            'activo': activo,
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> eliminarMaquina(int id) async {
    final res = await http
        .delete(_uri('/maquinas/$id'), headers: await _headers())
        .timeout(_timeout);
    _decode(res);
  }

  Future<List<dynamic>> mantenimientos({int? areaId}) async {
    final res = await http
        .get(
          _uri('/mantenimientos', {'area_id': areaId?.toString()}),
          headers: await _headers(),
        )
        .timeout(_timeout);
    final data = Map<String, dynamic>.from(_decode(res));
    return List<dynamic>.from(data['mantenimientos'] ?? []);
  }

  Future<void> crearMantenimiento({
    required String tipoMant,
    required String tiempoMant,
    required int areaId,
  }) async {
    final res = await http
        .post(
          _uri('/mantenimientos'),
          headers: await _headers(),
          body: jsonEncode({
            'tipo_mant': tipoMant,
            'tiempo_mant': tiempoMant,
            'id_area': areaId,
            'activo': '1',
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> editarMantenimiento({
    required int id,
    required String tipoMant,
    required String tiempoMant,
    required int areaId,
  }) async {
    final res = await http
        .put(
          _uri('/mantenimientos/$id'),
          headers: await _headers(),
          body: jsonEncode({
            'tipo_mant': tipoMant,
            'tiempo_mant': tiempoMant,
            'id_area': areaId,
            'activo': '1',
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> eliminarMantenimiento(int id) async {
    final res = await http
        .delete(_uri('/mantenimientos/$id'), headers: await _headers())
        .timeout(_timeout);
    _decode(res);
  }

  Future<Map<String, dynamic>> bitacoras({
    int? areaId,
    String maquina = '',
    String status = 'TODOS',
  }) async {
    final res = await http
        .get(
          _uri('/bitacoras', {
            'area_id': areaId?.toString(),
            'maquina': maquina,
            'status': status,
          }),
          headers: await _headers(),
        )
        .timeout(_timeout);
    return Map<String, dynamic>.from(_decode(res));
  }

  Future<void> crearBitacora({
    required int areaId,
    int? maquinaId,
    String? maquina,
    int? mantenimientoId,
    String? mantenimiento,
    String? operador,
    String? descripcionPreven,
    String statusManto = 'EN ESPERA',
  }) async {
    final res = await http
        .post(
          _uri('/bitacoras'),
          headers: await _headers(),
          body: jsonEncode({
            'area_id': areaId,
            'maquina_id': maquinaId,
            'maquina': maquina,
            'mantenimiento_id': mantenimientoId,
            'mantenimiento': mantenimiento,
            'operador': operador,
            'descripcionPreven': descripcionPreven,
            'status_manto': statusManto,
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> cerrarBitacora({
    required int id,
    String? supervisor2,
    String? descripcionCorrec,
    String statusManto = 'CERRADO',
  }) async {
    final res = await http
        .post(
          _uri('/bitacoras/$id/cerrar'),
          headers: await _headers(),
          body: jsonEncode({
            'Supervisor2': supervisor2,
            'descripcionCorrec': descripcionCorrec,
            'status_manto': statusManto,
            'cerrar': true,
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }

  Future<void> editarBitacora({
    required int id,
    int? maquinaId,
    int? mantenimientoId,
    String? operador,
    String? descripcionPreven,
    String? supervisor2,
    String? descripcionCorrec,
    String? statusManto,
    bool cerrar = false,
  }) async {
    final res = await http
        .put(
          _uri('/bitacoras/$id'),
          headers: await _headers(),
          body: jsonEncode({
            'maquina_id': maquinaId,
            'mantenimiento_id': mantenimientoId,
            'operador': operador,
            'descripcionPreven': descripcionPreven,
            'Supervisor2': supervisor2,
            'descripcionCorrec': descripcionCorrec,
            'status_manto': statusManto,
            'cerrar': cerrar,
          }),
        )
        .timeout(_timeout);
    _decode(res);
  }
}
