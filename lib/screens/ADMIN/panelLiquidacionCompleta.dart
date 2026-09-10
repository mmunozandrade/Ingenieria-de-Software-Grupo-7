import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';
import 'desgloseLiquidacionWidget.dart';
import 'cierreLiquidacion.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class PanelLiquidacionCompletaScreen extends StatefulWidget {
  const PanelLiquidacionCompletaScreen({super.key});

  @override
  State<PanelLiquidacionCompletaScreen> createState() =>
      _PanelLiquidacionCompletaScreenState();
}

class _PanelLiquidacionCompletaScreenState
    extends State<PanelLiquidacionCompletaScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _panel;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _buscarEmpleado(String texto) async {
    if (texto.trim().length < 3) {
      setState(() => _resultadosBusqueda = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/buscar-empleados?apellido=${Uri.encodeComponent(texto)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _resultadosBusqueda = data['empleados'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _buscando = false);
    }
  }

  void _seleccionarEmpleado(Map<String, dynamic> e) {
    setState(() {
      _empleadoSeleccionado = e;
      _resultadosBusqueda = [];
      _busquedaController.text = '${e['nombres']} ${e['apellidos']}';
      _panel = null;
      _error = '';
    });
  }

  Future<void> _consultar() async {
    if (_empleadoSeleccionado == null) {
      setState(() => _error = 'Selecciona un trabajador');
      return;
    }
    setState(() {
      _cargando = true;
      _error = '';
      _panel = null;
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/panel-liquidacion-completa?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _panel = data);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al consultar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(11, (i) => anioActual - i);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Panel de Liquidación',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Panel Consolidado de Liquidación',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Vista completa de un trabajador y período: resumen, costo empleador y detalle itemizado',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),

                Container(
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
                      const Text(
                        'Trabajador:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _busquedaController,
                        onChanged: (v) {
                          _empleadoSeleccionado = null;
                          _buscarEmpleado(v);
                        },
                        decoration: InputDecoration(
                          hintText:
                              'Buscar por apellido (mínimo 3 caracteres)...',
                          suffixIcon: _buscando
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      if (_resultadosBusqueda.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _resultadosBusqueda.length,
                            itemBuilder: (ctx, i) {
                              final e = _resultadosBusqueda[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${e['nombres']} ${e['apellidos']}',
                                ),
                                subtitle: Text('${e['rut']} · ${e['cargo']}'),
                                onTap: () => _seleccionarEmpleado(e),
                              );
                            },
                          ),
                        ),
                      if (_empleadoSeleccionado != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} (${_empleadoSeleccionado!['rut']})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      const Text(
                        'Periodo:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _mesSeleccionado,
                              decoration: InputDecoration(
                                labelText: 'Mes',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: List.generate(12, (i) => i + 1)
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m.toString().padLeft(2, '0')),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () => _mesSeleccionado = v ?? _mesSeleccionado,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _anioSeleccionado,
                              decoration: InputDecoration(
                                labelText: 'Año',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: anios
                                  .map(
                                    (a) => DropdownMenuItem(
                                      value: a,
                                      child: Text('$a'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () =>
                                    _anioSeleccionado = v ?? _anioSeleccionado,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_error.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Text(
                            _error,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _cargando ? null : _consultar,
                          icon: _cargando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.dashboard_outlined, size: 18),
                          label: const Text('Cargar Panel Completo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF001E42),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_panel != null) ...[
                  const SizedBox(height: 20),
                  _EstadoLiquidacionBanner(
                    estado: _panel!['estado_liquidacion'],
                  ),
                  const SizedBox(height: 16),
                  TarjetaDesgloseLiquidacion(resultado: _panel!['resumen']),
                  const SizedBox(height: 16),
                  if (_panel!['costo_empleador'] != null)
                    _TarjetaCostoEmpleador(costo: _panel!['costo_empleador']),
                  const SizedBox(height: 16),
                  _SeccionItemizado(itemizado: _panel!['itemizado'] ?? {}),
                  const SizedBox(height: 20),
                  if (_panel!['estado_liquidacion']['cerrada'] != true)
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CierreLiquidacionScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Ir a Cerrar Liquidación'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF001E42),
                          side: const BorderSide(color: Color(0xFF001E42)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EstadoLiquidacionBanner extends StatelessWidget {
  final Map<String, dynamic> estado;
  const _EstadoLiquidacionBanner({required this.estado});

  @override
  Widget build(BuildContext context) {
    final cerrada = estado['cerrada'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cerrada ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cerrada ? const Color(0xFFBFDBFE) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            cerrada ? Icons.lock : Icons.lock_open,
            color: cerrada ? const Color(0xFF1D4ED8) : const Color(0xFFD97706),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              cerrada
                  ? 'Liquidación CERRADA el ${estado['fecha_cierre'] ?? '—'} — no se pueden agregar más datos a este período.'
                  : 'Liquidación ABIERTA — aún se pueden registrar descuentos, bonos u otros conceptos.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cerrada
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFFD97706),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaCostoEmpleador extends StatelessWidget {
  final Map<String, dynamic> costo;
  const _TarjetaCostoEmpleador({required this.costo});

  @override
  Widget build(BuildContext context) {
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
          const Text(
            'Costo Total Empleador',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001E42),
            ),
          ),
          const Divider(height: 20),
          _fila('Sueldo bruto', costo['sueldo_bruto']),
          _fila('Aporte AFP (SIS)', costo['aporte_afp_empleador']),
          _fila('Aporte Salud empleador', costo['aporte_salud_empleador']),
          _fila('Aporte AFC empleador', costo['aporte_afc_empleador']),
          const Divider(height: 20),
          _fila(
            'COSTO TOTAL EMPLEADOR',
            costo['costo_total_empleador'],
            destacado: true,
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, dynamic monto, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: destacado ? 14 : 13,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
              color: const Color(0xFF475569),
            ),
          ),
          Text(
            '\$$monto CLP',
            style: TextStyle(
              fontSize: destacado ? 15 : 13,
              fontWeight: FontWeight.bold,
              color: destacado
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeccionItemizado extends StatelessWidget {
  final Map<String, dynamic> itemizado;
  const _SeccionItemizado({required this.itemizado});

  @override
  Widget build(BuildContext context) {
    final descuentos = itemizado['descuentos'] as List? ?? [];
    final bonosImp = itemizado['bonos_imponibles'] as List? ?? [];
    final bonosExc = itemizado['bonos_excepcionales'] as List? ?? [];
    final bonosCond = itemizado['bonos_condicionales'] as List? ?? [];
    final licencias = itemizado['licencias'] as List? ?? [];
    final horasExtras = itemizado['horas_extras'] as List? ?? [];
    final anticipos = itemizado['anticipos'] as List? ?? [];
    final movilizacion = itemizado['movilizacion_colacion'] as List? ?? [];

    final vacio =
        descuentos.isEmpty &&
        bonosImp.isEmpty &&
        bonosExc.isEmpty &&
        bonosCond.isEmpty &&
        licencias.isEmpty &&
        horasExtras.isEmpty &&
        anticipos.isEmpty &&
        movilizacion.isEmpty;

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
          const Text(
            'Detalle Itemizado del Período',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001E42),
            ),
          ),
          const Divider(height: 20),
          if (vacio)
            const Text(
              'No hay conceptos adicionales registrados para este período.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          if (descuentos.isNotEmpty)
            _grupo(
              'Descuentos',
              descuentos
                  .map(
                    (d) => '${d['tipo']} · ${d['fecha']} · \$${d['monto']} CLP',
                  )
                  .toList(),
              const Color(0xFFDC2626),
            ),
          if (bonosImp.isNotEmpty)
            _grupo(
              'Bonos Imponibles',
              bonosImp
                  .map((b) => '${b['tipo']} · \$${b['monto']} CLP')
                  .toList(),
              const Color(0xFF059669),
            ),
          if (bonosExc.isNotEmpty)
            _grupo(
              'Bonos Excepcionales',
              bonosExc
                  .map(
                    (b) =>
                        '${b['concepto']} (${b['clasificacion']}) · \$${b['monto']} CLP',
                  )
                  .toList(),
              const Color(0xFFD97706),
            ),
          if (bonosCond.isNotEmpty)
            _grupo(
              'Bonos Condicionales',
              bonosCond
                  .map(
                    (b) =>
                        '${b['concepto']} · ${b['cumple'] == true ? "Cumple" : "No cumple"} · \$${b['monto']} CLP',
                  )
                  .toList(),
              const Color(0xFF7C3AED),
            ),
          if (licencias.isNotEmpty)
            _grupo(
              'Licencias Médicas',
              licencias
                  .map(
                    (l) =>
                        '${l['tipo']} · ${l['inicio']} - ${l['fin']} · \$${l['monto']} CLP',
                  )
                  .toList(),
              const Color(0xFF64748B),
            ),
          if (horasExtras.isNotEmpty)
            _grupo(
              'Horas Extras',
              horasExtras
                  .map(
                    (h) =>
                        '${h['cantidad_horas']} hrs · valor hora extra \$${h['valor_hora_extra']}',
                  )
                  .toList(),
              const Color(0xFF1D4ED8),
            ),
          if (anticipos.isNotEmpty)
            _grupo(
              'Anticipos',
              anticipos
                  .map(
                    (a) =>
                        '${a['estado']} · Folio: ${a['folio']} · \$${a['monto']} CLP',
                  )
                  .toList(),
              const Color(0xFF0891B2),
            ),
          if (movilizacion.isNotEmpty)
            _grupo(
              'Movilización/Colación',
              movilizacion
                  .map(
                    (m) =>
                        '${m['concepto']} · Total \$${m['monto_total']} (exento \$${m['exento']}, excedente \$${m['excedente']})',
                  )
                  .toList(),
              const Color(0xFFEA580C),
            ),
        ],
      ),
    );
  }

  Widget _grupo(String titulo, List<String> lineas, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          ...lineas.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 8),
              child: Text(
                '• $l',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
