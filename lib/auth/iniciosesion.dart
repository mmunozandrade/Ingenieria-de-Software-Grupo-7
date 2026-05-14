import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'session_service.dart';
import 'registro.dart';
// Pantallas ADMIN
import '../screens/ADMIN/aprobarSolicitudesV.dart';
import '../screens/ADMIN/asignacionRoles.dart';
import '../screens/ADMIN/calculoHextra.dart';
import '../screens/ADMIN/cargaArchivos.dart';
import '../screens/ADMIN/registroBonos.dart';

// Pantallas USUARIO
import '../screens/USUARIO/descargaLiquidacion.dart';
import '../screens/USUARIO/solicitudVacaciones.dart';
import '../screens/USUARIO/vacacionesProgresivas.dart';

// URL de la API
const String apiUrl = 'http://127.0.0.1:8000';

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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        automaticallyImplyLeading: false,
        title: const Text(
          'Panel Administrador',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            // Tarjeta bienvenida
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
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Rol: Administrador',
                    style: TextStyle(color: Color(0xFF00897B), fontSize: 13),
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
                MaterialPageRoute(builder: (_) => const AprobarSolicitudesV()),
              ),
            ),
            _buildCard(
              context,
              icon: Icons.manage_accounts_outlined,
              color: Colors.blue,
              title: 'Asignación de Roles',
              descripcion: 'Gestionar roles de los trabajadores',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AsignacionRoles()),
              ),
            ),
            _buildCard(
              context,
              icon: Icons.calculate_outlined,
              color: Colors.teal,
              title: 'Cálculo Horas Extra',
              descripcion: 'Registrar y calcular horas extras al 50%',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CalculoHextra()),
              ),
            ),
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
            _buildCard(
              context,
              icon: Icons.attach_money,
              color: Colors.orange,
              title: 'Registro de Bonos',
              descripcion: 'Registrar bonos imponibles del personal',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RegistrarBonos()),
              ),
            ),
          ],
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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF009A8D),
        automaticallyImplyLeading: false,
        title: const Text(
          'Mi Portal',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            // Tarjeta bienvenida
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
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
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
                MaterialPageRoute(builder: (_) => const SolicitudVacaciones()),
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
                MaterialPageRoute(builder: (_) => const DescargaLiquidacion()),
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
          ],
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

    // Validaciones locales
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
        final idUsuario = data['id_usuario'] ?? 0;

        // Guardar sesión localmente
        await SessionService.guardarSesion(
          token: token,
          rol: rol,
          nombreCompleto: nombreCompleto,
          cargo: cargo,
          idUsuario: idUsuario,
        );

        if (!mounted) return;

        // Navegar según rol
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
              // Logo
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

              // Campo Correo
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

              // Campo Contraseña
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

              // Mensaje de error
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

              // Botón Ingresar
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
              // Enlace para ir al Registro
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('¿No tienes una cuenta? '),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegistroPage(),
                        ),
                      );
                    },
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
