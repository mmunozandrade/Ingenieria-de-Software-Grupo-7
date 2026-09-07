import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

const List<String> _tiposBono = [
  'Bonificacion',
  'Bonificacion de Produccion',
  'Bonificacion por Turno',
  'Otros',
];

class RegistrarBonosImponibles extends StatefulWidget {
  const RegistrarBonosImponibles({super.key});

  @override
  State<RegistrarBonosImponibles> createState() =>
      _RegistrarBonosImponiblesState();
}

class _RegistrarBonosImponiblesState extends State<RegistrarBonosImponibles> {
  // Busqueda de empleado
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  // Formulario
  String _tipoSeleccionado = _tiposBono[0];
  final _montoController = TextEditingController();
  final _conceptoOtrosController = TextEditingController();
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  // Historial
  List<dynamic> _bonos = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _montoController.dispose();
    _conceptoOtrosController.dispose();
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
    });
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/bonos-imponibles'),
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
      // silencioso
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
    final monto = int.tryParse(_montoController.text.trim());
    if (monto == null || monto <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Ingresa un monto valido mayor a 0';
      });
      return;
    }
    if (monto >= 1000000000) {
      setState(() {
        _exito = false;
        _mensaje = 'El monto no puede superar 9 digitos';
      });
      return;
    }

    final hoy = DateTime.now();
    if (_anioSeleccionado > hoy.year ||
        (_anioSeleccionado == hoy.year && _mesSeleccionado > hoy.month)) {
      setState(() {
        _exito = false;
        _mensaje = 'El periodo no puede ser futuro al mes actual';
      });
      return;
    }

    final conceptoOtros = _conceptoOtrosController.text.trim();
    if (_tipoSeleccionado == 'Otros' &&
        (conceptoOtros.length < 3 || conceptoOtros.length > 100)) {
      setState(() {
        _exito = false;
        _mensaje =
            'Especifica el concepto de "Otros" (entre 3 y 100 caracteres)';
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
        Uri.parse('$_apiUrl/admin/bonos-imponibles'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'tipo_bono': _tipoSeleccionado,
          'monto_clp': monto,
          'periodo': periodo,
          'concepto_otros': _tipoSeleccionado == 'Otros' ? conceptoOtros : '',
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Bono registrado correctamente'
            : (data['mensaje'] ?? 'Error al registrar el bono');
      });
      if (_exito) {
        setState(() {
          _empleadoSeleccionado = null;
          _busquedaController.clear();
          _montoController.clear();
          _conceptoOtrosController.clear();
          _tipoSeleccionado = _tiposBono[0];
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

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'Bonificacion':
        return const Color(0xFF059669);
      case 'Bonificacion de Produccion':
        return const Color(0xFF1D4ED8);
      case 'Bonificacion por Turno':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(
      11,
      (i) => anioActual - i,
    ); // 2000..anioActual seria mucho, limitamos a ultimos 11

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Registrar Bonos Imponibles',
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
                  'Nuevo Bono Imponible',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Se agrega automaticamente a la base imponible del periodo indicado',
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
                      // Buscar trabajador
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

                      // Tipo de bono
                      const Text(
                        'Tipo de bono:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _tiposBono.map((t) {
                          final seleccionado = _tipoSeleccionado == t;
                          return InkWell(
                            onTap: () => setState(() => _tipoSeleccionado = t),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: seleccionado
                                    ? _colorTipo(t).withOpacity(0.1)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: seleccionado
                                      ? _colorTipo(t)
                                      : const Color(0xFFCBD5E1),
                                  width: seleccionado ? 1.6 : 1,
                                ),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: seleccionado
                                      ? _colorTipo(t)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_tipoSeleccionado == 'Otros') ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Especifica el concepto:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _conceptoOtrosController,
                          maxLength: 100,
                          decoration: InputDecoration(
                            hintText: 'Ej: Bono por capacitación completada',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Monto
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
                          hintText: 'Ej: 50000',
                          prefixText: '\$ ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Periodo (mes/año)
                      const Text(
                        'Periodo de aplicacion:',
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
                      const SizedBox(height: 20),

                      if (_mensaje.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _exito ? Colors.green[50] : Colors.red[50],
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
                                    color: _exito ? Colors.green : Colors.red,
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
                              : const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text('Registrar Bono'),
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
                  'Historial de Bonos',
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
                        'No hay bonos registrados',
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
                              color: _colorTipo(
                                b['tipo_bono'],
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              b['tipo_bono'],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _colorTipo(b['tipo_bono']),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b['nombre_trabajador'] ?? '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${b['rut']} · Periodo: ${b['periodo']} · Registro: ${b['nombre_admin']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
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
      ),
    );
  }
}
