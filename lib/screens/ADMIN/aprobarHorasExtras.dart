import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlAprobarHE = 'http://127.0.0.1:8000';

/// Pantalla del ADMINISTRADOR para revisar las solicitudes de Horas
/// Extras: filtra por estado (Pendiente/Aprobada/Rechazada) y por
/// periodo (mes/año), y decide las pendientes. La decision es solo de
/// REFERENCIA: no calcula ni suma ningun monto. El administrador debe
/// ingresar las horas reales aparte, en Calculo Liquidacion Total
/// (donde vera esta misma solicitud aprobada como recordatorio).
class AprobarHorasExtrasScreen extends StatefulWidget {
  const AprobarHorasExtrasScreen({super.key});

  @override
  State<AprobarHorasExtrasScreen> createState() =>
      _AprobarHorasExtrasScreenState();
}

class _AprobarHorasExtrasScreenState extends State<AprobarHorasExtrasScreen> {
  List<dynamic> _solicitudes = [];
  bool _cargando = true;
  String _error = '';

  // Filtros: null = "Todos"
  String? _filtroEstado = 'pendiente'; // por defecto, igual que antes
  int? _filtroMes;
  int? _filtroAnio;

  @override
  void initState() {
    super.initState();
    _cargarSolicitudes();
  }

  String? get _periodoFiltro {
    if (_filtroMes == null || _filtroAnio == null) return null;
    return '${_filtroMes.toString().padLeft(2, '0')}/$_filtroAnio';
  }

  Future<void> _cargarSolicitudes() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final params = <String, String>{};
      if (_filtroEstado != null) params['estado'] = _filtroEstado!;
      if (_periodoFiltro != null) params['periodo'] = _periodoFiltro!;
      final uri = Uri.parse(
        '$_apiUrlAprobarHE/admin/horas-extras-solicitudes',
      ).replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _solicitudes = data['solicitudes'] ?? []);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _decidir(int solicitudId, String estado) async {
    String? observacion;
    if (estado == 'rechazada') {
      observacion = await _pedirObservacion();
      if (observacion == null) return; // cancelado
    }
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse(
          '$_apiUrlAprobarHE/admin/horas-extras-solicitud/$solicitudId/decidir',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'estado': estado,
          if (observacion != null) 'observacion': observacion,
        }),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['mensaje'] ?? (data['success'] == true ? 'Listo' : 'Error'),
          ),
          backgroundColor: data['success'] == true ? Colors.green : Colors.red,
        ),
      );
      if (data['success'] == true) _cargarSolicitudes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar al servidor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _pedirObservacion() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Motivo del rechazo'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Explica brevemente el motivo (opcional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'aprobada':
        return const Color(0xFF059669);
      case 'rechazada':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  Widget _filtros() {
    final anioActual = DateTime.now().year;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtrar por:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  value: _filtroEstado,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'pendiente',
                      child: Text('Pendiente'),
                    ),
                    DropdownMenuItem(
                      value: 'aprobada',
                      child: Text('Aprobada'),
                    ),
                    DropdownMenuItem(
                      value: 'rechazada',
                      child: Text('Rechazada'),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _filtroEstado = v);
                    _cargarSolicitudes();
                  },
                ),
              ),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<int?>(
                  value: _filtroMes,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Mes',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...List.generate(12, (i) => i + 1).map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.toString().padLeft(2, '0')),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() => _filtroMes = v);
                    _cargarSolicitudes();
                  },
                ),
              ),
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<int?>(
                  value: _filtroAnio,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Año',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...List.generate(
                      3,
                      (i) => anioActual - i,
                    ).map((a) => DropdownMenuItem(value: a, child: Text('$a'))),
                  ],
                  onChanged: (v) {
                    setState(() => _filtroAnio = v);
                    _cargarSolicitudes();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Solicitudes de Horas Extras',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _cargarSolicitudes,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Solicitudes de Horas Extras',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF001E42),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'La decisión es de referencia. El monto real se ingresa aparte, en Cálculo Liquidación Total.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  _filtros(),
                  if (_cargando)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_error.isNotEmpty)
                    Text(_error, style: const TextStyle(color: Colors.red))
                  else if (_solicitudes.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay solicitudes para los filtros seleccionados.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    )
                  else
                    ..._solicitudes.map((s) {
                      final estado = s['estado'] as String;
                      final esPendiente = estado == 'pendiente';
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: esPendiente
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    s['nombre'] ?? 'Trabajador',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _colorEstado(estado),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    estado.toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'RUT: ${s['rut'] ?? '—'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              'Periodo: ${s['periodo']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${s['cantidad_horas']} horas extras',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            if ((s['observacion'] ?? '')
                                .toString()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Observación: ${s['observacion']}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                            if (esPendiente) ...[
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _decidir(
                                        s['solicitud_id'],
                                        'rechazada',
                                      ),
                                      icon: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Color(0xFFDC2626),
                                      ),
                                      label: const Text(
                                        'Rechazar',
                                        style: TextStyle(
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => _decidir(
                                        s['solicitud_id'],
                                        'aprobada',
                                      ),
                                      icon: const Icon(Icons.check, size: 16),
                                      label: const Text('Aprobar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF059669,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
