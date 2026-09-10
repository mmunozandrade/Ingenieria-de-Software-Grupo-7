import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class ParametrizacionConceptosScreen extends StatefulWidget {
  const ParametrizacionConceptosScreen({super.key});

  @override
  State<ParametrizacionConceptosScreen> createState() =>
      _ParametrizacionConceptosScreenState();
}

class _ParametrizacionConceptosScreenState
    extends State<ParametrizacionConceptosScreen> {
  List<dynamic> _conceptos = [];
  bool _cargando = true;

  // Formulario nuevo/edicion
  int? _conceptoEditandoId;
  final _nombreController = TextEditingController();
  final _descripcionController = TextEditingController();
  String _tipo = 'Fijo';
  String _clasificacion = 'Imponible';

  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  @override
  void initState() {
    super.initState();
    _cargarConceptos();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _cargarConceptos() async {
    setState(() => _cargando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/conceptos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _conceptos = data['conceptos'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _iniciarEdicion(Map<String, dynamic> c) {
    setState(() {
      _conceptoEditandoId = c['concepto_id'];
      _nombreController.text = c['nombre'];
      _descripcionController.text = c['descripcion'] ?? '';
      _tipo = c['tipo'];
      _clasificacion = c['clasificacion'];
      _mensaje = '';
    });
  }

  void _cancelarEdicion() {
    setState(() {
      _conceptoEditandoId = null;
      _nombreController.clear();
      _descripcionController.clear();
      _tipo = 'Fijo';
      _clasificacion = 'Imponible';
      _mensaje = '';
    });
  }

  Future<void> _guardarConcepto() async {
    if (_nombreController.text.trim().length < 3) {
      setState(() {
        _exito = false;
        _mensaje = 'Debe rellenar los campos obligatorios';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensaje = '';
    });

    final body = jsonEncode({
      'nombre': _nombreController.text.trim(),
      'tipo': _tipo,
      'clasificacion': _clasificacion,
      'descripcion': _descripcionController.text.trim(),
    });

    try {
      final token = await SessionService.obtenerToken();
      final esEdicion = _conceptoEditandoId != null;
      final response = esEdicion
          ? await http.put(
              Uri.parse('$_apiUrl/admin/conceptos/$_conceptoEditandoId'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: body,
            )
          : await http.post(
              Uri.parse('$_apiUrl/admin/conceptos'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: body,
            );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? (esEdicion
                  ? 'Concepto actualizado correctamente'
                  : 'Concepto creado correctamente')
            : (data['mensaje'] ?? 'Error al guardar');
      });
      if (_exito) {
        _cancelarEdicion();
        _cargarConceptos();
      }
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _enviando = false);
    }
  }

  Future<void> _cambiarEstado(Map<String, dynamic> c) async {
    final nuevoEstado = !(c['activo'] as bool);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/admin/conceptos/${c['concepto_id']}/estado'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'activo': nuevoEstado}),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? (data['mensaje'] ?? 'Actualizado')
                  : (data['mensaje'] ?? 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
      if (data['success'] == true) _cargarConceptos();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar al servidor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _eliminarConcepto(Map<String, dynamic> c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Eliminar concepto'),
        content: Text(
          '¿Seguro que quieres eliminar "${c['nombre']}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.delete(
        Uri.parse('$_apiUrl/admin/conceptos/${c['concepto_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? (data['mensaje'] ?? 'Eliminado')
                  : (data['mensaje'] ?? 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
      if (data['success'] == true) _cargarConceptos();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar al servidor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _colorClasificacion(String c) =>
      c == 'Imponible' ? const Color(0xFF1D4ED8) : const Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Parametrización de Conceptos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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

          return SizedBox(
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
                    const Text(
                      'Conceptos de Haberes',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Los conceptos base (Sueldo base, Horas extras, AFP, Institución de salud) no se pueden eliminar ni desactivar',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 24),

                    // ── Formulario ────────────────────────────────
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
                          Text(
                            _conceptoEditandoId == null
                                ? 'Nuevo Concepto'
                                : 'Editando Concepto',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Nombre:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _nombreController,
                            maxLength: 100,
                            decoration: InputDecoration(
                              hintText: 'Ej: Bono de Antigüedad',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _tipo,
                                  decoration: InputDecoration(
                                    labelText: 'Tipo',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Fijo',
                                      child: Text('Fijo'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'Variable',
                                      child: Text('Variable'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _tipo = v ?? _tipo),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _clasificacion,
                                  decoration: InputDecoration(
                                    labelText: 'Clasificación',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'Imponible',
                                      child: Text('Imponible'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'No imponible',
                                      child: Text('No imponible'),
                                    ),
                                  ],
                                  onChanged: (v) => setState(
                                    () => _clasificacion = v ?? _clasificacion,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Descripción:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _descripcionController,
                            maxLength: 500,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Descripción del concepto...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (_mensaje.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: _exito
                                    ? Colors.green[50]
                                    : Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _exito
                                      ? Colors.green[200]!
                                      : Colors.red[200]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _exito
                                        ? Icons.check_circle_outline
                                        : Icons.error_outline,
                                    color: _exito ? Colors.green : Colors.red,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _mensaje,
                                      style: TextStyle(
                                        color: _exito
                                            ? Colors.green
                                            : Colors.red,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    onPressed: _enviando
                                        ? null
                                        : _guardarConcepto,
                                    icon: _enviando
                                        ? const SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            _conceptoEditandoId == null
                                                ? Icons.add
                                                : Icons.save,
                                            size: 18,
                                          ),
                                    label: Text(
                                      _conceptoEditandoId == null
                                          ? 'Crear Concepto'
                                          : 'Guardar Cambios',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF001E42),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_conceptoEditandoId != null) ...[
                                const SizedBox(width: 10),
                                TextButton(
                                  onPressed: _cancelarEdicion,
                                  child: const Text('Cancelar'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    const Text(
                      'Conceptos Registrados',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_cargando)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      ..._conceptos.map(
                        (c) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c['activo'] == true
                                ? Colors.white
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Text(
                                          c['nombre'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        if (c['es_base'] == true) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F5F9),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'BASE',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (c['activo'] != true) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEE2E2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Text(
                                              'INACTIVO',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFDC2626),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: c['activo'] == true,
                                    onChanged:
                                        c['es_base'] == true &&
                                            c['activo'] == true
                                        ? null
                                        : (_) => _cambiarEstado(c),
                                    activeColor: const Color(0xFF059669),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                      color: Color(0xFF64748B),
                                    ),
                                    onPressed: () => _iniciarEdicion(c),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: c['es_base'] == true
                                          ? const Color(0xFFCBD5E1)
                                          : const Color(0xFFDC2626),
                                    ),
                                    tooltip: c['es_base'] == true
                                        ? 'No se puede eliminar.'
                                        : 'Eliminar concepto',
                                    onPressed: c['es_base'] == true
                                        ? null
                                        : () => _eliminarConcepto(c),
                                  ),
                                ],
                              ),
                              Text(
                                '${c['tipo']} · ${c['clasificacion']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _colorClasificacion(
                                    c['clasificacion'],
                                  ),
                                ),
                              ),
                              if ((c['descripcion'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    c['descripcion'],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 30),
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
