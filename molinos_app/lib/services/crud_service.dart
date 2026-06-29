import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class CrudService {
  final String token;
  CrudService(this.token);

  Future<List<dynamic>> get(String path) async {
    final res = await http.get(Uri.parse('${ApiService.baseUrl}$path'), headers: ApiService.headers(token: token));
    return List<dynamic>.from(ApiService.decode(res));
  }

  Future<void> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(Uri.parse('${ApiService.baseUrl}$path'), headers: ApiService.headers(token: token), body: jsonEncode(body));
    ApiService.decode(res);
  }

  Future<void> put(String path, Map<String, dynamic> body) async {
    final res = await http.put(Uri.parse('${ApiService.baseUrl}$path'), headers: ApiService.headers(token: token), body: jsonEncode(body));
    ApiService.decode(res);
  }

  Future<void> delete(String path) async {
    final res = await http.delete(Uri.parse('${ApiService.baseUrl}$path'), headers: ApiService.headers(token: token));
    ApiService.decode(res);
  }
}
