import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'iniciosesion.dart';

const String apiUrl = 'http://127.0.0.1:8000';

class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key});
  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  // Controladores
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();

  // Estado
  bool _obscureText = true;
  bool _obscureConfirmar = true;
  bool _cargando = false;
  String _error = '';
  String _exito = '';

  // Validaciones en tiempo real
  bool get _tiene8Caracteres => _contrasenaController.text.length >= 8;
  bool get _tieneMayuscula =>
      _contrasenaController.text.contains(RegExp(r'[A-Z]'));
  bool get _tieneMinuscula =>
      _contrasenaController.text.contains(RegExp(r'[a-z]'));
  bool get _tieneNumero =>
      _contrasenaController.text.contains(RegExp(r'[0-9]'));
  bool get _tieneEspecial =>
      _contrasenaController.text.contains(RegExp(r'[!@#\$%^&*]'));
  bool get _contrasenaValida =>
      _tiene8Caracteres &&
      _tieneMayuscula &&
      _tieneMinuscula &&
      _tieneNumero &&
      _tieneEspecial;

  // Nivel de seguridad de la contraseña
  String get _nivelSeguridad {
    int puntos = [
      _tiene8Caracteres,
      _tieneMayuscula,
      _tieneMinuscula,
      _tieneNumero,
      _tieneEspecial,
    ].where((v) => v).length;
    if (puntos <= 2) return 'Débil';
    if (puntos <= 3) return 'Media';
    return 'Fuerte';
  }

  Color get _colorSeguridad {
    switch (_nivelSeguridad) {
      case 'Débil':
        return Colors.red;
      case 'Media':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  // ── Llamada a la API ────────────────────────────────────────
  Future<void> _registrar() async {
    final correo = _correoController.text.trim();
    final contrasena = _contrasenaController.text.trim();
    final confirmar = _confirmarController.text.trim();

    // Validaciones locales
    if (correo.isEmpty || contrasena.isEmpty || confirmar.isEmpty) {
      setState(() => _error = 'Por favor completa todos los campos.');
      return;
    }
    if (!correo.endsWith('@accaconcagua.cl')) {
      setState(
        () => _error = 'Debes usar tu correo institucional @accaconcagua.cl',
      );
      return;
    }
    if (!_contrasenaValida) {
      setState(
        () =>
            _error = 'La contraseña no cumple con los requisitos de seguridad.',
      );
      return;
    }
    if (contrasena != confirmar) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = '';
      _exito = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/registro'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'correo': correo, 'contrasena': contrasena}),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(
          () =>
              _exito = '¡Cuenta creada exitosamente! Ya puedes iniciar sesión.',
        );
        // Esperar 2 segundos y navegar al login
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
        );
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al crear la cuenta.');
      }
    } catch (e) {
      setState(
        () => _error = 'No se pudo conectar al servidor. Verifica tu conexión.',
      );
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset('assets/Logo.png', height: 100),
              const SizedBox(height: 20),
              const Text(
                'Registro de Usuario',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const Text(
                'Sistema de Personal Institucional',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 30),

              // ── Campo Correo ───────────────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Correo Institucional',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _correoController,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'usuario@accaconcagua.cl',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: Colors.grey,
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Debe usar su correo institucional @accaconcagua.cl',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),

              // ── Campo Contraseña ───────────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Contraseña',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contrasenaController,
                obscureText: _obscureText,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Ingrese su contraseña',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: Colors.grey,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureText = !_obscureText),
                  ),
                ),
              ),

              // Indicador de seguridad
              if (_contrasenaController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Seguridad: ',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      _nivelSeguridad,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _colorSeguridad,
                      ),
                    ),
                  ],
                ),
              ],

              // Validaciones en tiempo real
              const SizedBox(height: 10),
              _buildValidationItem('Mínimo 8 caracteres', _tiene8Caracteres),
              _buildValidationItem('Al menos una mayúscula', _tieneMayuscula),
              _buildValidationItem('Al menos una minúscula', _tieneMinuscula),
              _buildValidationItem('Al menos un número', _tieneNumero),
              _buildValidationItem(
                'Al menos un carácter especial (!@#\$%^&*)',
                _tieneEspecial,
              ),
              const SizedBox(height: 20),

              // ── Confirmar Contraseña ───────────────────────
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Confirmar Contraseña',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmarController,
                obscureText: _obscureConfirmar,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Confirme su contraseña',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: Colors.grey,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmar
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirmar = !_obscureConfirmar),
                  ),
                  // Borde rojo si no coinciden
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color:
                          _confirmarController.text.isNotEmpty &&
                              _confirmarController.text !=
                                  _contrasenaController.text
                          ? Colors.red
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
              if (_confirmarController.text.isNotEmpty &&
                  _confirmarController.text != _contrasenaController.text)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Las contraseñas no coinciden',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),

              // ── Mensaje de error ───────────────────────────
              if (_error.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Mensaje de éxito ───────────────────────────
              if (_exito.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _exito,
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Botón Registrar ────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _cargando ? null : _registrar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _cargando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Registrar Cuenta',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Link al login ──────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('¿Ya tienes una cuenta? '),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const IniciarSesionPage(),
                      ),
                    ),
                    child: const Text(
                      'Iniciar Sesión',
                      style: TextStyle(
                        color: Color(0xFF00897B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValidationItem(String texto, bool cumple) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            cumple ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: cumple ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              color: cumple ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
