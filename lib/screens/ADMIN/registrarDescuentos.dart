import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

const List<String> _tiposDescuento = ['Inasistencia', 'Retraso', 'Prestamo'];

class RegistrarDescuentos extends StatefulWidget {
  const RegistrarDescuentos({super.key});

  @override
  State<RegistrarDescuentos> createState() => _RegistrarDescuentosState();
}

class _RegistrarDescuentosState extends State<RegistrarDescuentos> {
  // Busqueda de empleado
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  // Formulario — seleccion multiple de tipos
  Set<String> _tiposSeleccionados = {};

  // Solo para tipo_descuento == 'Inasistencia'
  DateTimeRange? _rangoInasistencia;
  final _diasInasistenciaController = TextEditingController();
  final _montoInasistenciaController = TextEditingController();

  // Solo para tipo_descuento == 'Retraso'
  final _horasAtrasoController = TextEditingController(); // formato HH:MM
  final _montoRetrasoController = TextEditingController();
  int _mesRetraso = DateTime.now().month;
  int _anioRetraso = DateTime.now().year;

  // Solo para tipo_descuento == 'Prestamo'
  String? _subtipoPrestamo; // 'Interno' | 'CajaCompensacion'
  final _montoPrestamoController = TextEditingController();
  final _montoCuotaManualController = TextEditingController();
  final _cantidadCuotasController = TextEditingController();
  int _mesInicioPrestamo = DateTime.now().month;
  int _anioInicioPrestamo = DateTime.now().year;

  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  // Historial
  List<dynamic> _descuentos = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _montoInasistenciaController.dispose();
    _montoRetrasoController.dispose();
    _diasInasistenciaController.dispose();
    _horasAtrasoController.dispose();
    _montoPrestamoController.dispose();
    _montoCuotaManualController.dispose();
    _cantidadCuotasController.dispose();
    super.dispose();
  }

  // ── Calculo Inasistencia: sueldo_base / 30 * dias ─────────────
  int? get _sueldoBaseTrabajador {
    final s = _empleadoSeleccionado?['sueldo_base'];
    if (s == null) return null;
    return (s is int) ? s : (s as num).round();
  }

  double? get _jornadaSemanalTrabajador {
    final j = _empleadoSeleccionado?['jornada_semanal_horas'];
    if (j == null) return null;
    return (j as num).toDouble();
  }

  int? get _montoInasistenciaCalculado {
    final sueldo = _sueldoBaseTrabajador;
    final dias = int.tryParse(_diasInasistenciaController.text.trim());
    if (sueldo == null || dias == null || dias <= 0) return null;
    return (sueldo / 30 * dias).round();
  }

  // ── Calculo Retraso: (((sueldo/30)*7)/hrs_semanales) * factor ──
  double? _parseHorasAtraso(String texto) {
    final partes = texto.trim().split(':');
    if (partes.length != 2) return null;
    final horas = int.tryParse(partes[0]);
    final minutos = int.tryParse(partes[1]);
    if (horas == null || minutos == null || minutos < 0 || minutos > 59)
      return null;
    return horas + (minutos / 60);
  }

  int? get _montoRetrasoCalculado {
    final sueldo = _sueldoBaseTrabajador;
    final jornada = _jornadaSemanalTrabajador;
    final factor = _parseHorasAtraso(_horasAtrasoController.text);
    if (sueldo == null ||
        jornada == null ||
        jornada <= 0 ||
        factor == null ||
        factor <= 0)
      return null;
    final valorDia = sueldo / 30;
    final sueldoSemanal = valorDia * 7;
    final valorHora = sueldoSemanal / jornada;
    return (valorHora * factor).round();
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
        Uri.parse('$_apiUrl/admin/descuentos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _descuentos = data['descuentos'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  int? get _montoCuotaCalculado {
    final monto = int.tryParse(_montoPrestamoController.text.trim());
    final cuotas = int.tryParse(_cantidadCuotasController.text.trim());
    if (monto == null || cuotas == null || cuotas <= 0) return null;
    return (monto / cuotas).round();
  }

  String get _periodoFinPrestamo {
    final cuotas = int.tryParse(_cantidadCuotasController.text.trim()) ?? 1;
    int mes = _mesInicioPrestamo;
    int anio = _anioInicioPrestamo;
    for (int i = 1; i < cuotas; i++) {
      mes++;
      if (mes > 12) {
        mes = 1;
        anio++;
      }
    }
    return '${mes.toString().padLeft(2, '0')}/$anio';
  }

  Future<Map<String, dynamic>> _enviarUnDescuento(
    Map<String, dynamic> body,
  ) async {
    final token = await SessionService.obtenerToken();
    final response = await http.post(
      Uri.parse('$_apiUrl/admin/descuentos'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    return jsonDecode(response.body);
  }

  Future<void> _registrarDescuento() async {
    if (_empleadoSeleccionado == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona un trabajador';
      });
      return;
    }
    if (_tiposSeleccionados.isEmpty) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona al menos un tipo de descuento';
      });
      return;
    }

    // ── Validaciones previas de cada tipo marcado ────────────
    if (_tiposSeleccionados.contains('Inasistencia')) {
      final monto = int.tryParse(_montoInasistenciaController.text.trim());
      if (monto == null || monto <= 0) {
        setState(() {
          _exito = false;
          _mensaje = 'Inasistencia: ingresa un monto válido';
        });
        return;
      }
      if (_rangoInasistencia == null) {
        setState(() {
          _exito = false;
          _mensaje = 'Inasistencia: selecciona el rango de fechas';
        });
        return;
      }
    }
    if (_tiposSeleccionados.contains('Retraso')) {
      final monto = int.tryParse(_montoRetrasoController.text.trim());
      if (monto == null || monto <= 0) {
        setState(() {
          _exito = false;
          _mensaje = 'Retraso: ingresa un monto válido';
        });
        return;
      }
    }
    if (_tiposSeleccionados.contains('Prestamo')) {
      if (_subtipoPrestamo == null) {
        setState(() {
          _exito = false;
          _mensaje =
              'Préstamo: selecciona Interno/Empresa o Caja de Compensación';
        });
        return;
      }
      final cuotas = int.tryParse(_cantidadCuotasController.text.trim());
      if (cuotas == null || cuotas <= 0) {
        setState(() {
          _exito = false;
          _mensaje = 'Préstamo: ingresa la cantidad de cuotas';
        });
        return;
      }
      if (_subtipoPrestamo == 'Interno') {
        final montoPrestamo = int.tryParse(
          _montoPrestamoController.text.trim(),
        );
        if (montoPrestamo == null || montoPrestamo <= 0) {
          setState(() {
            _exito = false;
            _mensaje = 'Préstamo: ingresa el monto del préstamo';
          });
          return;
        }
      } else {
        final montoCuota = int.tryParse(
          _montoCuotaManualController.text.trim(),
        );
        if (montoCuota == null || montoCuota <= 0) {
          setState(() {
            _exito = false;
            _mensaje = 'Préstamo: ingresa el monto de la cuota';
          });
          return;
        }
      }
    }

    setState(() {
      _enviando = true;
      _mensaje = '';
    });

    try {
      final resultados = <String>[];
      bool huboError = false;
      final personaId = _empleadoSeleccionado!['id_empleado'];

      if (_tiposSeleccionados.contains('Inasistencia')) {
        final monto = int.parse(_montoInasistenciaController.text.trim());
        final r = await _enviarUnDescuento({
          'persona_id': personaId,
          'tipo_descuento': 'Inasistencia',
          'monto_clp': monto,
          'fecha_evento': _rangoInasistencia!.start.toIso8601String().split(
            'T',
          )[0],
        });
        if (r['success'] == true) {
          resultados.add('Inasistencia: registrada correctamente');
        } else {
          huboError = true;
          resultados.add('Inasistencia: ${r['mensaje'] ?? 'error'}');
        }
      }

      if (_tiposSeleccionados.contains('Retraso')) {
        final monto = int.parse(_montoRetrasoController.text.trim());
        final fechaRetraso = DateTime(_anioRetraso, _mesRetraso, 1);
        final r = await _enviarUnDescuento({
          'persona_id': personaId,
          'tipo_descuento': 'Retraso',
          'monto_clp': monto,
          'fecha_evento': fechaRetraso.toIso8601String().split('T')[0],
        });
        if (r['success'] == true) {
          resultados.add('Retraso: registrado correctamente');
        } else {
          huboError = true;
          resultados.add('Retraso: ${r['mensaje'] ?? 'error'}');
        }
      }

      if (_tiposSeleccionados.contains('Prestamo')) {
        Map<String, dynamic> bodyPrestamo = {
          'persona_id': personaId,
          'tipo_descuento': 'Prestamo',
          'subtipo_prestamo': _subtipoPrestamo,
          'cantidad_cuotas': int.parse(_cantidadCuotasController.text.trim()),
          'mes_inicio': _mesInicioPrestamo,
          'anio_inicio': _anioInicioPrestamo,
        };
        if (_subtipoPrestamo == 'Interno') {
          bodyPrestamo['monto_prestamo'] = int.parse(
            _montoPrestamoController.text.trim(),
          );
        } else {
          bodyPrestamo['monto_cuota_manual'] = int.parse(
            _montoCuotaManualController.text.trim(),
          );
        }
        final r = await _enviarUnDescuento(bodyPrestamo);
        if (r['success'] == true) {
          resultados.add(
            'Préstamo: ${r['mensaje'] ?? 'registrado correctamente'}',
          );
        } else {
          huboError = true;
          resultados.add('Préstamo: ${r['mensaje'] ?? 'error'}');
        }
      }

      setState(() {
        _exito = !huboError;
        _mensaje = resultados.join('  ·  ');
      });

      if (_exito) {
        setState(() {
          _empleadoSeleccionado = null;
          _busquedaController.clear();
          _rangoInasistencia = null;
          _diasInasistenciaController.clear();
          _montoInasistenciaController.clear();
          _horasAtrasoController.clear();
          _montoRetrasoController.clear();
          _tiposSeleccionados = {};
          _subtipoPrestamo = null;
          _montoPrestamoController.clear();
          _montoCuotaManualController.clear();
          _cantidadCuotasController.clear();
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

  String _formatFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'Inasistencia':
        return const Color(0xFFDC2626);
      case 'Retraso':
        return const Color(0xFFD97706);
      case 'Prestamo':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Registrar Descuentos',
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
                  'Nuevo Descuento',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Inasistencia, retraso o prestamo — se registra en la liquidacion del periodo',
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

                      // Tipo de descuento
                      const Text(
                        'Tipo de descuento (puedes elegir más de uno):',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: _tiposDescuento.map((t) {
                          final seleccionado = _tiposSeleccionados.contains(t);
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                onTap: () => setState(() {
                                  if (seleccionado) {
                                    _tiposSeleccionados.remove(t);
                                  } else {
                                    _tiposSeleccionados.add(t);
                                  }
                                }),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 6,
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
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        seleccionado
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        size: 16,
                                        color: seleccionado
                                            ? _colorTipo(t)
                                            : const Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          t,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: seleccionado
                                                ? _colorTipo(t)
                                                : const Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),

                      // Campos condicionales segun los tipos marcados
                      if (_tiposSeleccionados.contains('Inasistencia')) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cálculo: Sueldo base ÷ 30 × días de inasistencia',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_sueldoBaseTrabajador == null)
                                const Text(
                                  'Selecciona un trabajador para ver su sueldo base.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                )
                              else
                                Text(
                                  'Sueldo base: \$$_sueldoBaseTrabajador CLP',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              const Text(
                                'Días de inasistencia:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _diasInasistenciaController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Ej: 2',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (_) => setState(() {
                                  if (_montoInasistenciaCalculado != null) {
                                    _montoInasistenciaController.text =
                                        _montoInasistenciaCalculado.toString();
                                  }
                                }),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _montoInasistenciaCalculado != null
                                    ? 'Resultado: \$$_montoInasistenciaCalculado CLP'
                                    : 'Ingresa los días para calcular...',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _montoInasistenciaCalculado != null
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Monto (CLP):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _montoInasistenciaController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Ej: 15000',
                                  prefixText: '\$ ',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Rango de inasistencia:',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () async {
                                  final rango = await showDateRangePicker(
                                    context: context,
                                    firstDate: DateTime(2015),
                                    lastDate: DateTime.now(),
                                    initialDateRange: _rangoInasistencia,
                                  );
                                  if (rango != null) {
                                    setState(() => _rangoInasistencia = rango);
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.date_range,
                                        size: 18,
                                        color: Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _rangoInasistencia != null
                                            ? '${_formatFecha(_rangoInasistencia!.start)} - ${_formatFecha(_rangoInasistencia!.end)}'
                                            : 'Seleccionar rango de fechas...',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: _rangoInasistencia != null
                                              ? const Color(0xFF0F172A)
                                              : const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // ── Caja de formula (Retraso) ───────────
                      if (_tiposSeleccionados.contains('Retraso')) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cálculo: (((Sueldo base ÷ 30) × 7) ÷ Jornada semanal) × horas de atraso',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_sueldoBaseTrabajador == null ||
                                  _jornadaSemanalTrabajador == null)
                                const Text(
                                  'Selecciona un trabajador con sueldo base y jornada semanal registrados.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF94A3B8),
                                  ),
                                )
                              else
                                Text(
                                  'Sueldo base: \$$_sueldoBaseTrabajador CLP · Jornada: $_jornadaSemanalTrabajador hrs/semana',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              const SizedBox(height: 10),
                              const Text(
                                'Horas totales de atraso (HH:MM):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _horasAtrasoController,
                                decoration: InputDecoration(
                                  hintText: 'Ej: 4:15',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (_) => setState(() {
                                  if (_montoRetrasoCalculado != null) {
                                    _montoRetrasoController.text =
                                        _montoRetrasoCalculado.toString();
                                  }
                                }),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                _montoRetrasoCalculado != null
                                    ? 'Resultado: \$$_montoRetrasoCalculado CLP'
                                    : 'Ingresa las horas para calcular...',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _montoRetrasoCalculado != null
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Monto (CLP):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _montoRetrasoController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Ej: 15000',
                                  prefixText: '\$ ',
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Período (mes/año):',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _mesRetraso,
                                      isDense: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                        () => _mesRetraso = v ?? _mesRetraso,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      value: _anioRetraso,
                                      isDense: true,
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      items:
                                          List.generate(
                                                6,
                                                (i) => DateTime.now().year - i,
                                              )
                                              .map(
                                                (a) => DropdownMenuItem(
                                                  value: a,
                                                  child: Text('$a'),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (v) => setState(
                                        () => _anioRetraso = v ?? _anioRetraso,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_tiposSeleccionados.contains('Prestamo')) ...[
                        // ── Subtipo de prestamo ────────────────
                        const Text(
                          'Tipo de préstamo:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(
                                  () => _subtipoPrestamo = 'Interno',
                                ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _subtipoPrestamo == 'Interno'
                                        ? const Color(
                                            0xFF001E42,
                                          ).withOpacity(0.08)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _subtipoPrestamo == 'Interno'
                                          ? const Color(0xFF001E42)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: const Text(
                                    'Interno / Empresa',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: () => setState(
                                  () => _subtipoPrestamo = 'CajaCompensacion',
                                ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        _subtipoPrestamo == 'CajaCompensacion'
                                        ? const Color(
                                            0xFF001E42,
                                          ).withOpacity(0.08)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          _subtipoPrestamo == 'CajaCompensacion'
                                          ? const Color(0xFF001E42)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: const Text(
                                    'Caja de Compensación',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_subtipoPrestamo != null) ...[
                          const SizedBox(height: 20),
                          if (_subtipoPrestamo == 'Interno') ...[
                            const Text(
                              'Monto del préstamo (CLP):',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _montoPrestamoController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Ej: 200000',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          const Text(
                            'Cantidad de cuotas:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _cantidadCuotasController,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Ej: 3',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (_subtipoPrestamo == 'Interno') ...[
                            const Text(
                              'Monto de la cuota (calculado):',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                _montoCuotaCalculado != null
                                    ? '\$$_montoCuotaCalculado CLP por cuota'
                                    : 'Ingresa monto y cuotas...',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _montoCuotaCalculado != null
                                      ? const Color(0xFF059669)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ] else ...[
                            const Text(
                              'Monto de la cuota (CLP):',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _montoCuotaManualController,
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: 'Ej: 15000',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          const Text(
                            'Comienza a descontarse en:',
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
                                  value: _mesInicioPrestamo,
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
                                    () => _mesInicioPrestamo =
                                        v ?? _mesInicioPrestamo,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _anioInicioPrestamo,
                                  decoration: InputDecoration(
                                    labelText: 'Año',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  items:
                                      List.generate(
                                            6,
                                            (i) => DateTime.now().year + i - 1,
                                          )
                                          .map(
                                            (a) => DropdownMenuItem(
                                              value: a,
                                              child: Text('$a'),
                                            ),
                                          )
                                          .toList(),
                                  onChanged: (v) => setState(
                                    () => _anioInicioPrestamo =
                                        v ?? _anioInicioPrestamo,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_cantidadCuotasController.text
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Termina en la liquidación de: $_periodoFinPrestamo',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ],
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
                          onPressed: _enviando ? null : _registrarDescuento,
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
                          label: const Text('Registrar Descuento(s)'),
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

                // ── Historial ─────────────────────────────────
                const Text(
                  'Historial de Descuentos',
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
                else if (_descuentos.isEmpty)
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
                        'No hay descuentos registrados',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                else
                  ..._descuentos.map(
                    (d) => Container(
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
                                d['tipo_descuento'],
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              d['tipo_descuento'],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _colorTipo(d['tipo_descuento']),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  d['nombre_trabajador'] ?? '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '${d['rut']} · ${d['fecha_evento']} · Registro: ${d['nombre_admin']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '\$${d['monto_clp']} CLP',
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
