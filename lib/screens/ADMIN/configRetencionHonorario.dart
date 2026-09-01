import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

/// Configuracion del % de Retencion de Impuesto para Boletas de
/// Honorarios. Antes vivia dentro de la pantalla de Liquidacion de
/// Honorarios; ahora es un parametro global del sistema (se
/// actualiza una vez al año, no por liquidacion individual).
class ConfigRetencionHonorarioScreen extends StatefulWidget {
  const ConfigRetencionHonorarioScreen({super.key});

  @override
  State<ConfigRetencionHonorarioScreen> createState() =>
      _ConfigRetencionHonorarioScreenState();
}

class _ConfigRetencionHonorarioScreenState
    extends State<ConfigRetencionHonorarioScreen> {
  int _anioSeleccionado = DateTime.now().year;

  final _tasaRetencionController = TextEditingController();
  bool _guardandoTasa = false;
  String _mensajeTasa = '';
  bool _exitoTasa = false;
  List<dynamic> _historialTasas = [];
  bool _cargandoTasas = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorialTasas();
  }

  @override
  void dispose() {
    _tasaRetencionController.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorialTasas() async {
    setState(() => _cargandoTasas = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/config-retencion-honorario'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _historialTasas = data['valores'] ?? []);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoTasas = false);
    }
  }

  Future<void> _guardarTasaRetencion() async {
    final tasa = double.tryParse(
      _tasaRetencionController.text.trim().replaceAll(',', '.'),
    );
    if (tasa == null || tasa <= 0 || tasa > 100) {
      setState(() {
        _exitoTasa = false;
        _mensajeTasa = 'Ingresa un porcentaje válido entre 0 y 100';
      });
      return;
    }
    setState(() {
      _guardandoTasa = true;
      _mensajeTasa = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/config-retencion-honorario'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'tasa_retencion': tasa, 'anio': _anioSeleccionado}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoTasa = data['success'] == true;
        _mensajeTasa =
            data['mensaje'] ??
            (_exitoTasa ? 'Guardado correctamente' : 'Error');
      });
      if (_exitoTasa) _cargarHistorialTasas();
    } catch (_) {
      setState(() {
        _exitoTasa = false;
        _mensajeTasa = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardandoTasa = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(6, (i) => anioActual - i + 1);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '% de Retención de Impuesto (Honorarios)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Retención de Impuesto para Boletas de Honorarios',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Se usa para calcular el Honorario Líquido de los trabajadores con contrato Honorario.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _anioSeleccionado,
                              decoration: InputDecoration(
                                labelText: 'Año',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: anios
                                  .map(
                                    (a) => DropdownMenuItem(
                                      value: a,
                                      child: Text('$a'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () =>
                                    _anioSeleccionado = v ?? _anioSeleccionado,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Color(0xFFD97706),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Este porcentaje debe actualizarse cada año (a diferencia de otros parámetros mensuales).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, c) {
                          final angosto = c.maxWidth < 480;
                          final campo = TextField(
                            controller: _tasaRetencionController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Ej: 15.25',
                              suffixText: '%',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                          final boton = ElevatedButton(
                            onPressed: _guardandoTasa
                                ? null
                                : _guardarTasaRetencion,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF001E42),
                              foregroundColor: Colors.white,
                            ),
                            child: Text(
                              _guardandoTasa
                                  ? 'Guardando...'
                                  : 'Guardar para $_anioSeleccionado',
                            ),
                          );
                          if (angosto) {
                            return Column(
                              children: [
                                campo,
                                const SizedBox(height: 10),
                                SizedBox(width: double.infinity, child: boton),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: campo),
                              const SizedBox(width: 12),
                              boton,
                            ],
                          );
                        },
                      ),
                      if (_mensajeTasa.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _mensajeTasa,
                            style: TextStyle(
                              fontSize: 12,
                              color: _exitoTasa
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      if (_cargandoTasas)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_historialTasas.isNotEmpty) ...[
                        const Divider(),
                        const Text(
                          'Historial:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._historialTasas.map(
                          (t) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              'Año ${t['anio']}: ${t['tasa_retencion']}% · ingresado por ${t['nombre_admin']} el ${t['fecha_ingreso']}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}