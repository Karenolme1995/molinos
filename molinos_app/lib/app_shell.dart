import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/auth_service.dart';
import 'screens/molinos_screen.dart';
import 'screens/usuarios_screen.dart';
import 'screens/empleados_screen.dart';
import 'screens/login_screen.dart';
import 'screens/asistencias_screen.dart';
import 'screens/checador_screen.dart';
import 'screens/bitacoras_screen.dart';

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

    final pages = <Widget>[
      const MolinosScreen(),
      const UsuariosScreen(),
      const EmpleadosScreen(),
      BitacorasScreen(
        getToken: auth.getToken,
      ),
      AsistenciasScreen(
        getToken: auth.getToken,
      ),
      ChecadorScreen(
        getToken: auth.getToken,
      ),
    ];

    final destinations = const <NavigationRailDestination>[
      NavigationRailDestination(
        icon: Icon(Icons.precision_manufacturing),
        selectedIcon: Icon(Icons.precision_manufacturing),
        label: Text('Molinos'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.manage_accounts),
        selectedIcon: Icon(Icons.manage_accounts),
        label: Text('Usuarios'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.badge),
        selectedIcon: Icon(Icons.badge),
        label: Text('Empleados'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.assignment),
        selectedIcon: Icon(Icons.assignment),
        label: Text('Bitácoras'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.fact_check),
        selectedIcon: Icon(Icons.fact_check),
        label: Text('Asistencia'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.fingerprint),
        selectedIcon: Icon(Icons.fingerprint),
        label: Text('Checador'),
      ),
    ];

    if (_index >= pages.length) {
      _index = 0;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sistema Molinos'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                '${auth.user?['nombre'] ?? ''} (${auth.user?['tipo'] ?? ''})',
                overflow: TextOverflow.ellipsis,
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
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: pages,
            ),
          ),
        ],
      ),
    );
  }
}