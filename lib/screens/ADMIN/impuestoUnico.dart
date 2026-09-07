import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class ImpuestoUnicoScreen extends StatefulWidget {
  const ImpuestoUnicoScreen({super.key});

  @override
  State<ImpuestoUnicoScreen> createState() => _ImpuestoUnicoScreenState();
}

class _ImpuestoUnicoScreenState extends State<ImpuestoUnicoScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _calculando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  List<dynamic> _tramos = [];
  bool _cargandoTramos = true;

  // Referencia de periodo/UTM usada al editar celdas de la tabla
  int _mesCalculadora = DateTime.now().month;
  int _anioCalculadora = DateTime.now().year;
  List<dynamic> _valoresUtm = [];
  bool _cargandoUtm = true;

  double? get _valorUtmCalculadora {
    final periodo =
        '${_mesCalculadora.toString().padLeft(2, '0')}/$_anioCalculadora';
    final match = _valoresUtm.firstWhere(
      (v) => v['periodo'] == periodo,
      orElse: () => null,
    );
    return match != null ? (match['valor_clp'] as num).toDouble() : null;
  }

  @override
  void initState() {
    super.initState();
    _cargarTramos();
    _cargarValoresUtm();
  }

  Future<void> _cargarValoresUtm() async {
    setState(() => _cargandoUtm = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/valor-utm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _valoresUtm = data['valores'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _cargandoUtm = false);
    }
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _cargarTramos() async {
    setState(() => _cargandoTramos = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/config-tramos-impuesto'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _tramos = data['tramos'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoTramos = false);
    }
  }

  // ── Edicion celda por celda de la tabla de tramos ──────────────
  // 'campo' es uno de: 'desde_utm', 'hasta_utm', 'factor', 'rebaja_utm'.
  // 'esMontoClp' indica si el admin ingresa un monto en CLP (para
  // desde_utm/hasta_utm, que se convierte a UTM con la UTM actual)
  // o un valor directo (para factor/rebaja_utm).
  Future<void> _editarCeldaTramo(
    Map<String, dynamic> tramo,
    String campo,
    bool esMontoClp,
  ) async {
    if (esMontoClp && _valorUtmCalculadora == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Debes ingresar la UTM del período (${_mesCalculadora.toString().padLeft(2, '0')}/$_anioCalculadora) antes de editar esta celda.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final controller = TextEditingController();
    final nuevoValor = await showDialog<double>(
      context: context,
      builder: (ctx) {
        String? errorLocal;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(
              esMontoClp ? 'Ingresar monto en CLP' : 'Ingresar valor',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (esMontoClp)
                  Text(
                    'Se convertirá a UTM usando el valor de la UTM de ${_mesCalculadora.toString().padLeft(2, '0')}/$_anioCalculadora (\$${_valorUtmCalculadora!.toStringAsFixed(0)} CLP).',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    prefixText: esMontoClp ? '\$ ' : null,
                    hintText: esMontoClp ? 'Ej: 967261.51' : 'Ej: 0.04',
                    errorText: errorLocal,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final valor = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  );
                  if (valor == null || valor < 0) {
                    setDialogState(
                      () => errorLocal = 'Ingresa un número válido',
                    );
                    return;
                  }
                  final resultado = esMontoClp
                      ? valor / _valorUtmCalculadora!
                      : valor;
                  Navigator.pop(ctx, resultado);
                },
                child: const Text('Calcular'),
              ),
            ],
          ),
        );
      },
    );

    if (nuevoValor == null || !mounted) return;

    // ── Confirmacion final antes de guardar ──────────────────
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio'),
        content: Text(
          '¿Estás seguro que aplicaste todo correctamente?\n\nTramo ${tramo['tramo_numero']} · ${_nombreCampo(campo)}: '
          '${esMontoClp ? '${nuevoValor.toStringAsFixed(4)} UTM' : nuevoValor.toString()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    await _guardarTramo(tramo, campo, nuevoValor);
  }

  String _nombreCampo(String campo) {
    switch (campo) {
      case 'desde_utm':
        return 'Desde (UTM)';
      case 'hasta_utm':
        return 'Hasta (UTM)';
      case 'factor':
        return 'Factor';
      default:
        return 'Rebaja (UTM)';
    }
  }

  Future<void> _guardarTramo(
    Map<String, dynamic> tramo,
    String campoEditado,
    double nuevoValor,
  ) async {
    final body = {
      'tramo_numero': tramo['tramo_numero'],
      'desde_utm': campoEditado == 'desde_utm'
          ? nuevoValor
          : tramo['desde_utm'],
      'hasta_utm': campoEditado == 'hasta_utm'
          ? nuevoValor
          : tramo['hasta_utm'],
      'factor': campoEditado == 'factor' ? nuevoValor : tramo['factor'],
      'rebaja_utm': campoEditado == 'rebaja_utm'
          ? nuevoValor
          : tramo['rebaja_utm'],
    };
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/admin/config-tramos-impuesto'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? 'Tramo actualizado correctamente'
                  : (data['mensaje'] ?? 'Error al actualizar'),
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
      if (data['success'] == true) {
        await _cargarTramos();
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
      _error = '';
    });
  }

  Future<void> _calcular() async {
    if (_empleadoSeleccionado == null) {
      setState(() => _error = 'Selecciona un trabajador');
      return;
    }

    setState(() {
      _calculando = true;
      _error = '';
      _resultado = null;
    });

    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/calculo-impuesto-unico?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(periodo)}',
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
          'Impuesto Único',
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
                      'Impuesto Único de Segunda Categoría',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sobre la base tributable (imponible − AFP − salud − AFC trabajador), según tabla del SII',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 20),

                    // Tabla de tramos (referencia)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tabla de tramos vigente (SII):',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Toca cualquier celda resaltada para editarla. Los rangos se ingresan en CLP y se convierten a UTM automáticamente.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_cargandoTramos)
                            const Center(child: CircularProgressIndicator())
                          else
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: 520,
                                child: Table(
                                  columnWidths: const {
                                    0: FixedColumnWidth(55),
                                    1: FlexColumnWidth(),
                                    2: FixedColumnWidth(90),
                                    3: FixedColumnWidth(100),
                                  },
                                  children: [
                                    const TableRow(
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            'Tramo',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            'Rango (UTM)',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            'Factor',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            'Rebaja',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    ..._tramos.map(
                                      (t) => TableRow(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: Text(
                                              '${t['tramo_numero']}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: Row(
                                              children: [
                                                InkWell(
                                                  onTap: () =>
                                                      _editarCeldaTramo(
                                                        t,
                                                        'desde_utm',
                                                        true,
                                                      ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      color: const Color(
                                                        0xFFEFF6FF,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${t['desde_utm']}',
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Color(
                                                          0xFF1D4ED8,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                if (t['hasta_utm'] != null) ...[
                                                  const Text(
                                                    ' - ',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  InkWell(
                                                    onTap: () =>
                                                        _editarCeldaTramo(
                                                          t,
                                                          'hasta_utm',
                                                          true,
                                                        ),
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        color: const Color(
                                                          0xFFEFF6FF,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        '${t['hasta_utm']}',
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF1D4ED8,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ] else
                                                  const Text(
                                                    '+',
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: InkWell(
                                              onTap: () => _editarCeldaTramo(
                                                t,
                                                'factor',
                                                false,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  color: const Color(
                                                    0xFFEFF6FF,
                                                  ),
                                                ),
                                                child: Text(
                                                  '${t['factor']}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF1D4ED8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                            ),
                                            child: InkWell(
                                              onTap: () => _editarCeldaTramo(
                                                t,
                                                'rebaja_utm',
                                                false,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  color: const Color(
                                                    0xFFEFF6FF,
                                                  ),
                                                ),
                                                child: Text(
                                                  '${t['rebaja_utm']}',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF1D4ED8),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
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
                                      Icons.receipt_long_outlined,
                                      size: 18,
                                    ),
                              label: const Text('Calcular Impuesto Único'),
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
          );
        },
      ),
    );
  }
}

class _TarjetaResultado extends StatelessWidget {
  final Map<String, dynamic> resultado;
  const _TarjetaResultado({required this.resultado});

  @override
  Widget build(BuildContext context) {
    final bool exento = resultado['impuesto_unico'] == 0;

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
                Icons.receipt_long_outlined,
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

          _fila('Valor UTM del periodo', '\$${resultado['valor_utm']} CLP'),
          _fila('Total imponible', '\$${resultado['total_imponible']} CLP'),
          _fila('(-) Descuento AFP', '\$${resultado['descuento_afp']} CLP'),
          _fila('(-) Descuento Salud', '\$${resultado['descuento_salud']} CLP'),
          _fila(
            '(-) Descuento AFC trabajador',
            '\$${resultado['descuento_afc_trabajador']} CLP',
          ),
          const Divider(height: 20),
          _fila(
            'Base tributable',
            '\$${resultado['base_tributable']} CLP',
            destacado: true,
          ),
          _fila(
            'Base tributable en UTM',
            '${resultado['base_tributable_utm']} UTM',
          ),
          const Divider(height: 20),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tramo ${resultado['tramo_numero']}: ${resultado['desde_utm']} - ${resultado['hasta_utm'] ?? '∞'} UTM',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Factor: ${resultado['factor']} · Rebaja: ${resultado['rebaja_utm']} UTM',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Impuesto en UTM: ${resultado['impuesto_utm']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'IMPUESTO ÚNICO',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF001E42),
                ),
              ),
              Text(
                exento ? 'Exento' : '\$${resultado['impuesto_unico']} CLP',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: exento
                      ? const Color(0xFF059669)
                      : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, dynamic valor, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF475569),
              fontWeight: destacado ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            '$valor',
            style: TextStyle(
              fontSize: 13,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
