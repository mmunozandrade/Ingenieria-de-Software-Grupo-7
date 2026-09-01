import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class InformeRemuneracionesScreen extends StatefulWidget {
  const InformeRemuneracionesScreen({super.key});

  @override
  State<InformeRemuneracionesScreen> createState() =>
      _InformeRemuneracionesScreenState();
}

class _InformeRemuneracionesScreenState
    extends State<InformeRemuneracionesScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _cargando = false;
  bool _descargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

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
      _resultado = null;
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
      _resultado = null;
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/informe-remuneraciones?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _resultado = data);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al consultar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Future<void> _descargar(String formato) async {
    if (_empleadoSeleccionado == null) return;
    setState(() => _descargando = true);
    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';
    try {
      final token = await SessionService.obtenerToken();
      final url =
          '$_apiUrl/admin/informe-remuneraciones/$formato?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final contentType = formato == 'excel'
            ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            : 'application/pdf';
        final extension = formato == 'excel' ? 'xlsx' : 'pdf';
        final rut = _empleadoSeleccionado!['rut'].toString().replaceAll(
          RegExp(r'[.\-]'),
          '',
        );
        final nombreArchivo =
            'informe_remuneraciones_${rut}_${periodo.replaceAll('/', '-')}.$extension';

        final blob = html.Blob([response.bodyBytes], contentType);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: blobUrl)
          ..setAttribute('download', nombreArchivo)
          ..click();
        html.Url.revokeObjectUrl(blobUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Descargando $nombreArchivo'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['mensaje'] ?? 'Error al generar el informe'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo conectar al servidor'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _descargando = false);
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
          'Informe de Remuneraciones',
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

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: paddingHorizontal,
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidthContenido),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Generar Informe',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sueldo base, bonos, deducciones previsionales, impuesto único y monto neto — exportable a Excel o PDF',
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
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
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
                                    subtitle: Text(
                                      '${e['rut']} · ${e['cargo']}',
                                    ),
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
                                          child: Text(
                                            m.toString().padLeft(2, '0'),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(
                                    () => _mesSeleccionado =
                                        v ?? _mesSeleccionado,
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
                                    () => _anioSeleccionado =
                                        v ?? _anioSeleccionado,
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
                                  : const Icon(
                                      Icons.summarize_outlined,
                                      size: 18,
                                    ),
                              label: const Text('Generar Informe'),
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

                    if (_resultado != null) ...[
                      const SizedBox(height: 20),
                      _TarjetaInforme(datos: _resultado!),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _descargando
                                  ? null
                                  : () => _descargar('excel'),
                              icon: const Icon(Icons.grid_on, size: 18),
                              label: const Text('Exportar Excel'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF059669),
                                side: const BorderSide(
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _descargando
                                  ? null
                                  : () => _descargar('pdf'),
                              icon: const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 18,
                              ),
                              label: const Text('Exportar PDF'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _TarjetaInforme extends StatelessWidget {
  final Map<String, dynamic> datos;
  const _TarjetaInforme({required this.datos});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${datos['nombre']} · ${datos['periodo']}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001E42),
            ),
          ),
          Text(
            datos['rut'] ?? '',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const Divider(height: 24),
          _fila('Sueldo base', datos['sueldo_base']),
          _fila('Bonos no sujetos a impuestos', datos['bonos_no_imponibles']),
          _fila('Bonos sujetos a impuestos', datos['bonos_imponibles']),
          _fila(
            'Deducciones previsionales',
            datos['deducciones_previsionales'],
            esDescuento: true,
          ),
          _fila('Impuesto único', datos['impuesto_unico'], esDescuento: true),
          _fila(
            'Otras deducciones',
            datos['otras_deducciones'],
            esDescuento: true,
          ),
          const Divider(height: 24),
          _fila(
            'MONTO NETO A PAGAR',
            datos['monto_neto_a_pagar'],
            destacado: true,
          ),
        ],
      ),
    );
  }

  Widget _fila(
    String label,
    dynamic monto, {
    bool esDescuento = false,
    bool destacado = false,
  }) {
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
            '${esDescuento ? "-" : ""}\$$monto CLP',
            style: TextStyle(
              fontSize: destacado ? 16 : 13,
              fontWeight: FontWeight.bold,
              color: destacado
                  ? const Color(0xFF059669)
                  : (esDescuento
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }
}
