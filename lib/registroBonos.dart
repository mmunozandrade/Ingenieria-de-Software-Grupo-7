import 'package:flutter/material.dart';
import 'inicial.dart';
import 'cargaArchivos.dart';

class RegistrarBonos extends StatefulWidget {
  const RegistrarBonos({super.key});

  @override
  State<RegistrarBonos> createState() => _RegistrarBonosState();
}

class _RegistrarBonosState extends State<RegistrarBonos> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 1. BARRA SUPERIOR (Donde aparece el icono de las 3 rayas)
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42), // Azul oscuro institucional
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
      // 2. MENÚ LATERAL DESPLEGABLE
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF001E42)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Menú de Gestión',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sistema de Remuneraciones',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.home_outlined,
                color: Color(0xFF001E42),
              ),
              title: const Text('Inicio / Panel Principal'),
              onTap: () {
                // Navegación al archivo inicial.dart
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DashboardScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_zip, color: Color(0xFF001E42)),
              title: const Text('Carga Masiva de Liquidaciones'),
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => const CargaMasivaArchivosPage(),
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Cerrar Sesión',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                // Aquí iría tu lógica de login
              },
            ),
          ],
        ),
      ),
      // 3. CONTENIDO PRINCIPAL (Tu código original)
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            //logo
            Image.asset('assets/Logo.png', height: 80),
            const SizedBox(height: 20),
            //titulo
            const Text(
              "Registro de Bonos Imponibles",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            const Text(
              "Administracion de bonificaciones que se suman a la base imponible",
              style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            //Informacion del trabajador
            _InfoTrabajadorCard(),
            const SizedBox(height: 22),
            //Informacion importante
            _InfoImportanteCard(),
            const SizedBox(height: 24),
            //Bonos
            _RegistrarBonoCard(),
            const SizedBox(height: 24),
            //Acciones
            _BonosRegistradosCard(),
          ],
        ),
      ),
    );
  }
}

class _InfoTrabajadorCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBAE6FD), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información del Trabajador',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF334155),
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 22),

          Row(
            children: const [
              Expanded(
                child: _DatoTrabajador(titulo: 'RUT', valor: '12345678-9'),
              ),
              Expanded(
                child: _DatoTrabajador(
                  titulo: 'Nombre',
                  valor: 'Nombre ApellidoPaterno ApellidoMaterno',
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          Row(
            children: const [
              Expanded(
                child: _DatoTrabajador(
                  titulo: 'Cargo',
                  valor: 'Jefe de Servicios Generales',
                ),
              ),
              Expanded(
                child: _DatoTrabajador(
                  titulo: 'Departamento',
                  valor: 'Servicios Generales',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DatoTrabajador extends StatelessWidget {
  final String titulo;
  final String valor;

  const _DatoTrabajador({required this.titulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 4),
        Text(
          valor,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InfoImportanteCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 22),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Información Importante',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Los bonos imponibles se suman a la base imponible de la liquidación y están sujetos a cotizaciones previsionales. Solo puede registrar bonos para el período actual: Mayo 2026',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrarBonoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Registrar Nuevo Bono',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 22),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CampoSelect(label: 'Tipo de Bono', requerido: true),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: _CampoTexto(
                  label: 'Monto (CLP)',
                  hint: 'Ej: 150000',
                  requerido: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CampoTexto(
                  label: 'Período de Liquidación',
                  hint: '---------- de ----',
                  requerido: true,
                  textoAyuda: 'Periodo actual: Mayo 2026',
                  suffixIcon: Icons.calendar_today_outlined,
                ),
              ),

              const SizedBox(width: 18),

              Expanded(
                child: _CampoTexto(
                  label: 'Descripción',
                  hint: 'Detalle del bono',
                  requerido: true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F9F8F),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Guardar Bono',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoTexto extends StatelessWidget {
  final String label;
  final String hint;
  final bool requerido;
  final String? textoAyuda;
  final IconData? suffixIcon;

  const _CampoTexto({
    required this.label,
    required this.hint,
    this.requerido = false,
    this.textoAyuda,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabelCampo(texto: label, requerido: requerido),

        const SizedBox(height: 8),

        TextField(
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            suffixIcon: suffixIcon == null
                ? null
                : Icon(suffixIcon, size: 16, color: const Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
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

        if (textoAyuda != null) ...[
          const SizedBox(height: 6),
          Text(
            textoAyuda!,
            style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
          ),
        ],
      ],
    );
  }
}

class _CampoSelect extends StatelessWidget {
  final String label;
  final bool requerido;

  const _CampoSelect({required this.label, this.requerido = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LabelCampo(texto: label, requerido: requerido),

        const SizedBox(height: 8),

        DropdownButtonFormField<String>(
          value: null,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFF38BDF8),
                width: 1.5,
              ),
            ),
          ),
          hint: const Text(
            '-- Seleccione tipo --',
            style: TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'gratificacion',
              child: Text('Gratificación'),
            ),
            DropdownMenuItem(
              value: 'bono_produccion',
              child: Text('Bono de producción'),
            ),
            DropdownMenuItem(value: 'bono_turno', child: Text('Bono de turno')),
          ],
          onChanged: (value) {},
        ),
      ],
    );
  }
}

class _LabelCampo extends StatelessWidget {
  final String texto;
  final bool requerido;

  const _LabelCampo({required this.texto, this.requerido = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: texto,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF334155),
          fontWeight: FontWeight.w500,
        ),
        children: [
          if (requerido)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }
}

class _BonosRegistradosCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Encabezado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bonos Registrados (1)',
                style: TextStyle(
                  fontSize: 18,
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.bold,
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    'Total Bonos',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '\$150.000',
                    style: TextStyle(
                      fontSize: 24,
                      color: Color(0xFF00897B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Tarjeta de bono
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                // Información del bono
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        children: const [
                          Text(
                            'Gratificación',
                            style: TextStyle(
                              fontSize: 15,
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          _EtiquetaPeriodo(texto: 'Abril 2026'),
                        ],
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Gratificación mensual',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF334155),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Row(
                        children: const [
                          Icon(
                            Icons.attach_money,
                            size: 15,
                            color: Color(0xFF475569),
                          ),
                          Text(
                            '\$150.000',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF334155),
                            ),
                          ),

                          SizedBox(width: 16),

                          Icon(
                            Icons.calendar_month_outlined,
                            size: 15,
                            color: Color(0xFF475569),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Registrado: 29-04-2026',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Botón eliminar
                IconButton(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EtiquetaPeriodo extends StatelessWidget {
  final String texto;

  const _EtiquetaPeriodo({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
