import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlVacJefe = 'http://127.0.0.1:8000';

class VacacionesAreaJefe extends StatefulWidget {
  const VacacionesAreaJefe({super.key});

  @override
  State<VacacionesAreaJefe> createState() => _VacacionesAreaJefeState();
}

class _VacacionesAreaJefeState extends State<VacacionesAreaJefe> {
  // ── Paso 1: Lista trabajadores ────────────────────────────
  List<Map<String, dynamic>> _trabajadores = [];
  bool   _cargandoTrabajadores = true;
  String _errorTrabajadores    = '';

  // ── Paso 2: Historial trabajador seleccionado ─────────────
  Map<String, dynamic>? _trabajadorSeleccionado;
  List<Map<String, dynamic>> _solicitudes = [];
  bool   _cargandoHistorial = false;
  String _errorHistorial    = '';

  // Filtros
  String?   _filtroEstado;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  final List<String> _estados = ['Todos', 'Pendiente', 'Aprobada', 'Rechazada'];

  @override
  void initState() {
    super.initState();
    _cargarTrabajadores();
  }

  // ── Cargar lista trabajadores del area ────────────────────
  Future<void> _cargarTrabajadores() async {
    setState(() { _cargandoTrabajadores = true; _errorTrabajadores = ''; });
    try {
      final token    = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlVacJefe/jefe/panel-resumen'),
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _trabajadores = List<Map<String, dynamic>>.from(data['trabajadores'] ?? []);
        });
      } else {
        setState(() => _errorTrabajadores = data['mensaje'] ?? 'Error al cargar trabajadores');
      }
    } catch (_) {
      setState(() => _errorTrabajadores = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargandoTrabajadores = false);
    }
  }

  // ── Cargar historial de un trabajador ─────────────────────
  Future<void> _cargarHistorial(Map<String, dynamic> trabajador) async {
    setState(() {
      _trabajadorSeleccionado = trabajador;
      _cargandoHistorial      = true;
      _errorHistorial         = '';
      _solicitudes            = [];
      _filtroEstado           = null;
      _fechaDesde             = null;
      _fechaHasta             = null;
    });

    await _fetchHistorial(trabajador['id_empleado']);
  }

  Future<void> _fetchHistorial(int trabajadorId) async {
    setState(() { _cargandoHistorial = true; _errorHistorial = ''; });
    try {
      final token  = await SessionService.obtenerToken();
      final params = <String, String>{};

      if (_filtroEstado != null && _filtroEstado != 'Todos') {
        params['estado'] = _filtroEstado!;
      }
      if (_fechaDesde != null) {
        params['fecha_desde'] = _fechaDesde!.toIso8601String().split('T')[0];
      }
      if (_fechaHasta != null) {
        params['fecha_hasta'] = _fechaHasta!.toIso8601String().split('T')[0];
      }

      final uri = Uri.parse('$_apiUrlVacJefe/jefe/vacaciones-trabajador/$trabajadorId')
          .replace(queryParameters: params.isNotEmpty ? params : null);

      final response = await http.get(
        uri,
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer $token' },
      );
      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          _trabajadorSeleccionado = {
            ..._trabajadorSeleccionado!,
            'saldo_disponible': data['saldo_disponible'],
            'saldo_acumulado':  data['saldo_acumulado'],
            'saldo_utilizado':  data['saldo_utilizado'],
          };
          _solicitudes = List<Map<String, dynamic>>.from(data['solicitudes'] ?? []);
        });
      } else {
        setState(() => _errorHistorial = data['mensaje'] ?? 'Error al cargar historial');
      }
    } catch (_) {
      setState(() => _errorHistorial = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  void _volverALista() {
    setState(() {
      _trabajadorSeleccionado = null;
      _solicitudes            = [];
      _filtroEstado           = null;
      _fechaDesde             = null;
      _fechaHasta             = null;
    });
  }

  Future<void> _seleccionarFecha({required bool esDesde}) async {
    final f = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF001E42), onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (f != null) {
      setState(() {
        if (esDesde) _fechaDesde = f;
        else         _fechaHasta = f;
      });
      await _fetchHistorial(_trabajadorSeleccionado!['id_empleado']);
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'Aprobada':  return Colors.green;
      case 'Rechazada': return Colors.red;
      default:          return const Color(0xFFF59E0B);
    }
  }

  Color _bgEstado(String estado) {
    switch (estado) {
      case 'Aprobada':  return Colors.green[50]!;
      case 'Rechazada': return Colors.red[50]!;
      default:          return const Color(0xFFFFFBEB);
    }
  }

  String _formatFecha(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _trabajadorSeleccionado != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _volverALista,
              )
            : null,
        title: Text(
          _trabajadorSeleccionado != null
              ? _trabajadorSeleccionado!['nombre'] ?? 'Historial'
              : 'Vacaciones del Area',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _trabajadorSeleccionado != null
                ? () => _fetchHistorial(_trabajadorSeleccionado!['id_empleado'])
                : _cargarTrabajadores,
          ),
        ],
      ),
      body: _trabajadorSeleccionado == null
          ? _buildListaTrabajadores()
          : _buildHistorialTrabajador(),
    );
  }

  // ══════════════════════════════════════════════════════════
  // PASO 1 — Lista de trabajadores del area
  // ══════════════════════════════════════════════════════════
  Widget _buildListaTrabajadores() {
    if (_cargandoTrabajadores) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF001E42)));
    }
    if (_errorTrabajadores.isNotEmpty) {
      return Center(child: Text(_errorTrabajadores, style: const TextStyle(color: Colors.red)));
    }
    if (_trabajadores.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 48, color: Color(0xFF94A3B8)),
            SizedBox(height: 12),
            Text('No hay trabajadores en su area',
                style: TextStyle(color: Color(0xFF64748B))),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Aviso solo lectura
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFEFF6FF),
          child: const Row(children: [
            Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF2563EB)),
            SizedBox(width: 6),
            Text(
              'Modo lectura — selecciona un trabajador para ver su historial de vacaciones',
              style: TextStyle(fontSize: 12, color: Color(0xFF2563EB)),
            ),
          ]),
        ),

        // Nota privacidad
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFFFFFBEB),
          child: const Row(children: [
            Icon(Icons.lock_outline, size: 14, color: Color(0xFFD97706)),
            SizedBox(width: 6),
            Text(
              'Por privacidad no se muestran RUT, remuneraciones ni liquidaciones',
              style: TextStyle(fontSize: 12, color: Color(0xFFD97706)),
            ),
          ]),
        ),

        // Lista
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _trabajadores.length,
            itemBuilder: (context, index) {
              final t = _trabajadores[index];
              return InkWell(
                onTap: () => _cargarHistorial(t),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03),
                          blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Row(children: [
                    // Avatar
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF001E42).withOpacity(0.1),
                      child: Text(
                        (t['nombre'] ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                            color: Color(0xFF001E42),
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Datos
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['nombre'] ?? '—',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF0F172A))),
                          const SizedBox(height: 4),
                          Text(t['cargo'] ?? '—',
                              style: const TextStyle(
                                  fontSize: 13, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          Text('Ingreso: ${t['fecha_ingreso'] ?? '—'}',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),

                    // Flecha
                    const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                  ]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // PASO 2 — Historial del trabajador seleccionado
  // ══════════════════════════════════════════════════════════
  Widget _buildHistorialTrabajador() {
    final t = _trabajadorSeleccionado!;

    return Column(
      children: [

        // Tarjeta datos trabajador + saldo
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cargo
              Text(t['cargo'] ?? '—',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              const SizedBox(height: 12),

              // Saldos vacaciones
              Row(children: [
                _TarjetaSaldo(
                  titulo: 'Acumulados',
                  valor: '${t['saldo_acumulado'] ?? 0}',
                  color: const Color(0xFF1D4ED8),
                  bgColor: const Color(0xFFEFF6FF),
                ),
                const SizedBox(width: 8),
                _TarjetaSaldo(
                  titulo: 'Utilizados',
                  valor: '${t['saldo_utilizado'] ?? 0}',
                  color: const Color(0xFFD97706),
                  bgColor: const Color(0xFFFFFBEB),
                ),
                const SizedBox(width: 8),
                _TarjetaSaldo(
                  titulo: 'Disponibles',
                  valor: '${t['saldo_disponible'] ?? 0}',
                  color: const Color(0xFF059669),
                  bgColor: const Color(0xFFECFDF5),
                ),
              ]),
            ],
          ),
        ),

        // Filtros
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Filtro estado
              Row(children: [
                const Text('Estado:', style: TextStyle(fontSize: 13, color: Color(0xFF475569))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _filtroEstado ?? 'Todos',
                    isDense: true,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    ),
                    items: _estados.map((e) => DropdownMenuItem(
                        value: e, child: Text(e, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) {
                      setState(() => _filtroEstado = v);
                      _fetchHistorial(t['id_empleado']);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 8),

              // Rango fechas
              Row(children: [
                Expanded(child: _BotonFecha(
                  label: _fechaDesde != null ? 'Desde: ${_formatFecha(_fechaDesde!)}' : 'Desde',
                  onTap: () => _seleccionarFecha(esDesde: true),
                  activo: _fechaDesde != null,
                )),
                const SizedBox(width: 8),
                Expanded(child: _BotonFecha(
                  label: _fechaHasta != null ? 'Hasta: ${_formatFecha(_fechaHasta!)}' : 'Hasta',
                  onTap: () => _seleccionarFecha(esDesde: false),
                  activo: _fechaHasta != null,
                )),
                if (_fechaDesde != null || _fechaHasta != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() { _fechaDesde = null; _fechaHasta = null; });
                      _fetchHistorial(t['id_empleado']);
                    },
                  ),
                ],
              ]),
            ],
          ),
        ),

        // Aviso privacidad
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: const Color(0xFFFFFBEB),
          child: const Row(children: [
            Icon(Icons.lock_outline, size: 14, color: Color(0xFFD97706)),
            SizedBox(width: 6),
            Text('Sin RUT, remuneraciones ni liquidaciones — modo lectura',
                style: TextStyle(fontSize: 11, color: Color(0xFFD97706))),
          ]),
        ),

        // Historial
        Expanded(
          child: _cargandoHistorial
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF001E42)))
              : _errorHistorial.isNotEmpty
                  ? Center(child: Text(_errorHistorial,
                      style: const TextStyle(color: Colors.red)))
                  : _solicitudes.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF94A3B8)),
                              SizedBox(height: 12),
                              // Excepcion 1
                              Text(
                                'No existen solicitudes registradas para este trabajador',
                                style: TextStyle(color: Color(0xFF64748B)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _solicitudes.length,
                          itemBuilder: (context, index) {
                            final s      = _solicitudes[index];
                            final estado = s['estado'] ?? 'Pendiente';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.03),
                                      blurRadius: 6, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Estado + fecha solicitud
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _bgEstado(estado),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: _colorEstado(estado).withOpacity(0.3)),
                                        ),
                                        child: Text(estado,
                                            style: TextStyle(fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: _colorEstado(estado))),
                                      ),
                                      Text('Solicitud: ${s['fecha_solicitud'] ?? '—'}',
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                    ],
                                  ),
                                  const SizedBox(height: 10),

                                  // Fechas
                                  Row(children: [
                                    const Icon(Icons.calendar_today_outlined,
                                        size: 14, color: Color(0xFF94A3B8)),
                                    const SizedBox(width: 6),
                                    Text('${s['fecha_inicio']} → ${s['fecha_fin']}',
                                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                                    const Spacer(),
                                    const Icon(Icons.wb_sunny_outlined,
                                        size: 14, color: Color(0xFF94A3B8)),
                                    const SizedBox(width: 4),
                                    Text('${s['dias_habiles']} días hábiles',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                                  ]),

                                  // Observacion si existe
                                  if (s['observacion'] != null && s['observacion'] != '—') ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.comment_outlined,
                                              size: 14, color: Color(0xFF64748B)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(s['observacion'],
                                                style: const TextStyle(
                                                    fontSize: 12, color: Color(0xFF475569))),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────

class _TarjetaSaldo extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color  color;
  final Color  bgColor;

  const _TarjetaSaldo({
    required this.titulo, required this.valor,
    required this.color,  required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(children: [
          Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(titulo, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8))),
        ]),
      ),
    );
  }
}

class _BotonFecha extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         activo;

  const _BotonFecha({required this.label, required this.onTap, required this.activo});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: activo ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: activo ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 14,
              color: activo ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Expanded(child: Text(label,
              style: TextStyle(fontSize: 12,
                  color: activo ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)))),
        ]),
      ),
    );
  }
}