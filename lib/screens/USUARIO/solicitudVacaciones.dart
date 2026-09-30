import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/inicial.dart';
import '../../auth/session_service.dart';
import '../ADMIN/cargaArchivos.dart';
import '../ADMIN/registroBonos.dart';
import '../ADMIN/asignacionRoles.dart';
import '../ADMIN/calculoHextra.dart';
import 'descargaLiquidacion.dart';

const String _apiUrlVac = 'http://127.0.0.1:8000';

// ── Feriados nacionales Chile 2025-2026 ───────────────────────
// Fuente: Ley 2.977 y decretos vigentes
const List<String> _feriadosChile = [
  // 2025
  '2025-01-01', '2025-04-18', '2025-04-19', '2025-05-01', '2025-05-21',
  '2025-06-20', '2025-06-29', '2025-07-16', '2025-08-15', '2025-09-18',
  '2025-09-19', '2025-10-12', '2025-10-31', '2025-11-01', '2025-11-16',
  '2025-12-08', '2025-12-25',
  // 2026
  '2026-01-01', '2026-04-03', '2026-04-04', '2026-05-01', '2026-05-21',
  '2026-06-22', '2026-06-29', '2026-07-16', '2026-08-15', '2026-09-18',
  '2026-09-19', '2026-10-12', '2026-10-31', '2026-11-01', '2026-12-08',
  '2026-12-25',
];

class SolicitudVacaciones extends StatefulWidget {
  const SolicitudVacaciones({super.key});

  @override
  State<SolicitudVacaciones> createState() => _SolicitudVacacionesState();
}

class _SolicitudVacacionesState extends State<SolicitudVacaciones> {
  DateTime? fechaInicio;
  DateTime? fechaFin;

  // Saldos reales desde /mi-balance-vacaciones
  int _diasNormalesDisp = 15;
  int _diasProgresivosDisp = 0;
  bool _cargando = true;

  // Tipo de bolsa elegida por el trabajador: 'normal' | 'progresivo'
  String _tipoSeleccionado = 'normal';

  // Estado envio
  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  @override
  void initState() {
    super.initState();
    _cargarDiasDisponibles();
  }

