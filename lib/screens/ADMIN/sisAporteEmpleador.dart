import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

/// Configuracion de los aportes patronales que no tenian pantalla
/// propia: SIS, Expectativa de Vida y Aporte Previsional de
/// Capitalizacion Individual. Reutiliza el mismo endpoint generico
/// de config_aportes_empleador que ya usa "Costo Total Empleador".
class SisAportesEmpleadorScreen extends StatefulWidget {
  const SisAportesEmpleadorScreen({super.key});

  @override
  State<SisAportesEmpleadorScreen> createState() =>
      _SisAportesEmpleadorScreenState();
}

class _SisAportesEmpleadorScreenState extends State<SisAportesEmpleadorScreen> {
  static const _conceptos = <String, String>{
    'SIS_AFP': 'SIS (Seguro de Invalidez y Sobrevivencia)',
    'Expectativa_Vida': 'Expectativa de Vida',
    'Aporte_Capitalizacion': 'Aporte Previsional de Capitalización Individual',
  };

  final Map<String, TextEditingController> _controllers = {
    for (final k in _conceptos.keys) k: TextEditingController(),
  };

  bool _cargando = true;
  String _mensaje = '';

  @override
  void initState() {
    super.initState();
    _cargarAportes();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarAportes() async {
    setState(() => _cargando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/config-aportes-empleador'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final aportes = (data['aportes'] as List?) ?? [];
        for (final a in aportes) {
          final concepto = a['concepto'];
          if (_controllers.containsKey(concepto)) {
            _controllers[concepto]!.text = a['tasa_porcentaje'].toString();
          }
        }
      }
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _actualizarAporte(String concepto) async {
    final valor = double.tryParse(_controllers[concepto]!.text.trim());
    if (valor == null || valor < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un valor válido (mayor o igual a 0)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/admin/config-aportes-empleador'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'concepto': concepto, 'tasa_porcentaje': valor}),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? '${_conceptos[concepto]} actualizado'
                  : (data['mensaje'] ?? 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
      if (data['success'] == true) _cargarAportes();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar al servidor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'SIS y Aportes del Empleador',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final bool esEscritorio = ancho >= 1280;
          final bool esTablet = ancho >= 768 && ancho < 1280;
          final double paddingHorizontal = esEscritorio
              ? 40
              : (esTablet ? 28 : 16);
          final double maxWidthContenido = esEscritorio ? 760 : double.infinity;

          if (_cargando) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: paddingHorizontal,
              vertical: 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidthContenido),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aportes patronales para Cotizaciones Previsionales',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Estos porcentajes se aplican sobre el Total Imponible para AFP y Salud, y alimentan '
                      'tanto la pantalla de "Costo Total Empleador" como la de "Cotizaciones Previsionales".',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 24),
                    ..._conceptos.entries.map(
                      (entry) => _TarjetaAporte(
                        titulo: entry.value,
                        controller: _controllers[entry.key]!,
                        onGuardar: () => _actualizarAporte(entry.key),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TarjetaAporte extends StatelessWidget {
  final String titulo;
  final TextEditingController controller;
  final VoidCallback onGuardar;

  const _TarjetaAporte({
    required this.titulo,
    required this.controller,
    required this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool angosto = constraints.maxWidth < 480;
          final campo = TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: '%',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
          final boton = ElevatedButton(
            onPressed: onGuardar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              foregroundColor: Colors.white,
            ),
            child: const Text('Guardar'),
          );

          if (angosto) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                campo,
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: boton),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(width: 120, child: campo),
              const SizedBox(width: 12),
              boton,
            ],
          );
        },
      ),
    );
  }
}
