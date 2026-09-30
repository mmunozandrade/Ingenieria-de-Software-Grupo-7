import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlAprobarAnt = 'http://127.0.0.1:8000';

/// Pantalla del ADMINISTRADOR para revisar y decidir las solicitudes
/// pendientes de Anticipo de Sueldo Excepcional. Al decidir, el
/// sistema notifica al trabajador por correo institucional, y si es
/// aprobado, el descuento se aplica solo en la liquidacion del
/// periodo (sin ningun paso adicional aqui).
class AprobarAnticiposScreen extends StatefulWidget {
  const AprobarAnticiposScreen({super.key});

  @override
  State<AprobarAnticiposScreen> createState() => _AprobarAnticiposScreenState();
}

class _AprobarAnticiposScreenState extends State<AprobarAnticiposScreen> {
  List<dynamic> _anticipos = [];
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlAprobarAnt/admin/anticipos-sueldo?estado=pendiente'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _anticipos = data['anticipos'] ?? []);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _decidir(int anticipoId, String estado) async {
    String? observacion;
    if (estado == 'rechazado') {
      observacion = await _pedirObservacion();
      if (observacion == null) return; // cancelado
    }
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse(
          '$_apiUrlAprobarAnt/admin/anticipos-sueldo/$anticipoId/decision',
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
      if (data['success'] == true) _cargarPendientes();
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

  String _formatearMiles(dynamic valor) {
    final soloDigitos = valor.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) return '0';
    final buffer = StringBuffer();
    for (int i = 0; i < soloDigitos.length; i++) {
      final posicionDesdeDerecha = soloDigitos.length - i;
      buffer.write(soloDigitos[i]);
      if (posicionDesdeDerecha > 1 && posicionDesdeDerecha % 3 == 1)
        buffer.write('.');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Aprobar Anticipos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _cargarPendientes,
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
                    'Solicitudes de Anticipo Excepcional Pendientes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF001E42),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_cargando)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_error.isNotEmpty)
                    Text(_error, style: const TextStyle(color: Colors.red))
                  else if (_anticipos.isEmpty)
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
                          'No hay solicitudes pendientes.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    )
                  else
                    ..._anticipos.map(
                      (a) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  a['nombre_trabajador'] ?? 'Trabajador',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'PENDIENTE',
                                    style: TextStyle(
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
                              'RUT: ${a['rut'] ?? '—'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              'Periodo: ${a['periodo']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '\$${_formatearMiles(a['monto_clp'])} CLP',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _decidir(a['anticipo_id'], 'rechazado'),
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
                                    onPressed: () =>
                                        _decidir(a['anticipo_id'], 'aprobado'),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Aprobar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF059669),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
