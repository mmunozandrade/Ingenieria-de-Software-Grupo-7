import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlPend = 'http://127.0.0.1:8000';
const int _salarioMinimoPend = 500000;

const List<String> _afpListPend = [
  'AFP Capital',
  'AFP Cuprum',
  'AFP Habitat',
  'AFP PlanVital',
  'AFP ProVida',
  'AFP Modelo',
  'AFP Uno',
];
const List<String> _tiposContratoPend = [
  'Indefinido',
  'Plazo fijo',
  'Por obra',
];
const List<String> _institucionesPend = ['Fonasa', 'Isapre'];

class CuentasPendientes extends StatefulWidget {
  const CuentasPendientes({super.key});

  @override
  State<CuentasPendientes> createState() => _CuentasPendientesState();
}

class _CuentasPendientesState extends State<CuentasPendientes> {
  List<Map<String, dynamic>> _cuentas = [];
  bool _cargando = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargarCuentas();
  }

  Future<void> _cargarCuentas() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlPend/admin/cuentas-pendientes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(
          () =>
              _cuentas = List<Map<String, dynamic>>.from(data['cuentas'] ?? []),
        );
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  void _abrirFormulario(Map<String, dynamic> cuenta) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FormularioCompletarCuenta(cuenta: cuenta),
      ),
    ).then((_) => _cargarCuentas());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Cuentas Pendientes',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarCuentas,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF001E42)),
            )
          : _error.isNotEmpty
          ? Center(
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            )
          : Column(
              children: [
                // Banner informativo
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFFFFFBEB),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFD97706),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Estas cuentas fueron creadas por los trabajadores pero aun no tienen datos personales completos. Completa su informacion para que puedan usar el sistema.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista
                Expanded(
                  child: _cuentas.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 56,
                                color: Color(0xFF0D9488),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No hay cuentas pendientes',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Todas las cuentas tienen datos completos',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _cuentas.length,
                          itemBuilder: (context, index) {
                            final c = _cuentas[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: const Color(0xFFFEF3C7),
                                    child: const Icon(
                                      Icons.person_outline,
                                      color: Color(0xFFD97706),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c['correo'] ?? '—',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF3C7),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                'Sin datos personales',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF92400E),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Rol: ${c['rol'] ?? '—'}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Boton
                                  ElevatedButton.icon(
                                    onPressed: () => _abrirFormulario(c),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('Completar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF001E42),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
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

// ══════════════════════════════════════════════════════════════
// FORMULARIO COMPLETAR CUENTA
// ══════════════════════════════════════════════════════════════
class _FormularioCompletarCuenta extends StatefulWidget {
  final Map<String, dynamic> cuenta;
  const _FormularioCompletarCuenta({required this.cuenta});

  @override
  State<_FormularioCompletarCuenta> createState() =>
      _FormularioCompletarCuentaState();
}

class _FormularioCompletarCuentaState
    extends State<_FormularioCompletarCuenta> {
  final _formKey = GlobalKey<FormState>();

  final _rutCtrl = TextEditingController();
  final _primerNombreCtrl = TextEditingController();
  final _segundoNombreCtrl = TextEditingController();
  final _apPaternoCtrl = TextEditingController();
  final _apMaternoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController(text: '+56 9 ');
  final _direccionCtrl = TextEditingController();
  final _cargoCtrl = TextEditingController();
  final _sueldoCtrl = TextEditingController();
  final _discapacidadCtrl = TextEditingController();

  String? _salud;
  String? _afp;
  String? _tipoContrato;
  DateTime? _fechaIngreso;
  DateTime? _fechaNacimiento;

  bool _guardando = false;
  String _mensaje = '';
  bool _exito = false;

  @override
  void dispose() {
    _rutCtrl.dispose();
    _primerNombreCtrl.dispose();
    _segundoNombreCtrl.dispose();
    _apPaternoCtrl.dispose();
    _apMaternoCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _cargoCtrl.dispose();
    _sueldoCtrl.dispose();
    _discapacidadCtrl.dispose();
    super.dispose();
  }

  bool _validarRut(String rut) {
    final limpio = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
    if (limpio.length < 2) return false;
    final dv = limpio[limpio.length - 1];
    final cuerpo = limpio.substring(0, limpio.length - 1);
    if (!RegExp(r'^\d+$').hasMatch(cuerpo)) return false;
    int suma = 0, mult = 2;
    for (int i = cuerpo.length - 1; i >= 0; i--) {
      suma += int.parse(cuerpo[i]) * mult;
      mult++;
      if (mult > 7) mult = 2;
    }
    final resto = suma % 11;
    String dvEsperado;
    if (resto == 0)
      dvEsperado = '0';
    else if (resto == 1)
      dvEsperado = 'K';
    else
      dvEsperado = (11 - resto).toString();
    return dv == dvEsperado;
  }

  int? _calcularEdad() {
    if (_fechaNacimiento == null) return null;
    final hoy = DateTime.now();
    int edad = hoy.year - _fechaNacimiento!.year;
    if (hoy.month < _fechaNacimiento!.month ||
        (hoy.month == _fechaNacimiento!.month &&
            hoy.day < _fechaNacimiento!.day))
      edad--;
    return edad;
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaIngreso == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Debes seleccionar la fecha de ingreso';
      });
      return;
    }
    if (_salud == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Debes seleccionar la institucion de salud';
      });
      return;
    }
    if (_afp == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Debes seleccionar la AFP';
      });
      return;
    }
    if (_tipoContrato == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Debes seleccionar el tipo de contrato';
      });
      return;
    }

    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final body = {
        'cuenta_id': widget.cuenta['cuenta_id'],
        'rut': _rutCtrl.text.trim(),
        'primer_nombre': _primerNombreCtrl.text.trim(),
        'segundo_nombre': _segundoNombreCtrl.text.trim(),
        'apellido_paterno': _apPaternoCtrl.text.trim(),
        'apellido_materno': _apMaternoCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        'tipo_salud': _salud!,
        'afp': _afp!,
        'cargo': _cargoCtrl.text.trim(),
        'tipo_contrato': _tipoContrato!,
        'fecha_ingreso': _fechaIngreso!.toIso8601String().split('T')[0],
        'sueldo_base': int.parse(_sueldoCtrl.text.trim()),
        'discapacidad': _discapacidadCtrl.text.trim(),
        if (_fechaNacimiento != null)
          'fecha_nacimiento': _fechaNacimiento!.toIso8601String().split('T')[0],
      };

      final response = await http.post(
        Uri.parse('$_apiUrlPend/admin/completar-cuenta'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Datos completados correctamente'
            : data['mensaje'] ?? 'Error';
      });

      if (_exito) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Completar: ${widget.cuenta['correo'] ?? ''}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner correo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.email_outlined,
                          color: Color(0xFF2563EB),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Completando datos para: ${widget.cuenta['correo']}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── SECCION 1: IDENTIFICACION ───────────
                  _SecTitulo(
                    numero: '1',
                    titulo: 'Identificacion',
                    icono: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'RUT *',
                    hint: 'Ej: 18.679.609-8',
                    controller: _rutCtrl,
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'El RUT es obligatorio';
                      if (!RegExp(
                        r'^\d{1,2}\.\d{3}\.\d{3}-[\dkK]$',
                      ).hasMatch(v))
                        return 'Formato invalido. Use xx.xxx.xxx-x';
                      if (!_validarRut(v))
                        return 'El digito verificador no es valido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _Campo(
                          label: 'Primer nombre *',
                          hint: 'Ej: Matias',
                          controller: _primerNombreCtrl,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Obligatorio';
                            if (v.length < 2 || v.length > 30)
                              return 'Entre 2 y 30 caracteres';
                            if (!RegExp(
                              r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ]+$",
                            ).hasMatch(v))
                              return 'Solo letras';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Campo(
                          label: 'Segundo nombre',
                          hint: 'Opcional',
                          controller: _segundoNombreCtrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _Campo(
                          label: 'Apellido paterno *',
                          hint: 'Ej: Gonzalez',
                          controller: _apPaternoCtrl,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Obligatorio';
                            if (v.length < 2 || v.length > 30)
                              return 'Entre 2 y 30 caracteres';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Campo(
                          label: 'Apellido materno *',
                          hint: 'Ej: Perez',
                          controller: _apMaternoCtrl,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Obligatorio';
                            if (v.length < 2 || v.length > 30)
                              return 'Entre 2 y 30 caracteres';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── SECCION 2: CONTACTO ─────────────────
                  _SecTitulo(
                    numero: '2',
                    titulo: 'Contacto',
                    icono: Icons.contact_phone_outlined,
                  ),
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'Telefono',
                    hint: '+56 9 8765 4321',
                    controller: _telefonoCtrl,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _Campo(
                    label: 'Direccion',
                    hint: 'Av. Los Andes 1234',
                    controller: _direccionCtrl,
                    maxLines: 2,
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 10)
                        return 'Minimo 10 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── SECCION 3: PREVISION ────────────────
                  _SecTitulo(
                    numero: '3',
                    titulo: 'Prevision',
                    icono: Icons.health_and_safety_outlined,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _DropDown(
                          label: 'Institucion de salud *',
                          value: _salud,
                          items: _institucionesPend,
                          onChanged: (v) => setState(() => _salud = v),
                          validator: (v) =>
                              v == null ? 'Selecciona una opcion' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DropDown(
                          label: 'AFP *',
                          value: _afp,
                          items: _afpListPend,
                          onChanged: (v) => setState(() => _afp = v),
                          validator: (v) =>
                              v == null ? 'Selecciona una opcion' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── SECCION 4: CONTRACTUAL ──────────────
                  _SecTitulo(
                    numero: '4',
                    titulo: 'Informacion Contractual',
                    icono: Icons.work_outline,
                  ),
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'Cargo *',
                    hint: 'Ej: Tecnico en Enfermeria',
                    controller: _cargoCtrl,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obligatorio';
                      if (v.length < 2 || v.length > 100)
                        return 'Entre 2 y 100 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  _DropDown(
                    label: 'Tipo de contrato *',
                    value: _tipoContrato,
                    items: _tiposContratoPend,
                    onChanged: (v) => setState(() => _tipoContrato = v),
                    validator: (v) =>
                        v == null ? 'Selecciona una opcion' : null,
                  ),
                  const SizedBox(height: 12),

                  // Fecha ingreso
                  _SelectorFecha(
                    label: 'Fecha de ingreso *',
                    fecha: _fechaIngreso,
                    onTap: () async {
                      final f = await showDatePicker(
                        context: context,
                        initialDate: _fechaIngreso ?? DateTime.now(),
                        firstDate: DateTime(1990),
                        lastDate: DateTime.now(),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF001E42),
                              onPrimary: Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (f != null) setState(() => _fechaIngreso = f);
                    },
                  ),
                  const SizedBox(height: 12),

                  _Campo(
                    label: 'Sueldo base (CLP) *',
                    hint: 'Ej: 650000',
                    controller: _sueldoCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obligatorio';
                      final n = int.tryParse(v);
                      if (n == null) return 'Debe ser un numero entero';
                      if (n < _salarioMinimoPend)
                        return 'No puede ser inferior al salario minimo (\$$_salarioMinimoPend)';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // ── SECCION 5: OPCIONALES ───────────────
                  _SecTitulo(
                    numero: '5',
                    titulo: 'Informacion Opcional',
                    icono: Icons.info_outline,
                  ),
                  const SizedBox(height: 16),

                  _SelectorFecha(
                    label: 'Fecha de nacimiento (opcional)',
                    fecha: _fechaNacimiento,
                    onTap: () async {
                      final hoy = DateTime.now();
                      final limite = DateTime(
                        hoy.year - 18,
                        hoy.month,
                        hoy.day,
                      );
                      final f = await showDatePicker(
                        context: context,
                        initialDate: _fechaNacimiento ?? limite,
                        firstDate: DateTime(hoy.year - 70),
                        lastDate: limite,
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF001E42),
                              onPrimary: Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (f != null) setState(() => _fechaNacimiento = f);
                    },
                  ),
                  if (_fechaNacimiento != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Edad: ${_calcularEdad()} anos',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0D9488),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  _Campo(
                    label: 'Informacion discapacidad (Ley 20.422)',
                    hint: 'Opcional',
                    controller: _discapacidadCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),

                  // Mensaje
                  if (_mensaje.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: _exito ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _exito ? Colors.green[200]! : Colors.red[200]!,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _exito
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: _exito ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _mensaje,
                              style: TextStyle(
                                color: _exito
                                    ? Colors.green[800]
                                    : Colors.red[800],
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Boton guardar
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.person_add_outlined),
                      label: Text(
                        _guardando ? 'Guardando...' : 'Completar Datos',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF001E42),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widgets auxiliares ────────────────────────────────────────

class _SecTitulo extends StatelessWidget {
  final String numero, titulo;
  final IconData icono;
  const _SecTitulo({
    required this.numero,
    required this.titulo,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: Color(0xFF001E42),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              numero,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icono, color: const Color(0xFF001E42), size: 20),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF001E42),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: Color(0xFFCBD5E1))),
      ],
    );
  }
}

class _Campo extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  const _Campo({
    required this.label,
    required this.controller,
    this.hint = '',
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF001E42), width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

class _DropDown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> items;
  final void Function(String?) onChanged;
  final String? Function(String?)? validator;

  const _DropDown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF001E42), width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
    );
  }
}

class _SelectorFecha extends StatelessWidget {
  final String label;
  final DateTime? fecha;
  final VoidCallback onTap;
  const _SelectorFecha({
    required this.label,
    required this.fecha,
    required this.onTap,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              color: Color(0xFF64748B),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fecha != null ? _fmt(fecha!) : label,
                style: TextStyle(
                  fontSize: 15,
                  color: fecha != null
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
            if (fecha != null)
              const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF0D9488),
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
