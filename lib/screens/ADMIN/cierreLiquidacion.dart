import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class CierreLiquidacionScreen extends StatefulWidget {
  const CierreLiquidacionScreen({super.key});

  @override
  State<CierreLiquidacionScreen> createState() =>
      _CierreLiquidacionScreenState();
}

class _CierreLiquidacionScreenState extends State<CierreLiquidacionScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _procesando = false;
  String _mensaje = '';
  bool _exito = false;
  Map<String, dynamic>? _resultadoCierre;

  // Consulta / complementaria
  List<dynamic> _liquidacionesExistentes = [];
  bool _consultando = false;
  final _conceptoComplementarioController = TextEditingController();
  final _montoComplementarioController = TextEditingController();

  @override
  void dispose() {
    _busquedaController.dispose();
    _conceptoComplementarioController.dispose();
    _montoComplementarioController.dispose();
    super.dispose();
  }

  Future<void> _buscarEmpleado(String texto) async {
    if (texto.trim().length < 3) {
      setState(() => _resultadosBusqueda = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/buscar-empleados?apellido=${Uri.encodeComponent(texto)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _resultadosBusqueda = data['empleados'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _buscando = false);
    }
  }

  void _seleccionarEmpleado(Map<String, dynamic> empleado) {
    setState(() {
      _empleadoSeleccionado = empleado;
      _resultadosBusqueda = [];
      _busquedaController.text =
          '${empleado['nombres']} ${empleado['apellidos']}';
      _resultadoCierre = null;
      _liquidacionesExistentes = [];
      _mensaje = '';
    });
  }

  String get _periodo =>
      '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

  Future<void> _consultarLiquidacion() async {
    if (_empleadoSeleccionado == null) return;
    setState(() {
      _consultando = true;
      _liquidacionesExistentes = [];
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/liquidacion?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(_periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _liquidacionesExistentes = data['liquidaciones'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _consultando = false);
    }
  }

  Future<void> _cerrarLiquidacion() async {
    if (_empleadoSeleccionado == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona un trabajador';
      });
      return;
    }

    setState(() {
      _procesando = true;
      _mensaje = '';
      _resultadoCierre = null;
    });

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/liquidacion/cerrar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'periodo': _periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Liquidación cerrada correctamente'
            : (data['mensaje'] ?? 'Error al cerrar la liquidación');
        if (_exito) _resultadoCierre = data;
      });
      if (_exito) _consultarLiquidacion();
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _procesando = false);
    }
  }

  Future<void> _registrarComplementaria() async {
    final concepto = _conceptoComplementarioController.text.trim();
    final monto = int.tryParse(_montoComplementarioController.text.trim());
    if (concepto.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El concepto debe tener al menos 3 caracteres'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (monto == null || monto == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto distinto de 0 (puede ser negativo)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/liquidacion/complementaria'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'periodo': _periodo,
          'concepto': concepto,
          'monto_clp': monto,
        }),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? 'Liquidación complementaria registrada'
                  : (data['mensaje'] ?? 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
      if (data['success'] == true) {
        _conceptoComplementarioController.clear();
        _montoComplementarioController.clear();
        _consultarLiquidacion();
      }
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
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(11, (i) => anioActual - i);
    final bool yaEstaCerrada = _liquidacionesExistentes.any(
      (l) => l['tipo_liquidacion'] == 'normal' && l['estado'] == 'cerrada',
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Cierre de Liquidación',
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
                  'Cerrar Liquidación Mensual',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Consolida todos los cálculos del periodo y bloquea futuras modificaciones',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),

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
                      const Text(
                        'Trabajador:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _busquedaController,
                        onChanged: (v) {
                          _empleadoSeleccionado = null;
                          _buscarEmpleado(v);
                        },
                        decoration: InputDecoration(
                          hintText:
                              'Buscar por apellido (minimo 3 caracteres)...',
                          suffixIcon: _buscando
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      if (_resultadosBusqueda.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _resultadosBusqueda.length,
                            itemBuilder: (ctx, i) {
                              final e = _resultadosBusqueda[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${e['nombres']} ${e['apellidos']}',
                                ),
                                subtitle: Text('${e['rut']} · ${e['cargo']}'),
                                onTap: () => _seleccionarEmpleado(e),
                              );
                            },
                          ),
                        ),
                      if (_empleadoSeleccionado != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF1D4ED8),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} (${_empleadoSeleccionado!['rut']})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

                      const Text(
                        'Periodo:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _mesSeleccionado,
                              decoration: InputDecoration(
                                labelText: 'Mes',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: List.generate(12, (i) => i + 1)
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m.toString().padLeft(2, '0')),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                setState(
                                  () =>
                                      _mesSeleccionado = v ?? _mesSeleccionado,
                                );
                                _consultarLiquidacion();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
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
                              onChanged: (v) {
                                setState(
                                  () => _anioSeleccionado =
                                      v ?? _anioSeleccionado,
                                );
                                _consultarLiquidacion();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _empleadoSeleccionado == null
                                ? null
                                : _consultarLiquidacion,
                            icon: _consultando
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            tooltip: 'Consultar estado',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (_mensaje.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _exito ? Colors.green[50] : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _exito
                                  ? Colors.green[200]!
                                  : Colors.red[200]!,
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

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: (_procesando || yaEstaCerrada)
                              ? null
                              : _cerrarLiquidacion,
                          icon: _procesando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_outline, size: 18),
                          label: Text(
                            yaEstaCerrada
                                ? 'Liquidación ya cerrada'
                                : 'Cerrar Liquidación',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: yaEstaCerrada
                                ? Colors.grey
                                : const Color(0xFF001E42),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_resultadoCierre != null) ...[
                  const SizedBox(height: 20),
                  _TarjetaCierre(resultado: _resultadoCierre!),
                ],

                if (_liquidacionesExistentes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Liquidaciones de este periodo:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF001E42),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._liquidacionesExistentes.map(
                    (l) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: l['tipo_liquidacion'] == 'complementaria'
                            ? const Color(0xFFFFF7ED)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: l['tipo_liquidacion'] == 'complementaria'
                              ? const Color(0xFFFED7AA)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l['tipo_liquidacion'] == 'complementaria'
                                    ? 'Liquidación Complementaria'
                                    : 'Liquidación Normal',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'CERRADA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (l['observacion_complementaria'] != null)
                            Text(
                              l['observacion_complementaria'],
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            'Líquido: \$${l['liquido_a_pagar']?.toStringAsFixed(0) ?? '—'} CLP · Cerrada: ${l['fecha_cierre']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (yaEstaCerrada) ...[
                    const SizedBox(height: 16),
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
                          const Text(
                            'Registrar Liquidación Complementaria (corrección):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _conceptoComplementarioController,
                            decoration: InputDecoration(
                              hintText: 'Ej: Corrección bono no incluido',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _montoComplementarioController,
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Monto (positivo o negativo)',
                              prefixText: '\$ ',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _registrarComplementaria,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD97706),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Registrar Complementaria'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaCierre extends StatelessWidget {
  final Map<String, dynamic> resultado;
  const _TarjetaCierre({required this.resultado});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF059669),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${resultado['nombre']} · ${resultado['periodo']} — CERRADA',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          _fila('Total imponible', resultado['total_imponible']),
          _fila('(-) AFP', resultado['descuento_afp']),
          _fila('(-) Salud', resultado['descuento_salud']),
          _fila('(-) AFC trabajador', resultado['descuento_afc_trabajador']),
          _fila('(-) Impuesto único', resultado['impuesto_unico']),
          _fila('(-) Descuentos varios', resultado['total_descuentos_varios']),
          _fila('(-) Licencias médicas', resultado['total_licencias']),
          _fila('(-) Anticipos', resultado['total_anticipos']),
          const Divider(height: 20),
          _fila(
            'Total descuentos',
            resultado['total_descuento'],
            destacado: true,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LÍQUIDO A PAGAR',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF001E42),
                ),
              ),
              Text(
                '\$${resultado['liquido_a_pagar']} CLP',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Costo total empleador: \$${resultado['costo_total_empleador']} CLP',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, dynamic valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF475569),
              fontWeight: destacado ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            '\$$valor',
            style: TextStyle(
              fontSize: 13,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
