import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const String _apiUrl = 'http://127.0.0.1:8000';

class MisCompensaciones extends StatefulWidget {
  const MisCompensaciones({super.key});

  @override
  State<MisCompensaciones> createState() => _MisCompensacionesState();
}

class _MisCompensacionesState extends State<MisCompensaciones> {
  List<dynamic> _compensaciones = [];
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargarCompensaciones();
  }

  Future<void> _cargarCompensaciones() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/mis-compensaciones-progresivas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _compensaciones = data['compensaciones'] ?? []);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  // ── Previsualizar PDF ─────────────────────────────────────
  Future<void> _previsualizarPDF(int compensacionId) async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/comprobante-compensacion/$compensacionId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 &&
          response.headers['content-type']?.contains('application/pdf') ==
              true) {
        final blob = html.Blob([response.bodyBytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.window.open(url, 'comprobante_compensacion_$compensacionId');
        Future.delayed(const Duration(seconds: 5), () {
          html.Url.revokeObjectUrl(url);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo abrir el comprobante'),
              backgroundColor: Colors.orange,
            ),
          );
        }
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

  // ── Descargar PDF ─────────────────────────────────────────
  Future<void> _descargarPDF(int compensacionId) async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/comprobante-compensacion/$compensacionId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final blob = html.Blob([bytes], 'application/pdf');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute(
            'download',
            'comprobante_compensacion_$compensacionId.pdf',
          )
          ..click();
        html.Url.revokeObjectUrl(url);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al descargar el comprobante'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
    final aprobadas = _compensaciones
        .where((c) => c['estado'] == 'Aprobado')
        .toList();
    final otras = _compensaciones
        .where((c) => c['estado'] != 'Aprobado')
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Mis Compensaciones',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarCompensaciones,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)),
            )
          : _error.isNotEmpty
          ? Center(
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;
                final bool esEscritorio = ancho >= 1280;
                final bool esTablet = ancho >= 768 && ancho < 1280;
                final double paddingHorizontal = esEscritorio
                    ? 40
                    : (esTablet ? 28 : 24);
                final double maxWidthContenido = esEscritorio
                    ? 900
                    : (esTablet ? 720 : double.infinity);

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
                          // Titulo
                          const Text(
                            'Mis Compensaciones Progresivas',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Historial de solicitudes de compensacion en efectivo por dias progresivos',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Resumen tarjetas
                          Row(
                            children: [
                              Expanded(
                                child: _TarjetaResumen(
                                  titulo: 'Aprobadas',
                                  valor: '${aprobadas.length}',
                                  color: const Color(0xFF059669),
                                  bgColor: const Color(0xFFECFDF5),
                                  icono: Icons.check_circle_outline,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _TarjetaResumen(
                                  titulo: 'Pendientes',
                                  valor:
                                      '${_compensaciones.where((c) => c['estado'] == 'Pendiente').length}',
                                  color: const Color(0xFFD97706),
                                  bgColor: const Color(0xFFFFFBEB),
                                  icono: Icons.hourglass_empty_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _TarjetaResumen(
                                  titulo: 'Total CLP',
                                  valor:
                                      '\$${aprobadas.fold<int>(0, (sum, c) => sum + (c['monto_clp'] as int))}',
                                  color: const Color(0xFF7C3AED),
                                  bgColor: const Color(0xFFF5F3FF),
                                  icono: Icons.payments_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Lista aprobadas
                          if (aprobadas.isNotEmpty) ...[
                            const Text(
                              'Pagos Aprobados',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...aprobadas.map(
                              (c) => _TarjetaCompensacion(
                                comp: c,
                                onVisualizar: () =>
                                    _previsualizarPDF(c['compensacion_id']),
                                onDescargar: () =>
                                    _descargarPDF(c['compensacion_id']),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Lista otras (pendientes/rechazadas)
                          if (otras.isNotEmpty) ...[
                            const Text(
                              'Otras Solicitudes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...otras.map(
                              (c) => _TarjetaCompensacion(
                                comp: c,
                                onVisualizar: null,
                                onDescargar: null,
                              ),
                            ),
                          ],

                          // Sin compensaciones
                          if (_compensaciones.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.payments_outlined,
                                    size: 48,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No tienes compensaciones registradas',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 14,
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

// ── Tarjeta resumen ───────────────────────────────────────────
class _TarjetaResumen extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;
  final Color bgColor;
  final IconData icono;

  const _TarjetaResumen({
    required this.titulo,
    required this.valor,
    required this.color,
    required this.bgColor,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            valor,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            titulo,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta compensacion ──────────────────────────────────────
class _TarjetaCompensacion extends StatelessWidget {
  final Map<String, dynamic> comp;
  final VoidCallback? onVisualizar;
  final VoidCallback? onDescargar;

  const _TarjetaCompensacion({
    required this.comp,
    required this.onVisualizar,
    required this.onDescargar,
  });

  @override
  Widget build(BuildContext context) {
    final estado = comp['estado'] ?? 'Pendiente';
    final bool aprobada = estado == 'Aprobado';

    final Color colorEstado;
    final Color bgEstado;
    final IconData iconoEstado;

    switch (estado) {
      case 'Aprobado':
        colorEstado = const Color(0xFF059669);
        bgEstado = const Color(0xFFECFDF5);
        iconoEstado = Icons.check_circle_outline;
        break;
      case 'Rechazado':
        colorEstado = Colors.red;
        bgEstado = const Color(0xFFFEF2F2);
        iconoEstado = Icons.cancel_outlined;
        break;
      default:
        colorEstado = const Color(0xFFD97706);
        bgEstado = const Color(0xFFFFFBEB);
        iconoEstado = Icons.hourglass_empty_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bgEstado,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconoEstado, color: colorEstado, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${comp['dias_compensados']} día(s) compensado(s)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Solicitado: ${comp['fecha_solicitud']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bgEstado,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorEstado,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Detalle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FilaInfo(
                label: 'Monto:',
                valor: '\$${comp['monto_clp']} CLP',
                valorStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF059669),
                ),
              ),
              if (comp['fecha_decision'] != null)
                _FilaInfo(label: 'Aprobado:', valor: comp['fecha_decision']),
            ],
          ),
          if (comp['observacion'] != null &&
              comp['observacion'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Observación: ${comp['observacion']}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          // Botones solo si aprobada
          if (aprobada) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Visualizar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1D4ED8),
                      side: const BorderSide(color: Color(0xFF1D4ED8)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: onVisualizar,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Descargar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF001E42),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: onDescargar,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaInfo extends StatelessWidget {
  final String label;
  final String valor;
  final TextStyle? valorStyle;

  const _FilaInfo({required this.label, required this.valor, this.valorStyle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          valor,
          style:
              valorStyle ??
              const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
        ),
      ],
    );
  }
}
