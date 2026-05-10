import 'package:flutter/material.dart';
import 'inicial.dart';
import 'cargaArchivos.dart';
import 'registroBonos.dart';
import 'solicitudVacaciones.dart';
import 'calculoHextra.dart';
import 'descargaLiquidacion.dart';

class AsignacionRoles extends StatefulWidget {
  const AsignacionRoles({super.key});

  @override
  State<AsignacionRoles> createState() => _AsignacionRolesState();
}

class _AsignacionRolesState extends State<AsignacionRoles> {
  final TextEditingController _busquedaController = TextEditingController();
  String textoBusqueda = '';

  final List<Trabajador> trabajadores = [
    Trabajador(
      nombreCompleto: 'Juan Pérez González',
      rut: '12345678-9',
      fechaIngreso: '15-03-2022',
      cargo: 'Jefe de Servicios Generales',
      rol: 'Jefe',
    ),
    Trabajador(
      nombreCompleto: 'María Silva Torres',
      rut: '98765432-1',
      fechaIngreso: '10-08-2021',
      cargo: 'Asistente Administrativa',
      rol: 'Usuario',
    ),
    Trabajador(
      nombreCompleto: 'Carlos Rodríguez Muñoz',
      rut: '11223344-5',
      fechaIngreso: '05-01-2023',
      cargo: 'Auxiliar de Aseo',
      rol: 'Sin rol asignado',
    ),
    Trabajador(
      nombreCompleto: 'Ana López Vera',
      rut: '55667788-K',
      fechaIngreso: '22-06-2020',
      cargo: 'Jefa de Administración',
      rol: 'Jefe',
    ),
  ];

  List<Trabajador> get trabajadoresFiltrados {
    if (textoBusqueda.trim().isEmpty) {
      return trabajadores;
    }
    final busqueda = textoBusqueda.toLowerCase().trim();
    return trabajadores.where((trabajador) {
      return trabajador.nombreCompleto.toLowerCase().contains(busqueda) ||
          trabajador.rut.toLowerCase().contains(busqueda);
    }).toList();
  }

