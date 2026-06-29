import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/empleado_molinos.dart';
import '../models/maquina_molinos.dart';
import 'api_service.dart';

class TableroMolinos {
  final List<MaquinaMolinos> maquinas;
  final List<EmpleadoMolinos> espera;
  final List<EmpleadoMolinos> ausentes;
  final List<EmpleadoMolinos> alertas;

  TableroMolinos({required this.maquinas, required this.espera, required this.ausentes, required this.alertas});

  factory TableroMolinos.fromJson(Map<String, dynamic> json) {
    return TableroMolinos(
      maquinas: (json['maquinas'] as List? ?? []).map((e) => MaquinaMolinos.fromJson(Map<String, dynamic>.from(e))).toList(),
      espera: (json['espera'] as List? ?? []).map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e))).toList(),
      ausentes: (json['ausentes'] as List? ?? []).map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e))).toList(),
      alertas: (json['alertas'] as List? ?? []).map((e) => EmpleadoMolinos.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }
}

class MolinosService {
  final String token;
  MolinosService(this.token);

  Future<TableroMolinos> tablero(DateTime fecha) async {
    final f = '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
    final res = await http.get(
      Uri.parse('${ApiService.baseUrl}/molinos/tablero?fecha_jornada=$f'),
      headers: ApiService.headers(token: token),
    );
    return TableroMolinos.fromJson(Map<String, dynamic>.from(ApiService.decode(res)));
  }

  Future<void> asignar({required int empleadoId, required int maquinaId, required DateTime fecha}) async {
    final f = '${fecha.year.toString().padLeft(4, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/asignar'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({'empleado_id': empleadoId, 'maquina_id': maquinaId, 'fecha_jornada': f}),
    );
    ApiService.decode(res);
  }

  Future<void> cambiarEstado({required int maquinaId, required String estado}) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/molinos/maquina-estado'),
      headers: ApiService.headers(token: token),
      body: jsonEncode({'maquina_id': maquinaId, 'estado': estado}),
    );
    ApiService.decode(res);
  }
}
