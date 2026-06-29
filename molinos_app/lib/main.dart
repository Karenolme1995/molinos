import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'app_shell.dart';

void main() {
  runApp(const MolinosApp());
}

class MolinosApp extends StatelessWidget {
  const MolinosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthService()..loadSession(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Molinos',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          scaffoldBackgroundColor: const Color(0xfff4f6f9),
        ),
        home: Consumer<AuthService>(
          builder: (_, auth, __) {
            if (auth.loading) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return auth.isLoggedIn ? const AppShell() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
