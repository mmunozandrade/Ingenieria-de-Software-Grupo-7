import 'package:flutter/material.dart';
import 'valorUtm.dart';
import 'valorUf.dart';
import 'calculoAfpSalud.dart';
import 'sisAporteEmpleador.dart';
import 'impuestoUnico.dart';
import 'movilizacionColacion.dart';
import 'configGratificacion.dart';
import 'configRetencionHonorario.dart';

/// Pantalla "libro" de parametros del sistema — punto de entrada
/// unico a todas las configuraciones que deben revisarse ANTES de
/// empezar a desarrollar liquidaciones de un periodo nuevo.
///
/// Responsive segun el requisito de 3 tamaños de pantalla:
///   Escritorio >= 1280px, Tablet 768-1280px, Movil < 768px.
class ParametrosSistemaScreen extends StatelessWidget {
  const ParametrosSistemaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Parámetros del Sistema',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final bool esEscritorio = ancho >= 1280;
          final bool esTablet = ancho >= 768 && ancho < 1280;
          // Movil: ancho < 768

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
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFFD97706),
                            size: 24,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Antes de comenzar a desarrollar las liquidaciones del período',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Verifica que todos los parámetros de este mes estén actualizados '
                                  '(UTM, UF y sus topes, tasas de AFP y Salud, aportes del empleador, y la '
                                  'tabla de tramos del Impuesto Único). Si alguno falta o quedó desactualizado, '
                                  'los cálculos de la liquidación pueden verse afectados.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF92400E),
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
                        _TarjetaParametro(
                          icono: Icons.calendar_month_outlined,
                          color: const Color(0xFF1D4ED8),
                          titulo: 'Valor UTM Mensual',
                          descripcion:
                              'Unidad Tributaria Mensual del período, usada para el Impuesto Único.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ValorUtmScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.attach_money,
                          color: const Color(0xFF0D9488),
                          titulo: 'Valor UF y Topes',
                          descripcion:
                              'Valor UF del período y los multiplicadores de tope para AFP/Salud y Seguro de Cesantía.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ValorUfScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.health_and_safety_outlined,
                          color: const Color(0xFFEC4899),
                          titulo: 'Tasas AFP y Salud',
                          descripcion:
                              'Porcentaje de descuento de cada AFP y de las instituciones de salud.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CalculoAfpSaludScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.account_balance_outlined,
                          color: const Color(0xFF001E42),
                          titulo: 'SIS y Aportes del Empleador',
                          descripcion:
                              'SIS, Expectativa de Vida y Aporte Previsional de Capitalización Individual.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SisAportesEmpleadorScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.receipt_long_outlined,
                          color: const Color(0xFFEF4444),
                          titulo: 'Impuesto Único (Tabla SII)',
                          descripcion:
                              'Tabla de tramos vigente del SII para el cálculo del Impuesto Único.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ImpuestoUnicoScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.directions_bus_outlined,
                          color: const Color(0xFFEA580C),
                          titulo: 'Movilización y Colación',
                          descripcion:
                              'Montos fijos mensuales. Confirma una vez por período para aplicarlos a todos los trabajadores automáticamente.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const MovilizacionColacionScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.card_giftcard_outlined,
                          color: const Color(0xFFF59E0B),
                          titulo:
                              'Gratificación Legal - Se desarrollará en Incremento 3',
                          descripcion:
                              'Modalidad de gratificación y valor del IMM del período. Se calcula solo, sin pasos adicionales en el wizard.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ConfigGratificacionScreen(),
                            ),
                          ),
                        ),
                        _TarjetaParametro(
                          icono: Icons.receipt_long_outlined,
                          color: const Color(0xFF7C3AED),
                          titulo: 'Retención Honorarios',
                          descripcion:
                              '% de retención de impuesto para boletas de honorarios, actualizable una vez al año.',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ConfigRetencionHonorarioScreen(),
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

/// Tarjeta grande que navega a la pantalla de configuracion correspondiente.
class _TarjetaParametro extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _TarjetaParametro({
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
                    'Configurar',
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

/// Tarjeta "de referencia" — muestra los valores fijos sin navegar a
/// ninguna pantalla de edicion, ya que Movilizacion y Colacion no son
/// editables desde el sistema.
class _TarjetaReferencia extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;

  const _TarjetaReferencia({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.descripcion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Solo referencia',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
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
          Text(
            descripcion,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF9A6C3B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'Movilización',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9A6C3B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '\$50.000',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7C2D12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'Colación',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9A6C3B),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '\$60.000',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7C2D12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
