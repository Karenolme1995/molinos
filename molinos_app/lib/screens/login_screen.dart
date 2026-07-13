import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../app_shell.dart';
import 'checador_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _usuario = TextEditingController();
  final TextEditingController _password = TextEditingController();

  bool _loading = false;
  bool _verPassword = false;
  bool _recordarUsuario = false;

  String? _error;

  late final AnimationController _bgController;
  late final AnimationController _cardController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  static const Color azul = Color(0xFF005BAC);
  static const Color azulOscuro = Color(0xFF003B73);
  static const Color amarillo = Color(0xFFFFC107);

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: Curves.easeOutCubic,
      ),
    );

    _cardController.forward();
    _cargarUsuarioRecordado();
  }

  Future<void> _cargarUsuarioRecordado() async {
    final prefs = await SharedPreferences.getInstance();
    final usuarioGuardado = prefs.getString('molinos_usuario_recordado');

    if (!mounted) return;

    if (usuarioGuardado != null && usuarioGuardado.trim().isNotEmpty) {
      setState(() {
        _usuario.text = usuarioGuardado;
        _recordarUsuario = true;
      });
    }
  }

  Future<void> _guardarUsuarioRecordado() async {
    final prefs = await SharedPreferences.getInstance();

    if (_recordarUsuario) {
      await prefs.setString(
        'molinos_usuario_recordado',
        _usuario.text.trim(),
      );
    } else {
      await prefs.remove('molinos_usuario_recordado');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().login(
            _usuario.text.trim(),
            _password.text,
          );

      await _guardarUsuarioRecordado();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade600,
          content: const Text('Bienvenido a Molinos'),
        ),
      );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AppShell(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _abrirChecador() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecadorScreen(
          getToken: () async => null,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _cardController.dispose();
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool escritorio = MediaQuery.of(context).size.width >= 850;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, child) {
          return Stack(
            children: [
              CustomPaint(
                size: MediaQuery.of(context).size,
                painter: _MolinosBackground(_bgController.value),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: escritorio ? 940 : 430,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 35,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(34),
                            child: escritorio
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: _brandingPanel(),
                                      ),
                                      Expanded(
                                        child: _loginPanel(),
                                      ),
                                    ],
                                  )
                                : _loginPanel(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _brandingPanel() {
    return Container(
      height: 620,
      padding: const EdgeInsets.all(38),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            azulOscuro,
            azul,
            Color(0xFF1976D2),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: _circle(150, amarillo.withOpacity(0.18)),
          ),
          Positioned(
            bottom: 30,
            left: -45,
            child: _circle(190, Colors.white.withOpacity(0.10)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 135,
                height: 135,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Image.asset(
                  'images/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.precision_manufacturing_rounded,
                      size: 74,
                      color: azul,
                    );
                  },
                ),
              ),
              const Spacer(),
              const Text(
                'Sistema de Molinos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 90,
                height: 6,
                decoration: BoxDecoration(
                  color: amarillo,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Acceso seguro para consultar, administrar y controlar información del área de molinos.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    color: amarillo.withOpacity(0.95),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vitracoat Pinturas en Polvo S.A. de C.V.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loginPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 34,
        vertical: 38,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.of(context).size.width < 850) ...[
              Container(
                width: 108,
                height: 108,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: amarillo, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: azul.withOpacity(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.precision_manufacturing_rounded,
                      size: 64,
                      color: azul,
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Iniciar sesión',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: azulOscuro,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ingresa tus datos para continuar',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 26),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            _input(
              controller: _usuario,
              label: 'Usuario',
              icon: Icons.person_rounded,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa tu usuario';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            _input(
              controller: _password,
              label: 'Contraseña',
              icon: Icons.lock_rounded,
              obscureText: !_verPassword,
              suffixIcon: IconButton(
                tooltip:
                    _verPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                icon: Icon(
                  _verPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: azul,
                ),
                onPressed: () {
                  setState(() {
                    _verPassword = !_verPassword;
                  });
                },
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa tu contraseña';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _recordarUsuario,
                  activeColor: azul,
                  onChanged: (value) {
                    setState(() {
                      _recordarUsuario = value ?? false;
                    });
                  },
                ),
                const Text(
                  'Recordar usuario',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: azulOscuro,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: amarillo,
                  foregroundColor: azulOscuro,
                  elevation: 8,
                  shadowColor: amarillo.withOpacity(0.45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: azulOscuro,
                        ),
                      )
                    : const Text(
                        'ENTRAR',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _abrirChecador,
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text(
                  'CHECADOR',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: azul,
                  side: const BorderSide(color: azul, width: 1.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '2026 © | Todos los derechos reservados.',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      onChanged: (_) {
        if (_error != null) {
          setState(() {
            _error = null;
          });
        }
      },
      onFieldSubmitted: (_) {
        if (!_loading) {
          _login();
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: azul),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF4F7FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: amarillo,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.red.shade300,
            width: 1.4,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.red.shade400,
            width: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _circle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _MolinosBackground extends CustomPainter {
  final double progress;

  _MolinosBackground(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF003B73),
          Color(0xFF005BAC),
          Color(0xFF1E88E5),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, bg);

    final yellowPaint = Paint()
      ..color = const Color(0xFFFFC107).withOpacity(0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);

    canvas.drawCircle(
      Offset(
        size.width * (0.22 + math.sin(progress * math.pi) * 0.03),
        size.height * 0.24,
      ),
      150,
      yellowPaint,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.82,
        size.height * (0.75 + math.cos(progress * math.pi) * 0.03),
      ),
      190,
      yellowPaint,
    );

    final whitePowder = Paint()
      ..color = Colors.white.withOpacity(0.13)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 42; i++) {
      final random = math.Random(i);
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y =
          (baseY + progress * 90 * (0.5 + random.nextDouble())) % size.height;

      final radius = 2 + random.nextDouble() * 5;

      canvas.drawCircle(
        Offset(
          x + math.sin(progress * 2 * math.pi + i) * 18,
          y,
        ),
        radius,
        whitePowder,
      );
    }

    final wave = Paint()
      ..color = Colors.white.withOpacity(0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final path = Path();
    path.moveTo(0, size.height * 0.78);

    for (double x = 0; x <= size.width; x++) {
      final y = size.height * 0.78 +
          math.sin(
                (x / size.width * 2 * math.pi) + progress * 2 * math.pi,
              ) *
              24;
      path.lineTo(x, y);
    }

    canvas.drawPath(path, wave);
  }

  @override
  bool shouldRepaint(covariant _MolinosBackground oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
