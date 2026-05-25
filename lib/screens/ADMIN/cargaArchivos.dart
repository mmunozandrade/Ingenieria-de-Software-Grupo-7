import 'dart:typed_data';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/inicial.dart';
import '../../auth/session_service.dart';
import 'registroBonos.dart';
import '../USUARIO/solicitudVacaciones.dart';
import 'asignacionRoles.dart';
import 'calculoHextra.dart';
import '../USUARIO/descargaLiquidacion.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class CargaMasivaArchivosPage extends StatefulWidget {
  const CargaMasivaArchivosPage({super.key});

  @override
  State<CargaMasivaArchivosPage> createState() =>
      _CargaMasivaArchivosPageState();
}

class _CargaMasivaArchivosPageState extends State<CargaMasivaArchivosPage> {
  String? _nombreArchivo;
  Uint8List? _archivoBytes;
  bool _subiendo = false;

  // Resultado del proceso
  int? _procesados;
  int? _errores;
  List<String> _detalleProcessados = [];
  List<String> _detalleErrores = [];
  bool? _exito;
  String _mensaje = '';

  // ── Seleccionar archivo ZIP ───────────────────────────────
  Future<void> _seleccionarArchivoZip() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (resultado == null) return;

    final archivo = resultado.files.single;
    setState(() {
      _nombreArchivo = archivo.name;
      _archivoBytes = archivo.bytes;
      _procesados = null;
      _errores = null;
      _detalleProcessados = [];
      _detalleErrores = [];
      _exito = null;
      _mensaje = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Archivo seleccionado: ${archivo.name}'),
        backgroundColor: const Color(0xFF0F9F8F),
      ),
    );
  }

  // ── Subir ZIP al backend ──────────────────────────────────
  Future<void> _subirArchivo() async {
    if (_nombreArchivo == null || _archivoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero debes seleccionar un archivo .zip'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _subiendo = true;
      _procesados = null;
      _errores = null;
      _exito = null;
      _mensaje = '';
    });

    try {
      final token = await SessionService.obtenerToken();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_apiUrl/subir-liquidaciones'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes(
          'archivo',
          _archivoBytes!,
          filename: _nombreArchivo!,
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);

      setState(() {
        _exito = data['success'] == true;
        _mensaje = data['mensaje'] ?? '';
        _procesados = data['procesados'] ?? 0;
        _errores = data['errores'] ?? 0;
        _detalleProcessados = List<String>.from(
          data['detalle_procesados'] ?? [],
        );
        _detalleErrores = List<String>.from(data['detalle_errores'] ?? []);
      });
    } catch (e) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _subiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Menu Principal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Gestion Administrativa',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
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

      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titulo
                const Text(
                  'Carga Masiva de Archivos',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sube un archivo comprimido (.zip) con las liquidaciones de sueldo de los trabajadores.',
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 32),

                // Requisitos
                const _RequisitosArchivoCard(),
                const SizedBox(height: 32),

                // Zona de carga
                _ZonaCargaArchivo(
                  nombreArchivo: _nombreArchivo,
                  onSeleccionar: _seleccionarArchivoZip,
                ),
                const SizedBox(height: 32),

                // Boton subir
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _subiendo ? null : _subirArchivo,
                    icon: _subiendo
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                      _subiendo ? 'Procesando...' : 'Subir Archivo al Sistema',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF001E42),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Resultado
                if (_exito != null)
                  _ResultadoCarga(
                    exito: _exito!,
                    mensaje: _mensaje,
                    procesados: _procesados ?? 0,
                    errores: _errores ?? 0,
                    detalleProcessados: _detalleProcessados,
                    detalleErrores: _detalleErrores,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tarjeta de requisitos ─────────────────────────────────────
class _RequisitosArchivoCard extends StatelessWidget {
  const _RequisitosArchivoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Requisitos del archivo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                SizedBox(height: 8),
                _BulletText(texto: 'Formato: Archivo .zip'),
                _BulletText(texto: 'Maximo: 50 liquidaciones'),
                _BulletTextConEtiqueta(
                  texto: 'Nomenclatura: ',
                  etiqueta: 'RUT-AAAAMM.pdf',
                ),
                _BulletText(texto: 'Tamano maximo por PDF: 5 MB'),
                _BulletText(texto: 'Ejemplo: 12345678-9-202604.pdf'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Zona de carga ─────────────────────────────────────────────
class _ZonaCargaArchivo extends StatelessWidget {
  final String? nombreArchivo;
  final VoidCallback onSeleccionar;

  const _ZonaCargaArchivo({
    required this.nombreArchivo,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    final bool seleccionado = nombreArchivo != null;
    return InkWell(
      onTap: onSeleccionar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionado
                ? const Color(0xFF0F9F8F)
                : const Color(0xFFCBD5E1),
            width: seleccionado ? 1.8 : 1.4,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Color(0xFFCCFBF1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  seleccionado
                      ? Icons.check_circle_outline
                      : Icons.cloud_upload_outlined,
                  size: 38,
                  color: const Color(0xFF0F9F8F),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                seleccionado
                    ? 'Archivo seleccionado'
                    : 'Arrastra tu archivo .zip aqui',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                seleccionado ? nombreArchivo! : 'o haz clic para seleccionar',
                style: TextStyle(
                  fontSize: 13,
                  color: seleccionado
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF475569),
                  fontWeight: seleccionado
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onSeleccionar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F9F8F),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  seleccionado ? 'Cambiar Archivo' : 'Seleccionar Archivo',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Resultado de la carga ─────────────────────────────────────
class _ResultadoCarga extends StatelessWidget {
  final bool exito;
  final String mensaje;
  final int procesados;
  final int errores;
  final List<String> detalleProcessados;
  final List<String> detalleErrores;

  const _ResultadoCarga({
    required this.exito,
    required this.mensaje,
    required this.procesados,
    required this.errores,
    required this.detalleProcessados,
    required this.detalleErrores,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Banner principal
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: exito ? Colors.green[50] : Colors.red[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: exito ? Colors.green[200]! : Colors.red[200]!,
            ),
          ),
          child: Row(
            children: [
              Icon(
                exito ? Icons.check_circle_outline : Icons.error_outline,
                color: exito ? Colors.green : Colors.red,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mensaje,
                  style: TextStyle(
                    color: exito ? Colors.green[800] : Colors.red[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Contadores
        Row(
          children: [
            _ContadorChip(
              label: 'Procesados',
              valor: procesados,
              color: Colors.green,
            ),
            const SizedBox(width: 12),
            _ContadorChip(
              label: 'Con error',
              valor: errores,
              color: errores > 0 ? Colors.red : Colors.grey,
            ),
          ],
        ),

        // Detalle errores
        if (detalleErrores.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Archivos con error:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...detalleErrores.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.close, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        // Detalle procesados
        if (detalleProcessados.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Archivos procesados:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...detalleProcessados.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    e,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContadorChip extends StatelessWidget {
  final String label;
  final int valor;
  final Color color;

  const _ContadorChip({
    required this.label,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }
}

// ── Bullet helpers ────────────────────────────────────────────
class _BulletText extends StatelessWidget {
  final String texto;
  const _BulletText({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontSize: 14, color: Color(0xFF1D4ED8)),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletTextConEtiqueta extends StatelessWidget {
  final String texto;
  final String etiqueta;
  const _BulletTextConEtiqueta({required this.texto, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontSize: 14, color: Color(0xFF1D4ED8)),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                text: texto,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: Color(0xFF1E3A8A),
                ),
                children: [
                  TextSpan(
                    text: etiqueta,
                    style: const TextStyle(
                      backgroundColor: Color(0xFFDBEAFE),
                      color: Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