  // ── Cargar ambos saldos desde /mi-balance-vacaciones ──────
  Future<void> _cargarDiasDisponibles() async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlVac/mi-balance-vacaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _diasNormalesDisp = data['dias_disponibles'] ?? 15;
          _diasProgresivosDisp = data['dias_progresivos'] ?? 0;
        });
      }
    } catch (_) {
      // Si no hay conexion usa valores por defecto
    } finally {
      setState(() => _cargando = false);
    }
  }

  // Saldo disponible segun la bolsa elegida actualmente
  int get _diasDisponiblesSeleccion => _tipoSeleccionado == 'progresivo'
      ? _diasProgresivosDisp
      : _diasNormalesDisp;

  // ── Calcular dias habiles (excluye sabados, domingos y feriados) ──
  int _calcularDiasHabiles(DateTime inicio, DateTime fin) {
    int diasHabiles = 0;
    DateTime actual = inicio;
    final Set<String> feriados = _feriadosChile.toSet();

    while (!actual.isAfter(fin)) {
      final int diaSemana = actual.weekday;
      final String fechaStr =
          '${actual.year}-${actual.month.toString().padLeft(2, '0')}-${actual.day.toString().padLeft(2, '0')}';

      if (diaSemana != DateTime.saturday &&
          diaSemana != DateTime.sunday &&
          !feriados.contains(fechaStr)) {
        diasHabiles++;
      }
      actual = actual.add(const Duration(days: 1));
    }
    return diasHabiles;
  }

  int get diasHabiles {
    if (fechaInicio == null || fechaFin == null) return 0;
    return _calcularDiasHabiles(fechaInicio!, fechaFin!);
  }

  int get diasNoHabiles {
    if (fechaInicio == null || fechaFin == null) return 0;
    final totalDias = fechaFin!.difference(fechaInicio!).inDays + 1;
    return totalDias - diasHabiles;
  }

  // ── Seleccionar rango de fechas ───────────────────────────
  Future<void> _seleccionarRangoFechas() async {
    final DateTimeRange? rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      currentDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF001E42),
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (rango != null) {
      final inicio = rango.start;
      final diaInicio = inicio.weekday;
      final fechaInicioStr =
          '${inicio.year}-${inicio.month.toString().padLeft(2, '0')}-${inicio.day.toString().padLeft(2, '0')}';
      final bool inicioInvalido =
          diaInicio == DateTime.saturday ||
          diaInicio == DateTime.sunday ||
          _feriadosChile.contains(fechaInicioStr);

      if (inicioInvalido) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La fecha de inicio no puede ser un sábado, domingo o festivo',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      setState(() {
        fechaInicio = rango.start;
        fechaFin = rango.end;
        _mensaje = '';
        _exito = false;
      });
    }
  }

  // ── Enviar solicitud a la BD ──────────────────────────────
  Future<void> _enviarSolicitud() async {
    if (fechaInicio == null || fechaFin == null) return;
    if (diasHabiles == 0) {
      setState(() {
        _exito = false;
        _mensaje = 'El período seleccionado no contiene días hábiles.';
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
        Uri.parse('$_apiUrlVac/solicitar-vacaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'fecha_inicio': fechaInicio!.toIso8601String().split('T')[0],
          'fecha_fin': fechaFin!.toIso8601String().split('T')[0],
          'dias_habiles': diasHabiles,
          'tipo_dias': _tipoSeleccionado,
        }),
      );

      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Solicitud enviada correctamente. Queda pendiente de aprobación.'
            : data['mensaje'] ?? 'Error al enviar la solicitud';
      });

      if (_exito) {
        setState(() {
          fechaInicio = null;
          fechaFin = null;
        });
        _cargarDiasDisponibles();
      }
    } catch (e) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _enviando = false);
    }
  }

  String _formatFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Clinica Aconcagua',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF001E42)),
              child: Text(
                'Menu Principal',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Inicio'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Solicitud de Vacaciones'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const SolicitudVacaciones()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Mis Liquidaciones'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DescargaLiquidacion()),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Registro de Bonos'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RegistrarBonos()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Calculo de Horas Extra'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const CalculoHextra()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Asignacion de Roles'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const AsignacionRoles()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carga de Archivos'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const CargaMasivaArchivosPage(),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {},
            ),
          ],
        ),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)),
            )
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
                    vertical: 30,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidthContenido),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            'Solicitud de Vacaciones',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Seleccione el periodo de sus vacaciones legales',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF475569),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 30),

                          // ── Barra de saldos: Normales + Progresivos ──────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F9FF),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFBAE6FD),
                                width: 1.4,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _bloqueSaldo(
                                    titulo: 'Normales',
                                    valor: _diasNormalesDisp,
                                    color: const Color(0xFF0284C7),
                                    icono: Icons.beach_access_outlined,
                                  ),
                                ),
                                Container(
                                  height: 48,
                                  width: 1,
                                  color: const Color(0xFFBAE6FD),
                                ),
                                Expanded(
                                  child: _bloqueSaldo(
                                    titulo: 'Progresivos',
                                    valor: _diasProgresivosDisp,
                                    color: const Color(0xFF7C3AED),
                                    icono: Icons.trending_up,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Selector de bolsa ─────────────────────────────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '¿De dónde quieres restar los días?',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _opcionTipo(
                                        label: 'Normales',
                                        valorTipo: 'normal',
                                        disponible: _diasNormalesDisp,
                                        color: const Color(0xFF0284C7),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _opcionTipo(
                                        label: 'Progresivas',
                                        valorTipo: 'progresivo',
                                        disponible: _diasProgresivosDisp,
                                        color: const Color(0xFF7C3AED),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Seleccion de fechas
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Periodo Solicitado',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                InkWell(
                                  onTap: _seleccionarRangoFechas,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
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
                                          Icons.calendar_month,
                                          color: Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            fechaInicio == null
                                                ? 'Seleccionar fechas...'
                                                : '${_formatFecha(fechaInicio!)} - ${_formatFecha(fechaFin!)}',
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: fechaInicio == null
                                                  ? const Color(0xFF94A3B8)
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                if (fechaInicio != null) ...[
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Días hábiles a tomar:',
                                        style: TextStyle(
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      Text(
                                        '$diasHabiles',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color:
                                              diasHabiles >
                                                  _diasDisponiblesSeleccion
                                              ? Colors.red
                                              : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Sábados, domingos y feriados excluidos:',
                                        style: TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '$diasNoHabiles días',
                                        style: const TextStyle(
                                          color: Color(0xFF94A3B8),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Saldo restante (${_tipoSeleccionado == 'progresivo' ? 'progresivas' : 'normales'}):',
                                        style: const TextStyle(
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                      Text(
                                        '${_diasDisponiblesSeleccion - diasHabiles}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color:
                                              (_diasDisponiblesSeleccion -
                                                      diasHabiles) <
                                                  0
                                              ? Colors.red
                                              : const Color(0xFF0F9F8F),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (diasHabiles == 0 && fechaInicio != null)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8),
                                      child: Text(
                                        'El período seleccionado no tiene días hábiles (son todos feriados o fin de semana).',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (diasHabiles > _diasDisponiblesSeleccion)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Los días solicitados superan su saldo ${_tipoSeleccionado == 'progresivo' ? 'progresivo' : 'normal'} disponible.',
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFFDE68A),
                              ),
                            ),
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Color(0xFFD97706),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'El cálculo excluye automáticamente sábados, domingos y feriados nacionales de Chile vigentes.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

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
                                        color: _exito
                                            ? Colors.green
                                            : Colors.red,
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
                            child: ElevatedButton(
                              onPressed:
                                  (fechaInicio == null ||
                                      diasHabiles == 0 ||
                                      diasHabiles > _diasDisponiblesSeleccion ||
                                      _enviando)
                                  ? null
                                  : _enviarSolicitud,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F9F8F),
                                disabledBackgroundColor: const Color(
                                  0xFFE2E8F0,
                                ),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: _enviando
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Text(
                                      'Enviar Solicitud',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _bloqueSaldo({
    required String titulo,
    required int valor,
    required Color color,
    required IconData icono,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF334155),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$valor',
          style: TextStyle(
            fontSize: 28,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _opcionTipo({
    required String label,
    required String valorTipo,
    required int disponible,
    required Color color,
  }) {
    final bool seleccionado = _tipoSeleccionado == valorTipo;
    return InkWell(
      onTap: () => setState(() => _tipoSeleccionado = valorTipo),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: seleccionado ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionado ? color : const Color(0xFFCBD5E1),
            width: seleccionado ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  seleccionado
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: seleccionado ? color : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: seleccionado ? color : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$disponible día${disponible == 1 ? '' : 's'} disponible${disponible == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
