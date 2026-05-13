import 'package:flutter/material.dart';

// Imports hacia tus carpetas de auth y screens
import '../auth/inicial.dart';
import '../auth/iniciosesion.dart';
import '../screens/ADMIN/registroBonos.dart';
import '../screens/ADMIN/cargaArchivos.dart';
import '../screens/ADMIN/asignacionRoles.dart';
import '../screens/ADMIN/calculoHextra.dart';
import '../screens/USUARIO/vacacionesProgresivas.dart';
import '../screens/USUARIO/solicitudVacaciones.dart';
import '../screens/USUARIO/descargaLiquidacion.dart';

class MenuLateral extends StatelessWidget {
  final String rolUsuario;

  const MenuLateral({super.key, required this.rolUsuario});

  @override
  Widget build(BuildContext context) {
    final bool esAdmin =
        (rolUsuario == 'Administrador' || rolUsuario == 'Jefe');

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF001E42)),
            child: Text(
              'Menú Principal',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Inicio'),
            onTap: () =>
                _navegar(context, DashboardScreen(rolUsuario: rolUsuario)),
          ),

          // --- SECCIÓN: FUNCIONARIO (TODOS VEN ESTO) ---
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
            child: Text(
              "Mi Portal",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Solicitud de Vacaciones'),
            onTap: () => _navegar(context, const SolicitudVacaciones()),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Mis Liquidaciones'),
            onTap: () => _navegar(context, const DescargaLiquidacion()),
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: const Text('Vacaciones Progresivas'),
            onTap: () => _navegar(context, const VacacionesProgresivas()),
          ),

          // --- SECCIÓN: ADMINISTRACIÓN (SOLO ADMINS/JEFES) ---
          if (esAdmin) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text(
                "Administración",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carga Masiva'),
              onTap: () => _navegar(context, const CargaMasivaArchivosPage()),
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Asignación de Roles'),
              onTap: () => _navegar(context, const AsignacionRoles()),
            ),
            ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Registro de Bonos'),
              onTap: () => _navegar(context, const RegistrarBonos()),
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Cálculo de Horas Extra'),
              onTap: () => _navegar(context, const CalculoHextra()),
            ),
          ],

          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const IniciarSesionPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Función auxiliar para no repetir código de navegación
  void _navegar(BuildContext context, Widget pantalla) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => pantalla),
    );
  }
}
