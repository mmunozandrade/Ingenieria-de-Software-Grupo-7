import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class GratificacionScreen extends StatefulWidget {
  const GratificacionScreen({super.key});

  @override
  State<GratificacionScreen> createState() => _GratificacionScreenState();
}

class _GratificacionScreenState extends State<GratificacionScreen> {
  // Configuracion
  String _modalidad = 'Proporcional';
  final _porcentajeMensualController = TextEditingController(text: '25');
  final _limiteImmController = TextEditingController(text: '4.75');
  final _porcentajeAnualController = TextEditingController(text: '30');
  bool _cargandoConfig = true;
  bool _guardandoConfig = false;

  // Valor IMM
  final _valorImmController = TextEditingController();
  int _mesImm = DateTime.now().month;
  int _anioImm = DateTime.now().year;

  // Busqueda / calculo
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;
  final _utilidadAnualController = TextEditingController();

  Map<String, dynamic>? _datosBase;
  bool _cargandoDatosBase = false;

  bool _calculando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  @override
  void initState() {
    super.initState();
    _cargarConfig();
  }

  @override
  void dispose() {
    _porcentajeMensualController.dispose();
    _limiteImmController.dispose();
    _porcentajeAnualController.dispose();
    _valorImmController.dispose();
    _busquedaController.dispose();
    _utilidadAnualController.dispose();
    super.dispose();
  }

