import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

// ── Salario minimo configurable ───────────────────────────────
const int _salarioMinimoClp = 500000;

// ── Lista AFP activas en Chile ────────────────────────────────
const List<String> _afpList = [
  'AFP Capital',
  'AFP Cuprum',
  'AFP Habitat',
  'AFP PlanVital',
  'AFP ProVida',
  'AFP Modelo',
  'AFP Uno',
];

// ── Tipos de contrato ─────────────────────────────────────────
const List<String> _tiposContrato = [
  'Indefinido',
  'Plazo fijo',
  'Por obra',
];

// ── Instituciones de salud ────────────────────────────────────
const List<String> _institucionesSalud = ['Fonasa', 'Isapre'];

class RegistroEmpleado extends StatefulWidget {
  /// Si se pasa un empleado existente, entra en modo edicion
  final Map<String, dynamic>? empleadoExistente;

  const RegistroEmpleado({super.key, this.empleadoExistente});

  @override
  State<RegistroEmpleado> createState() => _RegistroEmpleadoState();
}

class _RegistroEmpleadoState extends State<RegistroEmpleado> {
  final _formKey = GlobalKey<FormState>();

  // ── Controladores ─────────────────────────────────────────
  final _rutCtrl            = TextEditingController();
  final _primerNombreCtrl   = TextEditingController();
  final _segundoNombreCtrl  = TextEditingController();
  final _apPaternoCtrl      = TextEditingController();
  final _apMaternoCtrl      = TextEditingController();
  final _correoCtrl         = TextEditingController();
  final _telefonoCtrl       = TextEditingController(text: '+56 9 ');
  final _direccionCtrl      = TextEditingController();
  final _cargoCtrl          = TextEditingController();
  final _sueldoCtrl         = TextEditingController();
  final _discapacidadCtrl   = TextEditingController();

  // ── Dropdowns ─────────────────────────────────────────────
  String? _salud;
  String? _afp;
  String? _tipoContrato;

  // ── Fechas ────────────────────────────────────────────────
  DateTime? _fechaIngreso;
  DateTime? _fechaNacimiento;

  // ── Estado ────────────────────────────────────────────────
  bool   _guardando = false;
  String _mensaje   = '';
  bool   _exito     = false;

