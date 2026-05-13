import 'package:flutter/material.dart';
import '../../auth/inicial.dart';
import 'cargaArchivos.dart';
import 'registroBonos.dart';
import '../USUARIO/solicitudVacaciones.dart';
import 'asignacionRoles.dart';
import '../USUARIO/descargaLiquidacion.dart';

class CalculoHextra extends StatefulWidget {
  const CalculoHextra({super.key});

  @override
  State<CalculoHextra> createState() => _CalculoHoraExtraState();
}

class _CalculoHoraExtraState extends State<CalculoHextra> {
  // Variables de estado para los filtros
  String textoBusqueda = "";

  // Controlador para el campo de texto de búsqueda
  final TextEditingController _busquedaController = TextEditingController();

  // Datos de ejemplo (sin horas extra pre-cargadas)
  final List<Map<String, dynamic>> _personal = [
    {"nombre": "María González", "rut": "12345678-9", "rol": "Administrativo"},
    {"nombre": "Carlos Pérez", "rut": "98765432-1", "rol": "Clínico"},
    {"nombre": "Ana Silva", "rut": "11223344-5", "rol": "Servicios"},
    {"nombre": "Luis Torres", "rut": "22334455-6", "rol": "Administrativo"},
    {"nombre": "Patricia Soto", "rut": "33445566-7", "rol": "Clínico"},
    {"nombre": "Diego Rojas", "rut": "44556677-8", "rol": "Servicios"},
  ];

  @override
  void initState() {
    super.initState();
    // Le asignamos DOS controladores a cada trabajador
    for (var trabajador in _personal) {
      trabajador['horasController'] = TextEditingController(); // Para las horas
      trabajador['fechaController'] = TextEditingController(); // Para la fecha
    }
  }

  @override
  void dispose() {
    // Limpiamos los controladores
    for (var trabajador in _personal) {
      trabajador['horasController'].dispose();
      trabajador['fechaController'].dispose();
    }
    _busquedaController.dispose();
    super.dispose();
  }

  // Getter para filtrar la lista
  List<Map<String, dynamic>> get personalFiltrado {
    if (textoBusqueda.trim().isEmpty) return _personal;

    final busqueda = textoBusqueda.toLowerCase();
    return _personal
        .where(
          (t) =>
              t['nombre'].toLowerCase().contains(busqueda) ||
              t['rut'].toLowerCase().contains(busqueda),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final trabajadoresMostrados = personalFiltrado;

    return Scaffold(
      backgroundColor: Colors.white,

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
            const Divider(),
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

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 1200,
          ), // Lo hice un poquito más ancho para que quepa bien la fecha
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cálculo de Horas Extra',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF141C24),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Administra el registro de horas extra para los trabajadores de la institución.',
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 24),

              // BARRA DE BÚSQUEDA
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _busquedaController,
                      onChanged: (value) {
                        setState(() {
                          textoBusqueda = value;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Buscar por nombre o rut',
                        hintText: 'Ej. Juan Pérez o 12345678-9',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.grey,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.rule_folder_outlined, size: 24),
                    label: const Text(
                      'Reporte General',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF009A8D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // TABLA DE TRABAJADORES (AHORA CON 6 COLUMNAS)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: const {
                    0: FlexColumnWidth(1.8), // Trabajador
                    1: FlexColumnWidth(1.2), // RUT
                    2: FlexColumnWidth(1.2), // Rol
                    3: FlexColumnWidth(1.4), // Fecha
                    4: FlexColumnWidth(1.2), // Horas
                    5: FlexColumnWidth(1), // Acción
                  },
                  children: [
                    // ENCABEZADO
                    const TableRow(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        color: Color(0xFFF9FAFB),
                      ),
                      children: [
                        Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Trabajador',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4B5563),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'RUT',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4B5563),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Rol',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4B5563),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Fecha',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4B5563),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Horas',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4B5563),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Acción',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4B5563),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // FILAS DINÁMICAS
                    ...trabajadoresMostrados.map((trabajador) {
                      return TableRow(
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFF3F4F6)),
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Text(
                              trabajador['nombre'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Text(
                              trabajador['rut'],
                              style: const TextStyle(color: Color(0xFF4B5563)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: Text(
                              trabajador['rol'],
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ),

                          // INPUT PARA FECHA
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: TextField(
                              controller: trabajador['fechaController'],
                              keyboardType: TextInputType.datetime,
                              decoration: InputDecoration(
                                hintText: 'dd/mm/aaaa',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 13,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),

                          // INPUT PARA HORAS
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: TextField(
                              controller: trabajador['horasController'],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                hintText: 'Ej: 2.5',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 13,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),

                          // BOTÓN GUARDAR
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 8.0,
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                String fecha =
                                    trabajador['fechaController'].text;
                                String horas =
                                    trabajador['horasController'].text;

                                if (fecha.isEmpty || horas.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Por favor ingresa fecha y horas',
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                  return;
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Guardado: $horas hrs el $fecha para ${trabajador['nombre']}',
                                    ),
                                    backgroundColor: const Color(0xFF009A8D),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE0F2F1),
                                foregroundColor: const Color(0xFF009A8D),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Guardar'),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
