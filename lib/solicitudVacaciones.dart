import 'package:flutter/material.dart';
import 'inicial.dart';
import 'cargaArchivos.dart';
import 'registroBonos.dart';
import 'asignacionRoles.dart';
import 'calculoHextra.dart';
import 'descargaLiquidacion.dart';

class SolicitudVacaciones extends StatefulWidget {
  const SolicitudVacaciones({super.key});

  @override
  State<SolicitudVacaciones> createState() => _SolicitudVacacionesState();
}

class _SolicitudVacacionesState extends State<SolicitudVacaciones> {
  // Variables de estado
  final int diasDisponibles = 15;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  // Calcular la cantidad de días seleccionados
  int get diasSeleccionados {
    if (fechaInicio == null || fechaFin == null) return 0;
    // Sumamos 1 para incluir el día de inicio en el conteo
    return fechaFin!.difference(fechaInicio!).inDays + 1;
  }

  // Método para abrir el calendario
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
              primary: Color(0xFF001E42), // Color de selección del calendario
              onPrimary: Colors.white,
              onSurface: Color(0xFF0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (rango != null) {
      setState(() {
        fechaInicio = rango.start;
        fechaFin = rango.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Título
            const Text(
              "Solicitud de Vacaciones",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              "Seleccione el período de sus vacaciones legales",
              style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),

            // Tarjeta de Días Disponibles
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBAE6FD), width: 1.4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Días Disponibles',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$diasDisponibles',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Color(0xFF0284C7),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Tarjeta de Selección de Fechas
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
                  const Text(
                    'Período Solicitado',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Botón para abrir calendario
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
                        border: Border.all(color: const Color(0xFFCBD5E1)),
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
                                  : '${fechaInicio!.day}/${fechaInicio!.month}/${fechaInicio!.year} - ${fechaFin!.day}/${fechaFin!.month}/${fechaFin!.year}',
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

                  // Resumen de la solicitud
                  if (fechaInicio != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Días a tomar:',
                          style: TextStyle(color: Color(0xFF475569)),
                        ),
                        Text(
                          '$diasSeleccionados',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: diasSeleccionados > diasDisponibles
                                ? Colors.red
                                : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Saldo restante:',
                          style: TextStyle(color: Color(0xFF475569)),
                        ),
                        Text(
                          '${diasDisponibles - diasSeleccionados}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (diasDisponibles - diasSeleccionados) < 0
                                ? Colors.red
                                : const Color(0xFF0F9F8F),
                          ),
                        ),
                      ],
                    ),
                    if (diasSeleccionados > diasDisponibles)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Los días solicitados superan su saldo disponible.',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Botón de Enviar
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed:
                    (fechaInicio == null || diasSeleccionados > diasDisponibles)
                    ? null // Se deshabilita si no hay fechas o si pide más de 15
                    : () {
                        // Lógica para enviar la solicitud
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F9F8F),
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Enviar Solicitud',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
