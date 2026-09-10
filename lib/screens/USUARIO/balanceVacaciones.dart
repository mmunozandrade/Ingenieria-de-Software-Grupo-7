import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class BalanceVacaciones extends StatefulWidget {
  const BalanceVacaciones({super.key});

  @override
  State<BalanceVacaciones> createState() => _BalanceVacacionesState();
}

class _BalanceVacacionesState extends State<BalanceVacaciones> {
  Map<String, dynamic>? _balance;
  List<dynamic> _compensaciones = [];
  bool _cargando = true;
  String _error = '';

  // Controlador para el modal
  final _diasController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarBalance();
  }

  @override
  void dispose() {
    _diasController.dispose();
    super.dispose();
  }

  Future<void> _cargarBalance() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

      // Cargar balance y compensaciones en paralelo
      final responses = await Future.wait([
        http.get(Uri.parse('$_apiUrl/mi-balance-vacaciones'), headers: headers),
        http.get(
          Uri.parse('$_apiUrl/mis-compensaciones-progresivas'),
          headers: headers,
        ),
      ]);

      final dataBalance = jsonDecode(responses[0].body);
      final dataComp = jsonDecode(responses[1].body);

      if (dataBalance['success'] == true) {
        setState(() {
          _balance = dataBalance;
          _compensaciones = dataComp['success'] == true
              ? (dataComp['compensaciones'] as List? ?? [])
              : [];
        });
      } else {
        setState(() => _error = dataBalance['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  // ── Modal solicitar compensacion ──────────────────────────
  void _abrirModalCompensacion() {
    _diasController.clear();
    final diasProgresivos = _balance!['dias_progresivos'] ?? 0;
    final sueldoBase = (_balance!['sueldo_base'] ?? 0).toDouble();

    if (diasProgresivos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No tienes dias progresivos disponibles para compensar',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    double montoCalculado = 0;
    int diasIngresados = 0;
    String errorDias = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void calcular(String val) {
            setModalState(() {
              errorDias = '';
              final n = int.tryParse(val);
              if (n == null || n <= 0) {
                errorDias = 'Ingresa un numero entero positivo';
                montoCalculado = 0;
                diasIngresados = 0;
              } else if (n > diasProgresivos) {
                errorDias =
                    'No puede exceder los $diasProgresivos dias progresivos disponibles';
                montoCalculado = 0;
                diasIngresados = 0;
              } else {
                diasIngresados = n;
                montoCalculado = (sueldoBase / 30) * n;
              }
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.payments_outlined, color: Color(0xFF001E42)),
                SizedBox(width: 10),
                Text(
                  'Solicitar Compensacion',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info dias disponibles
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFF1D4ED8),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dias progresivos disponibles: $diasProgresivos\nSueldo base: \$${sueldoBase.toStringAsFixed(0)} CLP',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Campo dias
                  const Text(
                    'Dias a compensar:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _diasController,
                    keyboardType: TextInputType.number,
                    onChanged: calcular,
                    decoration: InputDecoration(
                      hintText: 'Ej: 3',
                      errorText: errorDias.isNotEmpty ? errorDias : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF001E42)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Monto calculado
                  if (diasIngresados > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Calculo:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '(\$${sueldoBase.toStringAsFixed(0)} ÷ 30) × $diasIngresados dias',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF065F46),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Monto a recibir: \$${montoCalculado.toStringAsFixed(0)} CLP',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'La solicitud queda pendiente de aprobacion del Administrador.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001E42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: diasIngresados > 0 && errorDias.isEmpty
                    ? () =>
                          _enviarSolicitud(ctx, diasIngresados, montoCalculado)
                    : null,
                child: const Text(
                  'Solicitar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _enviarSolicitud(
    BuildContext ctx,
    int dias,
    double monto,
  ) async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/solicitar-compensacion-progresiva'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'dias_a_compensar': dias,
          'monto_calculado': monto.round(),
        }),
      );
      final data = jsonDecode(response.body);
      Navigator.pop(ctx);
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solicitud enviada correctamente. Pendiente de aprobacion.',
            ),
            backgroundColor: Color(0xFF059669),
          ),
        );
        _cargarBalance();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['mensaje'] ?? 'Error al enviar la solicitud'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (_) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo conectar al servidor'),
          backgroundColor: Colors.red,
        ),
      );
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
          'Balance de Vacaciones',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarBalance,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)),
            )
          : _error.isNotEmpty
          ? Center(
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            )
          : _balance == null
          ? const Center(child: Text('Sin datos disponibles'))
          : LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;
                final bool esEscritorio = ancho >= 1280;
                final bool esTablet = ancho >= 768 && ancho < 1280;
                final double paddingHorizontal = esEscritorio
                    ? 40
                    : (esTablet ? 28 : 24);
                final double maxWidthContenido = esEscritorio
                    ? 900
                    : (esTablet ? 720 : double.infinity);

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
                          // Titulo
                          const Text(
                            'Mi Balance de Vacaciones',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Art. 67 Codigo del Trabajo · Factor 1.25 por mes trabajado',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── BANNER INCREMENTO ANUAL (+15 dias) ────────
                          if (_balance!['incremento_anual_aplicado'] == true &&
                              _balance!['dias_acumulados_antes_incremento'] !=
                                  null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF059669),
                                    Color(0xFF10B981),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.celebration_outlined,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Se agregaron tus 15 dias de vacaciones de este año',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Saldo anterior: ${_balance!['dias_acumulados_antes_incremento']} + 15 (nuevo periodo) = ${_balance!['dias_acumulados']} dias'
                                          '${_balance!['fecha_ultimo_incremento'] != null ? ' · desde el ${_balance!['fecha_ultimo_incremento']}' : ''}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Alerta saldo excedido
                          if (_balance!['saldo_excedido'] == true)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red[200]!),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_outlined,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Saldo excedido: los dias utilizados superan los dias acumulados. Contacte a Recursos Humanos.',
                                      style: TextStyle(
                                        color: Colors.red[800],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Tarjetas resumen vacaciones
                          Row(
                            children: [
                              Expanded(
                                child: _TarjetaBalance(
                                  titulo: 'Dias Acumulados',
                                  valor: '${_balance!['dias_acumulados']}',
                                  subtitulo:
                                      '${_balance!['acumulado_4dec']} exacto',
                                  color: const Color(0xFF1D4ED8),
                                  bgColor: const Color(0xFFEFF6FF),
                                  borderColor: const Color(0xFFBFDBFE),
                                  icono: Icons.calendar_month_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _TarjetaBalance(
                                  titulo: 'Dias Utilizados',
                                  valor: '${_balance!['dias_utilizados']}',
                                  subtitulo: 'Vacaciones tomadas',
                                  color: const Color(0xFFD97706),
                                  bgColor: const Color(0xFFFFFBEB),
                                  borderColor: const Color(0xFFFDE68A),
                                  icono: Icons.beach_access_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _TarjetaBalance(
                                  titulo: 'Dias Disponibles',
                                  valor: '${_balance!['dias_disponibles']}',
                                  subtitulo: _balance!['saldo_excedido'] == true
                                      ? 'Saldo excedido'
                                      : 'Para usar',
                                  color: _balance!['saldo_excedido'] == true
                                      ? Colors.red
                                      : const Color(0xFF059669),
                                  bgColor: _balance!['saldo_excedido'] == true
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFECFDF5),
                                  borderColor:
                                      _balance!['saldo_excedido'] == true
                                      ? const Color(0xFFFECACA)
                                      : const Color(0xFFA7F3D0),
                                  icono: _balance!['saldo_excedido'] == true
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── SECCION DIAS PROGRESIVOS ──────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.trending_up_outlined,
                                      color: Color(0xFF7C3AED),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Vacaciones Progresivas',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF001E42),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _TarjetaBalance(
                                        titulo: 'Dias Progresivos',
                                        valor:
                                            '${_balance!['dias_progresivos'] ?? 0}',
                                        subtitulo:
                                            '${_balance!['anos_clinica'] ?? 0} años en clínica · Art. 68 · ${_balance!['dias_vendidos'] ?? 0} vendido(s)',
                                        color: const Color(0xFF7C3AED),
                                        bgColor: const Color(0xFFF5F3FF),
                                        borderColor: const Color(0xFFDDD6FE),
                                        icono: Icons.auto_awesome_outlined,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (_balance!['cumple_progresivos'] ==
                                                    true)
                                                ? 'Cumples los 120 meses de cotizaciones previas. Con ${_balance!['anos_clinica'] ?? 0} años en la clínica obtienes ${_balance!['dias_progresivos'] ?? 0} día(s) progresivo(s) (1 día cada 3 años).'
                                                : 'Aun no cumples los 120 meses de cotizaciones previas requeridos. Te faltan ${_balance!['meses_faltantes'] ?? 0} meses.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color:
                                                  (_balance!['cumple_progresivos'] ==
                                                      true)
                                                  ? const Color(0xFF059669)
                                                  : const Color(0xFF64748B),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          if ((_balance!['dias_progresivos'] ??
                                                  0) >
                                              0)
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton.icon(
                                                icon: const Icon(
                                                  Icons.payments_outlined,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Solicitar compensacion en efectivo',
                                                ),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFF7C3AED,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 12,
                                                      ),
                                                ),
                                                onPressed:
                                                    _abrirModalCompensacion,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── DETALLE DEL CALCULO ───────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.calculate_outlined,
                                      color: Color(0xFF001E42),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Detalle del Calculo',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF001E42),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                _FilaDetalle(
                                  label: 'Fecha de ingreso:',
                                  valor: _balance!['fecha_ingreso'] ?? '—',
                                ),
                                const SizedBox(height: 10),
                                _FilaDetalle(
                                  label: 'Meses en la clinica:',
                                  valor: '${_balance!['meses_clinica']} meses',
                                ),
                                const SizedBox(height: 10),
                                _FilaDetalle(
                                  label: 'Meses cotizaciones previas:',
                                  valor: '${_balance!['meses_previos']} meses',
                                ),
                                const SizedBox(height: 10),
                                _FilaDetalle(
                                  label:
                                      'Total meses considerados (referencial, incluye cotiz. previas):',
                                  valor: '${_balance!['total_meses']} meses',
                                ),
                                const Divider(height: 20),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.lock_outline,
                                        size: 18,
                                        color: Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Factor de cálculo (Art. 67 Código del Trabajo)',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF475569),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${_balance!['factor_acumulacion']} días por mes trabajado',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF001E42),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Solo lectura — este valor no puede ser modificado por ningún rol, incluido el Administrador.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF94A3B8),
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _FilaDetalle(
                                  label:
                                      'Calculo interno (solo meses en la clinica, 4 decimales):',
                                  valor:
                                      '${_balance!['meses_clinica']} × 1.25 = ${_balance!['acumulado_4dec']}',
                                ),
                                const SizedBox(height: 10),
                                _FilaDetalle(
                                  label: 'Dias acumulados (redondeado):',
                                  valor: '${_balance!['dias_acumulados']} dias',
                                  destacado: true,
                                ),
                                const Divider(height: 20),
                                _FilaDetalle(
                                  label: 'Dias utilizados:',
                                  valor: '${_balance!['dias_utilizados']} dias',
                                ),
                                const SizedBox(height: 10),
                                _FilaDetalle(
                                  label: 'Dias disponibles:',
                                  valor:
                                      '${_balance!['dias_disponibles']} dias',
                                  destacado: true,
                                  colorValor:
                                      _balance!['saldo_excedido'] == true
                                      ? Colors.red
                                      : const Color(0xFF059669),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── HISTORIAL COMPENSACIONES ──────────────────
                          if (_compensaciones.isNotEmpty) ...[
                            const Text(
                              'Mis Compensaciones Progresivas',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._compensaciones.map(
                              (c) => _TarjetaCompensacion(comp: c),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // Nota actualizacion
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.update_outlined,
                                  size: 16,
                                  color: Color(0xFF64748B),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Ultima actualizacion: ${_balance!['ultima_actualizacion']}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
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

// ── Tarjeta compensacion ──────────────────────────────────────
class _TarjetaCompensacion extends StatelessWidget {
  final Map<String, dynamic> comp;
  const _TarjetaCompensacion({required this.comp});

  @override
  Widget build(BuildContext context) {
    final estado = comp['estado'] ?? 'Pendiente';
    final Color colorEstado;
    final Color bgEstado;
    final IconData iconoEstado;

    switch (estado) {
      case 'Aprobada':
        colorEstado = const Color(0xFF059669);
        bgEstado = const Color(0xFFECFDF5);
        iconoEstado = Icons.check_circle_outline;
        break;
      case 'Rechazada':
        colorEstado = Colors.red;
        bgEstado = const Color(0xFFFEF2F2);
        iconoEstado = Icons.cancel_outlined;
        break;
      default:
        colorEstado = const Color(0xFFD97706);
        bgEstado = const Color(0xFFFFFBEB);
        iconoEstado = Icons.hourglass_empty_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bgEstado,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(iconoEstado, color: colorEstado, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${comp['dias_compensados']} dias · \$${comp['monto_clp']} CLP',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Solicitado: ${comp['fecha_solicitud']}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (comp['observacion'] != null &&
                    comp['observacion'].toString().isNotEmpty)
                  Text(
                    comp['observacion'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bgEstado,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              estado,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colorEstado,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tarjeta resumen ───────────────────────────────────────────
class _TarjetaBalance extends StatelessWidget {
  final String titulo;
  final String valor;
  final String subtitulo;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final IconData icono;

  const _TarjetaBalance({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            valor,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitulo,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

// ── Fila detalle ──────────────────────────────────────────────
class _FilaDetalle extends StatelessWidget {
  final String label;
  final String valor;
  final bool destacado;
  final Color? colorValor;

  const _FilaDetalle({
    required this.label,
    required this.valor,
    this.destacado = false,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
          valor,
          style: TextStyle(
            fontSize: 13,
            fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
            color: colorValor ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
