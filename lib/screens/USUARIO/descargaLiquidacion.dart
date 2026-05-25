import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/inicial.dart';
import '../../auth/session_service.dart';
import '../ADMIN/cargaArchivos.dart';
import '../ADMIN/registroBonos.dart';
import 'solicitudVacaciones.dart';
import '../ADMIN/asignacionRoles.dart';
import '../ADMIN/calculoHextra.dart';

const String _apiUrlDesc = 'http://127.0.0.1:8000';

class DescargaLiquidacion extends StatefulWidget {
  const DescargaLiquidacion({super.key});

  @override
  State<DescargaLiquidacion> createState() => _DescargaLiquidacionState();
}

class _DescargaLiquidacionState extends State<DescargaLiquidacion> {
  String _nombre = '';
  String _rut = '';
  String _cargo = '';

  List<Map<String, dynamic>> _liquidaciones = [];

  bool _cargando = true;
  String _error = '';

  // Para mostrar spinner por liquidacion
  int? _descargandoId;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Cargar ficha del trabajador
      final fichaResp = await http.get(
        Uri.parse('$_apiUrlDesc/mi-ficha'),
        headers: headers,
      );
      final fichaData = jsonDecode(fichaResp.body);
      if (fichaData['success'] == true) {
        setState(() {
          _nombre = fichaData['nombre_completo'] ?? '';
          _rut = fichaData['rut'] ?? '';
          _cargo = fichaData['cargo'] ?? '';
        });
      }

      // Cargar liquidaciones
      final liqResp = await http.get(
        Uri.parse('$_apiUrlDesc/mis-liquidaciones'),
        headers: headers,
      );
      final liqData = jsonDecode(liqResp.body);
      if (liqData['success'] == true) {
        setState(() {
          _liquidaciones = List<Map<String, dynamic>>.from(
            liqData['liquidaciones'] ?? [],
          );
        });
      }
    } catch (e) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  // ── Descargar PDF directo en el navegador ─────────────────
  Future<void> _descargarPDF(int id, String nombreArchivo) async {
    setState(() => _descargandoId = id);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlDesc/descargar-liquidacion/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        // Crear blob con los bytes del PDF
        final blob = html.Blob([response.bodyBytes], 'application/pdf');

        // Crear URL temporal del blob
        final url = html.Url.createObjectUrlFromBlob(blob);

        // Crear elemento <a> invisible y hacer clic para descargar
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', nombreArchivo)
          ..click();

        // Liberar la URL temporal
        html.Url.revokeObjectUrl(url);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Text('$nombreArchivo descargado en tu carpeta de Descargas'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        throw Exception('Error al descargar');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al descargar el archivo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _descargandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Clinica Aconcagua',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF001E42)),
              child: Text(
                'Menu Principal',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Inicio'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Solicitud de Vacaciones'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SolicitudVacaciones()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Mis Liquidaciones'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DescargaLiquidacion()),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Registro de Bonos'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RegistrarBonos()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Calculo de Horas Extra'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CalculoHextra()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Asignacion de Roles'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const AsignacionRoles()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carga de Archivos'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const CargaMasivaArchivosPage(),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesion',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {},
            ),
          ],
        ),
      ),

      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titulo
                      const Text(
                        'Mis Liquidaciones',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Revisa, descarga y administra tus liquidaciones de sueldo mensuales.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Tarjeta perfil
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                            width: 1.2,
                          ),
                        ),
                        child: Wrap(
                          spacing: 32,
                          runSpacing: 16,
                          children: [
                            _InfoPerfil(
                              icono: Icons.person_outline,
                              etiqueta: 'Trabajador',
                              valor: _nombre.isEmpty ? '—' : _nombre,
                            ),
                            _InfoPerfil(
                              icono: Icons.badge_outlined,
                              etiqueta: 'RUT',
                              valor: _rut.isEmpty ? '—' : _rut,
                            ),
                            _InfoPerfil(
                              icono: Icons.work_outline,
                              etiqueta: 'Cargo',
                              valor: _cargo.isEmpty ? '—' : _cargo,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),

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
                          child: Text(
                            _error,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),

                      // Titulo documentos
                      const Text(
                        'Documentos Disponibles',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Sin liquidaciones
                      if (_liquidaciones.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: Color(0xFF94A3B8),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No tienes liquidaciones disponibles aun.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'El administrador debe subir tus liquidaciones.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Lista de liquidaciones
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _liquidaciones.length,
                        itemBuilder: (context, index) {
                          final liq = _liquidaciones[index];
                          final bool esDescargando =
                              _descargandoId == liq['id'];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: Border.all(
                                color: const Color(0xFFF1F5F9),
                                width: 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final bool isMobile =
                                      constraints.maxWidth < 400;
                                  return Flex(
                                    direction: isMobile
                                        ? Axis.vertical
                                        : Axis.horizontal,
                                    crossAxisAlignment: isMobile
                                        ? CrossAxisAlignment.start
                                        : CrossAxisAlignment.center,
                                    children: [
                                      // Icono PDF
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.picture_as_pdf,
                                          color: Color(0xFFEF4444),
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      // Datos
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Liquidacion de Sueldo - ${liq['periodo']}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Subida el ${liq['fecha_subida']} • ${liq['tamano_kb']} KB',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (isMobile) const SizedBox(height: 16),

                                      // Boton descargar
                                      SizedBox(
                                        width: isMobile
                                            ? double.infinity
                                            : null,
                                        child: ElevatedButton.icon(
                                          onPressed: esDescargando
                                              ? null
                                              : () => _descargarPDF(
                                                  liq['id'],
                                                  liq['nombre_archivo'],
                                                ),
                                          icon: esDescargando
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.file_download_outlined,
                                                  size: 20,
                                                ),
                                          label: Text(
                                            esDescargando
                                                ? 'Descargando...'
                                                : 'Descargar',
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF009A8D,
                                            ),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _InfoPerfil extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;

  const _InfoPerfil({
    required this.icono,
    required this.etiqueta,
    required this.valor,
  });

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
            Text(
              etiqueta,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            Text(
              valor,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
