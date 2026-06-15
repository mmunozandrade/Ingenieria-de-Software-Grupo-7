import 'package:aconcagua/auth/auth.guard.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';
import 'registro.dart';
import '../screens/fichaUsuario.dart';

// Pantallas ADMIN
import '../screens/ADMIN/aprobarSolicitudesV.dart';
import '../screens/ADMIN/asignacionRoles.dart';
import '../screens/ADMIN/calculoHextra.dart';
import '../screens/ADMIN/cargaArchivos.dart';
import '../screens/ADMIN/registroBonos.dart';
import '../screens/ADMIN/registroEmpleado.dart';
import '../screens/ADMIN/busquedaEmpleados.dart';
import '../screens/ADMIN/cuentasPendientes.dart';
// Pantalla JEFE
import '../screens/JEFE/panelResumenJefe.dart';
import '../screens/JEFE/vacacionesAreaJefe.dart';
// Pantallas USUARIO
import '../screens/USUARIO/descargaLiquidacion.dart';
import '../screens/USUARIO/solicitudVacaciones.dart';
import '../screens/USUARIO/vacacionesProgresivas.dart';
import '../screens/USUARIO/historialVacaciones.dart';
import '../screens/USUARIO/balanceVacaciones.dart';

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
                  'Su sesión se cerrará en 2 minutos por inactividad',
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
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Cerrar sesión',
                onPressed: () => _cerrarSesion(context),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                _buildCard(
                  context,
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                  title: 'Aprobar Solicitudes',
                  descripcion: 'Revisar y aprobar solicitudes de vacaciones',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AprobarSolicitudesV(),
                    ),
                  ),
                ),
                //_buildCard(
                //context,
                //icon: Icons.calculate_outlined,
                //color: Colors.teal,
                //title: 'Cálculo Horas Extra',
                //descripcion: 'Registrar y calcular horas extras al 50%',
                //onTap: () => Navigator.push(
                //context,
                // MaterialPageRoute(builder: (_) => const CalculoHextra()),
                //),
                //),
                _buildCard(
                  context,
                  icon: Icons.upload_file_outlined,
                  color: Colors.indigo,
                  title: 'Carga de Archivos',
                  descripcion: 'Importar liquidaciones masivamente',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CargaMasivaArchivosPage(),
                    ),
                  ),
                ),
                //_buildCard(
                // context,
                //icon: Icons.attach_money,
                //color: Colors.orange,
                //title: 'Registro de Bonos',
                //descripcion: 'Registrar bonos imponibles del personal',
                //onTap: () => Navigator.push(
                //context,
                //MaterialPageRoute(builder: (_) => const RegistrarBonos()),
                //),
                //),
                _buildCard(
                  context,
                  icon: Icons.person_outline,
                  color: Colors.teal,
                  title: 'Mi Ficha Personal',
                  descripcion: 'Ver y actualizar mis datos personales',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FichaUsuario()),
                  ),
                ),
                _buildCard(
                  context,
                  icon: Icons.manage_search_outlined,
                  color: Colors.deepPurple,
                  title: 'Buscar Empleados',
                  descripcion: 'Buscar trabajadores por apellido o RUT',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BusquedaEmpleados(),
                    ),
                  ),
                ),
                _buildCard(
                  context,
                  icon: Icons.person_search_outlined,
                  color: Colors.orange,
                  title: 'Cuentas Pendientes',
                  descripcion: 'Completar datos de trabajadores registrados',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CuentasPendientes(),
                    ),
                  ),
                ),
              ],
            ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          descripcion,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Mis Módulos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

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
                  descripcion: 'Descargar mis liquidaciones de sueldo',
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
                  descripcion: 'Ver mis días de vacaciones según antigüedad',
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
                  descripcion: 'Ver todas mis solicitudes de vacaciones',
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
              ],
            ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          descripcion,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                _buildCard(
                  context,
                  icon: Icons.dashboard_outlined,
                  color: const Color(0xFF1D4ED8),
                  title: 'Panel Resumen del Area',
                  descripcion: 'Ver equipo, solicitudes y contratos por vencer',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PanelResumenJefe()),
                  ),
                ),
                _buildCard(
                  context,
                  icon: Icons.calendar_month_outlined,
                  color: const Color(0xFF0D9488),
                  title: 'Vacaciones del Area',
                  descripcion: 'Ver saldos e historial de solicitudes',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const VacacionesAreaJefe(),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Text(
                  'Mis Modulos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

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
                  descripcion: 'Descargar mis liquidaciones de sueldo',
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
                  descripcion: 'Ver mis dias de vacaciones segun antiguedad',
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
                  descripcion: 'Ver todas mis solicitudes de vacaciones',
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
              ],
            ),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(
          descripcion,
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
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
        setState(() => _error = data['mensaje'] ?? 'Credenciales incorrectas.');
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
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/Logo.png', height: 100),
              const SizedBox(height: 20),
              const Text(
                'Iniciar Sesión',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const Text(
                'Sistema de Personal Institucional',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Correo Institucional',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _correoController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'usuario@accaconcagua.cl',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(
                    Icons.email_outlined,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Contraseña',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contrasenaController,
                obscureText: _obscureText,
                decoration: InputDecoration(
                  hintText: 'Ingrese su contraseña',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: Colors.grey,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureText = !_obscureText),
                  ),
                ),
              ),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
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
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _cargando ? null : _iniciarSesion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _cargando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Ingresar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('¿No tienes una cuenta? '),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegistroPage()),
                    ),
                    child: const Text(
                      'Regístrate aquí',
                      style: TextStyle(
                        color: Color(0xFF00897B),
                        fontWeight: FontWeight.bold,
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
  }
}
