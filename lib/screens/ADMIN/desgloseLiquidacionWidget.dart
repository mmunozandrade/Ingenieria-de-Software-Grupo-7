import 'package:flutter/material.dart';

/// Formatea un numero con puntos como separador de miles (estilo
/// chileno): 1500000 -> "1.500.000". Acepta int, double o String.
/// Convierte horas decimales (ej. 4.25) a formato HH:MM (ej. "4:15").
String formatearHorasMinutos(dynamic horasDecimal) {
  if (horasDecimal == null) return '0:00';
  final double valor = horasDecimal is num
      ? horasDecimal.toDouble()
      : double.tryParse(horasDecimal.toString()) ?? 0;
  final horas = valor.floor();
  final minutos = ((valor - horas) * 60).round();
  return '$horas:${minutos.toString().padLeft(2, '0')}';
}

String formatearMiles(dynamic valor) {
  if (valor == null) return '0';
  final int numero = valor is num
      ? valor.round()
      : (int.tryParse(valor.toString()) ?? 0);
  final bool esNegativo = numero < 0;
  final String digitos = numero.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return (esNegativo ? '-' : '') + buffer.toString();
}

class ItemDesglose extends StatelessWidget {
  final String titulo;
  final int monto;
  final String? descripcion;
  final bool esDescuento;
  final bool destacado;
  final String? subtitulo;

  const ItemDesglose({
    super.key,
    required this.titulo,
    required this.monto,
    this.descripcion,
    this.esDescuento = false,
    this.destacado = false,
    this.subtitulo,
  });

