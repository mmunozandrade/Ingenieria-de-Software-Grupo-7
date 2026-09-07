import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

/// Configuracion de Gratificacion Legal — modalidad de calculo y
/// valor del IMM por periodo. Antes esto se configuraba dentro del
/// wizard de liquidacion (paso "Gratificacion Legal"); ahora vive
/// aca porque son parametros globales del sistema, no algo propio
/// de cada trabajador — una vez configurados, el calculo de
/// gratificacion se aplica solo, sin pasos manuales adicionales.
class ConfigGratificacionScreen extends StatefulWidget {
  const ConfigGratificacionScreen({super.key});

  @override
  State<ConfigGratificacionScreen> createState() =>
      _ConfigGratificacionScreenState();
}

class _ConfigGratificacionScreenState extends State<ConfigGratificacionScreen> {
  // ── Modalidad ──────────────────────────────────────────────
  bool _cargandoModalidad = true;
  String _modalidad = 'Proporcional';
  final _porcentajeMensualCtrl = TextEditingController(text: '25');
  final _limiteImmAnualCtrl = TextEditingController(text: '4.75');
  final _porcentajeAnualCtrl = TextEditingController(text: '30');
  String _fechaModificacionModalidad = '—';
  bool _guardandoModalidad = false;
  String _mensajeModalidad = '';
  bool _exitoModalidad = false;

