import 'package:flutter/material.dart';
import '../Fichausuario.dart';
import 'busquedaEmpleados.dart';
import 'cuentasPendientes.dart';
import 'aprobarSolicitudesV.dart';
import 'CompensacionesAdmin.dart';
import 'desgloseLiquidacionAdmin.dart';
import 'calculoLiquidacionWizardNuevo.dart';

/// Pantalla "libro" de Gestión de Personal — punto de entrada unico
/// a los modulos relacionados con los trabajadores y sus cuentas.
/// Mismo formato de tarjetas grandes y centrado que Parametros del
/// Sistema, para mantener consistencia visual en toda la app.
class GestionPersonalScreen extends StatelessWidget {
  const GestionPersonalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Gestión de Personal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final bool esEscritorio = ancho >= 1280;
          final bool esTablet = ancho >= 768 && ancho < 1280;
          final int columnas = esEscritorio ? 3 : (esTablet ? 2 : 1);
          final double maxWidthContenido = esEscritorio
              ? 1180
              : double.infinity;
          final double paddingHorizontal = esEscritorio
              ? 40
              : (esTablet ? 28 : 16);

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: paddingHorizontal,
              vertical: 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidthContenido),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 28),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDFA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF99F6E4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFF0D9488),
                            size: 24,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Trabajadores y sus cuentas',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF115E59),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Consulta y administra la información personal de los trabajadores, sus cuentas de acceso '
                                  'y sus solicitudes de vacaciones o compensaciones.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF115E59),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    GridView.count(
                      crossAxisCount: columnas,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                      childAspectRatio: columnas == 1 ? 2.6 : 1.35,
                      children: [
                        _TarjetaGestion(
                          icono: Icons.person_outline,
                          color: const Color(0xFF0D9488),
                          titulo: 'Mi Ficha Personal',
                          descripcion:
                              'Ver y actualizar tu propia información personal, como trabajador del sistema.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FichaUsuario(),
                            ),
                          ),
                        ),
                        _TarjetaGestion(
                          icono: Icons.search,
                          color: const Color(0xFF7C3AED),
                          titulo: 'Buscar Empleados',
                          descripcion:
                              'Consulta rápida de la información de cualquier trabajador de la clínica, por apellido o RUT.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BusquedaEmpleados(),
                            ),
                          ),
                        ),
                        _TarjetaGestion(
                          icono: Icons.person_add_alt_outlined,
                          color: const Color(0xFFD97706),
                          titulo: 'Cuentas Pendientes',
                          descripcion:
                              'Cuentas creadas por los trabajadores que aún no tienen sus datos personales completos.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CuentasPendientes(),
                            ),
                          ),
                        ),
                        _TarjetaGestion(
                          icono: Icons.check_circle_outline,
                          color: const Color(0xFF059669),
                          titulo: 'Aprobar Solicitudes',
                          descripcion:
                              'Solicitudes de vacaciones que los trabajadores han enviado para tu revisión.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AprobarSolicitudesV(),
                            ),
                          ),
                        ),
                        _TarjetaGestion(
                          icono: Icons.request_quote_outlined,
                          color: const Color(0xFF0891B2),
                          titulo: 'Compensaciones Progresivas',
                          descripcion:
                              'Solicitudes para compensar en efectivo días de vacaciones progresivas.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CompensacionesAdmin(),
                            ),
                          ),
                        ),
                        _TarjetaGestion(
                          icono: Icons.receipt_long_outlined,
                          color: const Color(0xFF7C3AED),
                          titulo: 'Desglose de Liquidación',
                          descripcion:
                              'Consulta el detalle completo de la liquidación de un trabajador para un período, con la glosa de cada concepto.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const DesgloseLiquidacionAdminScreen(),
                            ),
                          ),
                        ),
                        _TarjetaGestion(
                          icono: Icons.science_outlined,
                          color: const Color(0xFFDB2777),
                          titulo: '[PRUEBA] Liquidación Total Nuevo',
                          descripcion:
                              'Versión en pruebas del wizard de liquidación, con el orden de pasos reorganizado. Temporal, mientras se valida.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CalculoLiquidacionWizardNuevoScreen(),
                            ),
                          ),
                        ),
                      ],
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

class _TarjetaGestion extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _TarjetaGestion({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                titulo,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  descripcion,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Ingresar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 15, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
