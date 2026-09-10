import 'package:flutter/material.dart';
import 'parametrizacionConceptos.dart';
import 'bonosCondicionales.dart';
import 'bonoExcepcional.dart';

/// Pantalla "libro" de Conceptos y Bonos Especiales — agrupa la
/// configuracion de conceptos de haberes y los bonos que no forman
/// parte del flujo estandar del "Calculo de Liquidacion Total"
/// (bonos condicionales y bonos excepcionales de caracter puntual).
/// Mismo formato de tarjetas grandes y centrado que Parametros del
/// Sistema, para mantener consistencia visual en toda la app.
class ConceptosYBonosScreen extends StatelessWidget {
  const ConceptosYBonosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Conceptos y Bonos Especiales',
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
                        color: const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFDDD6FE)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFF7C3AED),
                            size: 24,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Configuración de haberes y bonos especiales',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5B21B6),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Estos módulos quedan fuera del flujo estándar del wizard de liquidación: se configuran '
                                  'o se registran de forma independiente, y sus montos se toman en cuenta automáticamente '
                                  'en los cálculos correspondientes.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF5B21B6),
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
                        _TarjetaConcepto(
                          icono: Icons.tune,
                          color: const Color(0xFF7C3AED),
                          titulo: 'Parametrización de Conceptos',
                          descripcion:
                              'Define qué haberes son imponibles o no imponibles, y sus características generales.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ParametrizacionConceptosScreen(),
                            ),
                          ),
                        ),
                        _TarjetaConcepto(
                          icono: Icons.rule,
                          color: const Color(0xFFF59E0B),
                          titulo: 'Bonos Condicionales',
                          descripcion:
                              'Bonos que se pagan solo si el trabajador cumple una condición definida (ej: sin atrasos en el mes).',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BonosCondicionalesScreen(),
                            ),
                          ),
                        ),
                        _TarjetaConcepto(
                          icono: Icons.star_outline,
                          color: const Color(0xFFEF4444),
                          titulo: 'Bono Excepcional',
                          descripcion:
                              'Bonos puntuales de un solo período, autorizados directamente por el Administrador.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BonoExcepcionalScreen(),
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

class _TarjetaConcepto extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _TarjetaConcepto({
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
