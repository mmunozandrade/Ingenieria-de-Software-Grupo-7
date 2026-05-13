import 'package:flutter/material.dart';

class VacacionesProgresivas extends StatefulWidget {
  const VacacionesProgresivas({super.key});

  @override
  State<VacacionesProgresivas> createState() => _VacacionesProgresivasState();
}

class _VacacionesProgresivasState extends State<VacacionesProgresivas> {
  // Datos de ejemplo del trabajador
  final String nombre = "María González Pérez";
  final String rut = "12.345.678-9";

  ///////////////////////////// Fecha de ingreso fija para el ejemplo, PARAMETRO A CAMBIAR PARA EL FUNCIONAMIENTO REAL
  final DateTime fechaIngresoTrabajador = DateTime(2012, 3, 15);

  final int mesesCotizacionesPrevias = 48;

  int calcularMesesTrabajados(DateTime ingreso) {
    final DateTime hoy = DateTime.now();

    int meses = (hoy.year - ingreso.year) * 12 + (hoy.month - ingreso.month);

    if (hoy.day < ingreso.day) {
      meses--;
    }

    return meses < 0 ? 0 : meses;
  }

  int calcularAniosTrabajados(DateTime ingreso) {
    final int mesesTrabajados = calcularMesesTrabajados(ingreso);
    return mesesTrabajados ~/ 12;
  }

  double calcularDiasProgresivos({
    required int mesesPrevios,
    required int mesesTrabajadosClinica,
  }) {
    final int totalMesesCotizados = mesesPrevios + mesesTrabajadosClinica;
    final int aniosClinica = mesesTrabajadosClinica ~/ 12;

    // Requisito: mínimo 120 meses de cotización total.
    if (totalMesesCotizados < 120) {
      return 0.0000;
    }

    // Requisito: se considera desde el año 10 en la clínica.
    if (aniosClinica < 10) {
      return 0.0000;
    }

    // 1 día hábil por cada 3 años completos desde el año 10.
    final double dias = ((aniosClinica - 10) / 3).floorToDouble();

    // Precisión interna de 4 decimales.
    return double.parse(dias.toStringAsFixed(4));
  }

  String formatearFecha(DateTime fecha) {
    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');
    final String anio = fecha.year.toString();

    return "$dia/$mes/$anio";
  }

