import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlCostos = 'http://127.0.0.1:8000';

/// Informe consolidado de COSTOS TOTALES de remuneraciones del
/// centro clinico, para un periodo especifico: costo total
/// empleador, total sueldos base, total bonos, total descuentos
/// previsionales y total impuesto unico. Exportable a Excel o PDF.
///
/// Con 20-40 trabajadores, el calculo puede tardar varios minutos
/// (recorre a cada trabajador). Para que la pantalla no se quede
/// "pegada" esperando, el calculo corre en SEGUNDO PLANO en el
/// servidor: se inicia un trabajo (job_id) y esta pantalla consulta
/// su estado cada 3 segundos hasta que quede listo.
class InformeConsolidadoCostosScreen extends StatefulWidget {
  const InformeConsolidadoCostosScreen({super.key});

  @override
  State<InformeConsolidadoCostosScreen> createState() =>
      _InformeConsolidadoCostosScreenState();
}

class _InformeConsolidadoCostosScreenState
    extends State<InformeConsolidadoCostosScreen> {
  final _periodoCtrl = TextEditingController();
  bool _iniciando = false;
  bool _procesando = false;
  bool _descargando = false;
  String? _jobId;
  Timer? _timerEstado;
  int _segundosTranscurridos = 0;
  Map<String, dynamic>? _resultado;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _periodoCtrl.text =
        '${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';
  }

  @override
  void dispose() {
    _periodoCtrl.dispose();
    _timerEstado?.cancel();
    super.dispose();
  }

  String get _periodo => _periodoCtrl.text.trim();

  Future<void> _generar() async {
    _timerEstado?.cancel();
    setState(() {
      _iniciando = true;
      _procesando = false;
      _error = '';
      _resultado = null;
      _jobId = null;
      _segundosTranscurridos = 0;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrlCostos/admin/informe-consolidado-costos/iniciar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'periodo': _periodo}),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _jobId = data['job_id'];
          _procesando = true;
        });
        _iniciarConsultaEstado();
      } else {
        setState(
          () => _error = data['mensaje'] ?? 'No se pudo iniciar el informe',
        );
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _iniciando = false);
    }
  }

  void _iniciarConsultaEstado() {
    _timerEstado = Timer.periodic(const Duration(seconds: 3), (_) async {
      setState(() => _segundosTranscurridos += 3);
      try {
        final token = await SessionService.obtenerToken();
        final response = await http.get(
          Uri.parse(
            '$_apiUrlCostos/admin/informe-consolidado-costos/estado/$_jobId',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );
        final data = jsonDecode(response.body);
        if (data['success'] != true) {
          _timerEstado?.cancel();
          setState(() {
            _procesando = false;
            _error =
                data['mensaje'] ?? 'Error al consultar el estado del informe';
          });
          return;
        }
        if (data['estado'] == 'listo') {
          _timerEstado?.cancel();
          setState(() {
            _procesando = false;
            _resultado = data;
          });
        } else if (data['estado'] == 'error') {
          _timerEstado?.cancel();
          setState(() {
            _procesando = false;
            _error = data['mensaje'] ?? 'No se pudo generar el informe';
          });
        }
        // si sigue "procesando", no se hace nada, se sigue esperando
      } catch (_) {
        // error de red puntual al consultar: se reintenta en el proximo tick
      }
    });
  }

  Future<void> _descargar(String formato) async {
    if (_jobId == null) return;
    setState(() => _descargando = true);
    try {
      final token = await SessionService.obtenerToken();
      final endpoint = formato == 'excel'
          ? 'informe-consolidado-costos/excel/$_jobId'
          : 'informe-consolidado-costos/pdf/$_jobId';
      final response = await http.get(
        Uri.parse('$_apiUrlCostos/admin/$endpoint'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 &&
          response.headers['content-type']?.contains('json') != true) {
        final ext = formato == 'excel' ? 'xlsx' : 'pdf';
        final blob = html.Blob([response.bodyBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute(
            'download',
            'informe_consolidado_costos_${_periodo.replaceAll('/', '-')}.$ext',
          )
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['mensaje'] ?? 'Error al descargar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar al servidor'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _descargando = false);
    }
  }

  String _formatearMiles(dynamic valor) {
    final soloDigitos = valor.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) return '0';
    final buffer = StringBuffer();
    for (int i = 0; i < soloDigitos.length; i++) {
      final posicionDesdeDerecha = soloDigitos.length - i;
      buffer.write(soloDigitos[i]);
      if (posicionDesdeDerecha > 1 && posicionDesdeDerecha % 3 == 1)
        buffer.write('.');
    }
    return buffer.toString();
  }

  Widget _filaTotal(String titulo, dynamic valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: destacado ? 15 : 13.5,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
              color: destacado
                  ? const Color(0xFF001E42)
                  : const Color(0xFF475569),
            ),
          ),
          Text(
            '\$${_formatearMiles(valor)} CLP',
            style: TextStyle(
              fontSize: destacado ? 17 : 14,
              fontWeight: FontWeight.bold,
              color: destacado
                  ? const Color(0xFF059669)
                  : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Informe Consolidado de Costos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Text(
                    'Genera el costo total consolidado de remuneraciones de toda la clínica para un período: costo total empleador, '
                    'sueldos base, bonos, descuentos previsionales e impuesto único, sumados entre todos los trabajadores. '
                    'Con muchos trabajadores puede tardar varios minutos: el cálculo corre en segundo plano, así que puedes esperar aquí sin que se congele la pantalla.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF065F46),
                      height: 1.4,
                    ),
                  ),
                ),

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
                        'Período (MM/AAAA)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF001E42),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _periodoCtrl,
                              enabled: !_procesando,
                              decoration: InputDecoration(
                                hintText: 'MM/AAAA',
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: (_iniciando || _procesando)
                                ? null
                                : _generar,
                            icon: _iniciando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search, size: 18),
                            label: const Text('Generar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF001E42),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                if (_procesando)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text(
                          'Generando el informe...',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF001E42),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tiempo transcurrido: ${_segundosTranscurridos}s — puede tardar varios minutos con muchos trabajadores',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (_error.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),

                if (_resultado != null)
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
                        Text(
                          'Período ${_resultado!['periodo']} · ${_resultado!['cantidad_trabajadores']} trabajadores',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const Divider(height: 24),
                        _filaTotal(
                          'Total sueldos base',
                          _resultado!['sueldo_base_total'],
                        ),
                        _filaTotal(
                          'Total de bonos',
                          _resultado!['bonos_total'],
                        ),
                        _filaTotal(
                          'Total descuentos previsionales',
                          _resultado!['descuentos_previsionales_total'],
                        ),
                        _filaTotal(
                          'Total impuesto único',
                          _resultado!['impuesto_unico_total'],
                        ),
                        const Divider(height: 24),
                        _filaTotal(
                          'COSTO TOTAL EMPLEADOR',
                          _resultado!['costo_total_empleador'],
                          destacado: true,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _descargando
                                    ? null
                                    : () => _descargar('excel'),
                                icon: const Icon(
                                  Icons.grid_on,
                                  size: 16,
                                  color: Color(0xFF059669),
                                ),
                                label: const Text(
                                  'Excel',
                                  style: TextStyle(color: Color(0xFF059669)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _descargando
                                    ? null
                                    : () => _descargar('pdf'),
                                icon: const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 16,
                                  color: Color(0xFFDC2626),
                                ),
                                label: const Text(
                                  'PDF',
                                  style: TextStyle(color: Color(0xFFDC2626)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'La descarga es instantánea: usa los datos ya calculados, no vuelve a recalcular.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
