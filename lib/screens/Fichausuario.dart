import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class FichaUsuario extends StatefulWidget {
  const FichaUsuario({super.key});

  @override
  State<FichaUsuario> createState() => _FichaUsuarioState();
}

class _FichaUsuarioState extends State<FichaUsuario> {
  final TextEditingController _telefonoController = TextEditingController();
  final TextEditingController _direccionController = TextEditingController();

  String _nombreCompleto = '';
  String _rut = '';
  String _correo = '';

  bool _cargando = false;
  bool _guardando = false;
  String _mensaje = '';
  bool _exito = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/mi-ficha'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _nombreCompleto = data['nombre_completo'] ?? '';
          _rut = data['rut'] ?? '';
          _correo = data['correo'] ?? '';
          _telefonoController.text = data['telefono'] ?? '';
          _direccionController.text = data['direccion'] ?? '';
        });
      }
    } catch (_) {
      setState(() => _mensaje = 'Error al cargar los datos');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _guardarCambios() async {
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/mi-ficha'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'telefono': _telefonoController.text.trim(),
          'direccion': _direccionController.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Datos actualizados correctamente'
            : data['mensaje'] ?? 'Error al actualizar';
      });
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
    }
  }

  @override
  void dispose() {
    _telefonoController.dispose();
    _direccionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Mi Ficha Personal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── LOGO GRANDE CENTRADO ──────────────────
                  Container(
                    width: 180,
                    height: 140,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Image.asset('assets/Logo.png', fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 28),

                  // ── DATOS PERSONALES (solo lectura) ───────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Datos Personales',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF001E42),
                          ),
                        ),
                        const Divider(height: 20),
                        _buildDatoLectura(
                          icono: Icons.person_outline,
                          label: 'Nombre Completo',
                          valor: _nombreCompleto,
                        ),
                        const SizedBox(height: 14),
                        _buildDatoLectura(
                          icono: Icons.badge_outlined,
                          label: 'RUT',
                          valor: _rut,
                        ),
                        const SizedBox(height: 14),
                        _buildDatoLectura(
                          icono: Icons.email_outlined,
                          label: 'Correo Institucional',
                          valor: _correo,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── DATOS EDITABLES ───────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Datos que puedes actualizar',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF001E42),
                          ),
                        ),
                        const Divider(height: 20),

                        // Teléfono
                        const Text(
                          'Teléfono',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _telefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Ej: 912345678',
                            prefixIcon: const Icon(
                              Icons.phone_outlined,
                              color: Colors.grey,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Dirección
                        const Text(
                          'Dirección',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF475569),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _direccionController,
                          keyboardType: TextInputType.streetAddress,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'Ej: Av. Los Andes 1234, Los Andes',
                            prefixIcon: const Icon(
                              Icons.home_outlined,
                              color: Colors.grey,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── MENSAJE ÉXITO / ERROR ─────────────────
                  if (_mensaje.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: _exito ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _exito ? Colors.green[200]! : Colors.red[200]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _exito
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: _exito ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _mensaje,
                              style: TextStyle(
                                color: _exito ? Colors.green : Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // ── BOTÓN GUARDAR ─────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardarCambios,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF001E42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _guardando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'Actualizar Datos Personales',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ── Widget: dato de solo lectura con ícono ────────────────
  Widget _buildDatoLectura({
    required IconData icono,
    required String label,
    required String valor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 20, color: const Color(0xFF009A8D)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                valor.isEmpty ? '—' : valor,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF263238),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
