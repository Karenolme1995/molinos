import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/crud_service.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  bool loading = true;
  List<dynamic> rows = [];

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => load()); }

  Future<void> load() async {
    final token = context.read<AuthService>().token!;
    setState(() => loading = true);
    rows = await CrudService(token).get('/usuarios');
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(color: Colors.white, padding: const EdgeInsets.all(12), child: Row(children: [
        const Text('Usuarios', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Spacer(), IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      ])),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final u = rows[i];
          return ListTile(
            leading: const Icon(Icons.manage_accounts),
            title: Text(u['nombre'] ?? ''),
            subtitle: Text('${u['usuario']} · ${u['tipo']} · ${u['area'] ?? ''}'),
            trailing: u['activo'] == 1 ? const Text('Activo') : const Text('Inactivo'),
          );
        },
      )),
    ]);
  }
}
