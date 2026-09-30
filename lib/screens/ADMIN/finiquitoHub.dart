import 'package:flutter/material.dart';
import 'registrarFiniquito.dart';

/// Pantalla "hub" de Finiquito -- mismo patron que Liquidaciones:
/// un punto de entrada central con tarjetas hacia cada sub-flujo.
/// Por ahora solo existe "Registrar Finiquito" (Requisito 1); las
/// tarjetas de los Requisitos 2, 3 y 4 se agregan aqui mismo cuando
/// se desarrollen, sin tener que rehacer esta pantalla.
class FiniquitoHubScreen extends StatelessWidget {
  const FiniquitoHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Finiquito',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Termino de Contrato',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Registra la desvinculación de un trabajador y genera su finiquito con el desglose legal completo.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),

                _TarjetaFiniquito(
                  icono: Icons.assignment_late_outlined,
                  color: const Color(0xFFDC2626),
                  titulo: 'Registrar Finiquito',
                  descripcion:
                      'Ingresa la fecha de término y la causal de desvinculación, revisa el desglose calculado automáticamente, y aprueba el finiquito.',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegistrarFiniquitoScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaFiniquito extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;

  const _TarjetaFiniquito({
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
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
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
          ),
        ),
      ),
    );
  }
}
