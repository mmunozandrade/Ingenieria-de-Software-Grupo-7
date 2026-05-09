import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'inicial.dart';
import 'registroBonos.dart';
import 'solicitudVacaciones.dart';
import 'asignacionRoles.dart';

class CargaMasivaArchivosPage extends StatefulWidget {
  const CargaMasivaArchivosPage({super.key});

  @override
  State<CargaMasivaArchivosPage> createState() =>
      _CargaMasivaArchivosPageState();
}

class _CargaMasivaArchivosPageState extends State<CargaMasivaArchivosPage> {
  String? nombreArchivo;
  Uint8List? archivoBytes;

  Future<void> seleccionarArchivoZip() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );

    if (resultado == null) {
      return;
    }

    final archivo = resultado.files.single;

    setState(() {
      nombreArchivo = archivo.name;
      archivoBytes = archivo.bytes;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Archivo seleccionado: ${archivo.name}'),
        backgroundColor: const Color(0xFF0F9F8F),
      ),
    );
  }

  void cargarArchivo() {
    if (nombreArchivo == null || archivoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero debes seleccionar un archivo .zip'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Aquí después puedes conectar con backend o procesar el archivo.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cargando archivo: $nombreArchivo'),
        backgroundColor: const Color(0xFF0F9F8F),
      ),
    );
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
          "Clínica Aconcagua",
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
                    'Menú Principal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Gestión Administrativa',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            // OPCIÓN: INICIO
            ListTile(
              leading: const Icon(
                Icons.home_outlined,
                color: Color(0xFF001E42),
              ),
              title: const Text('Inicio'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DashboardScreen(),
                  ),
                );
              },
            ),
            // OPCIÓN: BONOS
            ListTile(
              leading: const Icon(Icons.attach_money, color: Color(0xFF001E42)),
              title: const Text('Registrar Bonos'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegistrarBonos(),
                  ),
                );
              },
            ),
            // OPCIÓN: VACACIONES
            ListTile(
              leading: const Icon(
                Icons.calendar_today_outlined,
                color: Color(0xFF001E42),
              ),
              title: const Text('Solicitud de Vacaciones'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SolicitudVacaciones(),
                  ),
                );
              },
            ),
            // OPCIÓN: ASIGNACIÓN DE ROLES
            ListTile(
              leading: const Icon(
                Icons.manage_accounts_outlined,
                color: Color(0xFF001E42),
              ),
              title: const Text('Asignación de Roles'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AsignacionRoles(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

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
                _BulletText(texto: 'Máximo: 50 liquidaciones'),
                _BulletTextConEtiqueta(
                  texto: 'Nomenclatura: ',
                  etiqueta: 'RUT-AAAAMM.pdf',
                ),
                _BulletText(texto: 'Tamaño máximo por PDF: 5 MB'),
                _BulletText(texto: 'Ejemplo: 12345678-9-202604.pdf'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

class _ZonaCargaArchivo extends StatelessWidget {
  final String? nombreArchivo;
  final VoidCallback onSeleccionar;

  const _ZonaCargaArchivo({
    required this.nombreArchivo,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    final bool archivoSeleccionado = nombreArchivo != null;

    return InkWell(
      onTap: onSeleccionar,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        height: 300,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: archivoSeleccionado
                ? const Color(0xFF0F9F8F)
                : const Color(0xFFCBD5E1),
            width: archivoSeleccionado ? 1.8 : 1.4,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  color: Color(0xFFCCFBF1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  archivoSeleccionado
                      ? Icons.check_circle_outline
                      : Icons.cloud_upload_outlined,
                  size: 42,
                  color: const Color(0xFF0F9F8F),
                ),
              ),

              const SizedBox(height: 22),

              Text(
                archivoSeleccionado
                    ? 'Archivo seleccionado'
                    : 'Arrastra tu archivo .zip aquí',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                archivoSeleccionado
                    ? nombreArchivo!
                    : 'o haz clic para seleccionar',
                style: TextStyle(
                  fontSize: 13,
                  color: archivoSeleccionado
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF475569),
                  fontWeight: archivoSeleccionado
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 18),

              SizedBox(
                height: 42,
                child: ElevatedButton(
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
                    archivoSeleccionado
                        ? 'Cambiar Archivo'
                        : 'Seleccionar Archivo',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
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
