import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

class AsistenciasService {
  final Future<String?> Function() getToken;

  AsistenciasService({
    required this.getToken,
  });

  static const Duration _timeout = Duration(seconds: 12);

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

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    String message = 'Error ${res.statusCode}';

    if (body is Map && body['detail'] != null) {
      message = body['detail'].toString();
    }

    throw Exception(message);
  }

  String _date(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> getHoraMexico() async {
    final res = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/checador/hora'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<Map<String, dynamic>> getEstadoChecador({
    required int empleadoId,
  }) async {
    final res = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/checador/estado/$empleadoId'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<Map<String, dynamic>> checar({
    required int empleadoId,
  }) async {
    final res = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/checador/checar'),
          headers: await _headers(),
          body: jsonEncode({
            'empleado_id': empleadoId,
          }),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<Map<String, dynamic>> checarPorNomina({
    required String numeroNomina,
  }) async {
    final res = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/checador/checar-nomina'),
          headers: await _headers(),
          body: jsonEncode({
            'numero_nomina': numeroNomina,
          }),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<Map<String, dynamic>> getCastigos() async {
    final res = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/checador/castigos'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<Map<String, dynamic>> getTablero({
    required DateTime fecha,
    String departamento = 'MOLINOS',
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/asistencias/tablero').replace(
      queryParameters: {
        'fecha_jornada': _date(fecha),
        'departamento': departamento,
      },
    );

    final res = await http
        .get(
          uri,
          headers: await _headers(),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<Map<String, dynamic>> getMatriz({
    required int mes,
    required int anio,
    String departamento = 'MOLINOS',
  }) async {
    final uri = Uri.parse('${ApiService.baseUrl}/asistencias/matriz').replace(
      queryParameters: {
        'mes': mes.toString(),
        'anio': anio.toString(),
        'departamento': departamento,
      },
    );

    final res = await http
        .get(
          uri,
          headers: await _headers(),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }

  Future<List<dynamic>> getAcotaciones() async {
    final res = await http
        .get(
          Uri.parse('${ApiService.baseUrl}/asistencias/acotaciones'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    final data = _decode(res);

    if (data is List) {
      return data;
    }

    return [];
  }

  Future<Map<String, dynamic>> registrarAcotacion({
    required int empleadoId,
    required String clave,
    required DateTime fecha,
    String? observaciones,
  }) async {
    final res = await http
        .post(
          Uri.parse('${ApiService.baseUrl}/asistencias/acotacion'),
          headers: await _headers(),
          body: jsonEncode({
            'empleado_id': empleadoId,
            'clave': clave,
            'fecha': _date(fecha),
            'observaciones': observaciones,
          }),
        )
        .timeout(_timeout);

    return Map<String, dynamic>.from(_decode(res));
  }
}