  Future<void> _cargarConfig() async {
    setState(() => _cargandoConfig = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/config-gratificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _modalidad = data['modalidad'];
          _porcentajeMensualController.text = '${data['porcentaje_mensual']}';
          _limiteImmController.text = '${data['limite_imm_anual']}';
          _porcentajeAnualController.text = '${data['porcentaje_anual']}';
        });
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoConfig = false);
    }
  }

  Future<void> _guardarConfig() async {
    setState(() => _guardandoConfig = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/admin/config-gratificacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'modalidad': _modalidad,
          'porcentaje_mensual':
              double.tryParse(_porcentajeMensualController.text.trim()) ?? 25.0,
          'limite_imm_anual':
              double.tryParse(_limiteImmController.text.trim()) ?? 4.75,
          'porcentaje_anual':
              double.tryParse(_porcentajeAnualController.text.trim()) ?? 30.0,
        }),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? 'Configuración guardada correctamente'
                  : (data['mensaje'] ?? 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
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
      setState(() => _guardandoConfig = false);
    }
  }

  Future<void> _guardarValorImm() async {
    final valor = int.tryParse(_valorImmController.text.trim());
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un valor IMM valido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final periodo = '${_mesImm.toString().padLeft(2, '0')}/$_anioImm';
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/valor-imm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'valor_clp': valor, 'periodo': periodo}),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? 'Valor IMM guardado para $periodo'
                  : (data['mensaje'] ?? 'Error'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
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
    }
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
      // silencioso
    } finally {
      setState(() => _buscando = false);
    }
  }

  void _seleccionarEmpleado(Map<String, dynamic> empleado) {
    setState(() {
      _empleadoSeleccionado = empleado;
      _resultadosBusqueda = [];
      _busquedaController.text =
          '${empleado['nombres']} ${empleado['apellidos']}';
      _resultado = null;
      _datosBase = null;
      _error = '';
    });
    _cargarDatosBase();
  }

  Future<void> _cargarDatosBase() async {
    if (_empleadoSeleccionado == null) return;
    setState(() {
      _cargandoDatosBase = true;
      _datosBase = null;
    });
    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/gratificacion-datos-base?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _datosBase = data);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoDatosBase = false);
    }
  }

  Future<void> _calcular() async {
    if (_empleadoSeleccionado == null) {
      setState(() => _error = 'Selecciona un trabajador');
      return;
    }
    if (_modalidad == 'Anual' &&
        (double.tryParse(_utilidadAnualController.text.trim()) ?? 0) <= 0) {
      setState(
        () => _error = 'Ingresa la utilidad líquida anual de la empresa',
      );
      return;
    }

    setState(() {
      _calculando = true;
      _error = '';
      _resultado = null;
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';
    var url =
        '$_apiUrl/admin/calculo-gratificacion?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}';
    if (_modalidad == 'Anual') {
      url += '&utilidad_liquida_anual=${_utilidadAnualController.text.trim()}';
    }

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _resultado = data);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al calcular');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _calculando = false);
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
          'Gratificación Legal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Configuración de Gratificación',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Art. 50 (proporcional mensual) o Art. 47 (anual sobre utilidades)',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),

                // ── Configuracion de modalidad ──────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: _cargandoConfig
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Modalidad:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Proporcional (Art. 50)',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    value: 'Proporcional',
                                    groupValue: _modalidad,
                                    onChanged: (v) =>
                                        setState(() => _modalidad = v!),
                                  ),
                                ),
                                Expanded(
                                  child: RadioListTile<String>(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Anual (Art. 47)',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    value: 'Anual',
                                    groupValue: _modalidad,
                                    onChanged: (v) =>
                                        setState(() => _modalidad = v!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _porcentajeMensualController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: '% mensual (Art. 50)',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _limiteImmController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: 'Tope IMM anual',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _porcentajeAnualController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: '% anual (Art. 47)',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _guardandoConfig
                                    ? null
                                    : _guardarConfig,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF001E42),
                                  foregroundColor: Colors.white,
                                ),
                                child: Text(
                                  _guardandoConfig
                                      ? 'Guardando...'
                                      : 'Guardar Configuración',
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),

                // ── Trabajador y periodo ────────────────────────
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
                              'Buscar por apellido (minimo 3 caracteres)...',
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
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF1D4ED8),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} (${_empleadoSeleccionado!['rut']})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

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
                              onChanged: (v) {
                                setState(
                                  () =>
                                      _mesSeleccionado = v ?? _mesSeleccionado,
                                );
                                _cargarDatosBase();
                              },
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
                              onChanged: (v) {
                                setState(
                                  () => _anioSeleccionado =
                                      v ?? _anioSeleccionado,
                                );
                                _cargarDatosBase();
                              },
                            ),
                          ),
                        ],
                      ),

                      if (_modalidad == 'Anual') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Utilidad líquida anual de la empresa:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _utilidadAnualController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: 'Ej: 50000000',
                            prefixText: '\$ ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Datos base (solo lectura, modalidad Proporcional) ──
                if (_modalidad == 'Proporcional' &&
                    _empleadoSeleccionado != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: _cargandoDatosBase
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : _datosBase == null
                        ? const Text(
                            'No se pudieron cargar los datos base para este período.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Datos base del cálculo (solo lectura):',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF001E42),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _filaSoloLectura(
                                'Sueldo base',
                                _datosBase!['sueldo_base'],
                              ),
                              _filaSoloLectura(
                                'Horas extras',
                                _datosBase!['horas_extras'],
                              ),
                              _filaSoloLectura(
                                'Bonos imponibles',
                                _datosBase!['bonos_imponibles'],
                              ),
                              const Divider(height: 20),
                              _filaSoloLectura(
                                'Base de cálculo (suma)',
                                _datosBase!['base_calculo'],
                                destacado: true,
                              ),
                            ],
                          ),
                  ),

                // ── Valor IMM ──────────────────────────────────
                if (_modalidad == 'Proporcional')
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
                          'Valor IMM del periodo:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _valorImmController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Ej: 500000',
                                  prefixText: '\$ ',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _mesImm,
                                decoration: InputDecoration(
                                  isDense: true,
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
                                onChanged: (v) =>
                                    setState(() => _mesImm = v ?? _mesImm),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _anioImm,
                                decoration: InputDecoration(
                                  isDense: true,
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
                                onChanged: (v) =>
                                    setState(() => _anioImm = v ?? _anioImm),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _guardarValorImm,
                              child: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // ── Calculo ──────────────────────────────────
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
                      if (_error.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _calculando ? null : _calcular,
                          icon: _calculando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.card_giftcard_outlined,
                                  size: 18,
                                ),
                          label: const Text('Calcular Gratificación'),
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
                  const SizedBox(height: 24),
                  _TarjetaResultado(resultado: _resultado!),
                ],
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaSoloLectura(
    String label,
    dynamic valor, {
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
            '\$$valor CLP',
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

class _TarjetaResultado extends StatelessWidget {
  final Map<String, dynamic> resultado;
  const _TarjetaResultado({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final bool esProporcional = resultado['modalidad'] == 'Proporcional';

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
          Row(
            children: [
              const Icon(
                Icons.card_giftcard_outlined,
                color: Color(0xFF1D4ED8),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${resultado['nombre']} · ${resultado['periodo']}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
              ),
            ],
          ),
          Text(
            resultado['rut'] ?? '',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const Divider(height: 24),
          if (esProporcional) ...[
            _fila('Base de cálculo', '\$${resultado['base_calculo']} CLP'),
            _fila(
              'Gratificación sin tope (${resultado['porcentaje_mensual']}%)',
              '\$${resultado['gratificacion_sin_tope']} CLP',
            ),
            _fila('Valor IMM', '\$${resultado['valor_imm']} CLP'),
            _fila(
              'Tope mensual (${resultado['limite_imm_anual']} IMM/12)',
              '\$${resultado['tope_mensual']} CLP',
            ),
            if (resultado['se_aplico_tope'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '⚠ Se aplicó el tope legal',
                  style: TextStyle(fontSize: 12, color: Color(0xFFD97706)),
                ),
              ),
          ] else ...[
            _fila(
              'Utilidad líquida anual',
              '\$${resultado['utilidad_liquida_anual']} CLP',
            ),
            _fila(
              'Monto total gratificación (${resultado['porcentaje_anual']}%)',
              '\$${resultado['monto_total_gratificacion']} CLP',
            ),
            _fila(
              'Trabajadores activos',
              '${resultado['total_trabajadores_activos']}',
            ),
            _fila(
              'Gratificación anual por trabajador',
              '\$${resultado['gratificacion_anual_trabajador']} CLP',
            ),
            const SizedBox(height: 6),
            Text(
              resultado['nota'] ?? '',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GRATIFICACIÓN DEL PERIODO',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF001E42),
                ),
              ),
              Text(
                '\$${esProporcional ? resultado['gratificacion_final'] : resultado['gratificacion_mensual_equivalente']} CLP',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, dynamic valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
          ),
          Text(
            '$valor',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
