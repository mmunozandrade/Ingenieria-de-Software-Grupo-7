import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlAprob = 'http://127.0.0.1:8000';

class AprobarSolicitudesV extends StatefulWidget {
  const AprobarSolicitudesV({super.key});

  @override
  State<AprobarSolicitudesV> createState() => _AprobarSolicitudesVState();
}

class _AprobarSolicitudesVState extends State<AprobarSolicitudesV> {
  String _filtro        = 'Pendiente';
  bool   _cargando      = true;
  String _error         = '';
  int?   _anioFiltro;

  List<Map<String, dynamic>> _solicitudes = [];

  // Observaciones por solicitud
  final Map<int, TextEditingController> _obsControllers = {};
  final Map<int, bool> _procesando = {};

  @override
  void initState() {
    super.initState();
    _cargarSolicitudes();
  }

  @override
  void dispose() {
    for (final c in _obsControllers.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _cargarSolicitudes() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final token = await SessionService.obtenerToken();
      final params = <String, String>{'estado': _filtro};
      if (_anioFiltro != null) params['anio'] = _anioFiltro.toString();

      final uri = Uri.parse('$_apiUrlAprob/admin/solicitudes-vacaciones')
          .replace(queryParameters: params);

      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      });

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _solicitudes = List<Map<String, dynamic>>.from(data['solicitudes'] ?? []);
          // Inicializar controladores de observacion
          for (final s in _solicitudes) {
            final id = s['id_solicitud'] as int;
            _obsControllers[id] ??= TextEditingController();
          }
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

