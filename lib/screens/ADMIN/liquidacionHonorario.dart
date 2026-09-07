import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

/// Formatea un numero con puntos como separador de miles (estilo
/// chileno): 1500000 -> "1.500.000". Acepta int, double o String.
String formatearMiles(dynamic valor) {
  if (valor == null) return '0';
  final int numero = valor is num
      ? valor.round()
      : (int.tryParse(valor.toString()) ?? 0);
  final bool esNegativo = numero < 0;
  final String digitos = numero.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return (esNegativo ? '-' : '') + buffer.toString();
}

/// Convierte un texto con puntos de miles (ej. "1.500.000") de vuelta
/// a un numero (ej. 1500000).
double? desformatearMiles(String texto) {
  final soloDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (soloDigitos.isEmpty) return null;
  return double.tryParse(soloDigitos);
}

/// TextInputFormatter que aplica puntos de miles en vivo mientras el
/// usuario escribe en un campo de monto (estilo chileno).
class MilesInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final soloDigitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final buffer = StringBuffer();
    for (int i = 0; i < soloDigitos.length; i++) {
      final posicionDesdeDerecha = soloDigitos.length - i;
      buffer.write(soloDigitos[i]);
      if (posicionDesdeDerecha > 1 && posicionDesdeDerecha % 3 == 1) {
        buffer.write('.');
      }
    }
    final textoFormateado = buffer.toString();
    return TextEditingValue(
      text: textoFormateado,
      selection: TextSelection.collapsed(offset: textoFormateado.length),
    );
  }
}

/// Calculo de liquidacion para trabajadores con contrato Honorario
/// (boleta de honorarios): Honorario Bruto - Retencion = Honorario
/// Liquido. No lleva AFP, Salud, AFC ni Gratificacion — es un
/// calculo simplificado, distinto del "Calculo de Liquidacion Total".
class LiquidacionHonorarioScreen extends StatefulWidget {
  const LiquidacionHonorarioScreen({super.key});

  @override
  State<LiquidacionHonorarioScreen> createState() =>
      _LiquidacionHonorarioScreenState();
}

