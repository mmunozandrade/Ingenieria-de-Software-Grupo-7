import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';
import 'calculoLiquidacionTotalNuevo.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

// ══════════════════════════════════════════════════════════════
// WIZARD "TIPO LIBRO" (version NUEVA, orden reorganizado): elige
// trabajador + periodo UNA VEZ, y luego avanza pantalla completa
// por pantalla completa (nunca dos a la vez), reutilizando los
// mismos widgets de calculo ya construidos en
// calculoLiquidacionTotalNuevo.dart.
// ══════════════════════════════════════════════════════════════
class CalculoLiquidacionWizardNuevoScreen extends StatefulWidget {
  const CalculoLiquidacionWizardNuevoScreen({super.key});

  @override
  State<CalculoLiquidacionWizardNuevoScreen> createState() =>
      _CalculoLiquidacionWizardNuevoScreenState();
}

class _CalculoLiquidacionWizardNuevoScreenState
    extends State<CalculoLiquidacionWizardNuevoScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  int _pasoActual = 0;
  bool _procesoCompletado = false;

  static const List<_DefPaso> _pasos = [
    _DefPaso(
      'Cálculo Proporcional',
      Icons.calculate_outlined,
      Color(0xFF0D9488),
    ),
    _DefPaso(
      'Registrar Descuentos',
      Icons.remove_circle_outline,
      Color(0xFFDC2626),
    ),
    _DefPaso(
      'Licencias Médicas',
      Icons.medical_services_outlined,
      Color(0xFF64748B),
    ),
    _DefPaso('Horas Extras', Icons.access_time, Color(0xFF1D4ED8)),
    _DefPaso(
      'Registrar Bonos Imponibles',
      Icons.add_circle_outline,
      Color(0xFF059669),
    ),
    _DefPaso('Total Haberes', Icons.functions, Color(0xFF1D4ED8)),
    _DefPaso(
      'Total Imponible, AFP/Salud, AFC',
      Icons.calculate_outlined,
      Color(0xFF1D4ED8),
    ),
    _DefPaso(
      'Seguro de Cesantía, AFP/Salud y Total Tributable',
      Icons.shield_outlined,
      Color(0xFF3B82F6),
    ),
    _DefPaso('Impuesto Único', Icons.receipt_long_outlined, Color(0xFFEF4444)),
    _DefPaso(
      'Anticipo de Sueldo',
      Icons.request_page_outlined,
      Color(0xFF0891B2),
    ),
    _DefPaso(
      'Desglose de Liquidación',
      Icons.summarize_outlined,
      Color(0xFF059669),
    ),
    _DefPaso(
      'RESUMEN COTIZACIONES PREVISIONALES + IMPUESTOS PARA PAGAR ',
      Icons.account_balance_outlined,
      Color(0xFF001E42),
    ),
    _DefPaso('Cerrar Liquidación', Icons.lock_outline, Color(0xFF001E42)),
  ];

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  String get _periodo =>
      '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

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

  void _seleccionarEmpleado(Map<String, dynamic> e) async {
    setState(() {
      _empleadoSeleccionado = e;
      _resultadosBusqueda = [];
      _busquedaController.text = '${e['nombres']} ${e['apellidos']}';
      _pasoActual = 0;
      _procesoCompletado = false;
    });
    await _verificarLiquidacionCerrada();
    await _verificarProgresoGuardado();
  }

  Future<void> _verificarLiquidacionCerrada() async {
    if (_empleadoSeleccionado == null) return;
    final personaId = _empleadoSeleccionado!['id_empleado'] as int;
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/liquidacion-cerrada?persona_id=$personaId&periodo=${Uri.encodeComponent(_periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['cerrada'] == true && mounted) {
        _mostrarAvisoLiquidacionCerrada();
      }
    } catch (_) {
      // silencioso: si falla la consulta, simplemente no avisa de antemano
      // (el backend igual va a bloquear el guardado si corresponde)
    }
  }

  void _mostrarAvisoLiquidacionCerrada() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liquidación ya cerrada'),
        content: Text(
          'La liquidación de ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} '
          'para el período $_periodo ya fue cerrada. Puedes seguir revisando los datos, pero el sistema '
          'no va a permitir guardar cambios nuevos en este período.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _verificarProgresoGuardado() async {
    if (_empleadoSeleccionado == null) return;
    final personaId = _empleadoSeleccionado!['id_empleado'] as int;
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/wizard-progreso?persona_id=$personaId&periodo=${Uri.encodeComponent(_periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true && data['existe'] == true) {
        final pasoGuardado = data['paso_actual'] as int;
        if (pasoGuardado > 0 && mounted) {
          _mostrarDialogoProgreso(pasoGuardado);
        }
      }
    } catch (_) {
      // silencioso: si falla la consulta, simplemente arranca desde 0
    }
  }

  void _mostrarDialogoProgreso(int pasoGuardado) {
    final nombrePaso = pasoGuardado < _pasos.length
        ? _pasos[pasoGuardado].titulo
        : _pasos.last.titulo;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Liquidación en curso detectada'),
        content: Text(
          'Detectamos una liquidación en curso para ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} '
          'en el período $_periodo, en el paso "$nombrePaso". ¿Deseas continuar donde quedaste o empezar de nuevo?\n\n'
          'Nota: "Empezar de 0" no borra ningún dato ya registrado (descuentos, bonos, etc.) — solo reinicia la posición del asistente.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _borrarProgreso();
              setState(() => _pasoActual = 0);
            },
            child: const Text('Empezar de 0'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // El progreso guardado puede venir de una version anterior
              // del wizard con mas pasos que la actual; si el indice ya
              // no existe en la lista de hoy, se ajusta al ultimo paso
              // valido en vez de intentar acceder a un indice inexistente.
              final pasoValido = pasoGuardado.clamp(0, _pasos.length - 1);
              setState(() => _pasoActual = pasoValido);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              foregroundColor: Colors.white,
            ),
            child: const Text('Continuar donde quedé'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardarProgreso() async {
    if (_empleadoSeleccionado == null) return;
    try {
      final token = await SessionService.obtenerToken();
      await http.post(
        Uri.parse('$_apiUrl/admin/wizard-progreso'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'periodo': _periodo,
          'paso_actual': _pasoActual,
        }),
      );
    } catch (_) {
      // silencioso: si falla el guardado de progreso, no bloquea el flujo
    }
  }

  Future<void> _borrarProgreso() async {
    if (_empleadoSeleccionado == null) return;
    try {
      final token = await SessionService.obtenerToken();
      await http.delete(
        Uri.parse(
          '$_apiUrl/admin/wizard-progreso?persona_id=${_empleadoSeleccionado!['id_empleado']}&periodo=${Uri.encodeComponent(_periodo)}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      // silencioso
    }
  }

  void _irAlSiguientePaso() {
    setState(() {
      if (_pasoActual + 1 < _pasos.length) {
        _pasoActual++;
      } else {
        _procesoCompletado = true;
      }
    });
    if (_procesoCompletado) {
      _borrarProgreso();
    } else {
      _guardarProgreso();
    }
  }

  void _irAlPasoAnterior() {
    if (_pasoActual > 0) {
      setState(() => _pasoActual--);
      _guardarProgreso();
    }
  }

  void _empezarConOtroTrabajador() {
    setState(() {
      _empleadoSeleccionado = null;
      _busquedaController.clear();
      _pasoActual = 0;
      _procesoCompletado = false;
    });
  }

  Widget _contenidoPaso(int index, int personaId) {
    switch (index) {
      case 0:
        return SeccionCalculoProporcional(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 1:
        return SeccionDescuento(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
          sueldoBase: _empleadoSeleccionado?['sueldo_base'] is int
              ? _empleadoSeleccionado!['sueldo_base']
              : (_empleadoSeleccionado?['sueldo_base'] as num?)?.round(),
          jornadaSemanal:
              (_empleadoSeleccionado?['jornada_semanal_horas'] as num?)
                  ?.toDouble(),
        );
      case 2:
        return SeccionLicenciaMedica(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 3:
        return SeccionHorasExtras(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 4:
        return SeccionBonoImponible(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 5:
        return SeccionTotalImponible(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 6:
        return SeccionTotalImponibleTopado(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 7:
        return SeccionAfcYAfpSalud(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 8:
        return SeccionImpuestoUnico(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 9:
        return SeccionAnticipo(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 10:
        return SeccionDesgloseFinal(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 11:
        return SeccionCotizacionesPrevisionales(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      case 12:
        return SeccionCerrarLiquidacion(
          personaId: personaId,
          periodo: _periodo,
          onDone: _irAlSiguientePaso,
        );
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(11, (i) => anioActual - i);
    final personaId = _empleadoSeleccionado?['id_empleado'] as int?;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Cálculo de Liquidación Total',
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
              ? 850
              : (esTablet ? 700 : double.infinity);
          final double paddingPaso = esEscritorio ? 32 : (esTablet ? 26 : 18);
          final double iconoPasoSize = esEscritorio ? 26 : 22;
          final double tituloPasoSize = esEscritorio ? 21 : 18;

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
                      'Liquidación Completa por Trabajador',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Elige el trabajador y el período una sola vez, y avanza paso a paso hasta el cierre',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 20),

                    // ── Contexto compartido: trabajador + periodo ──
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
                                  onChanged: (v) {
                                    setState(() {
                                      _mesSeleccionado = v ?? _mesSeleccionado;
                                      _pasoActual = 0;
                                      _procesoCompletado = false;
                                    });
                                    _verificarLiquidacionCerrada();
                                    _verificarProgresoGuardado();
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
                                    setState(() {
                                      _anioSeleccionado =
                                          v ?? _anioSeleccionado;
                                      _pasoActual = 0;
                                      _procesoCompletado = false;
                                    });
                                    _verificarLiquidacionCerrada();
                                    _verificarProgresoGuardado();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (personaId == null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Text(
                          'Selecciona un trabajador arriba para comenzar.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      )
                    else if (_procesoCompletado)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF059669),
                                  size: 28,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Proceso completado para este trabajador y período.',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF059669),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _empezarConOtroTrabajador,
                                icon: const Icon(
                                  Icons.person_search_outlined,
                                  size: 18,
                                ),
                                label: const Text('Buscar Otro Trabajador'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF059669),
                                  side: const BorderSide(
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // ── Indicador de paso ──────────────────────────
                      Row(
                        children: [
                          Text(
                            'Paso ${_pasoActual + 1} de ${_pasos.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          if (_pasoActual > 0)
                            TextButton.icon(
                              onPressed: _irAlPasoAnterior,
                              icon: const Icon(Icons.arrow_back, size: 16),
                              label: const Text('Anterior'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (_pasoActual + 1) / _pasos.length,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _pasos[_pasoActual].color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Pantalla del paso actual (una sola a la vez) ──
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(paddingPaso),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _pasos[_pasoActual].color,
                            width: 1.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _pasos[_pasoActual].icono,
                                  color: _pasos[_pasoActual].color,
                                  size: iconoPasoSize,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _pasos[_pasoActual].titulo,
                                    style: TextStyle(
                                      fontSize: tituloPasoSize,
                                      fontWeight: FontWeight.bold,
                                      color: _pasos[_pasoActual].color,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 36),
                            _contenidoPaso(_pasoActual, personaId),
                          ],
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

class _DefPaso {
  final String titulo;
  final IconData icono;
  final Color color;
  const _DefPaso(this.titulo, this.icono, this.color);
}
