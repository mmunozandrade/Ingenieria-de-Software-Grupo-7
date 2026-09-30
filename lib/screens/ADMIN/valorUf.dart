import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

/// Valor UF del periodo + los 2 multiplicadores de tope (AFP/Salud y
/// Seguro de Cesantia). Antes vivia como un paso dentro del wizard
/// de "Calculo de Liquidacion Total" — se traslado aqui, a la
/// pantalla de Parametros del Sistema, para agrupar toda la
/// configuracion en un solo lugar. Sigue usando exactamente el
/// mismo endpoint (/admin/valor-uf), asi que los calculos de
/// liquidacion continuan funcionando igual, sin ningun cambio.
class ValorUfScreen extends StatefulWidget {
  const ValorUfScreen({super.key});

  @override
  State<ValorUfScreen> createState() => _ValorUfScreenState();
}

class _ValorUfScreenState extends State<ValorUfScreen> {
  final _valorUfController = TextEditingController();
  final _multiploAfpSaludController = TextEditingController(text: '90');
  final _multiploAfcController = TextEditingController(text: '135.2');
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  List<dynamic> _valores = [];
  bool _cargandoHistorial = true;

  double? get _valorUf =>
      double.tryParse(_valorUfController.text.trim().replaceAll(',', '.'));
  double? get _multiploAfpSalud => double.tryParse(
    _multiploAfpSaludController.text.trim().replaceAll(',', '.'),
  );
  double? get _multiploAfc =>
      double.tryParse(_multiploAfcController.text.trim().replaceAll(',', '.'));

  double? get _topeAfpSaludCalculado {
    final v = _valorUf;
    final m = _multiploAfpSalud;
    if (v == null || m == null) return null;
    return v * m;
  }

  double? get _topeAfcCalculado {
    final v = _valorUf;
    final m = _multiploAfc;
    if (v == null || m == null) return null;
    return v * m;
  }

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _valorUfController.dispose();
    _multiploAfpSaludController.dispose();
    _multiploAfcController.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/valor-uf'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _valores = data['valores'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _registrarValorUf() async {
    final valorUf = _valorUf;
    final topeAfpSalud = _topeAfpSaludCalculado;
    final topeAfc = _topeAfcCalculado;
    if (valorUf == null ||
        valorUf <= 0 ||
        topeAfpSalud == null ||
        topeAfpSalud <= 0 ||
        topeAfc == null ||
        topeAfc <= 0) {
      setState(() {
        _exito = false;
        _mensaje =
            'Ingresa el valor UF y ambos multiplicadores, todos deben ser positivos';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensaje = '';
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/valor-uf'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'valor_uf': valorUf,
          'tope_afp_salud': topeAfpSalud,
          'tope_afc': topeAfc,
          'periodo': periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Valores de UF registrados correctamente para el período $periodo'
            : (data['mensaje'] ?? 'Error al registrar los valores de UF');
      });
      if (_exito) {
        _cargarHistorial();
      }
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _enviando = false);
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
          'Valor UF y Topes',
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
          final bool dosColumnas = esEscritorio;

          final panelFormulario = Container(
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
                  'Ingresa el valor de la UF del período, y luego el multiplicador de cada tope; '
                  'el sistema calcula el monto en CLP automáticamente.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
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
                        onChanged: (v) => setState(
                          () => _mesSeleccionado = v ?? _mesSeleccionado,
                        ),
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
                              (a) =>
                                  DropdownMenuItem(value: a, child: Text('$a')),
                            )
                            .toList(),
                        onChanged: (v) => setState(
                          () => _anioSeleccionado = v ?? _anioSeleccionado,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Valor UF del período:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _valorUfController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Ej: 40844.79',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Multiplicador para AFP y Salud:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _multiploAfpSaludController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Ej: 90',
                    suffixText: 'UF',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                _cajaResultado(_topeAfpSaludCalculado),
                const SizedBox(height: 20),
                const Text(
                  'Multiplicador para Seguro de Cesantía:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _multiploAfcController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Ej: 135.2',
                    suffixText: 'UF',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                _cajaResultado(_topeAfcCalculado),
                const SizedBox(height: 20),
                if (_mensaje.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: _exito ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _exito ? Colors.green[200]! : Colors.red[200]!,
                      ),
                    ),
                    child: Text(
                      _mensaje,
                      style: TextStyle(
                        color: _exito ? Colors.green[800] : Colors.red[800],
                        fontSize: 13,
                      ),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _enviando ? null : _registrarValorUf,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF001E42),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      _enviando ? 'Guardando...' : 'Guardar Valores de UF',
                    ),
                  ),
                ),
              ],
            ),
          );

          final panelHistorial = Container(
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
                  'Historial de valores cargados',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 14),
                if (_cargandoHistorial)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_valores.isEmpty)
                  const Text(
                    'Aún no hay valores de UF registrados.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  )
                else
                  ..._valores.map(
                    (v) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Período ${v['periodo']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '\$${v['valor_uf']} CLP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF0D9488),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tope AFP/Salud: \$${v['tope_afp_salud']} CLP',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'Tope AFC: \$${v['tope_afc']} CLP',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ingresado por ${v['nombre_admin']} · ${v['fecha_ingreso']}',
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
            ),
          );

          final contenido = dosColumnas
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: panelFormulario),
                      const SizedBox(width: 24),
                      Expanded(child: panelHistorial),
                    ],
                  ),
                )
              : Column(
                  children: [
                    panelFormulario,
                    const SizedBox(height: 24),
                    panelHistorial,
                  ],
                );

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: paddingHorizontal,
              vertical: 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: esEscritorio ? 1180 : 700,
                ),
                child: contenido,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cajaResultado(double? valor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        valor != null
            ? 'Tope calculado: \$${valor.toStringAsFixed(0)} CLP'
            : 'Ingresa el valor UF y el multiplicador para calcular...',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: valor != null
              ? const Color(0xFF059669)
              : const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}
