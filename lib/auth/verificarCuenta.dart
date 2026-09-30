import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'iniciosesion.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

/// Pantalla que se abre cuando la persona hace clic en el enlace de
/// activacion que le llego por correo. Recibe el token directo desde
/// la URL (ver main.dart) y llama a GET /verificar-cuenta/{token}.
class VerificarCuentaScreen extends StatefulWidget {
  final String token;
  const VerificarCuentaScreen({super.key, required this.token});

  @override
  State<VerificarCuentaScreen> createState() => _VerificarCuentaScreenState();
}

class _VerificarCuentaScreenState extends State<VerificarCuentaScreen> {
  bool _cargando = true;
  bool _exito = false;
  bool _expirado = false;
  String _mensaje = '';

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/verificar-cuenta/${widget.token}'),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _expirado = data['expirado'] == true;
        _mensaje = data['mensaje'] ?? 'No se pudo verificar la cuenta.';
      });
    } catch (e) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor. Verifica tu conexión.';
      });
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_cargando) ...[
                    const CircularProgressIndicator(color: Color(0xFF001E42)),
                    const SizedBox(height: 20),
                    const Text(
                      'Verificando tu cuenta...',
                      style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                    ),
                  ] else ...[
                    Icon(
                      _exito ? Icons.check_circle_outline : Icons.error_outline,
                      color: _exito
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      size: 64,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _exito ? '¡Cuenta activada!' : 'No se pudo activar',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _mensaje,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const IniciarSesionPage(),
                          ),
                          (route) => false,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF001E42),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _exito
                              ? 'Ir a Iniciar Sesión'
                              : (_expirado
                                    ? 'Solicitar un nuevo enlace'
                                    : 'Volver al inicio'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
