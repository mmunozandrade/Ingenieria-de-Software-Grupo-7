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

// ── Feriados nacionales Chile 2025-2026 ───────────///////////////////////////////////////////////////
// Fuente: Ley 2.977 y decretos vigentes
const List<String> _feriadosChile = [
  // 2025
  '2025-01-01', // Año Nuevo
  '2025-04-18', // Viernes Santo
  '2025-04-19', // Sabado Santo
  '2025-05-01', // Dia del Trabajo
  '2025-05-21', // Glorias Navales
  '2025-06-20', // Dia de los Pueblos Indigenas
  '2025-06-29', // San Pedro y San Pablo
  '2025-07-16', // Virgen del Carmen
  '2025-08-15', // Asuncion de la Virgen
  '2025-09-18', // Independencia Nacional
  '2025-09-19', // Glorias del Ejercito
  '2025-10-12', // Encuentro de Dos Mundos
  '2025-10-31', // Dia de las Iglesias Evangelicas
  '2025-11-01', // Dia de Todos los Santos
  '2025-11-16', // Elecciones (feriado irrenunciable)
  '2025-12-08', // Inmaculada Concepcion
  '2025-12-25', // Navidad
  // 2026
  '2026-01-01', // Año Nuevo
  '2026-04-03', // Viernes Santo
  '2026-04-04', // Sabado Santo
  '2026-05-01', // Dia del Trabajo
  '2026-05-21', // Glorias Navales
  '2026-06-22', // Dia de los Pueblos Indigenas
  '2026-06-29', // San Pedro y San Pablo
  '2026-07-16', // Virgen del Carmen
  '2026-08-15', // Asuncion de la Virgen
  '2026-09-18', // Independencia Nacional
  '2026-09-19', // Glorias del Ejercito
  '2026-10-12', // Encuentro de Dos Mundos
  '2026-10-31', // Dia de las Iglesias Evangelicas
  '2026-11-01', // Dia de Todos los Santos
  '2026-12-08', // Inmaculada Concepcion
  '2026-12-25', // Navidad
];

class SolicitudVacaciones extends StatefulWidget {
  const SolicitudVacaciones({super.key});

  @override
  State<SolicitudVacaciones> createState() => _SolicitudVacacionesState();
}

class _SolicitudVacacionesState extends State<SolicitudVacaciones> {

  DateTime? fechaInicio;
  DateTime? fechaFin;

  // Dias disponibles reales desde BD
  int _diasDisponibles = 15;
  bool _cargando       = true;

  // Estado envio
  bool   _enviando = false;
  String _mensaje  = '';
  bool   _exito    = false;

  @override
  void initState() {
    super.initState();
    _cargarDiasDisponibles();
  }

