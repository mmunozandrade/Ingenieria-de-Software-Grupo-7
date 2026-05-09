import 'package:flutter/material.dart';
import 'login.dart';
import 'iniciosesion.dart';
import 'registroBonos.dart';
import 'cargaArchivos.dart';
import 'solicitudVacaciones.dart';
import 'asignacionRoles.dart';
import 'calculoHextra.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema de Gestión de RRHH',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF009A8D)),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 1. Barra de navegación superior
          _buildTopBar(context), // Pasamos el context aquí para poder navegar
          // Contenido desplazable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 40.0,
              ),
              child: Center(
                child: ConstrainedBox(
                  // Limitamos el ancho para que se vea bien en pantallas grandes
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 2. Título y Subtítulo
                      const Text(
                        'Sistema de Gestión de Recursos Humanos',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF141C24),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Plataforma integral para la administración de personal institucional, liquidaciones,\nvacaciones y cálculos laborales',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF6B7280),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 50),

                      // 3. Cuadrícula de Tarjetas
                      Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        alignment: WrapAlignment.center,
                        children: [
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SolicitudVacaciones(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(
                              12,
                            ), // Asegura que el clic respete los bordes curvos
                            child: _FeatureCard(
                              icon: Icons.calendar_today_outlined,
                              iconColor: Colors.blue[700]!,
                              iconBgColor: Colors.blue[50]!,
                              title: 'Solicitud de Vacaciones',
                              description:
                                  'Gestiona y solicita vacaciones con calendario interactivo',
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CalculoHextra(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: _FeatureCard(
                              icon: Icons.calculate_outlined,
                              iconColor: Colors.teal[700]!,
                              iconBgColor: Colors.teal[50]!,
                              title: 'Cálculo de Horas Extras',
                              description:
                                  'Registro y cálculo automático con recargo del 50%',
                            ),
                          ),
                          _FeatureCard(
                            icon: Icons.trending_up,
                            iconColor: Colors.purple[700]!,
                            iconBgColor: Colors.purple[50]!,
                            title: 'Vacaciones Progresivas',
                            description:
                                'Cálculo de vacaciones progresivas según antigüedad',
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const RegistrarBonos(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: _FeatureCard(
                              icon: Icons.attach_money,
                              iconColor: Colors.orange[700]!,
                              iconBgColor: Colors.orange[50]!,
                              title: 'Bonos Imponibles',
                              description:
                                  'Registro y gestión de bonos imponibles',
                            ),
                          ),
                          _FeatureCard(
                            icon: Icons.download_outlined,
                            iconColor: Colors.red[400]!,
                            iconBgColor: Colors.red[50]!,
                            title: 'Descarga de Liquidaciones',
                            description:
                                'Accede y descarga liquidaciones de sueldo',
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CargaMasivaArchivosPage(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: _FeatureCard(
                              icon: Icons.upload_outlined,
                              iconColor: Colors.indigo[400]!,
                              iconBgColor: Colors.indigo[50]!,
                              title: 'Carga Masiva',
                              description:
                                  'Importa liquidaciones de forma masiva',
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AsignacionRoles(),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: _FeatureCard(
                              icon: Icons.admin_panel_settings_outlined,
                              iconColor: Colors.green[400]!,
                              iconBgColor: Colors.green[50]!,
                              title: 'Asignación de Roles',
                              description:
                                  'Asigna roles y permisos a los usuarios',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 50),

                      // 4. Tarjeta inferior (Footer de Registro)
                      _buildBottomCard(
                        context,
                      ), // Pasamos el context aquí también
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget para la barra superior (Recibe el BuildContext)
  Widget _buildTopBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 16,
        children: [
          // Logo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8),
              Image.asset('assets/Logo.png', height: 80),
              const SizedBox(height: 20),
            ],
          ),
          // Botón Iniciar Sesión
          ElevatedButton(
            onPressed: () {
              // Navega hacia la página de Inicio de Sesión
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const IniciarSesionPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF009A8D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Iniciar Sesión',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // Widget para la tarjeta de registro inferior (Recibe el BuildContext)
  Widget _buildBottomCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.person_add_alt_1_outlined,
                color: Color(0xFF009A8D),
              ),
              const SizedBox(width: 10),
              const Text(
                '¿Primera vez en el sistema?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF141C24),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Crea tu cuenta usando tu correo institucional @accaconcagua.cl',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 16,
            children: [
              // Botón Registrar
              ElevatedButton(
                onPressed: () {
                  // Agregamos la navegación aquí también
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegistroPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF009A8D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Registrar Cuenta',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () {
                  // Opcional: Aquí podrías mostrar un diálogo con más info
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Más Información',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Widget reutilizable para las tarjetas de la cuadrícula
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String description;

  const _FeatureCard({
    Key? key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF141C24),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
