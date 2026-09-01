import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class BonosCondicionalesScreen extends StatefulWidget {
  const BonosCondicionalesScreen({super.key});

  @override
  State<BonosCondicionalesScreen> createState() =>
      _BonosCondicionalesScreenState();
}

class _BonosCondicionalesScreenState extends State<BonosCondicionalesScreen> {
  List<dynamic> _reglas = [];
  bool _cargandoReglas = true;

  final _nombreController = TextEditingController();
  final _condicionController = TextEditingController();
  final _montoController = TextEditingController();
  final _porcentajeController = TextEditingController();
  String _tipoMonto = 'fijo';
  String _clasificacion = 'Imponible';
  bool _enviandoRegla = false;
  String _mensajeRegla = '';
  bool _exitoRegla = false;

  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;
  int? _reglaSeleccionadaId;
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;
  bool _enviandoAplicacion = false;
  String _mensajeAplicacion = '';
  bool _exitoAplicacion = false;

  List<dynamic> _aplicadas = [];
  bool _consultando = false;

  @override
  void initState() {
    super.initState();
    _cargarReglas();
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _condicionController.dispose();
    _montoController.dispose();
    _porcentajeController.dispose();
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargarReglas() async {
    setState(() => _cargandoReglas = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/bono-reglas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _reglas = data['reglas'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _cargandoReglas = false);
    }
  }

  Future<void> _crearRegla() async {
    if (_nombreController.text.trim().length < 3) {
      setState(() {
        _exitoRegla = false;
        _mensajeRegla = 'El nombre debe tener al menos 3 caracteres';
      });
      return;
    }
    if (_condicionController.text.trim().isEmpty) {
      setState(() {
        _exitoRegla = false;
        _mensajeRegla = 'Describe la condición de aplicación';
      });
      return;
    }

    setState(() {
      _enviandoRegla = true;
      _mensajeRegla = '';
    });

    final body = <String, dynamic>{
      'nombre_concepto': _nombreController.text.trim(),
      'condicion_texto': _condicionController.text.trim(),
      'clasificacion': _clasificacion,
    };
    if (_tipoMonto == 'fijo') {
      body['monto_fijo_clp'] = int.tryParse(_montoController.text.trim());
    } else {
      body['porcentaje_base'] = double.tryParse(
        _porcentajeController.text.trim(),
      );
    }

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/bono-reglas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoRegla = data['success'] == true;
        _mensajeRegla = _exitoRegla
            ? 'Regla creada correctamente'
            : (data['mensaje'] ?? 'Error al crear la regla');
      });
      if (_exitoRegla) {
        _nombreController.clear();
        _condicionController.clear();
        _montoController.clear();
        _porcentajeController.clear();
        _cargarReglas();
      }
    } catch (_) {
      setState(() {
        _exitoRegla = false;
        _mensajeRegla = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _enviandoRegla = false);
    }
  }

  Future<void> _cambiarEstadoRegla(Map<String, dynamic> r) async {
    final nuevoEstado = !(r['activo'] as bool);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/admin/bono-reglas/${r['bono_id']}/estado'),
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
              data['mensaje'] ??
                  (data['success'] == true ? 'Actualizado' : 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
      if (data['success'] == true) _cargarReglas();
    } catch (_) {}
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
      _aplicadas = [];
    });
  }

  Future<void> _registrarAplicacion(bool cumple) async {
    if (_empleadoSeleccionado == null) {
      setState(() {
        _exitoAplicacion = false;
        _mensajeAplicacion = 'Selecciona un trabajador';
      });
      return;
    }
    if (_reglaSeleccionadaId == null) {
      setState(() {
        _exitoAplicacion = false;
        _mensajeAplicacion = 'Selecciona una regla';
      });
      return;
    }

    setState(() {
      _enviandoAplicacion = true;
      _mensajeAplicacion = '';
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/aplicar-bono-regla'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'bono_id': _reglaSeleccionadaId,
          'periodo': periodo,
          'cumple_condicion': cumple,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoAplicacion = data['success'] == true;
        _mensajeAplicacion = _exitoAplicacion
            ? (cumple
                  ? 'Cumple: se aplicó \$${data['monto_aplicado']} CLP'
                  : 'No cumple: no se aplica el bono')
            : (data['mensaje'] ?? 'Error al registrar');
      });
      if (_exitoAplicacion) _consultarAplicadas();
    } catch (_) {
      setState(() {
        _exitoAplicacion = false;
        _mensajeAplicacion = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _enviandoAplicacion = false);
    }
  }

  Future<void> _consultarAplicadas() async {
    if (_empleadoSeleccionado == null) return;
    setState(() => _consultando = true);
    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/bono-reglas-aplicadas?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _aplicadas = data['aplicaciones'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _consultando = false);
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
          'Bonos e Incentivos Condicionales',
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
                      'Nueva Regla de Bono',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'El bono solo se aplica si el trabajador cumple la condición (evaluación manual del administrador)',
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
                            'Nombre del concepto:',
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
                              hintText: 'Ej: Bono por Cumplimiento de Metas',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Condición de aplicación:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _condicionController,
                            maxLength: 200,
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText:
                                  'Ej: Asistencia completa durante el mes',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          const Text(
                            'Monto:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('Monto fijo CLP'),
                                selected: _tipoMonto == 'fijo',
                                onSelected: (_) =>
                                    setState(() => _tipoMonto = 'fijo'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('% del sueldo base'),
                                selected: _tipoMonto == 'porcentaje',
                                onSelected: (_) =>
                                    setState(() => _tipoMonto = 'porcentaje'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_tipoMonto == 'fijo')
                            TextField(
                              controller: _montoController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Ej: 50000',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            )
                          else
                            TextField(
                              controller: _porcentajeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                hintText: 'Ej: 10',
                                suffixText: '%',
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
                          const SizedBox(height: 16),

                          if (_mensajeRegla.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: _exitoRegla
                                    ? Colors.green[50]
                                    : Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _exitoRegla
                                      ? Colors.green[200]!
                                      : Colors.red[200]!,
                                ),
                              ),
                              child: Text(
                                _mensajeRegla,
                                style: TextStyle(
                                  color: _exitoRegla
                                      ? Colors.green
                                      : Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: _enviandoRegla ? null : _crearRegla,
                              icon: _enviandoRegla
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.add, size: 18),
                              label: const Text('Crear Regla'),
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
                    const SizedBox(height: 24),

                    const Text(
                      'Reglas Registradas',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_cargandoReglas)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      ..._reglas.map(
                        (r) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['nombre_concepto'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      r['condicion_texto'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    Text(
                                      r['monto_fijo_clp'] != null
                                          ? '\$${r['monto_fijo_clp']} CLP · ${r['clasificacion']}'
                                          : '${r['porcentaje_base']}% del sueldo base · ${r['clasificacion']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: r['activo'] == true,
                                onChanged: (_) => _cambiarEstadoRegla(r),
                                activeColor: const Color(0xFF059669),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),

                    const Text(
                      'Aplicar Regla a un Trabajador',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                              constraints: const BoxConstraints(maxHeight: 180),
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
                                    subtitle: Text(e['rut']),
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
                                'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),

                          const Text(
                            'Regla:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            value: _reglaSeleccionadaId,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: _reglas
                                .where((r) => r['activo'] == true)
                                .map<DropdownMenuItem<int>>(
                                  (r) => DropdownMenuItem(
                                    value: r['bono_id'] as int,
                                    child: Text(
                                      r['nombre_concepto'],
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _reglaSeleccionadaId = v),
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
                          const SizedBox(height: 16),

                          if (_mensajeAplicacion.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 14),
                              decoration: BoxDecoration(
                                color: _exitoAplicacion
                                    ? Colors.green[50]
                                    : Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _exitoAplicacion
                                      ? Colors.green[200]!
                                      : Colors.red[200]!,
                                ),
                              ),
                              child: Text(
                                _mensajeAplicacion,
                                style: TextStyle(
                                  color: _exitoAplicacion
                                      ? Colors.green
                                      : Colors.red,
                                  fontSize: 13,
                                ),
                              ),
                            ),

                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _enviandoAplicacion
                                      ? null
                                      : () => _registrarAplicacion(true),
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Cumple'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _enviandoAplicacion
                                      ? null
                                      : () => _registrarAplicacion(false),
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('No cumple'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFDC2626),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (_empleadoSeleccionado != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Bonos aplicados en este periodo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _consultarAplicadas,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Consultar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_consultando)
                        const Center(child: CircularProgressIndicator())
                      else if (_aplicadas.isEmpty)
                        const Text(
                          'Sin registros para este trabajador y periodo.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        )
                      else
                        ..._aplicadas.map(
                          (a) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: a['cumple_condicion'] == true
                                  ? const Color(0xFFECFDF5)
                                  : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  a['cumple_condicion'] == true
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  size: 18,
                                  color: a['cumple_condicion'] == true
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFDC2626),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a['nombre_concepto'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        a['condicion_texto'],
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '\$${a['monto_aplicado']} CLP',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
