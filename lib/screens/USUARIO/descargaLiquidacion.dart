import 'package:flutter/material.dart';
import '../../auth/inicial.dart';
import '../ADMIN/cargaArchivos.dart';
import '../ADMIN/registroBonos.dart';
import 'solicitudVacaciones.dart';
import '../ADMIN/asignacionRoles.dart';
import '../ADMIN/calculoHextra.dart';

class DescargaLiquidacion extends StatefulWidget {
  const DescargaLiquidacion({super.key});

  @override
  State<DescargaLiquidacion> createState() => _DescargaLiquidacionState();
}

class _DescargaLiquidacionState extends State<DescargaLiquidacion> {
  // DATOS SIMULADOS
  final Map<String, String> _usuarioActivo = {
    "nombre": "Juan Pérez González",
    "rut": "12345678-9",
    "cargo": "Enfermero Clínico",
    "departamento": "Unidad de Pacientes Críticos (UPC)",
  };

  final List<Map<String, dynamic>> _liquidaciones = [
    {
      "mes": "Abril 2026",
      "fechaEmision": "05/05/2026",
      "estado": "Disponible",
      "peso": "145 KB",
    },
    {
      "mes": "Marzo 2026",
      "fechaEmision": "05/04/2026",
      "estado": "Disponible",
      "peso": "142 KB",
    },
    {
      "mes": "Febrero 2026",
      "fechaEmision": "05/03/2026",
      "estado": "Disponible",
      "peso": "144 KB",
    },
  ];

  // Función para simular la descarga
  void _simularDescarga(String mes) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.downloading, color: Colors.white),
            const SizedBox(width: 12),
            Text('Descargando liquidación de $mes...'),
          ],
        ),
        backgroundColor: const Color(0xFF009A8D),
        duration: const Duration(seconds: 2),
      ),
    );
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
              child: Text(
                'Menú Principal',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
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

            // --- SECCIÓN: MI PORTAL (USUARIO) ---
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
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
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Mis Liquidaciones'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DescargaLiquidacion(),
                  ),
                );
              },
            ),
            const Divider(), // Separador visual para las opciones administrativas
            // --- SECCIÓN: ADMINISTRACIÓN ---
            ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Registro de Bonos'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegistrarBonos(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Cálculo de Horas Extra'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CalculoHextra(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
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
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carga de Archivos'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  // Asumo que tu clase se llama CargaMasivaArchivosPage como lo mostraste antes
                  MaterialPageRoute(
                    builder: (context) => const CargaMasivaArchivosPage(),
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

      // --- EL CUERPO DE TU PÁGINA ---
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 800,
            ), // Mantiene todo centrado en PC
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TÍTULO Y DESCRIPCIÓN
                const Text(
                  "Mis Liquidaciones",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Revisa, descarga y administra tus liquidaciones de sueldo mensuales.",
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 32),

                // 2. TARJETA DEL PERFIL DEL TRABAJADOR
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
                        etiqueta: "Trabajador",
                        valor: _usuarioActivo["nombre"]!,
                      ),
                      _InfoPerfil(
                        icono: Icons.badge_outlined,
                        etiqueta: "RUT",
                        valor: _usuarioActivo["rut"]!,
                      ),
                      _InfoPerfil(
                        icono: Icons.work_outline,
                        etiqueta: "Cargo",
                        valor: _usuarioActivo["cargo"]!,
                      ),
                      _InfoPerfil(
                        icono: Icons.business_outlined,
                        etiqueta: "Departamento",
                        valor: _usuarioActivo["departamento"]!,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // 3. SECCIÓN DE DOCUMENTOS DISPONIBLES
                const Text(
                  "Documentos Disponibles",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),

                // 4. LISTA DE LIQUIDACIONES
                ListView.builder(
                  shrinkWrap:
                      true, // Importante para que ListView funcione dentro de SingleChildScrollView
                  physics:
                      const NeverScrollableScrollPhysics(), // Desactiva el scroll interno de la lista
                  itemCount: _liquidaciones.length,
                  itemBuilder: (context, index) {
                    final liquidacion = _liquidaciones[index];

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
                        padding: const EdgeInsets.all(16.0),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            bool isMobile = constraints.maxWidth < 400;

                            return Flex(
                              direction: isMobile
                                  ? Axis.vertical
                                  : Axis.horizontal,
                              crossAxisAlignment: isMobile
                                  ? CrossAxisAlignment.start
                                  : CrossAxisAlignment.center,
                              children: [
                                // Ícono de PDF
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFEF2F2,
                                    ), // Fondo rojo muy clarito
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.picture_as_pdf,
                                    color: Color(0xFFEF4444),
                                    size: 32,
                                  ), // Ícono rojo
                                ),
                                const SizedBox(width: 16),

                                // Datos del documento
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Liquidación de Sueldo - ${liquidacion['mes']}",
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Emitida el ${liquidacion['fechaEmision']} • ${liquidacion['peso']}",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (isMobile) const SizedBox(height: 16),

                                // Botón Descargar
                                SizedBox(
                                  width: isMobile ? double.infinity : null,
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _simularDescarga(liquidacion['mes']),
                                    icon: const Icon(
                                      Icons.file_download_outlined,
                                      size: 20,
                                    ),
                                    label: const Text('Descargar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF009A8D),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
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

// Widget de ayuda para mostrar los datos del perfil ordenados
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
