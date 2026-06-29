import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class AuthService extends ChangeNotifier {
  bool loading = true;
  String? token;
  Map<String, dynamic>? user;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  bool get canEdit =>
      user?['tipo'] == 'administrador' || user?['tipo'] == 'supervisor';

  Future<String?> getToken() async {
    if (token != null && token!.isNotEmpty) {
      return token;
    }

    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    return token;
  }

  Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();

    token = prefs.getString('token');

    final userText = prefs.getString('user');
    if (userText != null && userText.isNotEmpty) {
      user = Map<String, dynamic>.from(jsonDecode(userText));
    }

    loading = false;
    notifyListeners();
  }

  Future<void> login(String usuario, String password) async {
    final res = await http.post(
      Uri.parse('${ApiService.baseUrl}/auth/login'),
      headers: ApiService.headers(),
      body: jsonEncode({
        'usuario': usuario,
        'password': password,
      }),
    );

    final data = ApiService.decode(res);

    token = data['access_token']?.toString();
    user = Map<String, dynamic>.from(data['user']);

    final prefs = await SharedPreferences.getInstance();

    if (token != null) {
      await prefs.setString('token', token!);
    }

    await prefs.setString('user', jsonEncode(user));

    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    notifyListeners();
  }
}