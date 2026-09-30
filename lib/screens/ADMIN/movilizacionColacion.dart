import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class MovilizacionColacionScreen extends StatefulWidget {
  const MovilizacionColacionScreen({super.key});

  @override
  State<MovilizacionColacionScreen> createState() =>
      _MovilizacionColacionScreenState();
}

class _MovilizacionColacionScreenState
    extends State<MovilizacionColacionScreen> {
  static const int _montoFijoMovilizacion = 50000;
  static const int _montoFijoColacion = 60000;

  // Confirmacion mensual (aplica a TODOS los trabajadores de una vez)
  int _mesConfirmacion = DateTime.now().month;
  int _anioConfirmacion = DateTime.now().year;
  bool _cargandoEstado = true;
  bool _confirmandoMes = false;
  bool? _periodoConfirmado; // null = aun no se sabe
  String? _confirmadoPor;
  String? _fechaConfirmacion;
  String _mensajeConfirmacion = '';
  bool _exitoConfirmacion = false;

  @override
  void initState() {
    super.initState();
    _cargarEstadoConfirmacion();
  }

  String get _periodoConfirmacion =>
      '${_mesConfirmacion.toString().padLeft(2, '0')}/$_anioConfirmacion';

  Future<void> _cargarEstadoConfirmacion() async {
    setState(() => _cargandoEstado = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/estado-movilizacion-colacion?periodo=${Uri.encodeComponent(_periodoConfirmacion)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _periodoConfirmado = data['confirmado'] == true;
          _confirmadoPor = data['confirmado_por'];
          _fechaConfirmacion = data['fecha_confirmacion'];
        });
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoEstado = false);
    }
  }

  Future<void> _confirmarMes() async {
    setState(() {
      _confirmandoMes = true;
      _mensajeConfirmacion = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/confirmar-movilizacion-colacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'periodo': _periodoConfirmacion}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoConfirmacion = data['success'] == true;
        _mensajeConfirmacion =
            data['mensaje'] ?? (_exitoConfirmacion ? 'Confirmado' : 'Error');
      });
      if (_exitoConfirmacion) _cargarEstadoConfirmacion();
    } catch (_) {
      setState(() {
        _exitoConfirmacion = false;
        _mensajeConfirmacion = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _confirmandoMes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(11, (i) => anioActual - i);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Movilización y Colación',
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
          final double maxWidthContenido = esEscritorio
              ? 900
              : (esTablet ? 700 : double.infinity);

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: paddingHorizontal,
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidthContenido),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Asignaciones No Imponibles',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Montos fijos mensuales, no imponibles en su totalidad',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
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
                              'La ley no fija un monto maximo exacto (se evalua por "razonabilidad").',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Montos fijos (informativo) ──────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Movilización',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\$$_montoFijoMovilizacion CLP',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF001E42),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: const Color(0xFFE2E8F0),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Colación',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '\$$_montoFijoColacion CLP',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF001E42),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Confirmacion mensual (aplica a TODOS de una vez) ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _periodoConfirmado == false
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFFE2E8F0),
                          width: _periodoConfirmado == false ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Confirmar para todos los trabajadores',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Una sola confirmación aplica los montos fijos automáticamente a todos los trabajadores en ese período, sin necesidad de registrarlos uno por uno.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _mesConfirmacion,
                                  decoration: InputDecoration(
                                    labelText: 'Mes',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items: List.generate(12, (i) => i + 1)
                                      .map(
                                        (m) => DropdownMenuItem(
                                          value: m,
                                          child: Text(
                                            m.toString().padLeft(2, '0'),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    setState(
                                      () => _mesConfirmacion =
                                          v ?? _mesConfirmacion,
                                    );
                                    _cargarEstadoConfirmacion();
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _anioConfirmacion,
                                  decoration: InputDecoration(
                                    labelText: 'Año',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items:
                                      List.generate(
                                            6,
                                            (i) => DateTime.now().year - i,
                                          )
                                          .map(
                                            (a) => DropdownMenuItem(
                                              value: a,
                                              child: Text('$a'),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) {
                                    setState(
                                      () => _anioConfirmacion =
                                          v ?? _anioConfirmacion,
                                    );
                                    _cargarEstadoConfirmacion();
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_cargandoEstado)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          else if (_periodoConfirmado == true)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Ya confirmado para $_periodoConfirmacion'
                                '${_confirmadoPor != null ? ' por $_confirmadoPor' : ''}'
                                '${_fechaConfirmacion != null ? ' el ${_fechaConfirmacion!.split('T').first}' : ''}.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else if (_periodoConfirmado == false)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Aún no se ha confirmado el monto para este período. Los trabajadores sin registro individual no tendrán Movilización/Colación hasta que confirmes.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          if (_mensajeConfirmacion.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                _mensajeConfirmacion,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _exitoConfirmacion
                                      ? const Color(0xFF166534)
                                      : Colors.red,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _confirmandoMes ? null : _confirmarMes,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF001E42),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                _confirmandoMes
                                    ? 'Confirmando...'
                                    : (_periodoConfirmado == true
                                          ? 'Volver a confirmar'
                                          : 'Confirmar para este mes'),
                              ),
                            ),
                          ),
                        ],
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