  @override
  Widget build(BuildContext context) {
    final int mesesTrabajados = calcularMesesTrabajados(fechaIngresoTrabajador);

    final int aniosTrabajados = calcularAniosTrabajados(fechaIngresoTrabajador);

    final int totalMesesCotizados = mesesCotizacionesPrevias + mesesTrabajados;

    final double diasProgresivosInterno = calcularDiasProgresivos(
      mesesPrevios: mesesCotizacionesPrevias,
      mesesTrabajadosClinica: mesesTrabajados,
    );

    final int diasProgresivosVisual = diasProgresivosInterno.round();

    final bool cumpleMeses = totalMesesCotizados >= 120;
    final bool cumpleAnioDiez = aniosTrabajados >= 10;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('assets/Logo.png', height: 80),

              const SizedBox(height: 20),

              const Text(
                "Cálculo de Vacaciones Progresivas",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              const Text(
                "Sistema de Personal Institucional",
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 35),

              LayoutBuilder(
                builder: (context, constraints) {
                  final bool esPantallaPequena = constraints.maxWidth < 700;

                  if (esPantallaPequena) {
                    return Column(
                      children: [
                        _tarjetaInformacionTrabajador(),
                        const SizedBox(height: 20),
                        _tarjetaDetalleCalculo(
                          mesesTrabajados: mesesTrabajados,
                          aniosTrabajados: aniosTrabajados,
                          totalMesesCotizados: totalMesesCotizados,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _tarjetaInformacionTrabajador()),
                      const SizedBox(width: 20),
                      Expanded(
                        child: _tarjetaDetalleCalculo(
                          mesesTrabajados: mesesTrabajados,
                          aniosTrabajados: aniosTrabajados,
                          totalMesesCotizados: totalMesesCotizados,
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),

              _tarjetaResultado(
                cumpleMeses: cumpleMeses,
                cumpleAnioDiez: cumpleAnioDiez,
                aniosTrabajados: aniosTrabajados,
                diasProgresivosInterno: diasProgresivosInterno,
                diasProgresivosVisual: diasProgresivosVisual,
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Saldo actualizado: $diasProgresivosVisual día(s) progresivo(s).",
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Actualizar Saldo de Vacaciones",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaInformacionTrabajador() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Información del Trabajador",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 20),
          _filaDato("Nombre:", nombre),
          const SizedBox(height: 14),
          _filaDato("RUT:", rut),
          const SizedBox(height: 14),
          _filaDato(
            "Fecha de Ingreso:",
            formatearFecha(fechaIngresoTrabajador),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDetalleCalculo({
    required int mesesTrabajados,
    required int aniosTrabajados,
    required int totalMesesCotizados,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Detalle del Cálculo",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 20),
          _filaDato(
            "Meses de cotizaciones previas:",
            "$mesesCotizacionesPrevias meses",
          ),
          const SizedBox(height: 14),
          _filaDato(
            "Meses trabajados en la clínica:",
            "$mesesTrabajados meses ($aniosTrabajados años)",
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 14),
          _filaDato(
            "Total de meses de cotización:",
            "$totalMesesCotizados meses",
          ),
        ],
      ),
    );
  }

  Widget _tarjetaResultado({
    required bool cumpleMeses,
    required bool cumpleAnioDiez,
    required int aniosTrabajados,
    required double diasProgresivosInterno,
    required int diasProgresivosVisual,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE6FFFB),
        border: Border.all(color: const Color(0xFF5EEAD4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF99F6E4))),
            ),
            child: const Row(
              children: [
                Expanded(
                  child: Text(
                    "Días Progresivos Calculados",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
                Icon(Icons.check_circle_outline, color: Color(0xFF0D9488)),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool esPantallaPequena = constraints.maxWidth < 650;

                if (esPantallaPequena) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detalleValidaciones(
                        cumpleMeses: cumpleMeses,
                        cumpleAnioDiez: cumpleAnioDiez,
                        aniosTrabajados: aniosTrabajados,
                      ),
                      const SizedBox(height: 24),
                      _resultadoDias(
                        diasProgresivosInterno: diasProgresivosInterno,
                        diasProgresivosVisual: diasProgresivosVisual,
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _detalleValidaciones(
                        cumpleMeses: cumpleMeses,
                        cumpleAnioDiez: cumpleAnioDiez,
                        aniosTrabajados: aniosTrabajados,
                      ),
                    ),
                    Container(
                      height: 90,
                      width: 1,
                      color: const Color(0xFF99F6E4),
                    ),
                    Expanded(
                      flex: 1,
                      child: _resultadoDias(
                        diasProgresivosInterno: diasProgresivosInterno,
                        diasProgresivosVisual: diasProgresivosVisual,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _detalleValidaciones({
    required bool cumpleMeses,
    required bool cumpleAnioDiez,
    required int aniosTrabajados,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _validacion(
          cumpleMeses,
          "Total supera 120 meses de cotización Art. 68",
        ),
        const SizedBox(height: 10),
        _validacion(
          cumpleAnioDiez,
          "Años desde el año 10: ${aniosTrabajados >= 10 ? aniosTrabajados - 10 : 0} años completos",
        ),
        const SizedBox(height: 10),
        _validacion(
          true,
          "Cálculo: 1 día hábil por cada 3 años desde el año 10",
        ),
        const SizedBox(height: 10),
        _validacion(
          true,
          "Precisión interna: 4 decimales; visualización redondeada",
        ),
      ],
    );
  }

  Widget _resultadoDias({
    required double diasProgresivosInterno,
    required int diasProgresivosVisual,
  }) {
    return Column(
      children: [
        const Text(
          "Total días progresivos disponibles:",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 10),
        Text(
          "$diasProgresivosVisual día${diasProgresivosVisual == 1 ? '' : 's'}",
          style: const TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w300,
            color: Color(0xFF0D9488),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Valor interno: ${diasProgresivosInterno.toStringAsFixed(4)}",
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _filaDato(String titulo, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            titulo,
            style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
          ),
        ),
        Expanded(
          child: Text(
            valor,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  Widget _validacion(bool cumple, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          cumple ? Icons.check : Icons.close,
          size: 18,
          color: cumple ? const Color(0xFF0D9488) : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
