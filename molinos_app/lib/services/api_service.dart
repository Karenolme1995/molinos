import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String serverUrl = 'http://127.0.0.1:8000';
  static const String baseUrl = '$serverUrl/api/v1';

  static Map<String, String> headers({String? token}) => {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  static dynamic decode(http.Response res) {
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }

    throw Exception(
      body is Map ? (body['detail'] ?? body.toString()) : 'Error ${res.statusCode}',
    );
  }

  static String fileUrl(dynamic file) {
    if (file == null || file.toString().trim().isEmpty) return '';

    final text = file.toString().trim();

    if (text.startsWith('http://') || text.startsWith('https://')) {
      return text;
    }

    if (text.startsWith('/uploads/')) {
      return '$serverUrl$text';
    }

    if (text.startsWith('uploads/')) {
      return '$serverUrl/$text';
    }

    return '$serverUrl/$text';
  }
}