class _LiquidacionHonorarioScreenState
    extends State<LiquidacionHonorarioScreen> {
  // ── Busqueda de trabajador ──────────────────────────────────
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;
  Timer? _debounce;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;
  DateTime _fechaEmision = DateTime.now();

  // ── Calculo de honorario ────────────────────────────────────
  final _numeroBoletaController = TextEditingController();
  final _numeroCuentaController = TextEditingController();
  final _periodoPrestacionController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _honorarioBrutoController = TextEditingController();
  bool _calculando = false;
  Map<String, dynamic>? _resultado;
  String _errorCalculo = '';
  bool _descargandoBoleta = false;

  Future<void> _descargarBoletaHonorarios() async {
    final liquidacionId = _resultado?['liquidacion_honorario_id'];
    if (liquidacionId == null) return;
    setState(() => _descargandoBoleta = true);
    try {
      final token = await SessionService.obtenerToken();
      // El numero de cuenta no se guarda en la base de datos (dato
      // sensible) -- se manda directo en esta peticion, tomado del
      // campo de texto que sigue en pantalla, o del mismo valor por
      // defecto que ya se uso en el calculo si se dejo vacio.
      final numeroCuenta = _numeroCuentaController.text.trim().isEmpty
          ? '123456889'
          : _numeroCuentaController.text.trim();
      final uri = Uri.parse(
        '$_apiUrl/admin/boleta-honorarios/$liquidacionId',
      ).replace(queryParameters: {'numero_cuenta': numeroCuenta});
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final blob = html.Blob([response.bodyBytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute(
            'download',
            'boleta_honorarios_${_resultado!['rut']}_${_resultado!['periodo'].toString().replaceAll('/', '-')}.pdf',
          )
          ..click();
        html.Url.revokeObjectUrl(url);
      }
    } catch (_) {
      // silencioso: si falla la descarga, simplemente no pasa nada visible
    } finally {
      if (mounted) setState(() => _descargandoBoleta = false);
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _numeroBoletaController.dispose();
    _numeroCuentaController.dispose();
    _periodoPrestacionController.dispose();
    _descripcionController.dispose();
    _honorarioBrutoController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _buscarEmpleado(String texto) async {
    _debounce?.cancel();
    if (texto.trim().length < 3) {
      setState(() => _resultadosBusqueda = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _buscando = true);
      try {
        final token = await SessionService.obtenerToken();
        final response = await http.get(
          Uri.parse(
            '$_apiUrl/buscar-empleados?apellido=${Uri.encodeComponent(texto.trim())}',
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
      } finally {
        if (mounted) setState(() => _buscando = false);
      }
    });
  }

  void _seleccionarEmpleado(Map<String, dynamic> e) {
    setState(() {
      _empleadoSeleccionado = e;
      _resultadosBusqueda = [];
      _busquedaController.text = '${e['nombres']} ${e['apellidos']}';
      _resultado = null;
      _errorCalculo = '';
    });
  }

  Future<void> _calcularHonorario() async {
    if (_empleadoSeleccionado == null) {
      setState(() {
        _errorCalculo = 'Selecciona un trabajador primero';
        _resultado = null;
      });
      return;
    }
    final bruto = desformatearMiles(_honorarioBrutoController.text);
    if (bruto == null || bruto <= 0) {
      setState(() {
        _errorCalculo = 'Ingresa un honorario bruto válido';
        _resultado = null;
      });
      return;
    }
    if (_descripcionController.text.trim().length < 3) {
      setState(() {
        _errorCalculo = 'Describe el tipo de trabajo realizado';
        _resultado = null;
      });
      return;
    }

    setState(() {
      _calculando = true;
      _errorCalculo = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final periodo =
          '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/liquidacion-honorario'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'periodo': periodo,
          'numero_boleta': _numeroBoletaController.text.trim().isEmpty
              ? null
              : _numeroBoletaController.text.trim(),
          'fecha_emision': _fechaEmision.toIso8601String().split('T')[0],
          'numero_cuenta': _numeroCuentaController.text.trim().isEmpty
              ? null
              : _numeroCuentaController.text.trim(),
          'periodo_prestacion': _periodoPrestacionController.text.trim().isEmpty
              ? null
              : _periodoPrestacionController.text.trim(),
          'descripcion_trabajo': _descripcionController.text.trim(),
          'honorario_bruto': bruto,
        }),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _resultado = data);
      } else {
        setState(() {
          _errorCalculo = data['mensaje'] ?? 'Error al calcular';
          _resultado = null;
        });
      }
    } catch (_) {
      setState(() {
        _errorCalculo = 'No se pudo conectar al servidor';
        _resultado = null;
      });
    } finally {
      setState(() => _calculando = false);
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
          'Liquidación Honorarios',
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
                      'Liquidación para trabajadores a Honorarios',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Cálculo simplificado de boleta de honorarios: no incluye AFP, Salud, Seguro de Cesantía ni Gratificación.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 20),

                    // ── Buscar trabajador ──────────────────────
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
                            'Nombre del prestador de servicio:',
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
                                  'Buscar por apellido (mínimo 3 caracteres)...',
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
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: _resultadosBusqueda.map((e) {
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      '${e['nombres']} ${e['apellidos']}',
                                    ),
                                    subtitle: Text(
                                      '${e['rut']} · ${e['cargo'] ?? ''}',
                                    ),
                                    onTap: () => _seleccionarEmpleado(e),
                                  );
                                }).toList(),
                              ),
                            ),
                          if (_empleadoSeleccionado != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDBEAFE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1D4ED8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          const Text(
                            'Período:',
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
                                          child: Text(
                                            m.toString().padLeft(2, '0'),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(
                                    () => _mesSeleccionado =
                                        v ?? _mesSeleccionado,
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
                                        (a) => DropdownMenuItem(
                                          value: a,
                                          child: Text('$a'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(
                                    () => _anioSeleccionado =
                                        v ?? _anioSeleccionado,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Informacion de la boleta ────────────────
                    if (_empleadoSeleccionado != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Información de la Boleta',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _filaInfoBoleta(
                              'Nombre del prestador de servicio',
                              '${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']}',
                            ),
                            _filaInfoBoleta(
                              'Rut del prestador de servicio',
                              _empleadoSeleccionado!['rut'] ?? '—',
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Número de cuenta bancaria:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _numeroCuentaController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Ej: 123456889',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Período de la prestación del servicio:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _periodoPrestacionController,
                              decoration: InputDecoration(
                                hintText: 'Ej: 2 de marzo a 2 de agosto',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Fecha de emisión de la boleta de honorarios:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final f = await showDatePicker(
                                  context: context,
                                  initialDate: _fechaEmision,
                                  firstDate: DateTime(2015),
                                  lastDate: DateTime.now(),
                                );
                                if (f != null) {
                                  setState(() => _fechaEmision = f);
                                }
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  suffixIcon: const Icon(
                                    Icons.calendar_today_outlined,
                                    size: 18,
                                  ),
                                ),
                                child: Text(
                                  '${_fechaEmision.day.toString().padLeft(2, '0')}/${_fechaEmision.month.toString().padLeft(2, '0')}/${_fechaEmision.year}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Calculo del Honorario ──────────────────
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
                            'Cálculo del Honorario',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'N° de Boleta:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _numeroBoletaController,
                            decoration: InputDecoration(
                              hintText: 'Ej: 4',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Describir el tipo de trabajo:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _descripcionController,
                            maxLength: 200,
                            decoration: InputDecoration(
                              hintText:
                                  'Ej: Asesoría en desarrollo de software',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const Text(
                            'Honorario Bruto (100%):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _honorarioBrutoController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [MilesInputFormatter()],
                            decoration: InputDecoration(
                              hintText: 'Ej: 200.000',
                              prefixText: '\$ ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (_errorCalculo.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFFECACA),
                                ),
                              ),
                              child: Text(
                                _errorCalculo,
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _calculando
                                  ? null
                                  : _calcularHonorario,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                _calculando
                                    ? 'Calculando...'
                                    : 'Calcular Honorario Líquido',
                              ),
                            ),
                          ),
                          if (_resultado != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _filaResultado(
                                    'Honorario Bruto',
                                    _resultado!['honorario_bruto'],
                                  ),
                                  _filaResultado(
                                    'Retención (${_resultado!['tasa_retencion_aplicada']}%)',
                                    _resultado!['monto_retencion'],
                                    esDescuento: true,
                                  ),
                                  const Divider(height: 20),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFA7F3D0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'HONORARIO LÍQUIDO',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF001E42),
                                        ),
                                      ),
                                      Text(
                                        '\$${formatearMiles(_resultado!['honorario_liquido'])} CLP',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_resultado!['honorario_liquido_palabras'] !=
                                      null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      '(${_resultado!['honorario_liquido_palabras']})',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: Color(0xFF166534),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton.icon(
                                onPressed: _descargandoBoleta
                                    ? null
                                    : _descargarBoletaHonorarios,
                                icon: _descargandoBoleta
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.download_outlined,
                                        size: 18,
                                      ),
                                label: Text(
                                  _descargandoBoleta
                                      ? 'Descargando...'
                                      : 'Descargar Boleta de Honorarios',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF001E42),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filaInfoBoleta(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(child: Text(valor, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _filaResultado(
    String label,
    dynamic monto, {
    bool esDescuento = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
          Text(
            '${esDescuento ? "-" : ""}\$${formatearMiles(monto)} CLP',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: esDescuento
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
