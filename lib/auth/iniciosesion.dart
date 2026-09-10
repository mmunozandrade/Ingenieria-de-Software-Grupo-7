import 'package:aconcagua/auth/auth.guard.dart';
import 'package:aconcagua/screens/USUARIO/MisCompensaciones.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';
import 'registro.dart';
import '../screens/fichaUsuario.dart';

// Pantallas ADMIN
import '../screens/ADMIN/asignacionRoles.dart';
import '../screens/ADMIN/calculoHextra.dart';
import '../screens/ADMIN/registroBonos.dart';
import '../screens/ADMIN/registroEmpleado.dart';
import '../screens/ADMIN/parametrosSistema.dart';
import '../screens/ADMIN/liquidaciones.dart';
import '../screens/ADMIN/gestionPersonal.dart';
import '../screens/ADMIN/conceptosYBonos.dart';
import '../screens/ADMIN/calculoLiquidacionTotal.dart';
import '../screens/USUARIO/miDesgloseLiquidacion.dart';
// Pantalla JEFE
import '../screens/JEFE/panelResumenJefe.dart';
import '../screens/JEFE/vacacionesAreaJefe.dart';
// Pantallas USUARIO
import '../screens/USUARIO/descargaLiquidacion.dart';
import '../screens/USUARIO/solicitudVacaciones.dart';
import '../screens/USUARIO/vacacionesProgresivas.dart';
import '../screens/USUARIO/historialVacaciones.dart';
import '../screens/USUARIO/balanceVacaciones.dart';
import '../screens/USUARIO/MisCompensaciones.dart';

const String apiUrl = 'http://127.0.0.1:8000';

// ============================================================
// SESSION GUARD — Cierre automático por inactividad/////////////////////////////////////
// ============================================================
class SessionGuard extends StatefulWidget {
  final Widget child;
  const SessionGuard({super.key, required this.child});

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  // 13 minutos de inactividad → advertencia
  // 2 minutos más → cierre automático
  static const int _minutosInactividad = 15;
  static const int _minutosAdvertencia = 3;

  Timer? _timerInactividad;
  Timer? _timerAdvertencia;
  Timer? _timerContador;
  bool _mostrandoAdvertencia = false;
  int _segundosRestantes = 120;

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timerInactividad?.cancel();
    _timerAdvertencia?.cancel();
    _timerContador?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timerInactividad?.cancel();
    _timerAdvertencia?.cancel();
    _timerContador?.cancel();

    // Si ya mostraba advertencia, cerrarla
    if (_mostrandoAdvertencia && mounted) {
      _mostrandoAdvertencia = false;
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.settings.name != 'session_warning';
      });
    }

    // Timer principal: 13 minutos → mostrar advertencia
    _timerInactividad = Timer(
      Duration(minutes: _minutosInactividad),
      _mostrarAdvertencia,
    );
  }

  void _mostrarAdvertencia() {
    if (!mounted || _mostrandoAdvertencia) return;
    _mostrandoAdvertencia = true;
    _segundosRestantes = _minutosAdvertencia * 60;

    // Contador regresivo
    _timerContador = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _segundosRestantes--);
      if (_segundosRestantes <= 0) {
        t.cancel();
        _cerrarSesionAutomatico();
      }
    });

    // Mostrar dialog de advertencia
    showDialog(
      context: context,
      barrierDismissible: false,
      routeSettings: const RouteSettings(name: 'session_warning'),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // Actualizar el dialogo cada segundo
          _timerContador?.cancel();
          _timerContador = Timer.periodic(const Duration(seconds: 1), (t) {
            if (!mounted) {
              t.cancel();
              return;
            }
            if (_segundosRestantes <= 0) {
              t.cancel();
              Navigator.of(ctx).pop();
              _cerrarSesionAutomatico();
              return;
            }
            setDialogState(() => _segundosRestantes--);
          });

          final int minutos = _segundosRestantes ~/ 60;
          final int segundos = _segundosRestantes % 60;
          final String tiempo =
              '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}';

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.access_time_outlined,
                  color: Color(0xFFD97706),
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Sesión por expirar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF001E42),
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Su sesión se cerrará en los próximos 2 minutos',
                  style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _segundosRestantes <= 30
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _segundosRestantes <= 30
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Text(
                    tiempo,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: _segundosRestantes <= 30
                          ? Colors.red
                          : const Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _timerContador?.cancel();
                  Navigator.of(ctx).pop();
                  _cerrarSesionManual(ctx);
                },
                child: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  _timerContador?.cancel();
                  Navigator.of(ctx).pop();
                  setState(() {
                    _mostrandoAdvertencia = false;
                  });
                  _resetTimer();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF001E42),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Extender Sesión',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _cerrarSesionAutomatico() async {
    if (!mounted) return;
    await SessionService.cerrarSesion();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
      (route) => false,
    );
  }

  Future<void> _cerrarSesionManual(BuildContext ctx) async {
    await SessionService.cerrarSesion();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detectar cualquier interaccion del usuario y resetear timer
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      onPointerMove: (_) => _resetTimer(),
      onPointerSignal: (_) => _resetTimer(),
      child: widget.child,
    );
  }
}