  void cambiarRol(Trabajador trabajador) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Asignar Rol'),
          content: Text('Selecciona el rol para ${trabajador.nombreCompleto}'),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  trabajador.rol = 'Jefe';
                });
                Navigator.pop(context);
              },
              child: const Text('Jefe'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  trabajador.rol = 'Usuario';
                });
                Navigator.pop(context);
              },
              child: const Text('Usuario'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  trabajador.rol = 'Sin rol asignado';
                });
                Navigator.pop(context);
              },
              child: const Text('Sin rol'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listaTrabajadores = trabajadoresFiltrados;

    return Scaffold(
      backgroundColor: Colors.white,

      // --- LA BARRA SUPERIOR AZUL ---
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Clínica Aconcagua",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // --- TU MENÚ LATERAL ---
      drawer: Drawer(
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
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DashboardScreen(),
                  ),
                );
              },
            ),
            // --- SECCIÓN: MI PORTAL (USUARIO) ---
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Solicitud de Vacaciones'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SolicitudVacaciones(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Mis Liquidaciones'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DescargaLiquidacion(),
                  ),
                );
              },
            ),
            const Divider(),
            // --- SECCIÓN: ADMINISTRACIÓN ---
            ListTile(
              leading: const Icon(Icons.attach_money_outlined),
              title: const Text('Registro de Bonos'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RegistrarBonos(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Cálculo de Horas Extra'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CalculoHextra(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts_outlined),
              title: const Text('Asignación de Roles'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AsignacionRoles(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Carga de Archivos'),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  // Asumo que tu clase se llama CargaMasivaArchivosPage como lo mostraste antes
                  MaterialPageRoute(
                    builder: (context) => const CargaMasivaArchivosPage(),
                  ),
                );
              },
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

      // --- EL CUERPO DE TU PÁGINA ---
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset("assets/Logo.png", height: 60),
                const SizedBox(height: 15),
                const Text(
                  "Gestión de Roles",
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Asignación de roles y permisos a trabajadores",
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 28),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFBFDBFE),
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Roles disponibles",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            SizedBox(height: 8),
                            _BulletText(
                              texto:
                                  "Jefe: Acceso completo para gestión de equipo y aprobaciones. Solo puede ver la información de su área.",
                            ),
                            _BulletText(
                              texto:
                                  "Usuario: Acceso estándar para funciones básicas del sistema. Solamente ve su propia información.",
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // BUSCADOR
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Buscar Trabajador',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _busquedaController,
                      onChanged: (valor) {
                        setState(() {
                          textoBusqueda = valor;
                        });
                      },
                      decoration: InputDecoration(
                        hintText:
                            'Buscar por nombre, apellido paterno, apellido materno o RUT...',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF94A3B8),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                            width: 1.3,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF38BDF8),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // LISTA DE TRABAJADORES
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lista de Trabajadores (${listaTrabajadores.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (listaTrabajadores.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: Text(
                              'No se encontraron trabajadores.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        )
                      else
                        Column(
                          children: listaTrabajadores.map((trabajador) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _TrabajadorCard(
                                trabajador: trabajador,
                                onAsignarRol: () {
                                  cambiarRol(trabajador);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// MODELO TEMPORAL DEL TRABAJADOR
class Trabajador {
  final String nombreCompleto;
  final String rut;
  final String fechaIngreso;
  final String cargo;
  String rol;

  Trabajador({
    required this.nombreCompleto,
    required this.rut,
    required this.fechaIngreso,
    required this.cargo,
    required this.rol,
  });
}

// TARJETA DE CADA TRABAJADOR
class _TrabajadorCard extends StatelessWidget {
  final Trabajador trabajador;
  final VoidCallback onAsignarRol;

  const _TrabajadorCard({required this.trabajador, required this.onAsignarRol});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              runSpacing: 14,
              children: [
                SizedBox(
                  width: 380,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        children: [
                          Text(
                            trabajador.nombreCompleto,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          _RolBadge(rol: trabajador.rol),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _DatoTrabajadorLista(
                        icono: Icons.badge_outlined,
                        texto: 'RUT: ${trabajador.rut}',
                      ),
                      const SizedBox(height: 6),
                      _DatoTrabajadorLista(
                        icono: Icons.calendar_month_outlined,
                        texto: 'Ingreso: ${trabajador.fechaIngreso}',
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 30),
                      _DatoTrabajadorLista(
                        icono: Icons.work_outline,
                        texto: trabajador.cargo,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: onAsignarRol,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Asignar Rol'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F9F8F),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// BADGE PEQUEÑO DEL ROL
class _RolBadge extends StatelessWidget {
  final String rol;

  const _RolBadge({required this.rol});

  @override
  Widget build(BuildContext context) {
    Color fondo;
    Color texto;

    if (rol == 'Jefe') {
      fondo = const Color(0xFFF3E8FF);
      texto = const Color(0xFF9333EA);
    } else if (rol == 'Usuario') {
      fondo = const Color(0xFFDBEAFE);
      texto = const Color(0xFF2563EB);
    } else {
      fondo = const Color(0xFFE2E8F0);
      texto = const Color(0xFF475569);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        rol,
        style: TextStyle(
          fontSize: 11,
          color: texto,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// DATO CON ICONO EN LA LISTA
class _DatoTrabajadorLista extends StatelessWidget {
  final IconData icono;
  final String texto;

  const _DatoTrabajadorLista({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 15, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
        ),
      ],
    );
  }
}

// WIDGET PERSONALIZADO PARA EL BULLET TEXT
class _BulletText extends StatelessWidget {
  final String texto;

  const _BulletText({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontSize: 14, color: Color(0xFF1D4ED8)),
          ),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                height: 1.3,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
