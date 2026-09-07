import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';
import 'desgloseLiquidacionWidget.dart';

/// Formatea un numero con puntos como separador de miles (estilo
/// chileno): 1500000 -> "1.500.000". Acepta int, double o String.
/// Convierte horas decimales (ej. 4.25) a formato HH:MM (ej. "4:15").
String formatearHorasMinutos(dynamic horasDecimal) {
  if (horasDecimal == null) return '0:00';
  final double valor = horasDecimal is num
      ? horasDecimal.toDouble()
      : double.tryParse(horasDecimal.toString()) ?? 0;
  final horas = valor.floor();
  final minutos = ((valor - horas) * 60).round();
  return '$horas:${minutos.toString().padLeft(2, '0')}';
}

String formatearMiles(dynamic valor) {
  if (valor == null) return '0';
  final int numero = valor is num
      ? valor.round()
      : (int.tryParse(valor.toString()) ?? 0);
  final bool esNegativo = numero < 0;
  final String digitos = numero.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digitos[i]);
  }
  return (esNegativo ? '-' : '') + buffer.toString();
}

/// Convierte un texto con puntos de miles (ej. "1.500.000") de vuelta
/// a un entero (ej. 1500000). Ignora cualquier caracter no numerico.
int? desformatearMiles(String texto) {
  final soloDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (soloDigitos.isEmpty) return null;
  return int.tryParse(soloDigitos);
}

/// TextInputFormatter que aplica puntos de miles en vivo mientras el
/// usuario escribe en un campo de monto (estilo chileno):
/// 1000000 -> 1.000.000, sin alterar el valor numerico real.
class MilesInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final soloDigitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final buffer = StringBuffer();
    for (int i = 0; i < soloDigitos.length; i++) {
      final posicionDesdeDerecha = soloDigitos.length - i;
      buffer.write(soloDigitos[i]);
      if (posicionDesdeDerecha > 1 && posicionDesdeDerecha % 3 == 1) {
        buffer.write('.');
      }
    }
    final textoFormateado = buffer.toString();
    return TextEditingValue(
      text: textoFormateado,
      selection: TextSelection.collapsed(offset: textoFormateado.length),
    );
  }
}

const String _apiUrl = 'http://127.0.0.1:8000';

// ══════════════════════════════════════════════════════════════
// PANTALLA PRINCIPAL: Calculo de Liquidacion Total
// Elige trabajador + periodo UNA VEZ, y despliega un acordeon con
// 3 grupos: Registro de Datos -> Calculos Derivados -> Cierre.
// ══════════════════════════════════════════════════════════════
class CalculoLiquidacionTotalNuevoScreen extends StatefulWidget {
  const CalculoLiquidacionTotalNuevoScreen({super.key});

  @override
  State<CalculoLiquidacionTotalNuevoScreen> createState() =>
      _CalculoLiquidacionTotalNuevoScreenState();
}

