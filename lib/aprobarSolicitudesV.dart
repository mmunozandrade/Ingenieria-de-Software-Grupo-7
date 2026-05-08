import 'package:flutter/material.dart';

class AprobarSolicitudesV extends StatefulWidget {
  const AprobarSolicitudesV({super.key});

  @override
  State<AprobarSolicitudesV> createState() => _AprobarSolicitudesVState();
}

class _AprobarSolicitudesVState extends State<AprobarSolicitudesV> {
  String filtroSeleccionado = 'Pendientes';

  final List<SolicitudVacacion> solicitudes = [
    SolicitudVacacion(
      nombre: 'Carlos Rodríguez Muñoz',
      rut: '15.678.234-5',
      estado: 'Pendiente',
      fechaSolicitud: '25/04/2026',
      periodo: 'Del 15/05/2026 al 29/05/2026',
      diasSolicitados: '15 días',
      saldoActual: '20 días disponibles',
      saldoDespues: '5 días restantes',
      expandida: true,
    ),
    SolicitudVacacion(
      nombre: 'Ana María Silva Torres',
      rut: '18.234.567-8',
      estado: 'Pendiente',
      fechaSolicitud: '26/04/2026',
      periodo: 'Del 01/06/2026 al 07/06/2026',
      diasSolicitados: '7 días',
      saldoActual: '14 días disponibles',
      saldoDespues: '7 días restantes',
      expandida: false,
    ),
    SolicitudVacacion(
      nombre: 'Pedro Valenzuela Soto',
      rut: '16.789.123-4',
      estado: 'Pendiente',
      fechaSolicitud: '27/04/2026',
      periodo: 'Del 10/06/2026 al 21/06/2026',
      diasSolicitados: '12 días',
      saldoActual: '18 días disponibles',
      saldoDespues: '6 días restantes',
      expandida: false,
    ),
  ];

  List<SolicitudVacacion> get solicitudesFiltradas {
    if (filtroSeleccionado == 'Pendientes') {
      return solicitudes.where((s) => s.estado == 'Pendiente').toList();
    }

    if (filtroSeleccionado == 'Aprobadas') {
      return solicitudes.where((s) => s.estado == 'Aprobada').toList();
    }

    return solicitudes.where((s) => s.estado == 'Rechazada').toList();
  }

  void seleccionarSolicitud(SolicitudVacacion solicitudSeleccionada) {
    setState(() {
      for (final solicitud in solicitudes) {
        solicitud.expandida = solicitud == solicitudSeleccionada;
      }
    });
  }

  void aprobarSolicitud(SolicitudVacacion solicitud) {
    setState(() {
      solicitud.estado = 'Aprobada';
      solicitud.expandida = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Solicitud de ${solicitud.nombre} aprobada'),
        backgroundColor: const Color(0xFF0F9F8F),
      ),
    );
  }