  // ── Valor IMM por periodo ──────────────────────────────────
  int _mesImm = DateTime.now().month;
  int _anioImm = DateTime.now().year;
  final _immCtrl = TextEditingController();
  bool _guardandoImm = false;
  String _mensajeImm = '';
  bool _exitoImm = false;
  List<dynamic> _historialImm = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _cargarModalidad();
    _cargarHistorialImm();
  }

  @override
  void dispose() {
    _porcentajeMensualCtrl.dispose();
    _limiteImmAnualCtrl.dispose();
    _porcentajeAnualCtrl.dispose();
    _immCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarModalidad() async {
    setState(() => _cargandoModalidad = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/config-gratificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _modalidad = data['modalidad'] ?? 'Proporcional';
          _porcentajeMensualCtrl.text = (data['porcentaje_mensual'] ?? 25.0)
              .toString();
          _limiteImmAnualCtrl.text = (data['limite_imm_anual'] ?? 4.75)
              .toString();
          _porcentajeAnualCtrl.text = (data['porcentaje_anual'] ?? 30.0)
              .toString();
          _fechaModificacionModalidad = data['fecha_modificacion'] ?? '—';
        });
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoModalidad = false);
    }
  }

  Future<void> _guardarModalidad() async {
    final porcentajeMensual = double.tryParse(
      _porcentajeMensualCtrl.text.trim(),
    );
    final limiteImmAnual = double.tryParse(_limiteImmAnualCtrl.text.trim());
    final porcentajeAnual = double.tryParse(_porcentajeAnualCtrl.text.trim());
    if (porcentajeMensual == null ||
        limiteImmAnual == null ||
        porcentajeAnual == null) {
      setState(() {
        _exitoModalidad = false;
        _mensajeModalidad = 'Revisa que los porcentajes sean números válidos';
      });
      return;
    }
    setState(() {
      _guardandoModalidad = true;
      _mensajeModalidad = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/admin/config-gratificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'modalidad': _modalidad,
          'porcentaje_mensual': porcentajeMensual,
          'limite_imm_anual': limiteImmAnual,
          'porcentaje_anual': porcentajeAnual,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoModalidad = data['success'] == true;
        _mensajeModalidad = _exitoModalidad
            ? 'Configuración de gratificación actualizada'
            : (data['mensaje'] ?? 'Error al guardar');
      });
      if (_exitoModalidad) _cargarModalidad();
    } catch (_) {
      setState(() {
        _exitoModalidad = false;
        _mensajeModalidad = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardandoModalidad = false);
    }
  }

  Future<void> _cargarHistorialImm() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/valor-imm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _historialImm = data['valores'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  String get _periodoImm => '${_mesImm.toString().padLeft(2, '0')}/$_anioImm';

  bool get _immYaConfiguradoEstePeriodo =>
      _historialImm.any((v) => v['periodo'] == _periodoImm);

  Future<void> _guardarImm() async {
    final valor = int.tryParse(_immCtrl.text.trim());
    if (valor == null || valor <= 0) {
      setState(() {
        _exitoImm = false;
        _mensajeImm = 'Ingresa un valor IMM válido';
      });
      return;
    }
    setState(() {
      _guardandoImm = true;
      _mensajeImm = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/valor-imm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'valor_clp': valor, 'periodo': _periodoImm}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoImm = data['success'] == true;
        _mensajeImm = _exitoImm
            ? 'Valor IMM guardado para $_periodoImm'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exitoImm) {
        _immCtrl.clear();
        _cargarHistorialImm();
      }
    } catch (_) {
      setState(() {
        _exitoImm = false;
        _mensajeImm = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardandoImm = false);
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
          'Gratificación Legal',
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
                      'Configuración de Gratificación',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Una vez configurado, el cálculo se aplica automáticamente a todos los trabajadores — no requiere ningún paso adicional en el wizard de liquidación.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 20),

                    // ── Modalidad ────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: _cargandoModalidad
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Modalidad de cálculo',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Color(0xFF001E42),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Última modificación: $_fechaModificacionModalidad',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                DropdownButtonFormField<String>(
                                  value: _modalidad,
                                  decoration: InputDecoration(
                                    labelText: 'Modalidad',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Proporcional',
                                      child: Text(
                                        'Proporcional (25% mensual, tope IMM)',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Anual',
                                      child: Text(
                                        'Anual (30% utilidad líquida)',
                                      ),
                                    ),
                                  ],
                                  // Deshabilitado: el cambio de modalidad se
                                  // habilitara en el Incremento 3.
                                  onChanged: null,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Configurable para el incremento 3',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (_modalidad == 'Proporcional') ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _porcentajeMensualCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: '% mensual',
                                            suffixText: '%',
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: _limiteImmAnualCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Tope (IMM anuales)',
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  TextField(
                                    controller: _porcentajeAnualCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText:
                                          '% anual sobre utilidad líquida',
                                      suffixText: '%',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                if (_mensajeModalidad.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      _mensajeModalidad,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _exitoModalidad
                                            ? const Color(0xFF166534)
                                            : Colors.red,
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  height: 44,
                                  child: ElevatedButton(
                                    onPressed: _guardandoModalidad
                                        ? null
                                        : _guardarModalidad,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF001E42),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: Text(
                                      _guardandoModalidad
                                          ? 'Guardando...'
                                          : 'Guardar modalidad',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 20),

                    // ── Valor IMM por periodo ────────────────────
                    if (_modalidad == 'Proporcional')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                !_cargandoHistorial &&
                                    !_immYaConfiguradoEstePeriodo
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFE2E8F0),
                            width:
                                !_cargandoHistorial &&
                                    !_immYaConfiguradoEstePeriodo
                                ? 1.5
                                : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Valor IMM por período',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Necesario para calcular el tope de la gratificación proporcional. Cámbialo cada vez que el IMM legal cambie.',
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
                                    value: _mesImm,
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
                                    onChanged: (v) =>
                                        setState(() => _mesImm = v ?? _mesImm),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _anioImm,
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
                                    onChanged: (v) => setState(
                                      () => _anioImm = v ?? _anioImm,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (!_cargandoHistorial &&
                                !_immYaConfiguradoEstePeriodo)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Aún no se ha configurado el IMM para este período.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            TextField(
                              controller: _immCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Valor IMM (CLP)',
                                hintText: 'Ej: 500000',
                                prefixText: '\$ ',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_mensajeImm.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  _mensajeImm,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _exitoImm
                                        ? const Color(0xFF166534)
                                        : Colors.red,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton(
                                onPressed: _guardandoImm ? null : _guardarImm,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF001E42),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _guardandoImm
                                      ? 'Guardando...'
                                      : 'Guardar valor IMM',
                                ),
                              ),
                            ),
                            if (_historialImm.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              const Divider(),
                              const SizedBox(height: 8),
                              const Text(
                                'Historial',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ..._historialImm.map(
                                (v) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${v['periodo']} · \$${v['valor_clp']} CLP',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '${v['nombre_admin']} · ${v['fecha_ingreso']}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
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
          );
        },
      ),
    );
  }
}
