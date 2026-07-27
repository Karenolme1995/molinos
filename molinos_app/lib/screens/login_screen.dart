import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../app_shell.dart';
import 'checador_screen.dart';
// Pantalla de inicio de sesión para la aplicación Molinos, que incluye animaciones de fondo, validación de formulario y manejo de autenticación
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
// Estado de la pantalla de inicio de sesión, que maneja la lógica de autenticación, animaciones y almacenamiento de preferencias del usuario
class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
// Controladores de texto para los campos de usuario y contraseña, que permiten acceder y modificar el contenido de los campos de entrada
  final TextEditingController _usuario = TextEditingController();
  final TextEditingController _password = TextEditingController();
// Variables de estado para controlar la carga, visibilidad de la contraseña y recordatorio del usuario, así como para almacenar mensajes de error
  bool _loading = false;
  bool _verPassword = false;
  bool _recordarUsuario = false;

  String? _error;

  late final AnimationController _bgController;
  late final AnimationController _cardController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
// Colores utilizados en la interfaz de usuario, definidos como constantes para mantener la consistencia del diseño
  static const Color azul = Color(0xFF005BAC);
  static const Color azulOscuro = Color(0xFF003B73);
  static const Color amarillo = Color(0xFFFFC107);
// Inicializa los controladores de animación y carga el usuario recordado desde las preferencias compartidas al iniciar la pantalla de inicio de sesión
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
// Carga el usuario previamente guardado en las preferencias compartidas y actualiza el estado de la pantalla de inicio de sesión para mostrarlo en el campo de usuario
  Future<void> _cargarUsuarioRecordado() async {
    final prefs = await SharedPreferences.getInstance();
    final usuarioGuardado = prefs.getString('molinos_usuario_recordado');
// Verifica si el widget sigue montado antes de actualizar el estado, para evitar errores si la pantalla se ha destruido mientras se cargaban las preferencias
    if (!mounted) return;
// Si se encuentra un usuario guardado, actualiza el campo de usuario y marca la opción "Recordar usuario" como seleccionada
    if (usuarioGuardado != null && usuarioGuardado.trim().isNotEmpty) {
      setState(() {
        _usuario.text = usuarioGuardado;
        _recordarUsuario = true;
      });
    }
  }
// Guarda o elimina el usuario en las preferencias compartidas según el estado de la opción "Recordar usuario", permitiendo que el usuario sea recordado en futuros inicios de sesión
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
// Maneja el proceso de inicio de sesión, incluyendo la validación del formulario, la autenticación con el servicio de autenticación, el almacenamiento del usuario recordado y la navegación a la pantalla principal de la aplicación
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });
// Intenta iniciar sesión utilizando el servicio de autenticación y maneja cualquier error que pueda ocurrir durante el proceso
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
// Abre la pantalla del checador, permitiendo al usuario acceder a la funcionalidad de registro de asistencia sin necesidad de iniciar sesión
  Future<void> _abrirChecador() async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChecadorScreen(
          getToken: () async => null,
        ),
      ),
    );
  }