class _CalculoLiquidacionTotalNuevoScreenState
    extends State<CalculoLiquidacionTotalNuevoScreen> {
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  int? _seccionAbierta;

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

  void _seleccionarEmpleado(Map<String, dynamic> e) {
    setState(() {
      _empleadoSeleccionado = e;
      _resultadosBusqueda = [];
      _busquedaController.text = '${e['nombres']} ${e['apellidos']}';
      _seccionAbierta = 0;
    });
  }

  void _onSeccionCompletada(int index) {
    setState(() {
      _seccionAbierta = (index + 1 < _secciones.length) ? index + 1 : null;
    });
  }

  List<_DefSeccion> get _secciones => [
    _DefSeccion(
      'Cálculo Proporcional',
      Icons.calculate_outlined,
      const Color(0xFF0D9488),
      'registro',
    ),
    _DefSeccion(
      'Descuentos',
      Icons.remove_circle_outline,
      const Color(0xFFDC2626),
      'registro',
    ),
    _DefSeccion(
      'Licencias Médicas',
      Icons.medical_services_outlined,
      const Color(0xFF64748B),
      'registro',
    ),
    _DefSeccion(
      'Horas Extras',
      Icons.access_time,
      const Color(0xFF1D4ED8),
      'registro',
    ),
    _DefSeccion(
      'Bonos Imponibles',
      Icons.add_circle_outline,
      const Color(0xFF059669),
      'registro',
    ),
    _DefSeccion(
      'Total Haberes',
      Icons.functions,
      const Color(0xFF1D4ED8),
      'resumen',
    ),
    _DefSeccion(
      'Total Imponible, AFP/Salud, AFC',
      Icons.calculate_outlined,
      const Color(0xFF1D4ED8),
      'calculo',
    ),
    _DefSeccion(
      'Seguro de Cesantía, AFP/Salud y Total Tributable',
      Icons.health_and_safety_outlined,
      const Color(0xFF3B82F6),
      'calculo',
    ),
    _DefSeccion(
      'Impuesto Único',
      Icons.receipt_long_outlined,
      const Color(0xFFEF4444),
      'calculo',
    ),
    _DefSeccion(
      'Anticipo de Sueldo',
      Icons.request_page_outlined,
      const Color(0xFF0891B2),
      'registro',
    ),
    _DefSeccion(
      'Desglose de Liquidación',
      Icons.summarize_outlined,
      const Color(0xFF059669),
      'final',
    ),
    _DefSeccion(
      'RESUMEN COTIZACIONES PREVISIONALES + IMPUESTOS PARA PAGAR ',
      Icons.request_quote_outlined,
      const Color(0xFF92400E),
      'calculo',
    ),
    _DefSeccion(
      'Cerrar Liquidación',
      Icons.lock_outline,
      const Color(0xFF001E42),
      'final',
    ),
  ];

  Widget _contenidoSeccion(int index, int personaId) {
    switch (index) {
      case 0:
        return SeccionCalculoProporcional(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(0),
        );
      case 1:
        return SeccionDescuento(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(1),
        );
      case 2:
        return SeccionLicenciaMedica(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(2),
        );
      case 3:
        return SeccionHorasExtras(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(3),
        );
      case 4:
        return SeccionBonoImponible(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(4),
        );
      case 5:
        return SeccionTotalImponible(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(5),
        );
      case 6:
        return SeccionTotalImponibleTopado(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(6),
        );
      case 7:
        return SeccionAfcYAfpSalud(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(7),
        );
      case 8:
        return SeccionImpuestoUnico(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(8),
        );
      case 9:
        return SeccionAnticipo(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(9),
        );
      case 10:
        return SeccionDesgloseFinal(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(10),
        );
      case 11:
        return SeccionCotizacionesPrevisionales(
          personaId: personaId,
          periodo: _periodo,
          onDone: () => _onSeccionCompletada(11),
        );
      case 12:
        return SeccionCerrarLiquidacion(
          personaId: personaId,
          periodo: _periodo,
          onDone: () {},
        );
      default:
        return const SizedBox();
    }
  }

  String _tituloGrupo(String grupo) {
    switch (grupo) {
      case 'registro':
        return 'REGISTRO DE DATOS';
      case 'resumen':
        return 'RESUMEN INTERMEDIO';
      case 'calculo':
        return 'CÁLCULOS DERIVADOS (solo consulta)';
      case 'final':
        return 'CIERRE';
      default:
        return '';
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 750),
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
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                    ),
                  )
                else
                  ...List.generate(_secciones.length, (index) {
                    final def = _secciones[index];
                    final abierta = _seccionAbierta == index;
                    final esNuevoGrupo =
                        index == 0 || _secciones[index - 1].grupo != def.grupo;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (esNuevoGrupo)
                          Padding(
                            padding: EdgeInsets.only(
                              top: index == 0 ? 0 : 12,
                              bottom: 8,
                            ),
                            child: Text(
                              _tituloGrupo(def.grupo),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: abierta
                                  ? def.color
                                  : const Color(0xFFE2E8F0),
                              width: abierta ? 1.4 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () => setState(
                                  () =>
                                      _seccionAbierta = abierta ? null : index,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      Icon(
                                        def.icono,
                                        color: def.color,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          def.titulo,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: abierta
                                                ? def.color
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        abierta
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: const Color(0xFF94A3B8),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (abierta)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    0,
                                    14,
                                    14,
                                  ),
                                  child: _contenidoSeccion(index, personaId),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DefSeccion {
  final String titulo;
  final IconData icono;
  final Color color;
  final String grupo;
  _DefSeccion(this.titulo, this.icono, this.color, this.grupo);
}

class _MensajeResultado extends StatelessWidget {
  final String mensaje;
  final bool exito;
  const _MensajeResultado({required this.mensaje, required this.exito});

  @override
  Widget build(BuildContext context) {
    if (mensaje.isEmpty) return const SizedBox();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: exito ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: exito ? Colors.green[200]! : Colors.red[200]!,
        ),
      ),
      child: Text(
        mensaje,
        style: TextStyle(
          color: exito ? Colors.green : Colors.red,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ── Helper compartido: consulta que ya esta registrado para este
// trabajador/periodo, asi cada seccion puede mostrar un banner
// "Ya registrado: ..." apenas se abre, sin tener que adivinar.
Future<Map<String, dynamic>?> obtenerResumenRegistros(
  int personaId,
  String periodo,
) async {
  try {
    final token = await SessionService.obtenerToken();
    final response = await http.get(
      Uri.parse(
        '$_apiUrl/admin/resumen-registros-periodo?persona_id=$personaId&periodo=${Uri.encodeComponent(periodo)}',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    final data = jsonDecode(response.body);
    if (data['success'] == true) return data['resumen'];
  } catch (_) {}
  return null;
}

// ── Banner reutilizable "Ya registrado: ..." ──────────────────
class BannerYaRegistrado extends StatelessWidget {
  final List<String> lineas;
  const BannerYaRegistrado({super.key, required this.lineas});

  @override
  Widget build(BuildContext context) {
    if (lineas.isEmpty) return const SizedBox();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: Color(0xFF059669),
              ),
              SizedBox(width: 6),
              Text(
                'Ya registrado para este período:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...lineas.map(
            (l) => Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Text(
                '• $l',
                style: const TextStyle(fontSize: 12, color: Color(0xFF166534)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION 1: DESCUENTOS
// ══════════════════════════════════════════════════════════════
class SeccionDescuento extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  final int? sueldoBase;
  final double? jornadaSemanal;
  const SeccionDescuento({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
    this.sueldoBase,
    this.jornadaSemanal,
  });

  @override
  State<SeccionDescuento> createState() => _SeccionDescuentoState();
}

class _SeccionDescuentoState extends State<SeccionDescuento> {
  Set<String> _tiposSeleccionados = {};
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  // Solo para 'Inasistencia'
  final _diasInasistenciaCtrl = TextEditingController();

  // Solo para 'Retraso'
  final _horasAtrasoCtrl = TextEditingController();
  late int _mesRetraso;
  late int _anioRetraso;

  // Solo para 'Prestamo'
  String? _subtipoPrestamo;
  final _montoPrestamoCtrl = TextEditingController();
  final _montoCuotaManualCtrl = TextEditingController();
  final _cantidadCuotasCtrl = TextEditingController();
  late int _mesInicioPrestamo;
  late int _anioInicioPrestamo;

  List<String> _yaRegistrado = [];

  // Sueldo base a usar en los calculos de esta pantalla: si existe un
  // Calculo Proporcional para este trabajador/periodo, se usa el
  // monto proporcional en su lugar (igual que ya hace Horas Extras).
  int? _sueldoBaseEfectivo;

  Future<void> _cargarSueldoProporcional() async {
    _sueldoBaseEfectivo = widget.sueldoBase;
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/calculo-proporcional?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final calculos = data['calculos'] as List<dynamic>;
        if (calculos.isNotEmpty && mounted) {
          setState(() {
            _sueldoBaseEfectivo = calculos.first['monto_proporcional'] as int;
          });
        }
      }
    } catch (_) {
      // silencioso: si falla, se sigue usando el sueldo base normal
    }
  }

  int? get _montoInasistenciaCalculado {
    final sueldo = _sueldoBaseEfectivo;
    final dias = int.tryParse(_diasInasistenciaCtrl.text.trim());
    if (sueldo == null || dias == null || dias <= 0) return null;
    return (sueldo / 30 * dias).round();
  }

  int get _ultimoDiaDelPeriodo {
    final partes = widget.periodo.split('/');
    final mes = int.tryParse(partes[0]) ?? DateTime.now().month;
    final anio = int.tryParse(partes[1]) ?? DateTime.now().year;
    return DateTime(anio, mes + 1, 0).day;
  }

  /// Dia de referencia a usar como fecha_evento cuando no hay un
  /// selector de fecha visual: si el periodo es el mes en curso, usa
  /// hoy (para no caer en "fecha futura"); si es un periodo pasado,
  /// usa el ultimo dia de ese mes.
  int get _diaReferenciaEvento {
    final partes = widget.periodo.split('/');
    final mes = int.tryParse(partes[0]) ?? DateTime.now().month;
    final anio = int.tryParse(partes[1]) ?? DateTime.now().year;
    final hoy = DateTime.now();
    if (anio == hoy.year && mes == hoy.month) {
      return hoy.day;
    }
    return _ultimoDiaDelPeriodo;
  }

  double? _parseHorasAtraso(String texto) {
    final partes = texto.trim().split(':');
    if (partes.length != 2) return null;
    final horas = int.tryParse(partes[0]);
    final minutos = int.tryParse(partes[1]);
    if (horas == null || minutos == null || minutos < 0 || minutos > 59) {
      return null;
    }
    return horas + (minutos / 60);
  }

  double? get _factorHorasAtraso {
    return _parseHorasAtraso(_horasAtrasoCtrl.text);
  }

  int? get _montoRetrasoCalculado {
    // Siempre usa el sueldo base COMPLETO del contrato (30 dias), no
    // el sueldo proporcional -- mismo criterio que Horas Extras: el
    // sueldo mensual pactado no cambia segun cuantos dias se trabajo
    // ese mes en particular.
    final sueldo = widget.sueldoBase;
    final jornada = widget.jornadaSemanal;
    final factor = _parseHorasAtraso(_horasAtrasoCtrl.text);
    if (sueldo == null ||
        jornada == null ||
        jornada <= 0 ||
        factor == null ||
        factor <= 0) {
      return null;
    }
    final valorDia = sueldo / 30;
    final sueldoSemanal = valorDia * 7;
    final valorHora = sueldoSemanal / jornada;
    return (valorHora * factor).round();
  }

  /// Meses seleccionables para un año dado: si es el año actual, solo
  /// hasta el mes actual (no permite meses futuros); años anteriores
  /// permiten los 12 meses completos.
  List<int> _mesesDisponibles(int anio) {
    final hoy = DateTime.now();
    final tope = anio == hoy.year ? hoy.month : 12;
    return List.generate(tope, (i) => i + 1);
  }

  int? get _montoCuotaCalculado {
    final monto = desformatearMiles(_montoPrestamoCtrl.text);
    final cuotas = int.tryParse(_cantidadCuotasCtrl.text.trim());
    if (monto == null || cuotas == null || cuotas <= 0) return null;
    return (monto / cuotas).round();
  }

  @override
  void initState() {
    super.initState();
    // Los selectores de mes/año de Retraso y Prestamo parten en el
    // periodo que se esta procesando en el wizard (no en la fecha de
    // hoy), para evitar que un descuento quede guardado en un periodo
    // distinto al que el admin realmente esta registrando.
    final partesPeriodo = widget.periodo.split('/');
    final mesInicial = partesPeriodo.length == 2
        ? int.tryParse(partesPeriodo[0]) ?? DateTime.now().month
        : DateTime.now().month;
    final anioInicial = partesPeriodo.length == 2
        ? int.tryParse(partesPeriodo[1]) ?? DateTime.now().year
        : DateTime.now().year;
    _mesRetraso = mesInicial;
    _anioRetraso = anioInicial;
    _mesInicioPrestamo = mesInicial;
    _anioInicioPrestamo = anioInicial;
    _cargarSueldoProporcional();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final descuentos = (resumen['descuentos'] as List?) ?? [];
    setState(() {
      _yaRegistrado = descuentos
          .map(
            (d) =>
                '${d['tipo']} · \$${formatearMiles(d['monto'])} CLP · ${d['fecha']}'
                    as String,
          )
          .toList();
    });
  }

  @override
  void dispose() {
    _diasInasistenciaCtrl.dispose();
    _horasAtrasoCtrl.dispose();
    _montoPrestamoCtrl.dispose();
    _montoCuotaManualCtrl.dispose();
    _cantidadCuotasCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _enviarUno(Map<String, dynamic> body) async {
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

  /// Compara widget.periodo (formato MM/AAAA) contra el mes actual.
  bool get _periodoEsFuturo {
    final partes = widget.periodo.split('/');
    if (partes.length != 2) return false;
    final mes = int.tryParse(partes[0]);
    final anio = int.tryParse(partes[1]);
    if (mes == null || anio == null) return false;
    final hoy = DateTime.now();
    return (anio > hoy.year) || (anio == hoy.year && mes > hoy.month);
  }

  Future<void> _enviar() async {
    if (_periodoEsFuturo) {
      setState(() {
        _exito = false;
        _mensaje = 'El periodo no puede ser futuro al mes actual';
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

    if (_tiposSeleccionados.contains('Inasistencia')) {
      final dias = int.tryParse(_diasInasistenciaCtrl.text.trim());
      if (dias == null || dias <= 0) {
        setState(() {
          _exito = false;
          _mensaje = 'Inasistencia: ingresa el total de días';
        });
        return;
      }
      if (_montoInasistenciaCalculado == null) {
        setState(() {
          _exito = false;
          _mensaje = 'Inasistencia: no se pudo calcular el monto';
        });
        return;
      }
    }
    if (_tiposSeleccionados.contains('Retraso')) {
      if (_montoRetrasoCalculado == null) {
        setState(() {
          _exito = false;
          _mensaje = 'Retraso: ingresa las horas de atraso (formato HH:MM)';
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
      final cuotas = int.tryParse(_cantidadCuotasCtrl.text.trim());
      if (cuotas == null || cuotas <= 0) {
        setState(() {
          _exito = false;
          _mensaje = 'Préstamo: ingresa la cantidad de cuotas';
        });
        return;
      }
      if (_subtipoPrestamo == 'Interno') {
        final montoPrestamo = desformatearMiles(_montoPrestamoCtrl.text);
        if (montoPrestamo == null || montoPrestamo <= 0) {
          setState(() {
            _exito = false;
            _mensaje = 'Préstamo: ingresa el monto del préstamo';
          });
          return;
        }
      } else {
        final montoCuota = desformatearMiles(_montoCuotaManualCtrl.text);
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

      if (_tiposSeleccionados.contains('Inasistencia')) {
        final monto = _montoInasistenciaCalculado!;
        final fechaEvento = DateTime(
          int.parse(widget.periodo.split('/')[1]),
          int.parse(widget.periodo.split('/')[0]),
          _diaReferenciaEvento,
        );
        final r = await _enviarUno({
          'persona_id': widget.personaId,
          'tipo_descuento': 'Inasistencia',
          'monto_clp': monto,
          'fecha_evento': fechaEvento.toIso8601String().split('T')[0],
          'dias_evento': int.parse(_diasInasistenciaCtrl.text.trim()),
        });
        if (r['success'] == true) {
          resultados.add('Inasistencia: registrada');
        } else {
          huboError = true;
          resultados.add('Inasistencia: ${r['mensaje'] ?? 'error'}');
        }
      }

      if (_tiposSeleccionados.contains('Retraso')) {
        final monto = _montoRetrasoCalculado!;
        final fechaRetraso = DateTime(_anioRetraso, _mesRetraso, 1);
        final r = await _enviarUno({
          'persona_id': widget.personaId,
          'tipo_descuento': 'Retraso',
          'monto_clp': monto,
          'fecha_evento': fechaRetraso.toIso8601String().split('T')[0],
          'dias_evento': _factorHorasAtraso,
        });
        if (r['success'] == true) {
          resultados.add('Retraso: registrado');
        } else {
          huboError = true;
          resultados.add('Retraso: ${r['mensaje'] ?? 'error'}');
        }
      }

      if (_tiposSeleccionados.contains('Prestamo')) {
        Map<String, dynamic> bodyPrestamo = {
          'persona_id': widget.personaId,
          'tipo_descuento': 'Prestamo',
          'subtipo_prestamo': _subtipoPrestamo,
          'cantidad_cuotas': int.parse(_cantidadCuotasCtrl.text.trim()),
          'mes_inicio': _mesInicioPrestamo,
          'anio_inicio': _anioInicioPrestamo,
        };
        if (_subtipoPrestamo == 'Interno') {
          bodyPrestamo['monto_prestamo'] = int.parse(
            _montoPrestamoCtrl.text.trim(),
          );
        } else {
          bodyPrestamo['monto_cuota_manual'] = int.parse(
            _montoCuotaManualCtrl.text.trim(),
          );
        }
        final r = await _enviarUno(bodyPrestamo);
        if (r['success'] == true) {
          resultados.add('Préstamo: ${r['mensaje'] ?? 'registrado'}');
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
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(lineas: _yaRegistrado),
        const Text(
          'Tipo (puedes elegir más de uno):',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: ['Inasistencia', 'Retraso', 'Prestamo'].map((t) {
            final seleccionado = _tiposSeleccionados.contains(t);
            const nombresVisibles = {
              'Inasistencia': 'Inasistencia',
              'Retraso': 'Horas de atraso',
              'Prestamo': 'Préstamo',
            };
            return FilterChip(
              label: Text(
                nombresVisibles[t] ?? t,
                style: const TextStyle(fontSize: 13),
              ),
              selected: seleccionado,
              onSelected: (marcado) => setState(() {
                if (marcado) {
                  _tiposSeleccionados.add(t);
                } else {
                  _tiposSeleccionados.remove(t);
                }
              }),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),

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
                if (_sueldoBaseEfectivo == null)
                  const Text(
                    'No se encontró el sueldo base del trabajador.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  )
                else
                  Text(
                    _sueldoBaseEfectivo != widget.sueldoBase
                        ? 'Sueldo base proporcional: \$${formatearMiles(_sueldoBaseEfectivo)} CLP'
                        : 'Sueldo base: \$${formatearMiles(_sueldoBaseEfectivo)} CLP',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Días de inasistencia:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _diasInasistenciaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Ej: 2',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Text(
                  _montoInasistenciaCalculado != null
                      ? 'Monto a descontar: \$${formatearMiles(_montoInasistenciaCalculado)} CLP'
                      : 'Ingresa los días para calcular...',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _montoInasistenciaCalculado != null
                        ? const Color(0xFF059669)
                        : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],

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
                if (widget.sueldoBase == null || widget.jornadaSemanal == null)
                  const Text(
                    'No se encontró sueldo base o jornada semanal del trabajador.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  )
                else
                  Text(
                    'Sueldo base: \$${formatearMiles(widget.sueldoBase)} CLP · Jornada: ${widget.jornadaSemanal} hrs/semana',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Horas totales de atraso (HH:MM):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _horasAtrasoCtrl,
                            decoration: InputDecoration(
                              hintText: 'Ej: 4:15',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Horas totales de atrasos en factor:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            readOnly: true,
                            controller: TextEditingController(
                              text: _factorHorasAtraso != null
                                  ? _factorHorasAtraso!.toStringAsFixed(2)
                                  : '',
                            ),
                            decoration: InputDecoration(
                              hintText: '—',
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _montoRetrasoCalculado != null
                      ? 'Monto a descontar: \$${formatearMiles(_montoRetrasoCalculado)} CLP'
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
                  'Período (mes/año):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
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
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _mesesDisponibles(_anioRetraso)
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m.toString().padLeft(2, '0')),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _mesRetraso = v ?? _mesRetraso),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _anioRetraso,
                        isDense: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: List.generate(6, (i) => DateTime.now().year - i)
                            .map(
                              (a) =>
                                  DropdownMenuItem(value: a, child: Text('$a')),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          _anioRetraso = v ?? _anioRetraso;
                          final disponibles = _mesesDisponibles(_anioRetraso);
                          if (!disponibles.contains(_mesRetraso)) {
                            _mesRetraso = disponibles.last;
                          }
                        }),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        if (_tiposSeleccionados.contains('Prestamo')) ...[
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
                  'Tipo de préstamo:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            setState(() => _subtipoPrestamo = 'Interno'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _subtipoPrestamo == 'Interno'
                                ? const Color(0xFF001E42).withOpacity(0.08)
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(
                          () => _subtipoPrestamo = 'CajaCompensacion',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _subtipoPrestamo == 'CajaCompensacion'
                                ? const Color(0xFF001E42).withOpacity(0.08)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _subtipoPrestamo == 'CajaCompensacion'
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
                  const SizedBox(height: 18),
                  if (_subtipoPrestamo == 'Interno') ...[
                    TextField(
                      controller: _montoPrestamoCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [MilesInputFormatter()],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Monto del préstamo (CLP)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _cantidadCuotasCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Cantidad de cuotas',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_subtipoPrestamo == 'Interno')
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        _montoCuotaCalculado != null
                            ? 'Cuota calculada: \$${formatearMiles(_montoCuotaCalculado)} CLP'
                            : 'Ingresa monto y cuotas...',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _montoCuotaCalculado != null
                              ? const Color(0xFF059669)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  else
                    TextField(
                      controller: _montoCuotaManualCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [MilesInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Monto de la cuota (CLP)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _mesInicioPrestamo,
                          decoration: InputDecoration(
                            labelText: 'Mes inicio',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          items: _mesesDisponibles(_anioInicioPrestamo)
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m.toString().padLeft(2, '0')),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(
                            () => _mesInicioPrestamo = v ?? _mesInicioPrestamo,
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
                              List.generate(6, (i) => DateTime.now().year - i)
                                  .map(
                                    (a) => DropdownMenuItem(
                                      value: a,
                                      child: Text('$a'),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (v) => setState(() {
                            _anioInicioPrestamo = v ?? _anioInicioPrestamo;
                            final disponibles = _mesesDisponibles(
                              _anioInicioPrestamo,
                            );
                            if (!disponibles.contains(_mesInicioPrestamo)) {
                              _mesInicioPrestamo = disponibles.last;
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],

        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _enviando ? 'Guardando...' : 'Confirmar Descuento(s)',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION 2: BONOS IMPONIBLES
// ══════════════════════════════════════════════════════════════
class SeccionBonoImponible extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionBonoImponible({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionBonoImponible> createState() => _SeccionBonoImponibleState();
}

class _SeccionBonoImponibleState extends State<SeccionBonoImponible> {
  String _tipo = 'Bonificacion';
  final _montoCtrl = TextEditingController();
  final _conceptoOtrosCtrl = TextEditingController();
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  List<String> _yaRegistrado = [];

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final bonos = (resumen['bonos_imponibles'] as List?) ?? [];
    setState(() {
      _yaRegistrado = bonos
          .map(
            (b) =>
                '${b['tipo']} · \$${formatearMiles(b['monto'])} CLP' as String,
          )
          .toList();
    });
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _conceptoOtrosCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final monto = desformatearMiles(_montoCtrl.text);
    if (monto == null || monto <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Ingresa un monto válido';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/bonos-imponibles'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'tipo_bono': _tipo,
          'monto_clp': monto,
          'periodo': widget.periodo,
          'concepto_otros': _tipo == 'Otros'
              ? _conceptoOtrosCtrl.text.trim()
              : '',
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Bono registrado correctamente'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(lineas: _yaRegistrado),
        const Text(
          'Tipo:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              [
                    'Bonificacion',
                    'Bonificacion de Produccion',
                    'Bonificacion por Turno',
                    'Otros',
                  ]
                  .map(
                    (t) => ChoiceChip(
                      label: Text(t, style: const TextStyle(fontSize: 12)),
                      selected: _tipo == t,
                      onSelected: (_) => setState(() => _tipo = t),
                    ),
                  )
                  .toList(),
        ),
        if (_tipo == 'Otros') ...[
          const SizedBox(height: 16),
          TextField(
            controller: _conceptoOtrosCtrl,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'Especifica el concepto',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _montoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [MilesInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Monto (CLP)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                ),
                child: Text(_enviando ? 'Guardando...' : 'Confirmar Bono'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION 3: LICENCIAS MEDICAS
// ══════════════════════════════════════════════════════════════
class SeccionLicenciaMedica extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionLicenciaMedica({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionLicenciaMedica> createState() => _SeccionLicenciaMedicaState();
}

class _SeccionLicenciaMedicaState extends State<SeccionLicenciaMedica> {
  final _tipoCtrl = TextEditingController(text: 'Licencia medica comun');
  final _entidadCtrl = TextEditingController();
  DateTime? _inicio;
  DateTime? _fin;
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  List<String> _yaRegistrado = [];

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final licencias = (resumen['licencias'] as List?) ?? [];
    setState(() {
      _yaRegistrado = licencias
          .map(
            (l) =>
                '${l['tipo']} · ${l['inicio']} - ${l['fin']} · \$${formatearMiles(l['monto'])} CLP'
                    as String,
          )
          .toList();
    });
  }

  @override
  void dispose() {
    _tipoCtrl.dispose();
    _entidadCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_inicio == null || _fin == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona fecha de inicio y fin';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/licencias-medicas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'fecha_inicio': _inicio!.toIso8601String().split('T')[0],
          'fecha_fin': _fin!.toIso8601String().split('T')[0],
          'tipo_de_licencia': _tipoCtrl.text.trim(),
          'entidad_emisora': _entidadCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Licencia registrada correctamente'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(lineas: _yaRegistrado),
        TextField(
          controller: _tipoCtrl,
          decoration: InputDecoration(
            labelText: 'Tipo de licencia',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _entidadCtrl,
          decoration: InputDecoration(
            labelText: 'Entidad emisora (opcional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final f = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (f != null) setState(() => _inicio = f);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Inicio',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _inicio == null
                        ? '...'
                        : '${_inicio!.day}/${_inicio!.month}/${_inicio!.year}',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  if (_inicio == null) return;
                  final f = await showDatePicker(
                    context: context,
                    initialDate: _inicio!,
                    firstDate: _inicio!,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (f != null) setState(() => _fin = f);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Fin',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    _fin == null
                        ? '...'
                        : '${_fin!.day}/${_fin!.month}/${_fin!.year}',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF64748B),
                  foregroundColor: Colors.white,
                ),
                child: Text(_enviando ? 'Guardando...' : 'Confirmar Licencia'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION 4: HORAS EXTRAS
// ══════════════════════════════════════════════════════════════
class SeccionHorasExtras extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionHorasExtras({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionHorasExtras> createState() => _SeccionHorasExtrasState();
}

class _SeccionHorasExtrasState extends State<SeccionHorasExtras> {
  final _horasCtrl = TextEditingController();
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  String? _yaRegistrado;

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final horas = resumen['horas_extras'];
    final montoHoras = resumen['horas_extras_monto'];
    setState(
      () => _yaRegistrado = horas != null
          ? '$horas horas registradas${montoHoras != null ? ' (\$${formatearMiles(montoHoras)} CLP)' : ''}'
          : null,
    );
  }

  @override
  void dispose() {
    _horasCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final horas = double.tryParse(_horasCtrl.text.trim().replaceAll(',', '.'));
    if (horas == null || horas <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Ingresa una cantidad válida';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/horas-extras'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'periodo': widget.periodo,
          'cantidad_horas': horas,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Registradas: \$${formatearMiles(data['monto_total'])} CLP'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(
          lineas: _yaRegistrado != null ? [_yaRegistrado!] : [],
        ),
        const Text(
          'Total de horas extra trabajadas en el mes:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _horasCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: 'Ej: 22.12',
            suffixText: 'hrs',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _enviando ? 'Guardando...' : 'Confirmar Horas Extras',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION 5: MOVILIZACION Y COLACION
// ══════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════
// SECCION: MOVILIZACION Y COLACION (valores fijos, sin tope)
// ══════════════════════════════════════════════════════════════
class SeccionMovilizacion extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionMovilizacion({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionMovilizacion> createState() => _SeccionMovilizacionState();
}

class _SeccionMovilizacionState extends State<SeccionMovilizacion> {
  static const int _montoFijoMovilizacion = 50000;
  static const int _montoFijoColacion = 60000;
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  List<String> _yaRegistrado = [];

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final items = (resumen['movilizacion_colacion'] as List?) ?? [];
    setState(() {
      _yaRegistrado = items
          .map(
            (i) =>
                '${i['concepto']} · \$${formatearMiles(i['monto'])} CLP'
                    as String,
          )
          .toList();
    });
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/movilizacion-colacion-fija'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'periodo': widget.periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Registrado: Movilización \$$_montoFijoMovilizacion · Colación \$$_montoFijoColacion'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 900));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(lineas: _yaRegistrado),
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La ley no fija un monto maximo exacto (se evalua por "razonabilidad").',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Movilización',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  Text(
                    '\$${formatearMiles(_montoFijoMovilizacion)} CLP',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF001E42),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Colación',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  Text(
                    '\$${formatearMiles(_montoFijoColacion)} CLP',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF001E42),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _enviando ? null : _enviar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
            ),
            child: Text(_enviando ? 'Guardando...' : 'Confirmar Asignación'),
          ),
        ),
      ],
    );
  }
}

class SeccionBonoExcepcional extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionBonoExcepcional({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionBonoExcepcional> createState() => _SeccionBonoExcepcionalState();
}

class _SeccionBonoExcepcionalState extends State<SeccionBonoExcepcional> {
  final _conceptoCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _clasificacion = 'Imponible';
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  List<String> _yaRegistrado = [];

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final bonos = (resumen['bonos_excepcionales'] as List?) ?? [];
    setState(() {
      _yaRegistrado = bonos
          .map(
            (b) =>
                '${b['concepto']} (${b['clasificacion']}) · \$${formatearMiles(b['monto'])} CLP'
                    as String,
          )
          .toList();
    });
  }

  @override
  void dispose() {
    _conceptoCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_conceptoCtrl.text.trim().length < 3) {
      setState(() {
        _exito = false;
        _mensaje = 'El concepto debe tener al menos 3 caracteres';
      });
      return;
    }
    final monto = desformatearMiles(_montoCtrl.text);
    if (monto == null || monto <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Ingresa un monto válido';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/bono-excepcional'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'concepto': _conceptoCtrl.text.trim(),
          'monto_clp': monto,
          'clasificacion': _clasificacion,
          'periodo': widget.periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Bono excepcional registrado correctamente'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(lineas: _yaRegistrado),
        TextField(
          controller: _conceptoCtrl,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'Concepto',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _montoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [MilesInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Monto (CLP)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Imponible'),
              selected: _clasificacion == 'Imponible',
              onSelected: (_) => setState(() => _clasificacion = 'Imponible'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('No imponible'),
              selected: _clasificacion == 'No imponible',
              onSelected: (_) =>
                  setState(() => _clasificacion = 'No imponible'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _enviando ? 'Guardando...' : 'Confirmar Bono Excepcional',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION 8: ANTICIPO DE SUELDO
// ══════════════════════════════════════════════════════════════
class SeccionAnticipo extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionAnticipo({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionAnticipo> createState() => _SeccionAnticipoState();
}

class _SeccionAnticipoState extends State<SeccionAnticipo> {
  final _montoCtrl = TextEditingController();
  final _folioCtrl = TextEditingController();
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  String? _yaRegistrado;

  @override
  void initState() {
    super.initState();
    _cargarResumen();
  }

  Future<void> _cargarResumen() async {
    final resumen = await obtenerResumenRegistros(
      widget.personaId,
      widget.periodo,
    );
    if (resumen == null || !mounted) return;
    final ant = resumen['anticipo'];
    setState(
      () => _yaRegistrado = ant != null
          ? '\$${formatearMiles(ant['monto'])} CLP · Folio: ${ant['folio']} · ${ant['estado']}'
          : null,
    );
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _folioCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final monto = desformatearMiles(_montoCtrl.text);
    if (monto == null || monto <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Debe completar la información solicitada.';
      });
      return;
    }
    if (_folioCtrl.text.trim().isEmpty) {
      setState(() {
        _exito = false;
        _mensaje = 'Debe completar la información solicitada.';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/anticipos-sueldo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'monto_clp': monto,
          'periodo': widget.periodo,
          'folio_autorizacion': _folioCtrl.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Anticipo registrado correctamente'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BannerYaRegistrado(
          lineas: _yaRegistrado != null ? [_yaRegistrado!] : [],
        ),
        TextField(
          controller: _montoCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [MilesInputFormatter()],
          decoration: InputDecoration(
            labelText: 'Monto del anticipo (CLP)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _folioCtrl,
          maxLength: 20,
          decoration: InputDecoration(
            labelText: 'Folio de autorización',
            hintText: 'Ej: ANT-2026-001',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  foregroundColor: Colors.white,
                ),
                child: Text(_enviando ? 'Guardando...' : 'Confirmar Anticipo'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: CALCULO PROPORCIONAL (Art. 41)
// ══════════════════════════════════════════════════════════════
class SeccionCalculoProporcional extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionCalculoProporcional({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionCalculoProporcional> createState() =>
      _SeccionCalculoProporcionalState();
}

class _SeccionCalculoProporcionalState
    extends State<SeccionCalculoProporcional> {
  String _motivo = 'Ingreso';
  DateTime? _fechaEgreso;
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  Map<String, dynamic>? _resultado;
  bool _cargandoInicial = true;

  @override
  void initState() {
    super.initState();
    _cargarSiYaExiste();
  }

  Future<void> _cargarSiYaExiste() async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/calculo-proporcional?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final calculos = data['calculos'] as List<dynamic>;
        if (calculos.isNotEmpty) {
          final c = calculos.first;
          setState(() {
            _motivo = c['motivo'];
            _resultado = {
              'dias_trabajados': c['dias_trabajados'],
              'monto_proporcional': c['monto_proporcional'],
              'colacion_proporcional': c['colacion_proporcional'],
              'locomocion_proporcional': c['locomocion_proporcional'],
            };
            _mensaje = 'Ya registrado: ${c['dias_trabajados']} días trabajados';
            _exito = true;
          });
        }
      }
    } catch (_) {
      // silencioso: si falla, simplemente parte vacio
    } finally {
      setState(() => _cargandoInicial = false);
    }
  }

  DateTime get _primerDiaDelPeriodo {
    final partes = widget.periodo.split('/');
    final mes = int.tryParse(partes[0]) ?? DateTime.now().month;
    final anio = int.tryParse(partes[1]) ?? DateTime.now().year;
    return DateTime(anio, mes, 1);
  }

  DateTime get _ultimoDiaDelPeriodo {
    final primerDiaSiguiente = DateTime(
      _primerDiaDelPeriodo.year,
      _primerDiaDelPeriodo.month + 1,
      1,
    );
    return primerDiaSiguiente.subtract(const Duration(days: 1));
  }

  Future<void> _elegirFechaEgreso() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaEgreso ?? _ultimoDiaDelPeriodo,
      firstDate: _primerDiaDelPeriodo,
      lastDate: _ultimoDiaDelPeriodo,
      helpText: 'Último día trabajado',
    );
    if (fecha != null) setState(() => _fechaEgreso = fecha);
  }

  Future<void> _enviar() async {
    if (_motivo == 'Egreso' && _fechaEgreso == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona el último día trabajado';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/calculo-proporcional'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'periodo': widget.periodo,
          'motivo': _motivo,
          if (_motivo == 'Egreso')
            'fecha_referencia':
                '${_fechaEgreso!.year.toString().padLeft(4, '0')}-${_fechaEgreso!.month.toString().padLeft(2, '0')}-${_fechaEgreso!.day.toString().padLeft(2, '0')}',
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _resultado = _exito ? data : null;
        _mensaje = _exito
            ? '${data['dias_trabajados']} días trabajados (desde/hasta ${data['fecha_usada']})'
            : (data['mensaje'] ?? 'Error');
      });
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
    if (_cargandoInicial) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Solo aplica si hubo ingreso o egreso a mitad de mes. Si no aplica, toca "Siguiente sin registrar".',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Ingreso'),
              selected: _motivo == 'Ingreso',
              onSelected: (_) => setState(() {
                _motivo = 'Ingreso';
                _resultado = null;
                _mensaje = '';
              }),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Egreso'),
              selected: _motivo == 'Egreso',
              onSelected: (_) => setState(() {
                _motivo = 'Egreso';
                _resultado = null;
                _mensaje = '';
              }),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_motivo == 'Ingreso')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Los días trabajados se calculan automáticamente a partir de la fecha de ingreso registrada en el contrato del trabajador.',
              style: TextStyle(fontSize: 12, color: Color(0xFF0D9488)),
            ),
          )
        else ...[
          const Text(
            'Último día trabajado:',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _elegirFechaEgreso,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fechaEgreso == null
                        ? 'Selecciona una fecha dentro de ${widget.periodo}'
                        : '${_fechaEgreso!.day.toString().padLeft(2, '0')}/${_fechaEgreso!.month.toString().padLeft(2, '0')}/${_fechaEgreso!.year}',
                    style: TextStyle(
                      color: _fechaEgreso == null
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (_resultado != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sueldo base proporcional: \$${formatearMiles(_resultado!['monto_proporcional'])} CLP',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Colación proporcional: \$${formatearMiles(_resultado!['colacion_proporcional'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Locomoción proporcional: \$${formatearMiles(_resultado!['locomocion_proporcional'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _enviar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _enviando ? 'Calculando...' : 'Calcular y Confirmar',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Siguiente sin registrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: TOTAL IMPONIBLE (resumen, solo consulta)
// ══════════════════════════════════════════════════════════════
class SeccionTotalImponible extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionTotalImponible({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionTotalImponible> createState() => _SeccionTotalImponibleState();
}

class _SeccionTotalImponibleState extends State<SeccionTotalImponible> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultado = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/total-imponible?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
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
        setState(() => _error = data['mensaje'] ?? 'Error');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desglose = _resultado?['desglose'];
    final bool esProporcional = desglose?['es_proporcional'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Suma todo lo registrado arriba: sueldo (o proporcional), horas extras, bonos, excedente de movilización/colación y gratificación legal.',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),
        if (_resultado != null && desglose != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _filaHaber(
                  esProporcional ? 'Sueldo proporcional' : 'Sueldo base',
                  desglose['sueldo_base_considerado'],
                  subtitulo: esProporcional
                      ? 'En función de ${desglose['detalle_proporcional']}'
                      : null,
                ),
                _filaHaber(
                  'Horas extras',
                  desglose['horas_extra_total'],
                  subtitulo: (desglose['horas_extra_horas'] ?? 0) > 0
                      ? '${desglose['horas_extra_horas']} horas extra ingresadas'
                      : null,
                ),
                _filaHaber(
                  'Bonos imponibles',
                  desglose['bonos_imponibles_total'],
                  subtitulo: _resumenBonos(
                    desglose['detalle_bonos_imponibles'],
                  ),
                ),
                if ((desglose['bono_excepcional_imponible_total'] ?? 0) > 0)
                  _filaHaber(
                    'Bono excepcional',
                    desglose['bono_excepcional_imponible_total'],
                    subtitulo: _resumenBonoExcepcional(
                      desglose['detalle_bono_excepcional'],
                      soloImponibles: true,
                    ),
                  ),
                _filaHaber(
                  'Movilización y Colación',
                  desglose['monto_exento_no_imponible_total'],
                  subtitulo:
                      ((desglose['colacion_total'] ?? 0) > 0 ||
                          (desglose['locomocion_total'] ?? 0) > 0)
                      ? 'Colación: \$${formatearMiles(desglose['colacion_total'])} CLP · Locomoción: \$${formatearMiles(desglose['locomocion_total'])} CLP'
                      : null,
                ),
                if ((desglose['excedente_no_imponible_total'] ?? 0) > 0)
                  _filaHaber(
                    'Excedente movilización/colación (imponible)',
                    desglose['excedente_no_imponible_total'],
                  ),
                _filaHaber(
                  'Gratificación legal',
                  desglose['gratificacion_total'],
                ),
                if ((desglose['descuento_atraso_total'] ?? 0) > 0)
                  _filaHaber(
                    'Descuento de atraso',
                    -(desglose['descuento_atraso_total'] as num),
                    subtitulo:
                        '${formatearHorasMinutos(desglose['horas_atraso_total'])} horas de atraso ingresadas',
                  ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL HABERES',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    Text(
                      '\$${formatearMiles(_resultado!['total_haberes'])} CLP',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_resultado != null)
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
                  'Resumen de días trabajados del mes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 8),
                _filaDias('Base del mes', desglose['dias_base_mes']),
                _filaDias(
                  'Número de días de inasistencia',
                  desglose['dias_inasistencia_total'],
                ),
                _filaDias(
                  'Número de días de licencia',
                  desglose['dias_licencia_total'],
                ),
                if (desglose['dias_proporcional'] != null)
                  _filaDias(
                    'Días de cálculo proporcional (ingreso/egreso)',
                    desglose['dias_proporcional'],
                  ),
                const Divider(height: 16),
                _filaDias(
                  'Total días a pagar',
                  desglose['dias_a_pagar'],
                  destacado: true,
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando ? 'Calculando...' : 'Calcular Total Haberes',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultado != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String? _resumenBonos(dynamic detalle) {
    if (detalle == null || (detalle as List).isEmpty) return null;
    return detalle
        .map((b) => '${b['tipo']}: \$${formatearMiles(b['monto'])} CLP')
        .join(' · ');
  }

  String? _resumenBonoExcepcional(
    dynamic detalle, {
    bool soloImponibles = false,
  }) {
    if (detalle == null) return null;
    final lista = (detalle as List).where(
      (b) => !soloImponibles || b['clasificacion'] == 'Imponible',
    );
    if (lista.isEmpty) return null;
    return lista
        .map((b) => '${b['concepto']}: \$${formatearMiles(b['monto'])} CLP')
        .join(' · ');
  }

  Widget _filaHaber(String label, dynamic monto, {String? subtitulo}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              Text(
                '\$${formatearMiles(monto)} CLP',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          if (subtitulo != null && subtitulo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitulo,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filaDias(String label, dynamic dias, {bool destacado = false}) {
    final valor = dias is num ? dias : num.tryParse(dias.toString()) ?? 0;
    final texto = valor == valor.roundToDouble()
        ? valor.round().toString()
        : valor.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: destacado ? 13 : 12,
                fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          Text(
            '$texto día(s)',
            style: TextStyle(
              fontSize: destacado ? 13 : 12,
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

// ══════════════════════════════════════════════════════════════
// SECCION: AFC (solo consulta)
// ══════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════
// SECCION: VALOR UF (3 valores independientes por periodo)
// ══════════════════════════════════════════════════════════════
class SeccionValorUF extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionValorUF({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionValorUF> createState() => _SeccionValorUFState();
}

class _SeccionValorUFState extends State<SeccionValorUF> {
  final _valorUfCtrl = TextEditingController();
  final _multiploAfpSaludCtrl = TextEditingController(text: '90');
  final _multiploAfcCtrl = TextEditingController(text: '135.2');
  bool _enviando = false;
  bool _cargandoExistente = true;
  String _mensaje = '';
  bool _exito = false;

  double? get _valorUf =>
      double.tryParse(_valorUfCtrl.text.trim().replaceAll(',', '.'));
  double? get _multiploAfpSalud =>
      double.tryParse(_multiploAfpSaludCtrl.text.trim().replaceAll(',', '.'));
  double? get _multiploAfc =>
      double.tryParse(_multiploAfcCtrl.text.trim().replaceAll(',', '.'));

  double? get _topeAfpSaludCalculado {
    final valorUf = _valorUf;
    final multiplo = _multiploAfpSalud;
    if (valorUf == null || multiplo == null) return null;
    return valorUf * multiplo;
  }

  double? get _topeAfcCalculado {
    final valorUf = _valorUf;
    final multiplo = _multiploAfc;
    if (valorUf == null || multiplo == null) return null;
    return valorUf * multiplo;
  }

  @override
  void initState() {
    super.initState();
    _cargarValorExistente();
  }

  @override
  void dispose() {
    _valorUfCtrl.dispose();
    _multiploAfpSaludCtrl.dispose();
    _multiploAfcCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarValorExistente() async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/valor-uf'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final valores = (data['valores'] as List?) ?? [];
        final match = valores.firstWhere(
          (v) => v['periodo'] == widget.periodo,
          orElse: () => null,
        );
        if (match != null && mounted) {
          final valorUfGuardado = (match['valor_uf'] as num).toDouble();
          final topeAfpSaludGuardado = (match['tope_afp_salud'] as num)
              .toDouble();
          final topeAfcGuardado = (match['tope_afc'] as num).toDouble();
          setState(() {
            _valorUfCtrl.text = valorUfGuardado.toString();
            // Se reconstruye el multiplicador dividiendo el tope guardado
            // por el valor UF, para mostrar lo mismo que se ingreso antes.
            if (valorUfGuardado > 0) {
              _multiploAfpSaludCtrl.text =
                  (topeAfpSaludGuardado / valorUfGuardado).toStringAsFixed(4);
              _multiploAfcCtrl.text = (topeAfcGuardado / valorUfGuardado)
                  .toStringAsFixed(4);
            }
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoExistente = false);
    }
  }

  Future<void> _guardar() async {
    final valorUf = _valorUf;
    final topeAfpSalud = _topeAfpSaludCalculado;
    final topeAfc = _topeAfcCalculado;
    if (valorUf == null ||
        valorUf <= 0 ||
        topeAfpSalud == null ||
        topeAfpSalud <= 0 ||
        topeAfc == null ||
        topeAfc <= 0) {
      setState(() {
        _exito = false;
        _mensaje =
            'Ingresa el valor UF y ambos multiplicadores, todos deben ser positivos';
      });
      return;
    }
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/valor-uf'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'valor_uf': valorUf,
          'tope_afp_salud': topeAfpSalud,
          'tope_afc': topeAfc,
          'periodo': widget.periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Valores de UF guardados para ${widget.periodo}'
            : (data['mensaje'] ?? 'Error');
      });
      if (_exito) {
        await Future.delayed(const Duration(milliseconds: 700));
        widget.onDone();
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

  Widget _cajaResultado(double? valor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Text(
        valor != null
            ? 'Tope calculado: \$${formatearMiles(valor.round())} CLP'
            : 'Ingresa el valor UF y el multiplicador para calcular...',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: valor != null
              ? const Color(0xFF059669)
              : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoExistente)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingresa el valor de la UF del período, y luego el multiplicador de cada tope; el sistema calcula el monto en CLP automáticamente.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 18),
        const Text(
          'Valor UF del período:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _valorUfCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: 40844.79',
            prefixText: '\$ ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 8),
        const Text(
          'Multiplicador para AFP y Salud:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _multiploAfpSaludCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: 90',
            suffixText: 'UF',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        _cajaResultado(_topeAfpSaludCalculado),
        const SizedBox(height: 20),
        const Text(
          'Multiplicador para Seguro de Cesantía:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _multiploAfcCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ej: 135.2',
            suffixText: 'UF',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        _cajaResultado(_topeAfcCalculado),
        const SizedBox(height: 18),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _enviando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _enviando ? 'Guardando...' : 'Guardar Valores de UF',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: ElevatedButton(
                onPressed: widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Continuar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: TOTAL IMPONIBLE PARA AFP/SALUD Y AFC (fusionada, solo consulta)
// ══════════════════════════════════════════════════════════════
class SeccionTotalImponibleTopado extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionTotalImponibleTopado({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionTotalImponibleTopado> createState() =>
      _SeccionTotalImponibleTopadoState();
}

class _SeccionTotalImponibleTopadoState
    extends State<SeccionTotalImponibleTopado> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultado = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/total-imponible-topado?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
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
        setState(() => _error = data['mensaje'] ?? 'Error');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Widget _fila(
    String label,
    dynamic monto, {
    bool destacado = false,
    bool esDescuento = false,
    String? subtitulo,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: destacado ? 13 : 12,
                    fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
              Text(
                '${esDescuento ? "-" : ""}\$${formatearMiles(monto)} CLP',
                style: TextStyle(
                  fontSize: destacado ? 14 : 12,
                  fontWeight: FontWeight.bold,
                  color: destacado
                      ? const Color(0xFF1D4ED8)
                      : (esDescuento
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF0F172A)),
                ),
              ),
            ],
          ),
          if (subtitulo != null && subtitulo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitulo,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _resumenBonos(dynamic detalle) {
    if (detalle == null || (detalle as List).isEmpty) return null;
    return detalle
        .map((b) => '${b['tipo']}: \$${formatearMiles(b['monto'])} CLP')
        .join(' · ');
  }

  String? _resumenBonoExcepcional(
    dynamic detalle, {
    bool soloImponibles = false,
  }) {
    if (detalle == null) return null;
    final lista = (detalle as List).where(
      (b) => !soloImponibles || b['clasificacion'] == 'Imponible',
    );
    if (lista.isEmpty) return null;
    return lista
        .map((b) => '${b['concepto']}: \$${formatearMiles(b['monto'])} CLP')
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final desglose = _resultado?['desglose'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Base sin tope: sueldo + horas extras + bonos imponibles + bono excepcional imponible + gratificación. Se limita al tope de AFP/Salud y al de AFC por separado (según los valores configurados).',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),
        if (_resultado != null && desglose != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Base sin tope:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
                _fila(
                  'Sueldo base',
                  desglose['sueldo_base_considerado'],
                  subtitulo: desglose['es_proporcional'] == true
                      ? 'En función de ${desglose['detalle_proporcional']}'
                      : null,
                ),
                _fila(
                  'Horas extras',
                  desglose['horas_extra_total'],
                  subtitulo: (desglose['horas_extra_horas'] ?? 0) > 0
                      ? '${desglose['horas_extra_horas']} horas extra ingresadas'
                      : null,
                ),
                _fila(
                  'Bonos imponibles',
                  desglose['bonos_imponibles_total'],
                  subtitulo: _resumenBonos(
                    desglose['detalle_bonos_imponibles'],
                  ),
                ),
                if ((desglose['bono_excepcional_imponible_total'] ?? 0) > 0)
                  _fila(
                    'Bono excepcional',
                    desglose['bono_excepcional_imponible_total'],
                    subtitulo: _resumenBonoExcepcional(
                      desglose['detalle_bono_excepcional'],
                      soloImponibles: true,
                    ),
                  ),
                _fila('Gratificación legal', desglose['gratificacion_total']),
                if ((desglose['descuento_atraso_total'] ?? 0) > 0)
                  _fila(
                    'Descuento de atraso',
                    desglose['descuento_atraso_total'],
                    esDescuento: true,
                    subtitulo:
                        '${formatearHorasMinutos(desglose['horas_atraso_total'])} horas de atraso ingresadas',
                  ),
                const Divider(height: 18),
                _fila(
                  'TOTAL sin tope',
                  _resultado!['base_sin_tope'],
                  destacado: true,
                ),
                const SizedBox(height: 14),
                Text(
                  'Valor UF: \$${_resultado!['valor_uf']} CLP',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'TOTAL IMPONIBLE para AFP y Salud:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF059669),
                  ),
                ),
                _fila(
                  'Tope AFP/Salud',
                  (_resultado!['tope_afp_salud'] as num).round(),
                ),
                _fila(
                  'Resultado',
                  _resultado!['total_imponible_afp_salud'],
                  destacado: true,
                ),
                if (_resultado!['se_aplico_tope_afp_salud'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '⚠ Se aplicó el tope (la base superó el tope configurado)',
                      style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                    ),
                  ),
                const SizedBox(height: 14),
                const Text(
                  'TOTAL IMPONIBLE para AFC:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF059669),
                  ),
                ),
                _fila('Tope AFC', (_resultado!['tope_afc'] as num).round()),
                _fila(
                  'Resultado',
                  _resultado!['total_imponible_afc'],
                  destacado: true,
                ),
                if (_resultado!['se_aplico_tope_afc'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '⚠ Se aplicó el tope (la base superó el tope configurado)',
                      style: TextStyle(fontSize: 11, color: Color(0xFFD97706)),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando
                      ? 'Calculando...'
                      : 'Calcular Total Imponible (AFP/Salud y AFC)',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultado != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: TOTAL TRIBUTABLE (solo consulta)
// ══════════════════════════════════════════════════════════════
class SeccionTotalTributable extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionTotalTributable({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionTotalTributable> createState() => _SeccionTotalTributableState();
}

class _SeccionTotalTributableState extends State<SeccionTotalTributable> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultado = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/total-tributable?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
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
        setState(() => _error = data['mensaje'] ?? 'Error');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Widget _fila(
    String label,
    dynamic monto, {
    bool esDescuento = false,
    bool destacado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: destacado ? 13 : 12,
                fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          Text(
            '${esDescuento ? "-" : ""}\$${formatearMiles(monto)} CLP',
            style: TextStyle(
              fontSize: destacado ? 14 : 12,
              fontWeight: FontWeight.bold,
              color: destacado
                  ? const Color(0xFF1D4ED8)
                  : (esDescuento
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Total imponible (sin tope) menos AFP, Salud y AFC del trabajador — es la base sobre la que se calcula el Impuesto Único.',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),
        if (_resultado != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fila(
                  'Total Imponible (sin tope)',
                  _resultado!['total_imponible'],
                ),
                _fila(
                  'Descuento AFP',
                  _resultado!['descuento_afp'],
                  esDescuento: true,
                ),
                _fila(
                  'Descuento Salud',
                  _resultado!['descuento_salud'],
                  esDescuento: true,
                ),
                _fila(
                  'Descuento Seguro Cesantía (AFC)',
                  _resultado!['descuento_afc_trabajador'],
                  esDescuento: true,
                ),
                const Divider(height: 18),
                _fila(
                  'TOTAL TRIBUTABLE',
                  _resultado!['total_tributable'],
                  destacado: true,
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando ? 'Calculando...' : 'Calcular Total Tributable',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultado != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION FUSIONADA: SEGURO DE CESANTIA (AFC) + AFP Y SALUD
// Un solo boton calcula ambas al mismo tiempo (en paralelo) y
// muestra los 2 resultados juntos.
// ══════════════════════════════════════════════════════════════
class SeccionAfcYAfpSalud extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionAfcYAfpSalud({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionAfcYAfpSalud> createState() => _SeccionAfcYAfpSaludState();
}

class _SeccionAfcYAfpSaludState extends State<SeccionAfcYAfpSalud> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultadoAfc;
  Map<String, dynamic>? _resultadoAfpSalud;
  Map<String, dynamic>? _resultadoTributable;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultadoAfc = null;
      _resultadoAfpSalud = null;
      _resultadoTributable = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // AFC y AFP/Salud se calculan en paralelo, no una despues de la otra.
      final resultados = await Future.wait([
        http.get(
          Uri.parse(
            '$_apiUrl/admin/calculo-afc?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
          ),
          headers: headers,
        ),
        http.get(
          Uri.parse(
            '$_apiUrl/admin/calculo-afp-salud?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
          ),
          headers: headers,
        ),
      ]);

      final dataAfc = jsonDecode(resultados[0].body);
      final dataAfpSalud = jsonDecode(resultados[1].body);

      if (dataAfc['success'] != true) {
        setState(() => _error = 'AFC: ${dataAfc['mensaje'] ?? 'error'}');
        return;
      }
      if (dataAfpSalud['success'] != true) {
        setState(
          () => _error = 'AFP y Salud: ${dataAfpSalud['mensaje'] ?? 'error'}',
        );
        return;
      }

      // El Total Tributable depende de que AFC y AFP/Salud ya esten
      // calculados, por eso se pide justo despues, no en paralelo.
      final responseTributable = await http.get(
        Uri.parse(
          '$_apiUrl/admin/total-tributable?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
        ),
        headers: headers,
      );
      final dataTributable = jsonDecode(responseTributable.body);
      if (dataTributable['success'] != true) {
        setState(
          () => _error =
              'Total Tributable: ${dataTributable['mensaje'] ?? 'error'}',
        );
        return;
      }

      setState(() {
        _resultadoAfc = dataAfc;
        _resultadoAfpSalud = dataAfpSalud;
        _resultadoTributable = dataTributable;
      });
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Widget _fila(
    String label,
    dynamic monto, {
    bool esDescuento = false,
    bool destacado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: destacado ? 13 : 12,
                fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          Text(
            '${esDescuento ? "-" : ""}\$${formatearMiles(monto)} CLP',
            style: TextStyle(
              fontSize: destacado ? 14 : 12,
              fontWeight: FontWeight.bold,
              color: destacado
                  ? const Color(0xFF1D4ED8)
                  : (esDescuento
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),

        if (_resultadoAfc != null) ...[
          const Text(
            'Seguro de Cesantía (AFC)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // El desglose por tipo de contrato (tipo, porcentaje
                // trabajador/empleador) se oculta por ahora -- ese
                // nivel de detalle corresponde al Incremento 3. El
                // monto se enmascara con "X CLP" -- el valor real
                // sigue calculandose por dentro (ver
                // _resultadoAfc!['descuento_trabajador']), solo no
                // se muestra en pantalla mientras dure este ocultamiento.
                Text(
                  'Descuento AFC: X CLP',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_resultadoAfpSalud != null) ...[
          const Text(
            'AFP y Salud',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFFEC4899),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE7F3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_resultadoAfpSalud!['tipo_afp']} (${_resultadoAfpSalud!['tasa_afp']}%): \$${formatearMiles(_resultadoAfpSalud!['descuento_afp'])} CLP',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_resultadoAfpSalud!['institucion_salud']} (${_resultadoAfpSalud!['tasa_salud']}%): \$${formatearMiles(_resultadoAfpSalud!['descuento_salud'])} CLP',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Total Tributable (se calculó junto con AFC y AFP/Salud) ──
        if (_resultadoTributable != null) ...[
          const Text(
            'Total Tributable',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Total imponible (sin tope) menos AFP, Salud y AFC — es la base sobre la que se calcula el Impuesto Único.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fila(
                  'Total Imponible (sin tope)',
                  _resultadoTributable!['total_imponible'],
                ),
                _fila(
                  'Descuento AFP',
                  _resultadoTributable!['descuento_afp'],
                  esDescuento: true,
                ),
                _fila(
                  'Descuento Salud',
                  _resultadoTributable!['descuento_salud'],
                  esDescuento: true,
                ),
                _fila(
                  'Descuento Seguro Cesantía (AFC)',
                  _resultadoTributable!['descuento_afc_trabajador'],
                  esDescuento: true,
                ),
                const Divider(height: 18),
                _fila(
                  'TOTAL TRIBUTABLE',
                  _resultadoTributable!['total_tributable'],
                  destacado: true,
                ),
              ],
            ),
          ),
        ],

        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando
                      ? 'Calculando...'
                      : 'Calcular AFC, AFP/Salud y Total Tributable',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultadoAfc != null &&
                _resultadoAfpSalud != null &&
                _resultadoTributable != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class SeccionImpuestoUnico extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionImpuestoUnico({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionImpuestoUnico> createState() => _SeccionImpuestoUnicoState();
}

class _SeccionImpuestoUnicoState extends State<SeccionImpuestoUnico> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultado = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/calculo-impuesto-unico?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
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
        setState(() => _error = data['mensaje'] ?? 'Error');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),
        if (_resultado != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tramo ${_resultado!['tramo_numero']} · Base tributable: \$${formatearMiles(_resultado!['base_tributable'])} CLP (${_resultado!['base_tributable_utm']} UTM)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF450A0A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Factor: ${_resultado!['factor']} · Crédito deducido: ${_resultado!['rebaja_utm']} UTM',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF450A0A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Valor UTM del período: \$${formatearMiles(_resultado!['valor_utm'])} CLP',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (_resultado!['impuesto_unico'] == 0)
                      ? 'Exento'
                      : 'Impuesto: \$${formatearMiles(_resultado!['impuesto_unico'])} CLP',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando ? 'Calculando...' : 'Calcular Impuesto Único',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultado != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: GRATIFICACION LEGAL (solo consulta; pide utilidad solo si modalidad es Anual)
// ══════════════════════════════════════════════════════════════
class SeccionGratificacion extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionGratificacion({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionGratificacion> createState() => _SeccionGratificacionState();
}

class _SeccionGratificacionState extends State<SeccionGratificacion> {
  bool _cargandoConfig = true;
  String _modalidad = 'Proporcional';
  final _utilidadCtrl = TextEditingController();
  final _immCtrl = TextEditingController();
  bool _guardandoImm = false;
  String _mensajeImm = '';
  bool _exitoImm = false;
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  @override
  void initState() {
    super.initState();
    _cargarModalidad();
  }

  @override
  void dispose() {
    _utilidadCtrl.dispose();
    _immCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarModalidad() async {
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
        setState(() => _modalidad = data['modalidad']);
      }
    } catch (_) {
    } finally {
      setState(() => _cargandoConfig = false);
    }
  }

  Future<void> _guardarImm() async {
    final valor = int.tryParse(_immCtrl.text.trim());
    if (valor == null || valor <= 0) {
      setState(() {
        _exitoImm = false;
        _mensajeImm = 'Ingresa un valor IMM válido';
      });
      return;
    }
    setState(() {
      _guardandoImm = true;
      _mensajeImm = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/valor-imm'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'valor_clp': valor, 'periodo': widget.periodo}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoImm = data['success'] == true;
        _mensajeImm = _exitoImm
            ? 'Valor IMM guardado para ${widget.periodo}'
            : (data['mensaje'] ?? 'Error');
      });
    } catch (_) {
      setState(() {
        _exitoImm = false;
        _mensajeImm = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardandoImm = false);
    }
  }

  Future<void> _calcular() async {
    if (_modalidad == 'Anual' &&
        (double.tryParse(_utilidadCtrl.text.trim()) ?? 0) <= 0) {
      setState(() {
        _error =
            'Ingresa la utilidad líquida anual (modalidad Anual configurada)';
      });
      return;
    }
    setState(() {
      _cargando = true;
      _error = '';
      _resultado = null;
    });
    var url =
        '$_apiUrl/admin/calculo-gratificacion?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}';
    if (_modalidad == 'Anual')
      url += '&utilidad_liquida_anual=${_utilidadCtrl.text.trim()}';
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
        setState(() => _error = data['mensaje'] ?? 'Error');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoConfig)
      return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modalidad configurada: $_modalidad',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        if (_modalidad == 'Proporcional') ...[
          const SizedBox(height: 12),
          const Text(
            'Valor IMM del período (necesario para el tope):',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _immCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MilesInputFormatter()],
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
              TextButton(
                onPressed: _guardandoImm ? null : _guardarImm,
                child: Text(_guardandoImm ? 'Guardando...' : 'Guardar IMM'),
              ),
            ],
          ),
          if (_mensajeImm.isNotEmpty)
            _MensajeResultado(mensaje: _mensajeImm, exito: _exitoImm),
        ],
        if (_modalidad == 'Anual') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _utilidadCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Utilidad líquida anual (CLP)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),
        if (_resultado != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Gratificación: \$${formatearMiles(_resultado!['modalidad'] == 'Proporcional' ? _resultado!['gratificacion_final'] : _resultado!['gratificacion_mensual_equivalente'])} CLP',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando ? 'Calculando...' : 'Calcular Gratificación',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultado != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: COSTO TOTAL EMPLEADOR (solo consulta)
// ══════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════
// SECCION FUSIONADA: COTIZACIONES PREVISIONALES + COSTO TOTAL
// EMPLEADOR. Un solo boton calcula ambas al mismo tiempo. Primero
// se muestra el detalle (Cotizaciones Previsionales), y abajo,
// separado con un divisor, el resumen (Costo Total Empleador).
// Ninguna de las 2 modifica el Liquido a Pagar del trabajador.
// ══════════════════════════════════════════════════════════════
class SeccionCotizacionesPrevisionales extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionCotizacionesPrevisionales({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionCotizacionesPrevisionales> createState() =>
      _SeccionCotizacionesPrevisionalesState();
}

class _SeccionCotizacionesPrevisionalesState
    extends State<SeccionCotizacionesPrevisionales> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultadoCotizaciones;
  Map<String, dynamic>? _resultadoCostoEmpleador;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultadoCotizaciones = null;
      _resultadoCostoEmpleador = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Se calculan las 2 en paralelo, no una despues de la otra.
      final resultados = await Future.wait([
        http.get(
          Uri.parse(
            '$_apiUrl/admin/cotizaciones-previsionales?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
          ),
          headers: headers,
        ),
        http.get(
          Uri.parse(
            '$_apiUrl/admin/costo-total-empleador?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
          ),
          headers: headers,
        ),
      ]);

      final dataCotizaciones = jsonDecode(resultados[0].body);
      final dataCostoEmpleador = jsonDecode(resultados[1].body);

      if (dataCotizaciones['success'] != true) {
        setState(
          () => _error =
              'Cotizaciones Previsionales: ${dataCotizaciones['mensaje'] ?? 'error'}',
        );
        return;
      }
      if (dataCostoEmpleador['success'] != true) {
        setState(
          () => _error =
              'Costo Total Empleador: ${dataCostoEmpleador['mensaje'] ?? 'error'}',
        );
        return;
      }
      setState(() {
        _resultadoCotizaciones = dataCotizaciones;
        _resultadoCostoEmpleador = dataCostoEmpleador;
      });
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  Widget _filaItem(String titulo, Map<String, dynamic> item) {
    final esAporteEmpresa = item['origen'] == 'Aporte de la Empresa';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esAporteEmpresa
            ? const Color(0xFFDCEAFB)
            : const Color(0xFFE3F3D9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  titulo + (item['tasa'] != null ? ' (${item['tasa']}%)' : ''),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                '\$${formatearMiles(item['monto'])} CLP',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item['origen'],
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: esAporteEmpresa
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFF15803D),
            ),
          ),
          Text(
            item['donde_pagar'],
            style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _resultadoCotizaciones?['items'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cuadro de referencia: todo lo que la Empresa debe pagar a terceros por este trabajador este período (lo descontado + los aportes propios de la Empresa). No modifica el Líquido a Pagar del trabajador.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),

        if (_resultadoCotizaciones != null && items != null) ...[
          const Text(
            'COTIZACIONES PREVISIONALES',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF001E42),
            ),
          ),
          const SizedBox(height: 8),
          _filaItem('AFP', items['afp']),
          _filaItem('Salud', items['salud']),
          _filaItem(
            'Seguro Cesantía - Aporte Trabajador',
            items['seguro_cesantia_trabajador'],
          ),
          _filaItem('Impuesto a la Renta', items['impuesto_renta']),
          _filaItem(
            'Seguro Cesantía Empresa - Aporte Empresa',
            items['seguro_cesantia_empresa'],
          ),
          _filaItem(
            'SIS (Seguro Invalidez y Sobrevivencia) - Aporte Empresa',
            items['sis'],
          ),
          _filaItem(
            'Expectativa de Vida - Aporte Empresa',
            items['expectativa_vida'],
          ),
          _filaItem(
            'Aporte Previsional Capitalización Individual - Aporte Empresa',
            items['aporte_capitalizacion'],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL A PAGAR',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF001E42),
                      ),
                    ),
                    Text(
                      '\$${formatearMiles(_resultadoCotizaciones!['total'])} CLP',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
                if (_resultadoCotizaciones!['total_palabras'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '(${_resultadoCotizaciones!['total_palabras']})',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        if (_resultadoCostoEmpleador != null) ...[
          const SizedBox(height: 24),
          const Divider(thickness: 1.2),
          const SizedBox(height: 10),
          const Text(
            'COSTO TOTAL EMPLEADOR',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3E2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Haberes de la liquidación: \$${formatearMiles(_resultadoCostoEmpleador!['total_haberes'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Seguro Cesantía Empresa - Aporte Empresa: \$${formatearMiles(_resultadoCostoEmpleador!['aporte_afc_empleador'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'SIS (Seguro Invalidez y Sobrevivencia) - Aporte Empresa (${_resultadoCostoEmpleador!['tasa_sis_afp']}%): \$${formatearMiles(_resultadoCostoEmpleador!['aporte_afp_empleador'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Expectativa de Vida - Aporte Empresa (${_resultadoCostoEmpleador!['tasa_expectativa_vida']}%): \$${formatearMiles(_resultadoCostoEmpleador!['aporte_expectativa_vida'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Aporte Previsional Capitalización Individual - Aporte Empresa (${_resultadoCostoEmpleador!['tasa_aporte_capitalizacion']}%): \$${formatearMiles(_resultadoCostoEmpleador!['aporte_capitalizacion'])} CLP',
                  style: const TextStyle(fontSize: 12),
                ),
                const Divider(height: 14),
                Text(
                  'COSTO TOTAL EMPLEADOR: \$${formatearMiles(_resultadoCostoEmpleador!['costo_total_empleador'])} CLP',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001E42),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando
                      ? 'Calculando...'
                      : 'Calcular Cotizaciones y Costo Empleador',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultadoCotizaciones != null &&
                _resultadoCostoEmpleador != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class SeccionDesgloseFinal extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionDesgloseFinal({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionDesgloseFinal> createState() => _SeccionDesgloseFinalState();
}

class _SeccionDesgloseFinalState extends State<SeccionDesgloseFinal> {
  bool _cargando = false;
  String _error = '';
  Map<String, dynamic>? _resultado;

  Future<void> _calcular() async {
    setState(() {
      _cargando = true;
      _error = '';
      _resultado = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/admin/desglose-liquidacion?persona_id=${widget.personaId}&periodo=${Uri.encodeComponent(widget.periodo)}',
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
        setState(() => _error = data['mensaje'] ?? 'Error');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error.isNotEmpty) _MensajeResultado(mensaje: _error, exito: false),
        if (_resultado != null)
          TarjetaDesgloseLiquidacion(resultado: _resultado!),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: _cargando ? null : _calcular,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _cargando ? 'Calculando...' : 'Ver Desglose Completo',
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_resultado != null)
              Expanded(
                flex: 4,
                child: ElevatedButton(
                  onPressed: widget.onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('Continuar'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// SECCION: CERRAR LIQUIDACION (paso final)
// ══════════════════════════════════════════════════════════════
class SeccionCerrarLiquidacion extends StatefulWidget {
  final int personaId;
  final String periodo;
  final VoidCallback onDone;
  const SeccionCerrarLiquidacion({
    super.key,
    required this.personaId,
    required this.periodo,
    required this.onDone,
  });

  @override
  State<SeccionCerrarLiquidacion> createState() =>
      _SeccionCerrarLiquidacionState();
}

class _SeccionCerrarLiquidacionState extends State<SeccionCerrarLiquidacion> {
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;
  Map<String, dynamic>? _resultado;

  Future<void> _cerrar() async {
    setState(() {
      _enviando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/liquidacion/cerrar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': widget.personaId,
          'periodo': widget.periodo,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? '¡Liquidación cerrada correctamente!'
            : (data['mensaje'] ?? 'Error');
        if (_exito) _resultado = data;
      });
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Esta acción consolida y bloquea la liquidación de este período. Ya no se podrán agregar más descuentos, bonos u otros conceptos.',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 12),
        _MensajeResultado(mensaje: _mensaje, exito: _exito),
        if (_resultado != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'LÍQUIDO A PAGAR: \$${formatearMiles(_resultado!['liquido_a_pagar'])} CLP',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF059669),
              ),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_enviando || _exito) ? null : _cerrar,
            icon: const Icon(Icons.lock_outline, size: 18),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              foregroundColor: Colors.white,
            ),
            label: Text(
              _enviando
                  ? 'Cerrando...'
                  : (_exito ? 'Liquidación Cerrada' : 'Cerrar Liquidación'),
            ),
          ),
        ),
      ],
    );
  }
}