  void rechazarSolicitud(SolicitudVacacion solicitud) {
    setState(() {
      solicitud.estado = 'Rechazada';
      solicitud.expandida = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Solicitud de ${solicitud.nombre} rechazada'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = solicitudesFiltradas;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ENCABEZADO SUPERIOR
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset("assets/Logo.png", height: 60),

                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "Panel de Administrador",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF334155),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Gestión de Solicitudes",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // BARRA AZUL
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                color: const Color(0xFF1D4ED8),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Aprobación y Rechazo de Solicitudes de Vacaciones",
                      style: TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      "Sistema de Personal Institucional",
                      style: TextStyle(fontSize: 13, color: Color(0xFFE0ECFF)),
                    ),
                  ],
                ),
              ),

              // CONTENIDO
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // FILTROS
                      Row(
                        children: [
                          _FiltroButton(
                            texto: 'Pendientes',
                            cantidad: solicitudes
                                .where((s) => s.estado == 'Pendiente')
                                .length,
                            seleccionado: filtroSeleccionado == 'Pendientes',
                            onTap: () {
                              setState(() {
                                filtroSeleccionado = 'Pendientes';
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          _FiltroButton(
                            texto: 'Aprobadas',
                            cantidad: solicitudes
                                .where((s) => s.estado == 'Aprobada')
                                .length,
                            seleccionado: filtroSeleccionado == 'Aprobadas',
                            onTap: () {
                              setState(() {
                                filtroSeleccionado = 'Aprobadas';
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          _FiltroButton(
                            texto: 'Rechazadas',
                            cantidad: solicitudes
                                .where((s) => s.estado == 'Rechazada')
                                .length,
                            seleccionado: filtroSeleccionado == 'Rechazadas',
                            onTap: () {
                              setState(() {
                                filtroSeleccionado = 'Rechazadas';
                              });
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      const Divider(color: Color(0xFFE2E8F0)),

                      const SizedBox(height: 16),

                      if (lista.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Text(
                              'No hay solicitudes en esta categoría.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          children: lista.map((solicitud) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _SolicitudCard(
                                solicitud: solicitud,
                                onSeleccionar: () =>
                                    seleccionarSolicitud(solicitud),
                                onAprobar: () => aprobarSolicitud(solicitud),
                                onRechazar: () => rechazarSolicitud(solicitud),
                              ),
                            );
                          }).toList(),
                        ),
                    ],
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

// MODELO TEMPORAL
class SolicitudVacacion {
  final String nombre;
  final String rut;
  String estado;
  final String fechaSolicitud;
  final String periodo;
  final String diasSolicitados;
  final String saldoActual;
  final String saldoDespues;
  bool expandida;

  SolicitudVacacion({
    required this.nombre,
    required this.rut,
    required this.estado,
    required this.fechaSolicitud,
    required this.periodo,
    required this.diasSolicitados,
    required this.saldoActual,
    required this.saldoDespues,
    required this.expandida,
  });
}

// BOTONES DE FILTRO
class _FiltroButton extends StatelessWidget {
  final String texto;
  final int cantidad;
  final bool seleccionado;
  final VoidCallback onTap;

  const _FiltroButton({
    required this.texto,
    required this.cantidad,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fondo = seleccionado
        ? const Color(0xFF1D4ED8)
        : const Color(0xFFF1F5F9);

    final Color textoColor = seleccionado
        ? Colors.white
        : const Color(0xFF475569);

    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: fondo,
        foregroundColor: textoColor,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        '$texto ($cantidad)',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// TARJETA DE SOLICITUD
class _SolicitudCard extends StatelessWidget {
  final SolicitudVacacion solicitud;
  final VoidCallback onSeleccionar;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  const _SolicitudCard({
    required this.solicitud,
    required this.onSeleccionar,
    required this.onAprobar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final bool estaPendiente = solicitud.estado == 'Pendiente';

    return InkWell(
      onTap: onSeleccionar,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: solicitud.expandida ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: solicitud.expandida
                ? const Color(0xFF3B82F6)
                : const Color(0xFFE2E8F0),
            width: solicitud.expandida ? 1.5 : 1.2,
          ),
        ),
        child: Column(
          children: [
            // ENCABEZADO DE LA TARJETA
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DATOS IZQUIERDA
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        children: [
                          Text(
                            solicitud.nombre,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          _EstadoBadge(estado: solicitud.estado),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'RUT: ${solicitud.rut}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),

                // FECHA DERECHA
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Fecha de solicitud:',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      solicitud.fechaSolicitud,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // INFORMACIÓN DE LA SOLICITUD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                runSpacing: 18,
                children: [
                  SizedBox(
                    width: 480,
                    child: _DatoSolicitud(
                      titulo: 'Período solicitado:',
                      valor: solicitud.periodo,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: _DatoSolicitud(
                      titulo: 'Días solicitados:',
                      valor: solicitud.diasSolicitados,
                    ),
                  ),
                  SizedBox(
                    width: 480,
                    child: _DatoSolicitud(
                      titulo: 'Saldo actual:',
                      valor: solicitud.saldoActual,
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: _DatoSolicitud(
                      titulo: 'Saldo después:',
                      valor: solicitud.saldoDespues,
                    ),
                  ),
                ],
              ),
            ),

            if (solicitud.expandida && estaPendiente) ...[
              const SizedBox(height: 20),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Observación (opcional para aprobación, obligatoria para rechazo):',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Ingrese observación...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B82F6),
                      width: 1.4,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: onAprobar,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Aprobar Solicitud'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F9F8F),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: onRechazar,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Rechazar Solicitud'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF000C),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// BADGE DE ESTADO
class _EstadoBadge extends StatelessWidget {
  final String estado;

  const _EstadoBadge({required this.estado});

  @override
  Widget build(BuildContext context) {
    Color fondo;
    Color texto;

    if (estado == 'Pendiente') {
      fondo = const Color(0xFFFEF3C7);
      texto = const Color(0xFF92400E);
    } else if (estado == 'Aprobada') {
      fondo = const Color(0xFFD1FAE5);
      texto = const Color(0xFF047857);
    } else {
      fondo = const Color(0xFFFEE2E2);
      texto = const Color(0xFFB91C1C);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        estado,
        style: TextStyle(
          fontSize: 11,
          color: texto,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// DATO PEQUEÑO DE LA SOLICITUD
class _DatoSolicitud extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoSolicitud({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF334155),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
        ),
      ],
    );
  }
}