// Libera los recursos de los controladores de animación y los controladores de texto cuando la pantalla de inicio de sesión se destruye, evitando fugas de memoria
  @override
  void dispose() {
    _bgController.dispose();
    _cardController.dispose();
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }
// Construye la interfaz de usuario de la pantalla de inicio de sesión, incluyendo el fondo animado, el panel de marca y el panel de inicio de sesión con campos de entrada y botones
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
  // Construye el panel de marca, que incluye el logotipo, el nombre del sistema, una descripción y un pie de página con información de la empresa, todo con un diseño atractivo y colores corporativos

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
      // Contenido del panel de marca
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
// Construye el panel de inicio de sesión, que incluye campos de entrada para el usuario y la contraseña, un botón de inicio de sesión, un botón para abrir el checador y mensajes de error, todo con un diseño limpio y funcional
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
                if (value == null || value.trim().isEmpty) {   // Valida que el campo de usuario no esté vacío
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
                    _verPassword ? 'Ocultar contraseña' : 'Mostrar contraseña', // Tooltip que indica la acción del botón de visibilidad de la contraseña
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
                  return 'Ingresa tu contraseña'; // Valida que el campo de contraseña no esté vacío
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
              '2026 © | Todos los derechos reservados.', // Pie de página con información de derechos de autor y año actual
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
// Construye un campo de entrada de texto personalizado con validación, iconos y estilo, utilizado para los campos de usuario y contraseña en el panel de inicio de sesión
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
// Construye un círculo decorativo utilizado en el fondo del panel de marca, con un tamaño y color especificados
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
// Pintor personalizado para el fondo animado de la pantalla de inicio de sesión, que dibuja un degradado, círculos amarillos, partículas blancas y una onda animada

class _MolinosBackground extends CustomPainter {
  final double progress;
// Constructor que recibe el progreso de la animación, utilizado para calcular las posiciones y movimientos de los elementos del fondo
  _MolinosBackground(this.progress);
// Dibuja el fondo animado en el lienzo, incluyendo un degradado lineal, círculos amarillos que se mueven suavemente, partículas blancas flotantes y una onda animada en la parte inferior
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
// Crea un objeto Paint con un degradado lineal que va desde azul oscuro hasta azul claro, para ser utilizado como fondo del lienzo
    canvas.drawRect(Offset.zero & size, bg);
// Dibuja un rectángulo de fondo con un degradado lineal que va desde azul oscuro hasta azul claro, cubriendo todo el lienzo
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
// Dibuja un círculo amarillo en el fondo, cuya posición vertical oscila suavemente con el tiempo, creando un efecto de animación
    canvas.drawCircle(
      Offset(
        size.width * 0.82,
        size.height * (0.75 + math.cos(progress * math.pi) * 0.03),
      ),
      190,
      yellowPaint,
    );
// Dibuja otro círculo amarillo en el fondo, cuya posición vertical también oscila suavemente con el tiempo, creando un efecto de animación complementario al primer círculo
    final whitePowder = Paint()
      ..color = Colors.white.withOpacity(0.13)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 42; i++) {
      final random = math.Random(i);
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y =
          (baseY + progress * 90 * (0.5 + random.nextDouble())) % size.height;
// Calcula un radio aleatorio para cada partícula, variando entre 2 y 7 píxeles, para crear un efecto de polvo flotante más natural y dinámico
      final radius = 2 + random.nextDouble() * 5;
// Dibuja partículas blancas en el fondo, que se mueven verticalmente y oscilan horizontalmente con el tiempo, creando un efecto de polvo flotante
      canvas.drawCircle(
        Offset(
          x + math.sin(progress * 2 * math.pi + i) * 18,
          y,
        ),
        radius,
        whitePowder,
      );
    }
// Dibuja partículas blancas en el fondo, que se mueven verticalmente y oscilan horizontalmente con el tiempo, creando un efecto de polvo flotante
    final wave = Paint()
      ..color = Colors.white.withOpacity(0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
// Dibuja una onda animada en la parte inferior del fondo, que se mueve horizontalmente y oscila verticalmente con el tiempo, creando un efecto de movimiento fluido
    final path = Path();
    path.moveTo(0, size.height * 0.78);
// Genera la forma de la onda utilizando una función seno para calcular la posición vertical de cada punto a lo largo del ancho del lienzo, creando un efecto de onda suave y continua
    for (double x = 0; x <= size.width; x++) {
      final y = size.height * 0.78 +
          math.sin(
                (x / size.width * 2 * math.pi) + progress * 2 * math.pi,
              ) *
              24;
      path.lineTo(x, y);
    }
// Dibuja la línea de la onda utilizando el objeto Path y el Paint configurado, creando un efecto visual de movimiento en el fondo
    canvas.drawPath(path, wave);
  }
// Determina si el pintor necesita repintarse cuando cambian las propiedades, en este caso, si el progreso de la animación ha cambiado
  @override
  bool shouldRepaint(covariant _MolinosBackground oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
// Clase de excepción personalizada para errores de autenticación, que extiende la clase Exception y permite manejar errores específicos de inicio de sesión en la aplicación