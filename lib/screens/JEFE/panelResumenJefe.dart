import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';
import 'vacacionesAreaJefe.dart';

const String _apiUrlJefe = 'http://127.0.0.1:8000';

class PanelResumenJefe extends StatefulWidget {
  const PanelResumenJefe({super.key});

  @override
  State<PanelResumenJefe> createState() => _PanelResumenJefeState();
}

class _PanelResumenJefeState extends State<PanelResumenJefe> {
  bool   _cargando     = true;
  String _departamento = '';
  String _error        = '';

  List<Map<String, dynamic>> _trabajadores         = [];
  List<Map<String, dynamic>> _solicitudesPendientes = [];
  List<Map<String, dynamic>> _enVacaciones          = [];
  List<Map<String, dynamic>> _contratosPorVencer    = [];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlJefe/jefe/panel-resumen'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _departamento          = data['departamento'] ?? '';
          _trabajadores          = List<Map<String, dynamic>>.from(data['trabajadores'] ?? []);
          _solicitudesPendientes = List<Map<String, dynamic>>.from(data['solicitudes_pendientes'] ?? []);
          _enVacaciones          = List<Map<String, dynamic>>.from(data['en_vacaciones'] ?? []);
          _contratosPorVencer    = List<Map<String, dynamic>>.from(data['contratos_por_vencer'] ?? []);
        });
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar datos');
      }
    } catch (e) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Panel - $_departamento',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Actualizar',
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)))
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(_error,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _cargarDatos,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarDatos,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Header departamento
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF001E42),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Panel Resumen de Area',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text(_departamento,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(children: [
                                const Icon(Icons.people_outline,
                                    color: Colors.white54, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  '${_trabajadores.length} trabajador${_trabajadores.length == 1 ? '' : 'es'} en el area',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Tarjetas resumen
                        Row(children: [
                          Expanded(
                            child: _TarjetaResumen(
                              icono: Icons.pending_actions_outlined,
                              color: const Color(0xFFF59E0B),
                              titulo: 'Solicitudes\nPendientes',
                              valor: '${_solicitudesPendientes.length}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TarjetaResumen(
                              icono: Icons.beach_access_outlined,
                              color: const Color(0xFF0D9488),
                              titulo: 'En\nVacaciones',
                              valor: '${_enVacaciones.length}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TarjetaResumen(
                              icono: Icons.warning_amber_outlined,
                              color: const Color(0xFFEF4444),
                              titulo: 'Contratos\npor Vencer',
                              valor: '${_contratosPorVencer.length}',
                            ),
                          ),
                        ]),
                        const SizedBox(height: 24),

                        // Contratos por vencer
                        if (_contratosPorVencer.isNotEmpty) ...[
                          _SeccionTitulo(
                            icono: Icons.warning_amber_outlined,
                            titulo: 'Contratos por Vencer (proximos 30 dias)',
                            color: const Color(0xFFEF4444),
                          ),
                          const SizedBox(height: 12),
                          ..._contratosPorVencer.map((c) => _TarjetaContrato(
                                nombre:    c['nombre'],
                                cargo:     c['cargo'],
                                vence:     c['vence'],
                                diasResta: c['dias_resta'],
                              )),
                          const SizedBox(height: 20),
                        ],

                        // Solicitudes pendientes
                        _SeccionTitulo(
                          icono: Icons.pending_actions_outlined,
                          titulo: 'Solicitudes de Vacaciones Pendientes',
                          color: const Color(0xFFF59E0B),
                        ),
                        const SizedBox(height: 12),
                        if (_solicitudesPendientes.isEmpty)
                          _MensajeVacio(texto: 'No hay solicitudes pendientes')
                        else
                          ..._solicitudesPendientes.map((s) => _TarjetaSolicitud(
                                nombre:      s['nombre'],
                                fechaInicio: s['fecha_inicio'],
                                fechaFin:    s['fecha_fin'],
                                diasHabiles: s['dias_habiles'],
                                estado:      s['estado'],
                              )),
                        const SizedBox(height: 24),

                        // En vacaciones ahora
                        _SeccionTitulo(
                          icono: Icons.beach_access_outlined,
                          titulo: 'Actualmente de Vacaciones',
                          color: const Color(0xFF0D9488),
                        ),
                        const SizedBox(height: 12),
                        if (_enVacaciones.isEmpty)
                          _MensajeVacio(texto: 'Nadie esta de vacaciones actualmente')
                        else
                          ..._enVacaciones.map((v) => _TarjetaVacaciones(
                                nombre:      v['nombre'],
                                fechaInicio: v['fecha_inicio'],
                                fechaFin:    v['fecha_fin'],
                              )),
                        const SizedBox(height: 24),

                        // Lista trabajadores
                        _SeccionTitulo(
                          icono: Icons.people_outline,
                          titulo: 'Trabajadores del Area',
                          color: const Color(0xFF185FA5),
                        ),
                        const SizedBox(height: 12),
                        if (_trabajadores.isEmpty)
                          _MensajeVacio(texto: 'No hay trabajadores en el area')
                        else
                          ..._trabajadores.map((t) => _TarjetaTrabajador(
                                nombre:       t['nombre'],
                                cargo:        t['cargo'],
                                fechaIngreso: t['fecha_ingreso'],
                                tipoContrato: t['tipo_contrato'],
                              )),
                        const SizedBox(height: 20),

                        // Boton ver vacaciones area
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const VacacionesAreaJefe()),
                            ),
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: const Text(
                              'Ver Saldos y Historial de Vacaciones',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D9488),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────

