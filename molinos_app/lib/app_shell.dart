import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'screens/molinos_screen.dart';
import 'screens/usuarios_screen.dart';
import 'screens/empleados_screen.dart';
import 'screens/login_screen.dart';
import 'screens/asistencias_screen.dart';
import 'screens/checador_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    final pages = [
      const MolinosScreen(),
      const UsuariosScreen(),
      const EmpleadosScreen(),
      AsistenciasScreen(
        getToken: auth.getToken,
      ),
      ChecadorScreen(
        getToken: auth.getToken,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sistema Molinos'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                '${auth.user?['nombre'] ?? ''} (${auth.user?['tipo'] ?? ''})',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Salir',
            onPressed: () async {
              await auth.logout();

              if (!context.mounted) return;

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                (_) => false,
              );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              setState(() {
                _index = i;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.precision_manufacturing),
                label: Text('Molinos'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.manage_accounts),
                label: Text('Usuarios'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.badge),
                label: Text('Empleados'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.fact_check),
                label: Text('Asistencia'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.fingerprint),
                label: Text('Checador'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: pages[_index],
          ),
        ],
      ),
    );
  }
}