  // ── Cargar dias disponibles desde BD ─────────────────────
  Future<void> _cargarDiasDisponibles() async {
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlVac/mis-vacaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _diasDisponibles = data['dias_disponibles'] ?? 15);
      }
    } catch (_) {
      // Si no hay conexion usa 15 por defecto
    } finally {
      setState(() => _cargando = false);
    }
  }

  // ── Calcular dias habiles (excluye sabados, domingos y feriados) ──
  int _calcularDiasHabiles(DateTime inicio, DateTime fin) {
    int diasHabiles = 0;
    DateTime actual = inicio;

    final Set<String> feriados = _feriadosChile.toSet();

    while (!actual.isAfter(fin)) {
      final int diaSemana = actual.weekday; // 1=Lun ... 6=Sab, 7=Dom
      final String fechaStr =
          '${actual.year}-${actual.month.toString().padLeft(2, '0')}-${actual.day.toString().padLeft(2, '0')}';

      // Excluir sabados (6), domingos (7) y feriados
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
              'La fecha de inicio no puede ser un sabado, domingo o festivo',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      setState(() {
        fechaInicio = rango.start;
        fechaFin    = rango.end;
        _mensaje    = '';
        _exito      = false;
      });
    }
  }

  // ── Enviar solicitud a la BD ──────────────────────────────
  Future<void> _enviarSolicitud() async {
    if (fechaInicio == null || fechaFin == null) return;
    if (diasHabiles == 0) {
      setState(() {
        _exito   = false;
        _mensaje = 'El periodo seleccionado no contiene dias habiles.';
      });
      return;
    }

    setState(() { _enviando = true; _mensaje = ''; });

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrlVac/solicitar-vacaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'fecha_inicio':  fechaInicio!.toIso8601String().split('T')[0],
          'fecha_fin':     fechaFin!.toIso8601String().split('T')[0],
          'dias_habiles':  diasHabiles,
        }),
      );

      final data = jsonDecode(response.body);
      setState(() {
        _exito   = data['success'] == true;
        _mensaje = _exito
            ? 'Solicitud enviada correctamente. Queda pendiente de aprobacion.'
            : data['mensaje'] ?? 'Error al enviar la solicitud';
      });

      if (_exito) {
        setState(() { fechaInicio = null; fechaFin = null; });
        _cargarDiasDisponibles();
      }
    } catch (e) {
      setState(() {
        _exito   = false;
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
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF001E42)),
              child: Text('Menu Principal',
                  style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Inicio'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const DashboardScreen())),
            ),

            ListTile(

              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Solicitud de Vacaciones'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const SolicitudVacaciones())),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Mis Liquidaciones'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const DescargaLiquidacion())),
            ),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Registro de Bonos'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const RegistrarBonos())),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Calculo de Horas Extra'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const CalculoHextra())),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Asignacion de Roles'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const AsignacionRoles())),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carga de Archivos'),
              onTap: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const CargaMasivaArchivosPage())),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Cerrar Sesion',
                  style: TextStyle(color: Colors.red)),
              onTap: () {},
            ),
          ],
        ),
      ),

      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)))
          : SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [

                  // Titulo
                  const Text(
                    'Solicitud de Vacaciones',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Seleccione el periodo de sus vacaciones legales',
                    style:
                        TextStyle(fontSize: 14, color: Color(0xFF475569)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  // Dias disponibles
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFBAE6FD), width: 1.4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Dias Disponibles',
                            style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w600)),
                        Text(
                          '$_diasDisponibles',
                          style: const TextStyle(
                              fontSize: 32,
                              color: Color(0xFF0284C7),
                              fontWeight: FontWeight.bold),
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
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Periodo Solicitado',
                            style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),

                        // Boton calendario
                        InkWell(
                          onTap: _seleccionarRangoFechas,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFCBD5E1)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_month,
                                  color: Color(0xFF64748B)),
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
                            ]),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Resumen
                        if (fechaInicio != null) ...[

                          // Dias habiles
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Dias habiles a tomar:',
                                  style:
                                      TextStyle(color: Color(0xFF475569))),
                              Text(
                                '$diasHabiles',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: diasHabiles > _diasDisponibles
                                      ? Colors.red
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Dias no habiles
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Sabados, domingos y feriados excluidos:',
                                style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12),
                              ),
                              Text(
                                '$diasNoHabiles dias',
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                          const Divider(height: 24),

                          // Saldo restante
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Saldo restante:',
                                  style:
                                      TextStyle(color: Color(0xFF475569))),
                              Text(
                                '${_diasDisponibles - diasHabiles}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: (_diasDisponibles - diasHabiles) <
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
                                'El periodo seleccionado no tiene dias habiles (son todos feriados o fin de semana).',
                                style: TextStyle(
                                    color: Colors.orange, fontSize: 12),
                              ),
                            ),

                          if (diasHabiles > _diasDisponibles)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Los dias solicitados superan su saldo disponible.',
                                style: TextStyle(
                                    color: Colors.red, fontSize: 12),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Nota feriados
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(children: const [
                      Icon(Icons.info_outline,
                          size: 16, color: Color(0xFFD97706)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El calculo excluye automaticamente sabados, domingos y feriados nacionales de Chile vigentes.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF92400E)),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // Mensaje exito/error
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
                      child: Row(children: [
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
                                color:
                                    _exito ? Colors.green : Colors.red,
                                fontSize: 13),
                          ),
                        ),
                      ]),
                    ),

                  // Boton enviar
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (fechaInicio == null ||
                              diasHabiles == 0 ||
                              diasHabiles > _diasDisponibles ||
                              _enviando)
                          ? null
                          : _enviarSolicitud,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F9F8F),
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Text('Enviar Solicitud',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}