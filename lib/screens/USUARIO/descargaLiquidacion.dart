import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlDesc = 'http://127.0.0.1:8000';

class DescargaLiquidacion extends StatefulWidget {
  const DescargaLiquidacion({super.key});

  @override
  State<DescargaLiquidacion> createState() => _DescargaLiquidacionState();
}

class _DescargaLiquidacionState extends State<DescargaLiquidacion> {
  String _nombre = '';
  String _rut    = '';
  String _cargo  = '';

  List<Map<String, dynamic>> _liquidaciones = [];

  bool   _cargando          = true;
  String _error             = '';
  int?   _descargandoId     = null;
  int?   _previsualizandoId = null;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final token   = await SessionService.obtenerToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Cargar ficha del trabajador
      final fichaResp = await http.get(Uri.parse('$_apiUrlDesc/mi-ficha'), headers: headers);
      final fichaData = jsonDecode(fichaResp.body);
      if (fichaData['success'] == true) {
        setState(() {
          _nombre = fichaData['nombre_completo'] ?? '';
          _rut    = fichaData['rut'] ?? '';
          _cargo  = fichaData['cargo'] ?? '';
        });
      }

      // Cargar liquidaciones
      final liqResp = await http.get(Uri.parse('$_apiUrlDesc/mis-liquidaciones'), headers: headers);
      final liqData = jsonDecode(liqResp.body);
      if (liqData['success'] == true) {
        final lista = List<Map<String, dynamic>>.from(liqData['liquidaciones'] ?? []);

        // Ordenar cronológicamente de más nueva a más antigua
        lista.sort((a, b) {
          final periodoA = a['periodo'] ?? '';
          final periodoB = b['periodo'] ?? '';
          try {
            final partsA = periodoA.split('/');
            final partsB = periodoB.split('/');
            final dateA  = DateTime(int.parse(partsA[1]), int.parse(partsA[0]));
            final dateB  = DateTime(int.parse(partsB[1]), int.parse(partsB[0]));
            return dateB.compareTo(dateA);
          } catch (_) {
            return periodoB.compareTo(periodoA);
          }
        });

        setState(() => _liquidaciones = lista);
      }
    } catch (e) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  // ── Mostrar SnackBar helper ───────────────────────────────
  void _mostrarSnackBar(String mensaje, Color color, IconData icono) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(icono, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(mensaje, style: const TextStyle(fontSize: 13))),
        ]),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ── Manejar respuesta del servidor ────────────────────────
  bool _manejarErrorRespuesta(http.Response response, String accion) {
    if (response.statusCode == 403 || response.statusCode == 404) {
      // Excepcion 1: Liquidacion no disponible
      _mostrarSnackBar(
        'Liquidacion no disponible.',
        Colors.orange,
        Icons.block_outlined,
      );
      return false;
    }
    if (response.statusCode != 200 ||
        response.headers['content-type']?.contains('application/pdf') != true) {
      // Excepcion 2: Error de servidor o archivo no encontrado
      _mostrarSnackBar(
        'Error al descargar la liquidacion, por favor intente mas tarde.',
        Colors.red,
        Icons.error_outline,
      );
      return false;
    }
    return true;
  }

  // ── Previsualizar PDF en nueva pestaña del navegador ──────
  Future<void> _previsualizarPDF(int id, String nombreArchivo, bool disponible) async {
    // Excepcion 1: Estado no disponible — deshabilitar antes de llamar
    if (!disponible) {
      _mostrarSnackBar('Liquidacion no disponible.', Colors.orange, Icons.block_outlined);
      return;
    }

    setState(() => _previsualizandoId = id);
    try {
      final token    = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlDesc/descargar-liquidacion/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!_manejarErrorRespuesta(response, 'previsualizar')) return;

      final blob = html.Blob([response.bodyBytes], 'application/pdf');
      final url  = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');

      Future.delayed(const Duration(seconds: 5), () {
        html.Url.revokeObjectUrl(url);
      });

      _mostrarSnackBar(
        '$nombreArchivo abierto en nueva pestaña',
        const Color(0xFF001E42),
        Icons.visibility_outlined,
      );
    } catch (_) {
      // Excepcion 2: Error de conexion
      _mostrarSnackBar(
        'Error al descargar la liquidacion, por favor intente mas tarde.',
        Colors.red,
        Icons.error_outline,
      );
    } finally {
      setState(() => _previsualizandoId = null);
    }
  }

  // ── Descargar PDF directo en el navegador ─────────────────
  Future<void> _descargarPDF(int id, String nombreArchivo, bool disponible) async {
    // Excepcion 1: Estado no disponible — deshabilitar antes de llamar
    if (!disponible) {
      _mostrarSnackBar('Liquidacion no disponible.', Colors.orange, Icons.block_outlined);
      return;
    }

    setState(() => _descargandoId = id);
    try {
      final token    = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlDesc/descargar-liquidacion/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!_manejarErrorRespuesta(response, 'descargar')) return;

      final blob   = html.Blob([response.bodyBytes], 'application/pdf');
      final url    = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', nombreArchivo)
        ..click();
      html.Url.revokeObjectUrl(url);

      _mostrarSnackBar(
        '$nombreArchivo descargado en tu carpeta de Descargas',
        Colors.green,
        Icons.check_circle_outline,
      );
    } catch (_) {
      // Excepcion 2: Error de conexion
      _mostrarSnackBar(
        'Error al descargar la liquidacion, por favor intente mas tarde.',
        Colors.red,
        Icons.error_outline,
      );
    } finally {
      setState(() => _descargandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mis Liquidaciones',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF001E42)))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // Titulo
                      const Text('Mis Liquidaciones',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      const SizedBox(height: 8),
                      const Text('Revisa, previsualiza y descarga tus liquidaciones de sueldo mensuales.',
                          style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
                      const SizedBox(height: 32),

                      // Tarjeta perfil
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                        ),
                        child: Wrap(
                          spacing: 32, runSpacing: 16,
                          children: [
                            _InfoPerfil(icono: Icons.person_outline, etiqueta: 'Trabajador', valor: _nombre.isEmpty ? '—' : _nombre),
                            _InfoPerfil(icono: Icons.badge_outlined,  etiqueta: 'RUT',        valor: _rut.isEmpty ? '—' : _rut),
                            _InfoPerfil(icono: Icons.work_outline,    etiqueta: 'Cargo',      valor: _cargo.isEmpty ? '—' : _cargo),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Error de carga
                      if (_error.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red[50], borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Text(_error, style: const TextStyle(color: Colors.red)),
                        ),

                      // Encabezado tabla
                      if (_liquidaciones.isNotEmpty) ...[
                        Row(children: [
                          const Text('Historial de Liquidaciones',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                          const Spacer(),
                          Text('${_liquidaciones.length} documento${_liquidaciones.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        ]),
                        const SizedBox(height: 4),
                        const Text(
                          'Ordenado del más reciente al más antiguo · Haz clic en Ver para previsualizar en el navegador',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 16),

                        // Encabezado columnas
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF001E42),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: const Row(children: [
                            Expanded(flex: 2, child: Text('Periodo',   style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 2, child: Text('Documento', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 1, child: Text('Estado',    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            Expanded(flex: 2, child: Text('Acciones',  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center)),
                          ]),
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Sin liquidaciones
                      if (_liquidaciones.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(children: [
                            Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF94A3B8)),
                            SizedBox(height: 12),
                            Text('No tienes liquidaciones disponibles aun.',
                                style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
                            SizedBox(height: 4),
                            Text('El administrador debe subir tus liquidaciones.',
                                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                          ]),
                        ),

                      // Lista de liquidaciones
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _liquidaciones.length,
                        itemBuilder: (context, index) {
                          final liq = _liquidaciones[index];
                          final bool esDescargando     = _descargandoId == liq['id'];
                          final bool esPrevisualizando = _previsualizandoId == liq['id'];

                          // Estado disponible desde la BD (default true si no viene)
                          final bool disponible = liq['disponible'] != false;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: index % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(children: [

                                // Periodo MM/AAAA
                                Expanded(
                                  flex: 2,
                                  child: Row(children: [
                                    const Icon(Icons.calendar_month_outlined, size: 16, color: Color(0xFF64748B)),
                                    const SizedBox(width: 8),
                                    Text(liq['periodo'] ?? '—',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                  ]),
                                ),

                                // Nombre documento
                                Expanded(
                                  flex: 2,
                                  child: Row(children: [
                                    const Icon(Icons.picture_as_pdf, size: 16, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(liq['nombre_archivo'] ?? '—',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ]),
                                ),

                                // Estado
                                Expanded(
                                  flex: 1,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: disponible ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      disponible ? 'Disponible' : 'No disponible',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: disponible ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),

                                // Acciones
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [

                                      // Boton Ver
                                      OutlinedButton.icon(
                                        // Excepcion 1: deshabilitar si no disponible
                                        onPressed: (!disponible || esPrevisualizando)
                                            ? null
                                            : () => _previsualizarPDF(liq['id'], liq['nombre_archivo'], disponible),
                                        icon: esPrevisualizando
                                            ? const SizedBox(width: 14, height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF001E42)))
                                            : const Icon(Icons.visibility_outlined, size: 15),
                                        label: Text(esPrevisualizando ? '...' : 'Ver',
                                            style: const TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: disponible ? const Color(0xFF001E42) : const Color(0xFF94A3B8),
                                          side: BorderSide(color: disponible ? const Color(0xFF001E42) : const Color(0xFFCBD5E1)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Boton Descargar
                                      ElevatedButton.icon(
                                        // Excepcion 1: deshabilitar si no disponible
                                        onPressed: (!disponible || esDescargando)
                                            ? null
                                            : () => _descargarPDF(liq['id'], liq['nombre_archivo'], disponible),
                                        icon: esDescargando
                                            ? const SizedBox(width: 14, height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                            : const Icon(Icons.file_download_outlined, size: 15),
                                        label: Text(esDescargando ? '...' : 'Descargar',
                                            style: const TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: disponible ? const Color(0xFF009A8D) : const Color(0xFF94A3B8),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────
class _InfoPerfil extends StatelessWidget {
  final IconData icono;
  final String   etiqueta;
  final String   valor;

  const _InfoPerfil({required this.icono, required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 20, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiqueta, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            Text(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          ],
        ),
      ],
    );
  }
}