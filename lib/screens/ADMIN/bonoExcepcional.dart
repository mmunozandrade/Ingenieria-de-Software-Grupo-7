import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class BonoExcepcionalScreen extends StatefulWidget {
  final Map<String, dynamic>? empleadoPreseleccionado;
  const BonoExcepcionalScreen({super.key, this.empleadoPreseleccionado});

  @override
  State<BonoExcepcionalScreen> createState() => _BonoExcepcionalScreenState();
}

class _BonoExcepcionalScreenState extends State<BonoExcepcionalScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  final _conceptoController = TextEditingController();
  final _montoController = TextEditingController();
  String _clasificacion = 'Imponible';
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  List<dynamic> _bonos = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    if (widget.empleadoPreseleccionado != null) {
      _empleadoSeleccionado = widget.empleadoPreseleccionado;
      _busquedaController.text =
          '${widget.empleadoPreseleccionado!['nombres'] ?? ''} ${widget.empleadoPreseleccionado!['apellidos'] ?? ''}';
    }
    _cargarHistorial();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _conceptoController.dispose();
    _montoController.dispose();
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
    });
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/bono-excepcional'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _bonos = data['bonos'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _registrarBono() async {
    if (_empleadoSeleccionado == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona un trabajador';
      });
      return;
    }
    if (_conceptoController.text.trim().length < 3) {
      setState(() {
        _exito = false;
        _mensaje = 'El concepto debe tener al menos 3 caracteres';
      });
      return;
    }
    final monto = int.tryParse(_montoController.text.trim());
    if (monto == null || monto <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Ingresa un monto válido mayor a 0';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensaje = '';
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/bono-excepcional'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'concepto': _conceptoController.text.trim(),
          'monto_clp': monto,
          'clasificacion': _clasificacion,
          'periodo': periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Bono excepcional registrado correctamente'
            : (data['mensaje'] ?? 'Error al registrar');
      });
      if (_exito) {
        setState(() {
          _empleadoSeleccionado = null;
          _busquedaController.clear();
          _conceptoController.clear();
          _montoController.clear();
          _clasificacion = 'Imponible';
        });
        _cargarHistorial();
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
          'Bono Excepcional',
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
                      'Agregar Bono Excepcional',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Se registra automáticamente en el log de auditoría (administrador, RUT del trabajador, monto y fecha)',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 24),

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
                          const SizedBox(height: 20),

                          const Text(
                            'Concepto del bono:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _conceptoController,
                            maxLength: 100,
                            decoration: InputDecoration(
                              hintText:
                                  'Ej: Reconocimiento por desempeño destacado',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          const Text(
                            'Monto (CLP):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _montoController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Ej: 100000',
                              prefixText: '\$ ',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          const Text(
                            'Clasificación:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Imponible'),
                                selected: _clasificacion == 'Imponible',
                                onSelected: (_) => setState(
                                  () => _clasificacion = 'Imponible',
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('No imponible'),
                                selected: _clasificacion == 'No imponible',
                                onSelected: (_) => setState(
                                  () => _clasificacion = 'No imponible',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

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
                          const SizedBox(height: 20),

                          if (_mensaje.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
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
                              child: Text(
                                _mensaje,
                                style: TextStyle(
                                  color: _exito ? Colors.green : Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _enviando ? null : _registrarBono,
                              icon: _enviando
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.star_outline, size: 18),
                              label: const Text('Registrar Bono Excepcional'),
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
                    const SizedBox(height: 28),

                    const Text(
                      'Historial de Bonos Excepcionales',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_cargandoHistorial)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_bonos.isEmpty)
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
                            'No hay bonos excepcionales registrados',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ),
                      )
                    else
                      ..._bonos.map(
                        (b) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: b['clasificacion'] == 'Imponible'
                                      ? const Color(0xFFEFF6FF)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  b['clasificacion'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: b['clasificacion'] == 'Imponible'
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      b['concepto'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${b['nombre_trabajador']} (${b['rut']}) · Periodo: ${b['periodo']}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    Text(
                                      'Registrado por ${b['nombre_admin']} el ${b['fecha_registro']}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '\$${b['monto_clp']} CLP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
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