  Future<void> _decidir(Map<String, dynamic> s, String decision) async {
    final id          = s['id_solicitud'] as int;
    final observacion = _obsControllers[id]?.text.trim() ?? '';

    // Validar observacion obligatoria al rechazar
    if (decision == 'Rechazada') {
      if (observacion.length < 10) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La observacion es obligatoria al rechazar (minimo 10 caracteres)'),
          backgroundColor: Colors.red,
        ));
        return;
      }
      if (observacion.length > 500) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La observacion no puede superar 500 caracteres'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    setState(() => _procesando[id] = true);

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrlAprob/admin/solicitudes-vacaciones/$id'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'estado':      decision,
          'observacion': observacion,
        }),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(decision == 'Aprobada'
              ? 'Solicitud aprobada correctamente'
              : 'Solicitud rechazada'),
          backgroundColor: decision == 'Aprobada' ? Colors.green : Colors.red,
        ));

        // Si aprobada, descargar PDF automaticamente
        if (decision == 'Aprobada' && data['pdf_disponible'] == true) {
          await _descargarPDF(id, s['nombre'] ?? 'trabajador');
        }

        _cargarSolicitudes();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['mensaje'] ?? 'Error al procesar'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo conectar al servidor'),
        backgroundColor: Colors.red,
      ));
    } finally {
      setState(() => _procesando[id] = false);
    }
  }

  Future<void> _descargarPDF(int idSolicitud, String nombreTrabajador) async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlAprob/vacaciones/recibo/$idSolicitud'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final blob = html.Blob([response.bodyBytes], 'application/pdf');
        final url  = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'recibo_vacaciones_$idSolicitud.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Recibo PDF descargado en Descargas'),
            backgroundColor: Colors.green,
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Aprobacion y Rechazo de Solicitudes',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Panel de Administrador',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                Text('Gestion de Solicitudes',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [

              // Logo centrado
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Image.asset('assets/Logo.png', height: 70),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Filtros estado
                      Row(children: [
                        _FiltroBtn(texto: 'Pendiente',  activo: _filtro == 'Pendiente',
                            onTap: () { setState(() => _filtro = 'Pendiente'); _cargarSolicitudes(); }),
                        const SizedBox(width: 10),
                        _FiltroBtn(texto: 'Aprobada',   activo: _filtro == 'Aprobada',
                            onTap: () { setState(() => _filtro = 'Aprobada'); _cargarSolicitudes(); }),
                        const SizedBox(width: 10),
                        _FiltroBtn(texto: 'Rechazada',  activo: _filtro == 'Rechazada',
                            onTap: () { setState(() => _filtro = 'Rechazada'); _cargarSolicitudes(); }),
                        const SizedBox(width: 10),
                        _FiltroBtn(texto: 'Todas',      activo: _filtro == 'Todas',
                            onTap: () { setState(() => _filtro = 'Todas'); _cargarSolicitudes(); }),
                      ]),
                      const SizedBox(height: 12),

                      // Filtro por anio
                      Row(children: [
                        const Text('Filtrar por ano:', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 100,
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
                                _cargarSolicitudes();
                              } else if (v.isEmpty) {
                                setState(() => _anioFiltro = null);
                                _cargarSolicitudes();
                              }
                            },
                          ),
                        ),
                        if (_anioFiltro != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () { setState(() => _anioFiltro = null); _cargarSolicitudes(); },
                          ),
                        ],
                      ]),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 16),

                      // Error
                      if (_error.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Text(_error, style: const TextStyle(color: Colors.red)),
                        ),

                      // Lista
                      if (_cargando)
                        const Center(child: CircularProgressIndicator(color: Color(0xFF1D4ED8)))
                      else if (_solicitudes.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Text('No hay solicitudes en esta categoria.',
                                style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                          ),
                        )
                      else
                        Column(
                          children: _solicitudes.map((s) {
                            final id = s['id_solicitud'] as int;
                            _obsControllers[id] ??= TextEditingController();
                            final bool expandida = s['expandida'] == true;
                            final bool pendiente = s['estado'] == 'Pendiente';
                            final bool proc      = _procesando[id] == true;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: InkWell(
                                onTap: () => setState(() => s['expandida'] = !expandida),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: expandida ? const Color(0xFFEFF6FF) : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: expandida ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                                      width: expandida ? 1.5 : 1.2,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header tarjeta
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  crossAxisAlignment: WrapCrossAlignment.center,
                                                  spacing: 10,
                                                  children: [
                                                    Text(s['nombre'] ?? '—',
                                                        style: const TextStyle(fontSize: 16,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFF0F172A))),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: _bgEstado(s['estado'] ?? ''),
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: Text(s['estado'] ?? '—',
                                                          style: TextStyle(fontSize: 11,
                                                              color: _colorEstado(s['estado'] ?? ''),
                                                              fontWeight: FontWeight.w600)),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text('Cargo: ${s['cargo'] ?? '—'}',
                                                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              const Text('Fecha solicitud:',
                                                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                              Text(s['fecha_solicitud'] ?? '—',
                                                  style: const TextStyle(fontSize: 13,
                                                      fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Datos solicitud
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Wrap(
                                          runSpacing: 12,
                                          spacing: 24,
                                          children: [
                                            _Dato(titulo: 'Periodo:', valor: '${s['fecha_inicio']} - ${s['fecha_fin']}'),
                                            _Dato(titulo: 'Dias habiles:', valor: '${s['dias_habiles']} dias'),
                                            _Dato(titulo: 'Saldo actual:', valor: '${s['saldo_actual']} dias'),
                                            _Dato(titulo: 'Saldo despues:', valor: '${s['saldo_despues']} dias'),
                                            if (s['observacion'] != null && s['observacion'].toString().isNotEmpty)
                                              _Dato(titulo: 'Observacion:', valor: s['observacion']),
                                            if (s['fecha_decision'] != null)
                                              _Dato(titulo: 'Fecha decision:', valor: s['fecha_decision']),
                                          ],
                                        ),
                                      ),

                                      // Botones si esta expandida y pendiente
                                      if (expandida && pendiente) ...[
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Observacion (opcional para aprobar, obligatoria para rechazar - minimo 10 caracteres):',
                                          style: TextStyle(fontSize: 13, color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _obsControllers[id],
                                          maxLines: 3,
                                          maxLength: 500,
                                          decoration: InputDecoration(
                                            hintText: 'Ingrese observacion...',
                                            filled: true,
                                            fillColor: const Color(0xFFF8FAFC),
                                            contentPadding: const EdgeInsets.all(14),
                                            enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                                            focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.4)),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: 48,
                                              child: ElevatedButton.icon(
                                                onPressed: proc ? null : () => _decidir(s, 'Aprobada'),
                                                icon: proc
                                                    ? const SizedBox(width: 16, height: 16,
                                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                                    : const Icon(Icons.check, size: 18),
                                                label: const Text('Aprobar Solicitud'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF0F9F8F),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: SizedBox(
                                              height: 48,
                                              child: ElevatedButton.icon(
                                                onPressed: proc ? null : () => _decidir(s, 'Rechazada'),
                                                icon: const Icon(Icons.close, size: 18),
                                                label: const Text('Rechazar Solicitud'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFFEF4444),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ]),
                                      ],

                                      // Boton descargar recibo si aprobada
                                      if (expandida && s['estado'] == 'Aprobada') ...[
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 44,
                                          child: ElevatedButton.icon(
                                            onPressed: () => _descargarPDF(id, s['nombre'] ?? ''),
                                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                            label: const Text('Descargar Recibo PDF'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF1D4ED8),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltroBtn extends StatelessWidget {
  final String     texto;
  final bool       activo;
  final VoidCallback onTap;
  const _FiltroBtn({required this.texto, required this.activo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: activo ? const Color(0xFF1D4ED8) : const Color(0xFFF1F5F9),
        foregroundColor: activo ? Colors.white : const Color(0xFF475569),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}

class _Dato extends StatelessWidget {
  final String titulo;
  final String valor;
  const _Dato({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(valor, style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A))),
      ],
    );
  }
}