  void _mostrarDescripcion(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          titulo,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF001E42),
          ),
        ),
        content: Text(
          descripcion ?? 'Descripción del ítem no disponible por el momento.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = esDescuento
        ? const Color(0xFFDC2626)
        : const Color(0xFF0F172A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        titulo,
                        style: TextStyle(
                          fontSize: destacado ? 15 : 13,
                          fontWeight: destacado
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: destacado
                              ? const Color(0xFF001E42)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => _mostrarDescripcion(context),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${esDescuento ? "-" : ""}\$${formatearMiles(monto)} CLP',
                style: TextStyle(
                  fontSize: destacado ? 16 : 13,
                  fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
                  color: destacado ? const Color(0xFF059669) : color,
                ),
              ),
            ],
          ),
          if (subtitulo != null && subtitulo!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitulo!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TarjetaDesgloseLiquidacion extends StatelessWidget {
  final Map<String, dynamic> resultado;

  const TarjetaDesgloseLiquidacion({super.key, required this.resultado});

  @override
  Widget build(BuildContext context) {
    final items = resultado['items'] as Map<String, dynamic>;
    final descripciones = resultado['descripciones'] as Map<String, dynamic>;
    final detalleHaberes =
        resultado['detalle_haberes'] as Map<String, dynamic>? ?? {};

    String? resumenBonos(dynamic detalle) {
      if (detalle == null || (detalle as List).isEmpty) return null;
      return detalle
          .map((b) => '${b['tipo']}: \$${formatearMiles(b['monto'])} CLP')
          .join(' · ');
    }

    String? resumenBonoExcepcional(
      dynamic detalle, {
      bool soloImponibles = false,
    }) {
      if (detalle == null) return null;
      final lista = (detalle as List).where(
        (b) => !soloImponibles || b['clasificacion'] == 'Imponible',
      );
      if (lista.isEmpty) return null;
      return lista
          .map((b) => '${b['concepto']}: \$${formatearMiles(b['monto'])} CLP')
          .join(' · ');
    }

    final subtituloBonosImponibles = [
      resumenBonos(detalleHaberes['detalle_bonos_imponibles']),
      resumenBonoExcepcional(
        detalleHaberes['detalle_bono_excepcional'],
        soloImponibles: true,
      ),
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${resultado['nombre']} · ${resultado['periodo']}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
              ),
              if (resultado['sueldo_base_completo'] != null)
                Text(
                  'Sueldo Base Contrato: \$${formatearMiles(resultado['sueldo_base_completo'])} / mes',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
            ],
          ),
          Text(
            'Rut:${resultado['rut'] ?? ''}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          if (resultado['fecha_ingreso'] != null)
            Text(
              'Fecha de ingreso: ${resultado['fecha_ingreso']}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          if (resultado['cargo'] != null &&
              resultado['cargo'].toString().isNotEmpty)
            Text(
              'Cargo: ${resultado['cargo']}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          const SizedBox(height: 16),

          const Text(
            'HABERES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF059669),
              letterSpacing: 1,
            ),
          ),
          const Divider(),
          ItemDesglose(
            titulo: detalleHaberes['es_proporcional'] == true
                ? 'Sueldo proporcional'
                : 'Sueldo base',
            monto: items['sueldo_base'],
            descripcion: descripciones['sueldo_base'],
            subtitulo: detalleHaberes['es_proporcional'] == true
                ? 'En función de ${detalleHaberes['detalle_proporcional']}'
                : null,
          ),
          ItemDesglose(
            titulo: 'Bonos imponibles',
            monto: items['bonos_imponibles'],
            descripcion: descripciones['bonos_imponibles'],
            subtitulo: subtituloBonosImponibles.isNotEmpty
                ? subtituloBonosImponibles
                : null,
          ),
          ItemDesglose(
            titulo: 'Movilización y Colación',
            monto: items['movilizacion_colacion'],
            descripcion: descripciones['bonos_no_imponibles'],
            subtitulo:
                ((detalleHaberes['colacion_total'] ?? 0) > 0 ||
                    (detalleHaberes['locomocion_total'] ?? 0) > 0)
                ? 'Colación: \$${formatearMiles(detalleHaberes['colacion_total'])} CLP · Locomoción: \$${formatearMiles(detalleHaberes['locomocion_total'])} CLP'
                : null,
          ),
          if ((items['bonos_no_imponibles_otros'] ?? 0) > 0)
            ItemDesglose(
              titulo: 'Otros bonos no imponibles',
              monto: items['bonos_no_imponibles_otros'],
              descripcion:
                  'Bonos condicionales o excepcionales clasificados como no imponibles este período.',
            ),
          ItemDesglose(
            titulo: 'Horas extras',
            monto: items['horas_extras'],
            descripcion: descripciones['horas_extras'],
            subtitulo: (detalleHaberes['horas_extra_horas'] ?? 0) > 0
                ? '${detalleHaberes['horas_extra_horas']} horas extra ingresadas'
                : null,
          ),
          if ((items['excedente_no_imponible'] ?? 0) > 0)
            ItemDesglose(
              titulo: 'Excedente movilización/colación (imponible)',
              monto: items['excedente_no_imponible'],
              descripcion: descripciones['excedente_no_imponible'],
            ),
          if ((items['gratificacion'] ?? 0) > 0)
            ItemDesglose(
              titulo: 'Gratificación legal',
              monto: items['gratificacion'],
              descripcion: descripciones['gratificacion'],
            ),
          if ((items['descuento_atraso'] ?? 0) > 0)
            ItemDesglose(
              titulo: 'Descuento de atraso',
              monto: items['descuento_atraso'],
              descripcion: descripciones['descuento_retraso'],
              esDescuento: true,
              subtitulo:
                  '${formatearHorasMinutos(detalleHaberes['horas_atraso_total'])} horas de atraso ingresadas',
            ),
          const SizedBox(height: 4),
          ItemDesglose(
            titulo: 'Total haberes',
            monto: resultado['total_haberes'],
            descripcion:
                'Suma de todos los conceptos que se pagan al trabajador este período.',
            destacado: true,
          ),

          if (resultado['bases_calculo'] != null) ...[
            const SizedBox(height: 20),
            const Text(
              'BASES DE CÁLCULO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1D4ED8),
                letterSpacing: 1,
              ),
            ),
            const Divider(),
            if (resultado['bases_calculo']['total_imponible_afp_salud'] != null)
              ItemDesglose(
                titulo: 'Total Imponible AFP y Salud',
                monto: resultado['bases_calculo']['total_imponible_afp_salud'],
                descripcion:
                    'Base sobre la que se calculan los descuentos de AFP y Salud, limitada al tope configurado.',
              ),
            if (resultado['bases_calculo']['total_imponible_afc'] != null)
              ItemDesglose(
                titulo: 'Total Imponible AFC',
                monto: resultado['bases_calculo']['total_imponible_afc'],
                descripcion:
                    'Base sobre la que se calcula el Seguro de Cesantía, limitada al tope configurado.',
              ),
            if (resultado['bases_calculo']['total_tributable'] != null)
              ItemDesglose(
                titulo: 'Total Tributable',
                monto: resultado['bases_calculo']['total_tributable'],
                descripcion:
                    'Total imponible menos AFP, Salud y AFC del trabajador. Es la base sobre la que se calcula el Impuesto Único.',
              ),
          ],

          const SizedBox(height: 20),
          const Text(
            'DESCUENTOS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFDC2626),
              letterSpacing: 1,
            ),
          ),
          const Divider(),
          ItemDesglose(
            titulo: 'AFP',
            monto: items['descuento_afp'],
            descripcion: descripciones['descuento_afp'],
            esDescuento: true,
          ),
          ItemDesglose(
            titulo: 'Salud',
            monto: items['descuento_salud'],
            descripcion: descripciones['descuento_salud'],
            esDescuento: true,
          ),
          ItemDesglose(
            titulo: 'Seguro de Cesantía (AFC)',
            monto: items['descuento_afc'],
            descripcion: descripciones['descuento_afc'],
            esDescuento: true,
          ),
          ItemDesglose(
            titulo: 'Impuesto único',
            monto: items['impuesto_unico'],
            descripcion: resultado['impuesto_disponible'] == true
                ? descripciones['impuesto_unico']
                : '${descripciones['impuesto_unico']} (Falta cargar la UTM del período; se muestra como \$0 mientras tanto).',
            esDescuento: true,
          ),
          if ((items['descuento_prestamo'] ?? 0) > 0)
            ItemDesglose(
              titulo: 'Préstamo',
              monto: items['descuento_prestamo'],
              descripcion: descripciones['descuento_prestamo'],
              esDescuento: true,
            ),
          if ((items['descuento_anticipo'] ?? 0) > 0)
            ItemDesglose(
              titulo: 'Anticipo de Sueldo',
              monto: items['descuento_anticipo'],
              descripcion: descripciones['descuento_anticipo'],
              esDescuento: true,
            ),
          const SizedBox(height: 4),
          ItemDesglose(
            titulo: 'Total descuentos',
            monto: resultado['total_descuentos'],
            descripcion: 'Suma de todos los descuentos aplicados este período.',
            esDescuento: true,
            destacado: true,
          ),

          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ItemDesglose(
                  titulo: 'LÍQUIDO A PAGAR',
                  monto: resultado['liquido_a_pagar'],
                  descripcion: descripciones['liquido_a_pagar'],
                  destacado: true,
                ),
                if (resultado['liquido_a_pagar_palabras'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '(${resultado['liquido_a_pagar_palabras']})',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