  bool get _esEdicion => widget.empleadoExistente != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) _preLlenarFormulario();
  }

  void _preLlenarFormulario() {
    final e = widget.empleadoExistente!;
    _rutCtrl.text           = e['rut'] ?? '';
    _primerNombreCtrl.text  = e['primer_nombre'] ?? '';
    _segundoNombreCtrl.text = e['segundo_nombre'] ?? '';
    _apPaternoCtrl.text     = e['apellido_paterno'] ?? '';
    _apMaternoCtrl.text     = e['apellido_materno'] ?? '';
    _correoCtrl.text        = e['correo'] ?? '';
    _telefonoCtrl.text      = e['telefono'] ?? '+56 9 ';
    _direccionCtrl.text     = e['direccion'] ?? '';
    _cargoCtrl.text         = e['cargo'] ?? '';
    _sueldoCtrl.text        = e['sueldo_base']?.toString() ?? '';
    _discapacidadCtrl.text  = e['discapacidad'] ?? '';
    _salud                  = e['tipo_salud'];
    _afp                    = e['afp'];
    _tipoContrato           = e['tipo_contrato'];
    if (e['fecha_ingreso'] != null) {
      _fechaIngreso = DateTime.tryParse(e['fecha_ingreso']);
    }
    if (e['fecha_nacimiento'] != null) {
      _fechaNacimiento = DateTime.tryParse(e['fecha_nacimiento']);
    }
  }

  @override
  void dispose() {
    _rutCtrl.dispose();
    _primerNombreCtrl.dispose();
    _segundoNombreCtrl.dispose();
    _apPaternoCtrl.dispose();
    _apMaternoCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _cargoCtrl.dispose();
    _sueldoCtrl.dispose();
    _discapacidadCtrl.dispose();
    super.dispose();
  }

  // ── Validacion digito verificador RUT ────────────────────
  bool _validarRut(String rut) {

    // Limpiar puntos y guion
    final limpio = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
    if (limpio.length < 2) return false;

    final dv     = limpio[limpio.length - 1];
    final cuerpo = limpio.substring(0, limpio.length - 1);

    if (!RegExp(r'^\d+$').hasMatch(cuerpo)) return false;

    // Algoritmo modulo 11
    int suma = 0;
    int mult = 2;
    for (int i = cuerpo.length - 1; i >= 0; i--) {
      suma += int.parse(cuerpo[i]) * mult;
      mult++;
      if (mult > 7) mult = 2;
    }

    final resto = suma % 11;
    String dvEsperado;
    if (resto == 0)      dvEsperado = '0';
    else if (resto == 1) dvEsperado = 'K';
    else                 dvEsperado = (11 - resto).toString();

    return dv == dvEsperado;
  }

  // ── Seleccionar fecha ─────────────────────────────────────
  Future<DateTime?> _seleccionarFecha({
    required DateTime firstDate,
    required DateTime lastDate,
    DateTime? initial,
  }) async {
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: firstDate,
      lastDate: lastDate,
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
  }

  String _formatFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ── Guardar empleado ──────────────────────────────────────
  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fechaIngreso == null) {
      setState(() { _exito = false; _mensaje = 'Debes seleccionar la fecha de ingreso'; });
      return;
    }
    if (_salud == null) {
      setState(() { _exito = false; _mensaje = 'Debes seleccionar la institucion de salud'; });
      return;
    }
    if (_afp == null) {
      setState(() { _exito = false; _mensaje = 'Debes seleccionar la AFP'; });
      return;
    }
    if (_tipoContrato == null) {
      setState(() { _exito = false; _mensaje = 'Debes seleccionar el tipo de contrato'; });
      return;
    }

    setState(() { _guardando = true; _mensaje = ''; });

    try {
      final token = await SessionService.obtenerToken();
      final afpFinal = _afp!;

      final body = {
        'rut':              _rutCtrl.text.trim(),
        'primer_nombre':    _primerNombreCtrl.text.trim(),
        'segundo_nombre':   _segundoNombreCtrl.text.trim(),
        'apellido_paterno': _apPaternoCtrl.text.trim(),
        'apellido_materno': _apMaternoCtrl.text.trim(),
        'correo':           _correoCtrl.text.trim(),
        'telefono':         _telefonoCtrl.text.trim(),
        'direccion':        _direccionCtrl.text.trim(),
        'tipo_salud':       _salud!,
        'afp':              afpFinal,
        'cargo':            _cargoCtrl.text.trim(),
        'tipo_contrato':    _tipoContrato!,
        'fecha_ingreso':    _fechaIngreso!.toIso8601String().split('T')[0],
        'sueldo_base':      int.parse(_sueldoCtrl.text.trim()),
        'discapacidad':     _discapacidadCtrl.text.trim(),
        if (_fechaNacimiento != null)
          'fecha_nacimiento': _fechaNacimiento!.toIso8601String().split('T')[0],
      };

      http.Response response;
      if (_esEdicion) {
        response = await http.put(
          Uri.parse('$_apiUrl/empleados/${widget.empleadoExistente!['id_empleado']}'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        );
      } else {
        response = await http.post(
          Uri.parse('$_apiUrl/empleados'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        );
      }

      final data = jsonDecode(response.body);
      setState(() {
        _exito   = data['success'] == true;
        _mensaje = _exito
            ? _esEdicion
                ? 'Empleado actualizado correctamente'
                : 'Empleado registrado correctamente. Se creo su cuenta con correo ${_correoCtrl.text.trim()}'
            : data['mensaje'] ?? 'Error al guardar';
      });

      if (_exito && !_esEdicion) {
        _formKey.currentState!.reset();
        setState(() {
          _salud = null; _afp = null; _tipoContrato = null;
          _fechaIngreso = null; _fechaNacimiento = null;
          _telefonoCtrl.text = '+56 9 ';
        });
      }
    } catch (e) {
      setState(() { _exito = false; _mensaje = 'No se pudo conectar al servidor'; });
    } finally {
      setState(() => _guardando = false);
    }
  }

  // ── Calcular edad ─────────────────────────────────────────
  int? _calcularEdad() {
    if (_fechaNacimiento == null) return null;
    final hoy  = DateTime.now();
    int   edad = hoy.year - _fechaNacimiento!.year;
    if (hoy.month < _fechaNacimiento!.month ||
        (hoy.month == _fechaNacimiento!.month && hoy.day < _fechaNacimiento!.day)) {
      edad--;
    }
    return edad;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _esEdicion ? 'Editar Empleado' : 'Registrar Nuevo Empleado',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── SECCION 1: IDENTIFICACION ───────────
                  _SeccionTitulo(
                    numero: '1',
                    titulo: 'Identificacion',
                    icono: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 16),

                  // RUT
                  _Campo(
                    label: 'RUT *',
                    hint: 'Ej: 18.679.609-8',
                    controller: _rutCtrl,
                    enabled: !_esEdicion,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'El RUT es obligatorio';
                      final patron = RegExp(r'^\d{1,2}\.\d{3}\.\d{3}-[\dkK]$');
                      if (!patron.hasMatch(v)) return 'Formato invalido. Use xx.xxx.xxx-x';
                      if (!_validarRut(v)) return 'El digito verificador no es valido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(
                      child: _Campo(
                        label: 'Primer nombre *',
                        hint: 'Ej: Edgar',
                        controller: _primerNombreCtrl,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obligatorio';
                          if (v.length < 2 || v.length > 30) return 'Entre 2 y 30 caracteres';
                          if (!RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ]+$").hasMatch(v)) return 'Solo letras';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Campo(
                        label: 'Segundo nombre',
                        hint: 'Opcional',
                        controller: _segundoNombreCtrl,
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          if (v.length < 2 || v.length > 30) return 'Entre 2 y 30 caracteres';
                          if (!RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ]+$").hasMatch(v)) return 'Solo letras';
                          return null;
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(
                      child: _Campo(
                        label: 'Apellido paterno *',
                        hint: 'Ej: Guerra',
                        controller: _apPaternoCtrl,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obligatorio';
                          if (v.length < 2 || v.length > 30) return 'Entre 2 y 30 caracteres';
                          if (!RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ-]+$").hasMatch(v)) return 'Solo letras y guion';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Campo(
                        label: 'Apellido materno *',
                        hint: 'Ej: Estay',
                        controller: _apMaternoCtrl,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Obligatorio';
                          if (v.length < 2 || v.length > 30) return 'Entre 2 y 30 caracteres';
                          if (!RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ-]+$").hasMatch(v)) return 'Solo letras y guion';
                          return null;
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 32),

                  // ── SECCION 2: CONTACTO ─────────────────
                  _SeccionTitulo(
                    numero: '2',
                    titulo: 'Contacto',
                    icono: Icons.contact_phone_outlined,
                  ),
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'Correo institucional *',
                    hint: 'usuario@accaconcagua.cl',
                    controller: _correoCtrl,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_esEdicion,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obligatorio';
                      if (v.length > 100) return 'Maximo 100 caracteres';
                      if (!v.endsWith('@accaconcagua.cl')) return 'Debe ser @accaconcagua.cl';
                      if (!RegExp(r'^[\w.]+@accaconcagua\.cl$').hasMatch(v)) return 'Formato invalido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'Telefono *',
                    hint: '+56 9 8765 4321',
                    controller: _telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obligatorio';
                      final digits = v.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 11) return 'Debe tener 11 digitos numericos incluyendo codigo de pais (56)';
                      if (!digits.startsWith('569')) return 'Debe comenzar con +56 9';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'Direccion *',
                    hint: 'Ej: Av. Los Andes 1234, Los Andes, Region de Valparaiso',
                    controller: _direccionCtrl,
                    maxLines: 2,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Obligatorio';
                      if (v.length < 10) return 'Minimo 10 caracteres';
                      if (v.length > 200) return 'Maximo 200 caracteres';
                      if (!RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ0-9\s.,\-]+$').hasMatch(v)) {
                        return 'Solo letras, numeros, espacios, puntos, comas y guiones';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // ── SECCION 3: PREVISION ────────────────
                  _SeccionTitulo(
                    numero: '3',
                    titulo: 'Prevision',
                    icono: Icons.health_and_safety_outlined,
                  ),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(
                      child: _Dropdown(
                        label: 'Institucion de salud *',
                        value: _salud,
                        items: _institucionesSalud,
                        onChanged: (v) => setState(() => _salud = v),
                        validator: (v) => v == null ? 'Selecciona una opcion' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _Dropdown(
                        label: 'AFP *',
                        value: _afp,
                        items: _afpList,
                        onChanged: (v) => setState(() => _afp = v),
                        validator: (v) => v == null ? 'Selecciona una opcion' : null,
                      ),
                    ),
                  ]),

                  const SizedBox(height: 32),

                  // ── SECCION 4: CONTRACTUAL ──────────────
                  _SeccionTitulo(
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
                      if (v.length < 2) return 'Minimo 2 caracteres';
                      if (v.length > 100) return 'Maximo 100 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  _Dropdown(
                    label: 'Tipo de contrato *',
                    value: _tipoContrato,
                    items: _tiposContrato,
                    onChanged: (v) => setState(() => _tipoContrato = v),
                    validator: (v) => v == null ? 'Selecciona una opcion' : null,
                  ),
                  const SizedBox(height: 16),

                  // Fecha de ingreso
                  _SelectorFecha(
                    label: 'Fecha de ingreso *',
                    fecha: _fechaIngreso,
                    onTap: () async {
                      final f = await _seleccionarFecha(
                        firstDate: DateTime(1990),
                        lastDate: DateTime.now(),
                        initial: _fechaIngreso,
                      );
                      if (f != null) setState(() => _fechaIngreso = f);
                    },
                  ),
                  const SizedBox(height: 16),

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
                      if (n < _salarioMinimoClp) {
                        return 'No puede ser inferior al salario minimo (\$${_salarioMinimoClp.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')})';
                      }
                      if (v.length > 9) return 'Maximo 9 digitos';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // ── SECCION 5: OPCIONALES ───────────────
                  _SeccionTitulo(
                    numero: '5',
                    titulo: 'Informacion Opcional',
                    icono: Icons.info_outline,
                  ),
                  const SizedBox(height: 16),

                  // Fecha de nacimiento ///////FECHA DE NACIMIENTO CAMPO
                  _SelectorFecha(
                    label: 'Fecha de nacimiento (opcional)',
                    fecha: _fechaNacimiento,
                    onTap: () async {
                      final hoy = DateTime.now();
                      final limite = DateTime(hoy.year - 18, hoy.month, hoy.day);
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
                      if (f != null) {
                        final edad = hoy.year - f.year -
                            ((hoy.month < f.month ||
                                    (hoy.month == f.month && hoy.day < f.day))
                                ? 1
                                : 0);
                        if (edad < 18 || edad > 70) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('El empleado debe tener entre 18 y 70 anos'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        setState(() => _fechaNacimiento = f);
                      }
                    },
                  ),

                  if (_fechaNacimiento != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6FFFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF5EEAD4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.cake_outlined,
                            size: 16, color: Color(0xFF0D9488)),
                        const SizedBox(width: 8),
                        Text(
                          'Edad calculada: ${_calcularEdad()} anos',
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF0D9488),
                              fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 16),

                  _Campo(
                    label: 'Informacion sobre discapacidad (Ley 20.422)',
                    hint: 'Opcional - Describe si aplica',
                    controller: _discapacidadCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 32),

                  // ── MENSAJE ─────────────────────────────
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
                      child: Row(children: [
                        Icon(
                          _exito ? Icons.check_circle_outline : Icons.error_outline,
                          color: _exito ? Colors.green : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _mensaje,
                            style: TextStyle(
                              color: _exito ? Colors.green[800] : Colors.red[800],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ]),
                    ),

                  // ── BOTON GUARDAR ───────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Icon(_esEdicion ? Icons.save_outlined : Icons.person_add_outlined),
                      label: Text(
                        _guardando
                            ? 'Guardando...'
                            : _esEdicion
                                ? 'Guardar Cambios'
                                : 'Registrar Empleado',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF001E42),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
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

class _SeccionTitulo extends StatelessWidget {
  final String  numero;
  final String  titulo;
  final IconData icono;

  const _SeccionTitulo({
    required this.numero,
    required this.titulo,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32, height: 32,
        decoration: const BoxDecoration(
            color: Color(0xFF001E42), shape: BoxShape.circle),
        child: Center(
          child: Text(numero,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
      ),
      const SizedBox(width: 12),
      Icon(icono, color: const Color(0xFF001E42), size: 20),
      const SizedBox(width: 8),
      Text(titulo,
          style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001E42))),
      const SizedBox(width: 12),
      const Expanded(child: Divider(color: Color(0xFFCBD5E1))),
    ]);
  }
}

class _Campo extends StatelessWidget {
  final String                  label;
  final String                  hint;
  final TextEditingController   controller;
  final String? Function(String?)? validator;
  final TextInputType?          keyboardType;
  final int                     maxLines;
  final bool                    enabled;
  final List<TextInputFormatter>? inputFormatters;

  const _Campo({
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled  = true,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:        controller,
      validator:         validator,
      keyboardType:      keyboardType,
      maxLines:          maxLines,
      enabled:           enabled,
      inputFormatters:   inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText:  hint,
        filled:    true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFF001E42), width: 1.8)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String               label;
  final String?              value;
  final List<String>         items;
  final void Function(String?) onChanged;
  final String? Function(String?)? validator;

  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value:     value,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled:    true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFF001E42), width: 1.8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
    );
  }
}

class _SelectorFecha extends StatelessWidget {
  final String    label;
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
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined,
              color: Color(0xFF64748B), size: 20),
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
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF0D9488), size: 18),
        ]),
      ),
    );
  }
}