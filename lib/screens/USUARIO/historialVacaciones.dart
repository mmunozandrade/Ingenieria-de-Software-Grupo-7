import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlHist = 'http://127.0.0.1:8000';

class HistorialVacaciones extends StatefulWidget {
  const HistorialVacaciones({super.key});

  @override
  State<HistorialVacaciones> createState() => _HistorialVacacionesState();
}

class _HistorialVacacionesState extends State<HistorialVacaciones> {
  List<Map<String, dynamic>> _historial = [];
  bool   _cargando  = true;
  String _error     = '';
  int?   _anioFiltro;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final token = await SessionService.obtenerToken();
      final params = <String, String>{};
      if (_anioFiltro != null) params['anio'] = _anioFiltro.toString();

      final uri = Uri.parse('$_apiUrlHist/mis-solicitudes-vacaciones')
          .replace(queryParameters: params.isNotEmpty ? params : null);

      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _historial = List<Map<String, dynamic>>.from(data['solicitudes'] ?? []);
        });
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (e) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _descargarRecibo(int idSolicitud) async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlHist/vacaciones/recibo/$idSolicitud'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final blob   = html.Blob([response.bodyBytes], 'application/pdf');
        final url    = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'recibo_vacaciones_$idSolicitud.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Recibo descargado en Descargas'),
            backgroundColor: Colors.green,
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El recibo no esta disponible aun'),
            backgroundColor: Colors.orange,
          ));
        }
      }
    } catch (_) {}
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'Aprobada':  return Colors.green;
      case 'Rechazada': return Colors.red;
      default:          return const Color(0xFFF59E0B);
    }
  }

  Color _bgEstado(String estado) {
    switch (estado) {
      case 'Aprobada':  return const Color(0xFFD1FAE5);
      case 'Rechazada': return const Color(0xFFFEE2E2);
      default:          return const Color(0xFFFEF3C7);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Historial de Vacaciones',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarHistorial,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filtro por anio
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              const Text('Filtrar por ano:', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Ej: 2026',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                  ),
                  onChanged: (v) {
                    final anio = int.tryParse(v);
                    if (anio != null && v.length == 4) {
                      setState(() => _anioFiltro = anio);
                      _cargarHistorial();
                    } else if (v.isEmpty) {
                      setState(() => _anioFiltro = null);
                      _cargarHistorial();
                    }
                  },
                ),
              ),
              if (_anioFiltro != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: Colors.red),
                  onPressed: () { setState(() => _anioFiltro = null); _cargarHistorial(); },
                ),
              ],
              const Spacer(),
              Text(
                '${_historial.length} solicitud${_historial.length == 1 ? '' : 'es'}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ]),
          ),

          // Lista
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF001E42)))
                : _error.isNotEmpty
                    ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
                    : _historial.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.beach_access_outlined, size: 48, color: Color(0xFF94A3B8)),
                                SizedBox(height: 12),
                                Text('No tienes solicitudes de vacaciones',
                                    style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _historial.length,
                            itemBuilder: (context, index) {
                              final s      = _historial[index];
                              final estado = s['estado'] ?? 'Pendiente';
                              final id     = s['id_solicitud'] as int;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(children: [
                                          const Icon(Icons.calendar_today_outlined,
                                              size: 16, color: Color(0xFF64748B)),
                                          const SizedBox(width: 6),
                                          Text(
                                            '${s['fecha_inicio']} - ${s['fecha_fin']}',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          ),
                                        ]),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _bgEstado(estado),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(estado,
                                              style: TextStyle(fontSize: 11,
                                                  color: _colorEstado(estado),
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // Detalles
                                    Wrap(spacing: 24, runSpacing: 8, children: [
                                      _ItemHistorial(label: 'Dias habiles', valor: '${s['dias_habiles']}'),
                                      _ItemHistorial(label: 'Fecha solicitud', valor: s['fecha_solicitud'] ?? '—'),
                                      if (s['fecha_decision'] != null)
                                        _ItemHistorial(label: 'Fecha decision', valor: s['fecha_decision']),
                                    ]),

                                    // Observacion
                                    if (s['observacion'] != null && s['observacion'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFC),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Text(
                                          'Observacion: ${s['observacion']}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                        ),
                                      ),
                                    ],

                                    // Boton descargar si aprobada
                                    if (estado == 'Aprobada') ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 40,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _descargarRecibo(id),
                                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                          label: const Text('Descargar Recibo PDF',
                                              style: TextStyle(fontSize: 13)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF1D4ED8),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ItemHistorial extends StatelessWidget {
  final String label;
  final String valor;
  const _ItemHistorial({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
      ],
    );
  }
}