class _SeccionTitulo extends StatelessWidget {
  final IconData icono;
  final String   titulo;
  final Color    color;

  const _SeccionTitulo({
    required this.icono,
    required this.titulo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icono, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(titulo,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color)),
      ),
    ]);
  }
}

class _TarjetaResumen extends StatelessWidget {
  final IconData icono;
  final Color    color;
  final String   titulo;
  final String   valor;

  const _TarjetaResumen({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        Icon(icono, color: color, size: 28),
        const SizedBox(height: 8),
        Text(valor,
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color)),
        const SizedBox(height: 4),
        Text(titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF64748B))),
      ]),
    );
  }
}

class _TarjetaTrabajador extends StatelessWidget {
  final String nombre;
  final String cargo;
  final String fechaIngreso;
  final String tipoContrato;

  const _TarjetaTrabajador({
    required this.nombre,
    required this.cargo,
    required this.fechaIngreso,
    required this.tipoContrato,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFF001E42).withOpacity(0.1),
          child: Text(nombre[0].toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF001E42),
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text(cargo,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(fechaIngreso,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8))),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: tipoContrato == 'Indefinido'
                    ? const Color(0xFFE6FFFB)
                    : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tipoContrato,
                  style: TextStyle(
                      fontSize: 10,
                      color: tipoContrato == 'Indefinido'
                          ? const Color(0xFF0D9488)
                          : const Color(0xFFF59E0B),
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ]),
    );
  }
}

class _TarjetaSolicitud extends StatelessWidget {
  final String nombre;
  final String fechaInicio;
  final String fechaFin;
  final int    diasHabiles;
  final String estado;

  const _TarjetaSolicitud({
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
    required this.diasHabiles,
    required this.estado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(children: [
        const Icon(Icons.pending_actions_outlined,
            color: Color(0xFFF59E0B), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text('$fechaInicio - $fechaFin  |  $diasHabiles dias habiles',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF92400E))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(estado,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class _TarjetaVacaciones extends StatelessWidget {
  final String nombre;
  final String fechaInicio;
  final String fechaFin;

  const _TarjetaVacaciones({
    required this.nombre,
    required this.fechaInicio,
    required this.fechaFin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE6FFFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF99F6E4)),
      ),
      child: Row(children: [
        const Icon(Icons.beach_access_outlined,
            color: Color(0xFF0D9488), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text('$fechaInicio - $fechaFin',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF0D9488))),
            ],
          ),
        ),
      ]),
    );
  }
}

class _TarjetaContrato extends StatelessWidget {
  final String nombre;
  final String cargo;
  final String vence;
  final int    diasResta;

  const _TarjetaContrato({
    required this.nombre,
    required this.cargo,
    required this.vence,
    required this.diasResta,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_outlined,
            color: Color(0xFFEF4444), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text(cargo,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Vence: $vence',
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600)),
          Text('$diasResta dias',
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFF94A3B8))),
        ]),
      ]),
    );
  }
}

class _MensajeVacio extends StatelessWidget {
  final String texto;
  const _MensajeVacio({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(texto,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Color(0xFF94A3B8), fontSize: 13)),
    );
  }
}