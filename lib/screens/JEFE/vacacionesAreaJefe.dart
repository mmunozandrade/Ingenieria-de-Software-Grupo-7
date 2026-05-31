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
  List<Map<String, dynamic>> _solicitudes = [];
  bool   _cargando = true;
  String _error    = '';

  // Filtros
  String? _filtroEstado;
  DateTime? _fechaDesde;
  DateTime? _fechaHasta;

  final List<String> _estados = ['Todos', 'Pendiente', 'Aprobada', 'Rechazada'];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final token = await SessionService.obtenerToken();

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

      final uri = Uri.parse('$_apiUrlVacJefe/jefe/vacaciones-area')
          .replace(queryParameters: params.isNotEmpty ? params : null);

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _solicitudes = List<Map<String, dynamic>>.from(
              data['solicitudes'] ?? []);
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

  Future<void> _seleccionarFecha({required bool esDesde}) async {
    final f = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF001E42),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (f != null) {
      setState(() {
        if (esDesde) _fechaDesde = f;
        else _fechaHasta = f;
      });
      _cargarDatos();
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
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Vacaciones del Area',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: Column(
        children: [

          // Filtros
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filtros',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF001E42))),
                const SizedBox(height: 12),

                // Filtro estado
                Row(children: [
                  const Text('Estado:',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF475569))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _filtroEstado ?? 'Todos',
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFCBD5E1))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFCBD5E1))),
                      ),
                      items: _estados
                          .map((e) => DropdownMenuItem(
                              value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) {
                        setState(() => _filtroEstado = v);
                        _cargarDatos();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),

                // Rango fechas
                Row(children: [
                  Expanded(
                    child: _BotonFecha(
                      label: _fechaDesde != null
                          ? 'Desde: ${_formatFecha(_fechaDesde!)}'
                          : 'Desde',
                      onTap: () => _seleccionarFecha(esDesde: true),
                      activo: _fechaDesde != null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BotonFecha(
                      label: _fechaHasta != null
                          ? 'Hasta: ${_formatFecha(_fechaHasta!)}'
                          : 'Hasta',
                      onTap: () => _seleccionarFecha(esDesde: false),
                      activo: _fechaHasta != null,
                    ),
                  ),
                  if (_fechaDesde != null || _fechaHasta != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _fechaDesde = null;
                          _fechaHasta = null;
                        });
                        _cargarDatos();
                      },
                    ),
                  ],
                ]),
              ],
            ),
          ),

          // Aviso solo lectura
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFEFF6FF),
            child: const Row(children: [
              Icon(Icons.visibility_outlined,
                  size: 14, color: Color(0xFF2563EB)),
              SizedBox(width: 6),
              Text(
                'Modo lectura — solo puedes visualizar esta informacion',
                style: TextStyle(fontSize: 12, color: Color(0xFF2563EB)),
              ),
            ]),
          ),

          // Lista
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF001E42)))
                : _error.isNotEmpty
                    ? Center(
                        child: Text(_error,
                            style: const TextStyle(color: Colors.red)))
                    : _solicitudes.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 48,
                                    color: Color(0xFF94A3B8)),
                                SizedBox(height: 12),
                                Text('No hay solicitudes con esos filtros',
                                    style: TextStyle(
                                        color: Color(0xFF64748B))),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _solicitudes.length,
                            itemBuilder: (context, index) {
                              final s = _solicitudes[index];
                              final estado = s['estado'] ?? 'Pendiente';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withOpacity(0.03),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              s['nombre'] ?? '—',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  fontSize: 15),
                                            ),
                                          ),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _bgEstado(estado),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      6),
                                              border: Border.all(
                                                  color: _colorEstado(
                                                          estado)
                                                      .withOpacity(0.3)),
                                            ),
                                            child: Text(estado,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: _colorEstado(
                                                        estado))),
                                          ),
                                        ]),
                                    const SizedBox(height: 6),
                                    Text(s['cargo'] ?? '—',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B))),
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      const Icon(
                                          Icons.calendar_today_outlined,
                                          size: 14,
                                          color: Color(0xFF94A3B8)),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${s['fecha_inicio']} - ${s['fecha_fin']}',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF475569)),
                                      ),
                                      const Spacer(),
                                      const Icon(Icons.wb_sunny_outlined,
                                          size: 14,
                                          color: Color(0xFF94A3B8)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${s['dias_habiles']} dias habiles',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF475569)),
                                      ),
                                    ]),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      const Icon(Icons.beach_access_outlined,
                                          size: 14,
                                          color: Color(0xFF0D9488)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Saldo total: ${s['saldo_total']} dias',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF0D9488),
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ]),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _BotonFecha extends StatelessWidget {
  final String    label;
  final VoidCallback onTap;
  final bool      activo;

  const _BotonFecha({
    required this.label,
    required this.onTap,
    required this.activo,
  });

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
            color: activo
                ? const Color(0xFF2563EB)
                : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined,
              size: 14,
              color: activo
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: activo
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF94A3B8))),
          ),
        ]),
      ),
    );
  }
}