// ============================================================
// NOTIFICACIONES ART. 70 — Campana con badge para el Admin
// ============================================================
class NotificacionesArticulo70 extends StatefulWidget {
  const NotificacionesArticulo70({super.key});

  @override
  State<NotificacionesArticulo70> createState() =>
      _NotificacionesArticulo70State();
}

class _NotificacionesArticulo70State extends State<NotificacionesArticulo70> {
  int _count = 0;
  List<dynamic> _alertas = [];
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargarAlertas();
  }

  Future<void> _cargarAlertas() async {
    setState(() => _cargando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$apiUrl/admin/alertas-articulo-70'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _alertas = data['alertas'] ?? [];
          _count = data['count'] ?? 0;
        });
      }
    } catch (_) {
      // Silencioso: si falla, simplemente no se muestra el badge
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _abrirPanel() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: _PanelAlertasArt70(
            alertas: _alertas,
            cargando: _cargando,
            onRefresh: _cargarAlertas,
          ),
        ),
      ),
    ).then((_) => _cargarAlertas());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          tooltip: 'Alertas Art. 70 (feriado acumulado)',
          onPressed: _abrirPanel,
        ),
        if (_count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _count > 9 ? '9+' : '$_count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _PanelAlertasArt70 extends StatelessWidget {
  final List<dynamic> alertas;
  final bool cargando;
  final VoidCallback onRefresh;

  const _PanelAlertasArt70({
    required this.alertas,
    required this.cargando,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Alertas',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF001E42),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Trabajadores con 2 o mas periodos anuales de vacaciones sin usar.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: cargando
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : alertas.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No hay alertas activas.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: alertas.length,
                    itemBuilder: (ctx, i) {
                      final a = alertas[i];
                      final bool bloqueado = a['bloqueado'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: bloqueado
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: bloqueado
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    a['nombre'] ?? '—',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bloqueado
                                        ? Colors.red
                                        : const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    bloqueado ? 'BLOQUEADO' : 'ALERTA',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Cargo: ${a['cargo'] ?? '—'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              'Periodos acumulados sin usar: ${a['periodos_acumulados']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              'Dias normales disponibles: ${a['dias_disponibles']}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD ADMIN
// ============================================================
class AdminDashboard extends StatelessWidget {
  final String nombreCompleto;
  final String cargo;

  const AdminDashboard({
    super.key,
    required this.nombreCompleto,
    required this.cargo,
  });

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      child: AuthGuard(
        rolRequerido: 'admin',
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          appBar: AppBar(
            backgroundColor: const Color(0xFF001E42),
            automaticallyImplyLeading: false,
            title: const Text(
              'Panel Administrador',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              const NotificacionesArticulo70(),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Cerrar sesión',
                onPressed: () => _cerrarSesion(context),
              ),
            ],
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
                  ? 560
                  : (esTablet ? 480 : double.infinity);

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
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF001E42),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bienvenido/a, $nombreCompleto',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cargo,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Rol: Administrador',
                                style: TextStyle(
                                  color: Color(0xFF00897B),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Módulos de Administración',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        GridView.count(
                          crossAxisCount: esEscritorio ? 2 : (esTablet ? 2 : 1),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 32,
                          mainAxisSpacing: 32,
                          childAspectRatio: esEscritorio || esTablet
                              ? 2.2
                              : 2.6,
                          children: [
                            _buildCard(
                              context,
                              icon: Icons.payments_outlined,
                              color: const Color(0xFF7C3AED),
                              title: 'Liquidaciones',
                              descripcion:
                                  'Calcula liquidaciones (planilla u honorarios) y descarga los informes de remuneraciones, todo en un solo lugar',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LiquidacionesScreen(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.settings_outlined,
                              color: const Color(0xFFD97706),
                              title: 'Parámetros del Sistema',
                              descripcion:
                                  'UTM, UF y topes, tasas de AFP y Salud, aportes del empleador, y tabla del Impuesto Único — revisa todo antes de empezar a liquidar',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const ParametrosSistemaScreen(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.groups_outlined,
                              color: const Color(0xFF0D9488),
                              title: 'Gestión de Personal',
                              descripcion:
                                  'Ficha personal, búsqueda de empleados, cuentas pendientes, solicitudes de vacaciones y compensaciones progresivas',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const GestionPersonalScreen(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.star_outline,
                              color: const Color(0xFF7C3AED),
                              title: 'Conceptos y Bonos Especiales',
                              descripcion:
                                  'Parametrización de conceptos, bonos condicionales y bono excepcional',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ConceptosYBonosScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String descripcion,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  descripcion,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Ingresar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 15, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cerrarSesion(BuildContext context) {
    SessionService.cerrarSesion();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
      (route) => false,
    );
  }
}

// ============================================================
// DASHBOARD USUARIO
// ============================================================
class UsuarioDashboard extends StatelessWidget {
  final String nombreCompleto;
  final String cargo;

  const UsuarioDashboard({
    super.key,
    required this.nombreCompleto,
    required this.cargo,
  });

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      child: AuthGuard(
        rolRequerido: 'usuario',
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          appBar: AppBar(
            backgroundColor: const Color(0xFF009A8D),
            automaticallyImplyLeading: false,
            title: const Text(
              'Mi Portal',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FichaUsuario()),
                ),
                icon: const Icon(
                  Icons.person_outline,
                  color: Colors.white,
                  size: 20,
                ),
                label: const Text(
                  'Mi Ficha',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Cerrar sesión',
                onPressed: () => _cerrarSesion(context),
              ),
            ],
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
                  : (esTablet ? 720 : double.infinity);
              final int columnas = esEscritorio ? 3 : (esTablet ? 2 : 1);

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
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF009A8D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hola, $nombreCompleto',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cargo,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Rol: Trabajador',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Mis Módulos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        GridView.count(
                          crossAxisCount: columnas,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                          childAspectRatio: esEscritorio || esTablet
                              ? 1.5
                              : 2.6,
                          children: [
                            _buildCard(
                              context,
                              icon: Icons.calendar_today_outlined,
                              color: Colors.blue,
                              title: 'Solicitud de Vacaciones',
                              descripcion: 'Solicitar y revisar mis vacaciones',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SolicitudVacaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.download_outlined,
                              color: Colors.red,
                              title: 'Mis Liquidaciones',
                              descripcion:
                                  'Descargar mis liquidaciones de sueldo',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DescargaLiquidacion(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.trending_up,
                              color: Colors.purple,
                              title: 'Vacaciones Progresivas',
                              descripcion:
                                  'Ver mis días de vacaciones según antigüedad',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VacacionesProgresivas(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.history_outlined,
                              color: Colors.indigo,
                              title: 'Historial de Vacaciones',
                              descripcion:
                                  'Ver todas mis solicitudes de vacaciones',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HistorialVacaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.account_balance_wallet_outlined,
                              color: Colors.teal,
                              title: 'Balance de Vacaciones',
                              descripcion:
                                  'Ver mis dias acumulados, utilizados y disponibles',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BalanceVacaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.receipt_long_outlined,
                              color: Colors.purple,
                              title: 'Mis Compensaciones',
                              descripcion:
                                  'Ver historial y comprobantes de compensaciones progresivas',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MisCompensaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.receipt_long,
                              color: Colors.green,
                              title: 'Mi Desglose de Sueldo',
                              descripcion:
                                  'Ver el detalle de haberes y descuentos de mi liquidación mensual',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const MiDesgloseLiquidacionScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String descripcion,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  descripcion,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Ingresar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 15, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cerrarSesion(BuildContext context) {
    SessionService.cerrarSesion();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
      (route) => false,
    );
  }
}

// ============================================================
// DASHBOARD JEFE
// ============================================================
class JefeDashboard extends StatelessWidget {
  final String nombreCompleto;
  final String cargo;

  const JefeDashboard({
    super.key,
    required this.nombreCompleto,
    required this.cargo,
  });

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      child: AuthGuard(
        rolRequerido: 'jefe',
        child: Scaffold(
          backgroundColor: const Color(0xFFF4F7FB),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1D4ED8),
            automaticallyImplyLeading: false,
            title: const Text(
              'Portal Jefe',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FichaUsuario()),
                ),
                icon: const Icon(
                  Icons.person_outline,
                  color: Colors.white,
                  size: 20,
                ),
                label: const Text(
                  'Mi Ficha',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Cerrar sesión',
                onPressed: () => _cerrarSesion(context),
              ),
            ],
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
                  : (esTablet ? 720 : double.infinity);
              final int columnasSupervision = esEscritorio || esTablet ? 2 : 1;
              final int columnasModulos = esEscritorio ? 3 : (esTablet ? 2 : 1);

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
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D4ED8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bienvenido/a, $nombreCompleto',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cargo,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Rol: Jefe de Area',
                                style: TextStyle(
                                  color: Color(0xFF93C5FD),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Modulos de Supervision',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        GridView.count(
                          crossAxisCount: columnasSupervision,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                          childAspectRatio: esEscritorio || esTablet
                              ? 1.6
                              : 2.6,
                          children: [
                            _buildCard(
                              context,
                              icon: Icons.dashboard_outlined,
                              color: const Color(0xFF1D4ED8),
                              title: 'Panel Resumen del Area',
                              descripcion:
                                  'Ver equipo, solicitudes y contratos por vencer',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PanelResumenJefe(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.calendar_month_outlined,
                              color: const Color(0xFF0D9488),
                              title: 'Vacaciones del Area',
                              descripcion:
                                  'Ver saldos e historial de solicitudes',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VacacionesAreaJefe(),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                        const Text(
                          'Mis Modulos',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        GridView.count(
                          crossAxisCount: columnasModulos,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                          childAspectRatio: esEscritorio || esTablet
                              ? 1.5
                              : 2.6,
                          children: [
                            _buildCard(
                              context,
                              icon: Icons.calendar_today_outlined,
                              color: Colors.blue,
                              title: 'Solicitud de Vacaciones',
                              descripcion: 'Solicitar y revisar mis vacaciones',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SolicitudVacaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.download_outlined,
                              color: Colors.red,
                              title: 'Mis Liquidaciones',
                              descripcion:
                                  'Descargar mis liquidaciones de sueldo',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DescargaLiquidacion(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.trending_up,
                              color: Colors.purple,
                              title: 'Vacaciones Progresivas',
                              descripcion:
                                  'Ver mis dias de vacaciones segun antiguedad',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VacacionesProgresivas(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.history_outlined,
                              color: Colors.indigo,
                              title: 'Historial de Vacaciones',
                              descripcion:
                                  'Ver todas mis solicitudes de vacaciones',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HistorialVacaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.account_balance_wallet_outlined,
                              color: Colors.teal,
                              title: 'Balance de Vacaciones',
                              descripcion:
                                  'Ver mis dias acumulados, utilizados y disponibles',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BalanceVacaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.receipt_long_outlined,
                              color: Colors.purple,
                              title: 'Mis Compensaciones',
                              descripcion:
                                  'Ver historial y comprobantes de compensaciones progresivas',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MisCompensaciones(),
                                ),
                              ),
                            ),
                            _buildCard(
                              context,
                              icon: Icons.receipt_long,
                              color: Colors.green,
                              title: 'Mi Desglose de Sueldo',
                              descripcion:
                                  'Ver el detalle de haberes y descuentos de mi liquidación mensual',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const MiDesgloseLiquidacionScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String descripcion,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  descripcion,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Ingresar',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 15, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cerrarSesion(BuildContext context) {
    SessionService.cerrarSesion();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
      (route) => false,
    );
  }
}

// ============================================================
// PANTALLA LOGIN
// ============================================================
class IniciarSesionPage extends StatefulWidget {
  const IniciarSesionPage({super.key});

  @override
  State<IniciarSesionPage> createState() => _IniciarSesionPageState();
}

class _IniciarSesionPageState extends State<IniciarSesionPage> {
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();

  bool _obscureText = true;
  bool _cargando = false;
  String _error = '';

  // Reenvio de correo de verificacion (cuenta creada pero sin activar)
  bool _cuentaNoVerificada = false;
  bool _reenviando = false;
  String _mensajeReenvio = '';
  bool _exitoReenvio = false;

  Future<void> _reenviarVerificacion() async {
    final correo = _correoController.text.trim();
    setState(() {
      _reenviando = true;
      _mensajeReenvio = '';
    });
    try {
      final response = await http.post(
        Uri.parse('$apiUrl/reenviar-verificacion'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'correo': correo}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoReenvio = data['success'] == true;
        _mensajeReenvio = data['mensaje'] ?? 'No se pudo reenviar el correo.';
      });
    } catch (e) {
      setState(() {
        _exitoReenvio = false;
        _mensajeReenvio = 'No se pudo conectar al servidor.';
      });
    } finally {
      setState(() => _reenviando = false);
    }
  }

  Future<void> _iniciarSesion() async {
    final correo = _correoController.text.trim();
    final contrasena = _contrasenaController.text.trim();

    if (correo.isEmpty || contrasena.isEmpty) {
      setState(() => _error = 'Por favor completa todos los campos.');
      return;
    }
    if (!correo.contains('@')) {
      setState(() => _error = 'Ingresa un correo válido.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = '';
      _cuentaNoVerificada = false;
      _mensajeReenvio = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'correo': correo, 'contrasena': contrasena}),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        final rol = data['rol'];
        final nombreCompleto = data['nombre_completo'] ?? '';
        final cargo = data['cargo'] ?? '';
        final token = data['access_token'] ?? '';
        final personaId = data['persona_id'] ?? 0;

        await SessionService.guardarSesion(
          token: token,
          rol: rol,
          nombreCompleto: nombreCompleto,
          cargo: cargo,
          personaId: personaId,
        );

        if (!mounted) return;

        if (rol == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AdminDashboard(nombreCompleto: nombreCompleto, cargo: cargo),
            ),
          );
        } else if (rol == 'usuario') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => UsuarioDashboard(
                nombreCompleto: nombreCompleto,
                cargo: cargo,
              ),
            ),
          );
        } else if (rol == 'jefe') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  JefeDashboard(nombreCompleto: nombreCompleto, cargo: cargo),
            ),
          );
        }
      } else {
        setState(() {
          _error = data['mensaje'] ?? 'Credenciales incorrectas.';
          _cuentaNoVerificada = data['cuenta_no_verificada'] == true;
        });
      }
    } catch (e) {
      setState(
        () => _error = 'No se pudo conectar al servidor. Verifica tu conexión.',
      );
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool esAncho = constraints.maxWidth >= 920;
          final panelFormulario = _PanelFormularioLogin(
            correoController: _correoController,
            contrasenaController: _contrasenaController,
            obscureText: _obscureText,
            cargando: _cargando,
            error: _error,
            cuentaNoVerificada: _cuentaNoVerificada,
            reenviando: _reenviando,
            mensajeReenvio: _mensajeReenvio,
            exitoReenvio: _exitoReenvio,
            onReenviarVerificacion: _reenviarVerificacion,
            onToggleObscure: () => setState(() => _obscureText = !_obscureText),
            onIngresar: _iniciarSesion,
            onIrARegistro: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegistroPage()),
            ),
          );

          if (esAncho) {
            return Row(
              children: [
                Expanded(flex: 5, child: _PanelMarcaLogin()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 40,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: panelFormulario,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                _PanelMarcaLogin(compacto: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                  child: panelFormulario,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Panel izquierdo (o superior en movil): marca institucional
// ══════════════════════════════════════════════════════════════
class _PanelMarcaLogin extends StatelessWidget {
  final bool compacto;
  const _PanelMarcaLogin({this.compacto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: compacto ? 260 : double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF001E42), Color(0xFF0B3B5C)],
        ),
      ),
      child: Stack(
        children: [
          // Elemento decorativo: arcos concentricos sutiles, alusivos
          // a las fichas/registros circulares de un sistema clinico.
          Positioned(
            right: -90,
            top: -90,
            child: _AroDecorativo(diametro: 320, grosor: 1.4, opacidad: 0.10),
          ),
          Positioned(
            right: -40,
            bottom: -120,
            child: _AroDecorativo(diametro: 260, grosor: 1.4, opacidad: 0.08),
          ),
          Positioned(
            left: -60,
            bottom: 40,
            child: _AroDecorativo(diametro: 140, grosor: 1.2, opacidad: 0.08),
          ),

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compacto ? 28 : 64,
              vertical: compacto ? 28 : 56,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (!compacto)
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 2,
                        color: const Color(0xFF0F9F8F),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TE DA LA BIENVENIDA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.8,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Sistema de Gestión de Personal',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                SizedBox(height: compacto ? 16 : 28),
                if (!compacto) const Spacer(flex: 3),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aconcagua Centro Clínico',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 34 : 54,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (!compacto)
                      SizedBox(
                        width: 360,
                        child: Text(
                          'Moderno centro de salud que brinda a la provincia de Los Andes acceso a más de 18 especialidades médicas, con un equipo de más de 45 especialistas altamente calificados.',
                          textAlign: TextAlign.justify,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),

                if (!compacto) const Spacer(flex: 4),
                if (!compacto)
                  Row(
                    children: const [
                      _MarcaPunto(texto: 'Seguridad'),
                      SizedBox(width: 22),
                      _MarcaPunto(texto: 'Confianza'),
                      SizedBox(width: 22),
                      _MarcaPunto(texto: 'Compromiso'),
                    ],
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AroDecorativo extends StatelessWidget {
  final double diametro;
  final double grosor;
  final double opacidad;
  const _AroDecorativo({
    required this.diametro,
    required this.grosor,
    required this.opacidad,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(opacidad),
          width: grosor,
        ),
      ),
    );
  }
}

class _MarcaPunto extends StatelessWidget {
  final String texto;
  const _MarcaPunto({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Color(0xFF0F9F8F),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          texto,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Panel derecho (o inferior en movil): formulario de acceso
// ══════════════════════════════════════════════════════════════
class _PanelFormularioLogin extends StatelessWidget {
  final TextEditingController correoController;
  final TextEditingController contrasenaController;
  final bool obscureText;
  final bool cargando;
  final String error;
  final bool cuentaNoVerificada;
  final bool reenviando;
  final String mensajeReenvio;
  final bool exitoReenvio;
  final VoidCallback onReenviarVerificacion;
  final VoidCallback onToggleObscure;
  final VoidCallback onIngresar;
  final VoidCallback onIrARegistro;

  const _PanelFormularioLogin({
    required this.correoController,
    required this.contrasenaController,
    required this.obscureText,
    required this.cargando,
    required this.error,
    required this.cuentaNoVerificada,
    required this.reenviando,
    required this.mensajeReenvio,
    required this.exitoReenvio,
    required this.onReenviarVerificacion,
    required this.onToggleObscure,
    required this.onIngresar,
    required this.onIrARegistro,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BIENVENIDO',
          style: TextStyle(
            color: Color(0xFF0F9F8F),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Iniciar sesión',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Ingresa con tu correo institucional para continuar.',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 36),

        const Text(
          'Correo institucional',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: correoController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'usuario@accaconcagua.cl',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF0F9F8F),
                width: 1.6,
              ),
            ),
            prefixIcon: const Icon(
              Icons.mail_outline,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 20),

        const Text(
          'Contraseña',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: contrasenaController,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: 'Ingresa tu contraseña',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: Color(0xFF0F9F8F),
                width: 1.6,
              ),
            ),
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF94A3B8),
                size: 20,
              ),
              onPressed: onToggleObscure,
            ),
          ),
        ),

        if (error.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (cuentaNoVerificada) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: reenviando ? null : onReenviarVerificacion,
                icon: reenviando
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mail_outline, size: 16),
                label: Text(
                  reenviando
                      ? 'Enviando...'
                      : 'Reenviar correo de verificación',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF001E42),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
            ),
          ],
          if (mensajeReenvio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              mensajeReenvio,
              style: TextStyle(
                fontSize: 12,
                color: exitoReenvio
                    ? const Color(0xFF059669)
                    : const Color(0xFFDC2626),
              ),
            ),
          ],
        ],

        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: cargando ? null : onIngresar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: cargando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Ingresar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '¿No tienes una cuenta? ',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
            ),
            InkWell(
              onTap: onIrARegistro,
              child: const Text(
                'Regístrate aquí',
                style: TextStyle(
                  color: Color(0xFF0F9F8F),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
