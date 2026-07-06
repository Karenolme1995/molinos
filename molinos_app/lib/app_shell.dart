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

  static const Color primaryColor = Color(0xFF1E3A5F);
  static const Color secondaryColor = Color(0xFF2563EB);
  static const Color railBackground = Color(0xFFF8FAFC);
  static const Color pageBackground = Color(0xFFF1F5F9);
  static const Color selectedBackground = Color(0xFFE0ECFF);
  static const Color selectedIconColor = Color(0xFF1D4ED8);
  static const Color unselectedIconColor = Color(0xFF64748B);

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
        icon: Icon(Icons.precision_manufacturing_outlined),
        selectedIcon: Icon(Icons.precision_manufacturing),
        label: Text('Molinos'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.manage_accounts_outlined),
        selectedIcon: Icon(Icons.manage_accounts),
        label: Text('Usuarios'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.badge_outlined),
        selectedIcon: Icon(Icons.badge),
        label: Text('Empleados'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.assignment_outlined),
        selectedIcon: Icon(Icons.assignment),
        label: Text('Bitácoras'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.fact_check_outlined),
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
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
        centerTitle: false,
        title: const Text(
          'Sistema Molinos',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.22),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  '${auth.user?['nombre'] ?? ''} (${auth.user?['tipo'] ?? ''})',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Salir',
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red.withOpacity(0.18),
              hoverColor: Colors.red.withOpacity(0.28),
            ),
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
          const SizedBox(width: 10),
        ],
      ),
      body: Row(
        children: [
          Container(
            color: railBackground,
            child: NavigationRail(
              backgroundColor: railBackground,
              selectedIndex: _index,
              onDestinationSelected: (i) {
                setState(() {
                  _index = i;
                });
              },
              minWidth: 92,
              groupAlignment: -0.92,
              labelType: NavigationRailLabelType.all,
              useIndicator: true,
              indicatorColor: selectedBackground,
              selectedIconTheme: const IconThemeData(
                color: selectedIconColor,
                size: 28,
              ),
              unselectedIconTheme: const IconThemeData(
                color: unselectedIconColor,
                size: 25,
              ),
              selectedLabelTextStyle: const TextStyle(
                color: selectedIconColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: unselectedIconColor,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              destinations: destinations,
            ),
          ),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: Color(0xFFE2E8F0),
          ),
          Expanded(
            child: Container(
              color: pageBackground,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation);

                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: slideAnimation,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_index),
                  child: pages[_index],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}