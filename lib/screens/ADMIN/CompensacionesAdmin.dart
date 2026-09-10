import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class CompensacionesAdmin extends StatefulWidget {
  const CompensacionesAdmin({super.key});

  @override
  State<CompensacionesAdmin> createState() => _CompensacionesAdminState();
}

class _CompensacionesAdminState extends State<CompensacionesAdmin> {
  List<dynamic> _compensaciones = [];
  bool _cargando = true;
  String _error = '';
  String _filtroEstado = 'Todas';

  final List<String> _estados = ['Todas', 'Pendiente', 'Aprobada', 'Rechazada'];

  @override
  void initState() {
    super.initState();
    _cargarCompensaciones();
  }

  Future<void> _cargarCompensaciones() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/compensaciones-pendientes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _compensaciones = data['compensaciones'] ?? []);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  /// Compara ignorando el género de la palabra (Aprobada/Aprobado,
  /// Rechazada/Rechazado), ya que el backend puede guardar el estado
  /// en masculino aunque los filtros se muestren en femenino.
  bool _mismoEstado(String estadoBackend, String filtro) {
    String raiz(String s) =>
        s.toLowerCase().substring(0, s.length > 3 ? s.length - 1 : s.length);
    return raiz(estadoBackend) == raiz(filtro);
  }

  List<dynamic> get _compensacionesFiltradas {
    if (_filtroEstado == 'Todas') return _compensaciones;
    return _compensaciones
        .where((c) => _mismoEstado(c['estado'] ?? '', _filtroEstado))
        .toList();
  }

  // ── Modal aprobar/rechazar ────────────────────────────────
  void _abrirModalDecision(Map<String, dynamic> comp, String accion) {
    final obsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              accion == 'Aprobada'
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              color: accion == 'Aprobada'
                  ? const Color(0xFF059669)
                  : Colors.red,
            ),
            const SizedBox(width: 10),
            Text(
              accion == 'Aprobada'
                  ? 'Aprobar Compensacion'
                  : 'Rechazar Compensacion',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF001E42),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Resumen
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comp['nombre_trabajador'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Dias a compensar: ${comp['dias_compensados']}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF475569),
                      ),
                    ),
                    Text(
                      'Monto: \$${comp['monto_clp']} CLP',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF475569),
                      ),
                    ),
                    Text(
                      'Solicitado: ${comp['fecha_solicitud']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Observacion
              Text(
                accion == 'Aprobada'
                    ? 'Observacion (opcional):'
                    : 'Motivo de rechazo (obligatorio):',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: obsController,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: accion == 'Aprobada'
                      ? 'Ej: Aprobado por RRHH'
                      : 'Ej: No cumple los requisitos...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF001E42)),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accion == 'Aprobada'
                  ? const Color(0xFF059669)
                  : Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => _procesarDecision(
              ctx,
              comp['compensacion_id'],
              accion,
              obsController.text.trim(),
            ),
            child: Text(
              accion == 'Aprobada' ? 'Aprobar' : 'Rechazar',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _procesarDecision(
    BuildContext ctx,
    int compensacionId,
    String estado,
    String observacion,
  ) async {
    // Validar observacion obligatoria para rechazo
    if (estado == 'Rechazada' && observacion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El motivo de rechazo es obligatorio'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/aprobar-compensacion/$compensacionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'estado': estado, 'observacion': observacion}),
      );
      final data = jsonDecode(response.body);
      Navigator.pop(ctx);

      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              estado == 'Aprobada'
                  ? 'Compensacion aprobada correctamente'
                  : 'Compensacion rechazada',
            ),
            backgroundColor: estado == 'Aprobada'
                ? const Color(0xFF059669)
                : Colors.red,
          ),
        );
        _cargarCompensaciones();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['mensaje'] ?? 'Error al procesar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar al servidor'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lista = _compensacionesFiltradas;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Compensaciones Progresivas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarCompensaciones,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final bool esEscritorio = ancho >= 1280;
          final bool esTablet = ancho >= 768 && ancho < 1280;
          final double paddingHorizontal = esEscritorio
              ? 40
              : (esTablet ? 28 : 16);
          final double maxWidthContenido = esEscritorio
              ? 900
              : (esTablet ? 700 : double.infinity);

          return _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF001E42)),
                )
              : _error.isNotEmpty
              ? Center(
                  child: Text(
                    _error,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: paddingHorizontal,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidthContenido),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Titulo
                          const Text(
                            'Gestion de Compensaciones',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Aprobacion de solicitudes de compensacion en efectivo por dias progresivos',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Filtro estado
                          Row(
                            children: [
                              const Text(
                                'Filtrar por estado:',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ..._estados.map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(e),
                                    selected: _filtroEstado == e,
                                    selectedColor: const Color(0xFF001E42),
                                    labelStyle: TextStyle(
                                      color: _filtroEstado == e
                                          ? Colors.white
                                          : const Color(0xFF475569),
                                      fontSize: 12,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _filtroEstado = e),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Lista
                          if (lista.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(40),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.payments_outlined,
                                    size: 48,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _filtroEstado == 'Todas'
                                        ? 'No hay solicitudes de compensacion'
                                        : 'No hay solicitudes con estado "$_filtroEstado"',
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...lista.map(
                              (c) => _TarjetaCompensacionAdmin(
                                comp: c,
                                onAprobar: () =>
                                    _abrirModalDecision(c, 'Aprobada'),
                                onRechazar: () =>
                                    _abrirModalDecision(c, 'Rechazada'),
                              ),
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

// ── Tarjeta compensacion admin ────────────────────────────────
class _TarjetaCompensacionAdmin extends StatelessWidget {
  final Map<String, dynamic> comp;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  const _TarjetaCompensacionAdmin({
    required this.comp,
    required this.onAprobar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final estado = comp['estado'] ?? 'Pendiente';
    final bool isPendiente = estado == 'Pendiente';

    final Color colorEstado;
    final Color bgEstado;

    switch (estado) {
      case 'Aprobado':
        colorEstado = const Color(0xFF059669);
        bgEstado = const Color(0xFFECFDF5);
        break;
      case 'Rechazado':
        colorEstado = Colors.red;
        bgEstado = const Color(0xFFFEF2F2);
        break;
      default:
        colorEstado = const Color(0xFFD97706);
        bgEstado = const Color(0xFFFFFBEB);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPendiente
              ? const Color(0xFFFDE68A)
              : const Color(0xFFE2E8F0),
          width: isPendiente ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  comp['nombre_trabajador'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bgEstado,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  estado,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorEstado,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 20),

          // Detalle
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FilaInfo(
                      label: 'Dias a compensar:',
                      valor: '${comp['dias_compensados']} dias',
                    ),
                    const SizedBox(height: 6),
                    _FilaInfo(
                      label: 'Monto calculado:',
                      valor: '\$${comp['monto_clp']} CLP',
                      valorStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _FilaInfo(
                      label: 'Fecha solicitud:',
                      valor: comp['fecha_solicitud'] ?? '',
                    ),
                    if (comp['fecha_decision'] != null) ...[
                      const SizedBox(height: 6),
                      _FilaInfo(
                        label: 'Fecha decision:',
                        valor: comp['fecha_decision'],
                      ),
                    ],
                    if (comp['observacion'] != null &&
                        comp['observacion'].toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _FilaInfo(
                        label: 'Observacion:',
                        valor: comp['observacion'],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // Botones solo si pendiente
          if (isPendiente) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Rechazar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onRechazar,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Aprobar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: onAprobar,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaInfo extends StatelessWidget {
  final String label;
  final String valor;
  final TextStyle? valorStyle;

  const _FilaInfo({required this.label, required this.valor, this.valorStyle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF475569),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            valor,
            style:
                valorStyle ??
                const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
