import 'package:flutter/material.dart';
import 'calculoLiquidacionWizardNuevo.dart';
import 'liquidacionHonorario.dart';
import 'informeRemuneraciones.dart';
import 'informeConsolidadoRemuneraciones.dart';
import 'cargaArchivos.dart';
import 'alertasPreCierre.dart';

/// Pantalla "libro" de Liquidaciones — punto de entrada unico a los
/// 2 flujos de calculo (planilla e honorarios), la descarga de
/// informes, la carga masiva de archivos y las alertas pre-cierre.
/// Mismo formato de tarjetas grandes y centrado que Parametros del
/// Sistema, para mantener consistencia visual en toda la app.
class LiquidacionesScreen extends StatelessWidget {
  const LiquidacionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Liquidaciones',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final bool esEscritorio = ancho >= 1280;
          final bool esTablet = ancho >= 768 && ancho < 1280;
          final double maxWidthContenido = esEscritorio
              ? 1180
              : double.infinity;
          final double paddingHorizontal = esEscritorio
              ? 40
              : (esTablet ? 28 : 16);
          final bool dosColumnas = ancho >= 768;

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
                    // ── 1. Alertas Pre-Cierre (primero) ─────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            color: Color(0xFFDC2626),
                            size: 24,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Antes de cerrar el período, revisa las alertas pendientes: trabajadores sin liquidación calculada, '
                              'montos inusuales u otras validaciones que requieran tu atención.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF991B1B),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _TarjetaLiquidacion(
                      icono: Icons.warning_amber_outlined,
                      color: const Color(0xFFDC2626),
                      titulo: 'Alertas Pre-Cierre',
                      descripcion:
                          'Revisión previa al cierre mensual de todas las liquidaciones del período.',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AlertasPreCierreScreen(),
                        ),
                      ),
                      ancho: true,
                    ),

                    const SizedBox(height: 28),

                    // ── 2. Iniciar el calculo de liquidaciones ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Color(0xFF1D4ED8),
                            size: 24,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'A continuación puedes iniciar el proceso de cálculo de liquidaciones para los trabajadores. '
                              'Si seleccionas la opción de la derecha, corresponde a la liquidación para trabajadores con '
                              'contrato Indefinido, Plazo Fijo o Por Obra. Si eliges la opción de la izquierda, se calculará '
                              'la liquidación para los trabajadores con contrato Honorario.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF1E40AF),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Las 2 tarjetas de calculo, mas al centro y
                    // mas separadas entre si que el resto de la grilla.
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: esEscritorio ? 760 : 520,
                        ),
                        child: dosColumnas
                            ? Row(
                                children: [
                                  Expanded(
                                    child: _TarjetaLiquidacion(
                                      icono: Icons.receipt_outlined,
                                      color: const Color(0xFFF59E0B),
                                      titulo: 'Liquidación Honorarios',
                                      descripcion:
                                          'Trabajadores con contrato Honorario (boleta): honorario bruto menos retención de impuesto.',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const LiquidacionHonorarioScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 36),
                                  Expanded(
                                    child: _TarjetaLiquidacion(
                                      icono: Icons.playlist_add_check,
                                      color: const Color(0xFF1D4ED8),
                                      titulo: 'Cálculo de Liquidación Total',
                                      descripcion:
                                          'Trabajadores con contrato Indefinido, Plazo Fijo o Por Obra: registro completo paso a paso.',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const CalculoLiquidacionWizardNuevoScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _TarjetaLiquidacion(
                                    icono: Icons.receipt_outlined,
                                    color: const Color(0xFFF59E0B),
                                    titulo: 'Liquidación Honorarios',
                                    descripcion:
                                        'Trabajadores con contrato Honorario (boleta): honorario bruto menos retención de impuesto.',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const LiquidacionHonorarioScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _TarjetaLiquidacion(
                                    icono: Icons.playlist_add_check,
                                    color: const Color(0xFF1D4ED8),
                                    titulo: 'Cálculo de Liquidación Total',
                                    descripcion:
                                        'Trabajadores con contrato Indefinido, Plazo Fijo o Por Obra: registro completo paso a paso.',
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
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── 3. Informe de Remuneraciones ────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Color(0xFF1D4ED8),
                            size: 24,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Una vez realizadas todas las liquidaciones correspondientes, puedes descargar los PDF o Excel a continuación.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF1E40AF),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: esEscritorio ? 760 : 520,
                        ),
                        child: dosColumnas
                            ? Row(
                                children: [
                                  Expanded(
                                    child: _TarjetaLiquidacion(
                                      icono: Icons.description_outlined,
                                      color: const Color(0xFF64748B),
                                      titulo: 'Informe de Remuneraciones',
                                      etiqueta: 'Desarrollo en incremento 3',
                                      descripcion:
                                          'Generar y exportar el informe por trabajador y período (Excel / PDF).',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const InformeRemuneracionesScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 36),
                                  Expanded(
                                    child: _TarjetaLiquidacion(
                                      icono: Icons.summarize_outlined,
                                      color: const Color(0xFF059669),
                                      titulo:
                                          'Informe Consolidado de Remuneraciones',
                                      etiqueta: 'Desarrollo en incremento 3',
                                      descripcion:
                                          'Costo trabajador vs. costo empleador de todos los trabajadores, con el total general del período.',
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const InformeConsolidadoRemuneracionesScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  _TarjetaLiquidacion(
                                    icono: Icons.description_outlined,
                                    color: const Color(0xFF64748B),
                                    titulo: 'Informe de Remuneraciones',
                                    etiqueta: 'Desarrollo en incremento 3',
                                    descripcion:
                                        'Generar y exportar el informe por trabajador y período (Excel / PDF).',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const InformeRemuneracionesScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _TarjetaLiquidacion(
                                    icono: Icons.summarize_outlined,
                                    color: const Color(0xFF059669),
                                    titulo:
                                        'Informe Consolidado de Remuneraciones',
                                    etiqueta: 'Desarrollo en incremento 3',
                                    descripcion:
                                        'Costo trabajador vs. costo empleador de todos los trabajadores, con el total general del período.',
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const InformeConsolidadoRemuneracionesScreen(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── 4. Carga de Archivos (ultimo) ───────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Color(0xFF1D4ED8),
                            size: 24,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'En este apartado puedes subir de forma masiva las liquidaciones ya generadas de los trabajadores, '
                              'en formato PDF o Excel, para dejarlas disponibles en el sistema.',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF1E40AF),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    _TarjetaLiquidacion(
                      icono: Icons.upload_file_outlined,
                      color: const Color(0xFF0D9488),
                      titulo: 'Carga de Archivos',
                      descripcion:
                          'Importar liquidaciones masivamente (PDF o Excel).',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CargaMasivaArchivosPage(),
                        ),
                      ),
                      ancho: true,
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

class _TarjetaLiquidacion extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;
  final bool ancho;
  final String? etiqueta;

  const _TarjetaLiquidacion({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
    this.ancho = false,
    this.etiqueta,
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
          width: double.infinity,
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
          child: ancho
              ? Row(
                  children: [
                    _icono(),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (etiqueta != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              etiqueta!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            descripcion,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 18, color: color),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _icono(),
                    const SizedBox(height: 16),
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (etiqueta != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        etiqueta!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      descripcion,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        height: 1.4,
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

  Widget _icono() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icono, color: color, size: 26),
    );
  }
}
