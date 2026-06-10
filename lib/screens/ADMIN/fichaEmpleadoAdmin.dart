import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlFichaAdmin = 'http://127.0.0.1:8000';

const List<String> _afpListAdmin = [
  'AFP Capital',
  'AFP Cuprum',
  'AFP Habitat',
  'AFP PlanVital',
  'AFP ProVida',
  'AFP Modelo',
  'AFP Uno',
];

const List<String> _rolesDisponibles = ['usuario', 'jefe'];

const List<String> _tiposContrato = ['Indefinido', 'Plazo fijo', 'Por obra'];
const List<String> _institucionesSalud = ['Fonasa', 'Isapre'];
const int _salarioMinimo = 500000;

class FichaEmpleadoAdmin extends StatefulWidget {
  final Map<String, dynamic> empleado;
  const FichaEmpleadoAdmin({super.key, required this.empleado});

  @override
  State<FichaEmpleadoAdmin> createState() => _FichaEmpleadoAdminState();
}

class _FichaEmpleadoAdminState extends State<FichaEmpleadoAdmin> {
  // ── Cotizaciones / AFP ────────────────────────────────────
  final _mesesCtrl = TextEditingController();
  String? _afpSeleccionada;
  String? _rolSeleccionado;
  String? _nombreCertificado;
  Uint8List? _certificadoBytes;
  bool _guardando = false;
  bool _guardandoRol = false;
  String _mensaje = '';
  bool _exito = false;
  String _mensajeRol = '';
  bool _exitoRol = false;
  int _mesesClinica = 0;
  int _totalMeses = 0;
  bool _cumpleProgresivos = false;

  // ── Formulario edicion desplegable ────────────────────────
  bool _formularioVisible = false;
  bool _guardandoEdicion = false;
  String _mensajeEdicion = '';
  bool _exitoEdicion = false;

  final _primerNombreCtrl = TextEditingController();
  final _segundoNombreCtrl = TextEditingController();
  final _apPaternoCtrl = TextEditingController();
  final _apMaternoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _cargoCtrl = TextEditingController();
  final _sueldoCtrl = TextEditingController();
  final _discapacidadCtrl = TextEditingController();
  String? _saludEdicion;
  String? _tipoContratoEdicion;
  DateTime? _fechaIngresoEdicion;
  DateTime? _fechaNacimientoEdicion;

  @override
  void initState() {
    super.initState();
    final previos = widget.empleado['meses_cotizados_previos'] ?? 0;
    _mesesCtrl.text = previos.toString();
    _afpSeleccionada = widget.empleado['afp'];
    if (_afpSeleccionada != null && !_afpListAdmin.contains(_afpSeleccionada)) {
      _afpSeleccionada = null;
    }
    _rolSeleccionado = null; // Inicia vacío — Excepción 1
    _calcularMeses();
  }

  @override
  void dispose() {
    _mesesCtrl.dispose();
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

  void _calcularMeses() {
    final fechaIngresoStr = widget.empleado['fecha_ingreso'];
    if (fechaIngresoStr != null) {
      try {
        final partes = fechaIngresoStr.split('/');
        DateTime fechaIngreso;
        if (partes.length == 3) {
          fechaIngreso = DateTime(
            int.parse(partes[2]),
            int.parse(partes[1]),
            int.parse(partes[0]),
          );
        } else {
          fechaIngreso = DateTime.parse(fechaIngresoStr);
        }
        final hoy = DateTime.now();
        int meses =
            (hoy.year - fechaIngreso.year) * 12 +
            (hoy.month - fechaIngreso.month);
        if (hoy.day < fechaIngreso.day) meses--;
        _mesesClinica = meses < 0 ? 0 : meses;
      } catch (_) {
        _mesesClinica = 0;
      }
    }
    final previos = int.tryParse(_mesesCtrl.text) ?? 0;
    final limitados = previos.clamp(0, 120);
    _totalMeses = limitados + _mesesClinica;
    _cumpleProgresivos = _totalMeses >= 120;
  }

  // ── Prellenar formulario edicion ──────────────────────────
  void _abrirFormulario() {
    final e = widget.empleado;
    final salud = (e['tipo_salud'] ?? e['institucion_salud'] ?? '')
        .toString()
        .trim();
    final contrato = e['tipo_contrato'] ?? '';
    _primerNombreCtrl.text = e['primer_nombre'] ?? '';
    _segundoNombreCtrl.text = e['segundo_nombre'] ?? '';
    _apPaternoCtrl.text = e['apellido_paterno'] ?? '';
    _apMaternoCtrl.text = e['apellido_materno'] ?? '';
    _telefonoCtrl.text = e['telefono'] ?? '';
    _direccionCtrl.text = e['direccion'] ?? '';
    _cargoCtrl.text = e['cargo'] ?? '';
    _sueldoCtrl.text = e['sueldo_base']?.toString() ?? '';
    _discapacidadCtrl.text = e['discapacidad'] ?? '';
    _saludEdicion = _institucionesSalud.contains(salud) ? salud : null;
    _tipoContratoEdicion = _tiposContrato.contains(contrato) ? contrato : null;
    if (e['fecha_ingreso'] != null) {
      final p = (e['fecha_ingreso'] as String).split('/');
      if (p.length == 3)
        _fechaIngresoEdicion = DateTime(
          int.parse(p[2]),
          int.parse(p[1]),
          int.parse(p[0]),
        );
    }
    if (e['fecha_nacimiento'] != null) {
      _fechaNacimientoEdicion = DateTime.tryParse(e['fecha_nacimiento']);
    }
    setState(() {
      _formularioVisible = true;
      _mensajeEdicion = '';
    });
  }

  void _cerrarFormulario() => setState(() {
    _formularioVisible = false;
    _mensajeEdicion = '';
  });

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  int? _calcularEdad() {
    if (_fechaNacimientoEdicion == null) return null;
    final hoy = DateTime.now();
    int edad = hoy.year - _fechaNacimientoEdicion!.year;
    if (hoy.month < _fechaNacimientoEdicion!.month ||
        (hoy.month == _fechaNacimientoEdicion!.month &&
            hoy.day < _fechaNacimientoEdicion!.day))
      edad--;
    return edad;
  }

  Future<void> _seleccionarCertificado() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (resultado == null) return;
    final archivo = resultado.files.single;
    if ((archivo.size) > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El certificado no puede superar 5 MB'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() {
      _nombreCertificado = archivo.name;
      _certificadoBytes = archivo.bytes;
    });
  }

  // ── Guardar AFP/Cotizaciones ──────────────────────────────
  Future<void> _guardar() async {
    final meses = int.tryParse(_mesesCtrl.text.trim());
    if (meses == null || meses < 0 || meses > 600) {
      setState(() {
        _exito = false;
        _mensaje = 'Los meses deben ser un numero entre 0 y 600';
      });
      return;
    }
    if (_afpSeleccionada == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Debes seleccionar la AFP del trabajador';
      });
      return;
    }
    if (_certificadoBytes == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Debes adjuntar el certificado AFP en formato PDF';
      });
      return;
    }
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final idEmple = widget.empleado['id_empleado'];
      if (_certificadoBytes != null) {
        final reqPdf = http.MultipartRequest(
          'POST',
          Uri.parse('$_apiUrlFichaAdmin/empleados/$idEmple/certificado-afp'),
        );
        reqPdf.headers['Authorization'] = 'Bearer $token';
        reqPdf.files.add(
          http.MultipartFile.fromBytes(
            'certificado',
            _certificadoBytes!,
            filename: _nombreCertificado ?? 'certificado_afp.pdf',
          ),
        );
        await reqPdf.send();
      }
      final response = await http.put(
        Uri.parse('$_apiUrlFichaAdmin/empleados/$idEmple/cotizaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'meses_cotizados_previos': meses,
          'afp': _afpSeleccionada,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Datos actualizados correctamente'
            : data['mensaje'] ?? 'Error al guardar';
      });
      if (_exito) _calcularMeses();
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
    }
  }

  // ── Guardar Rol ───────────────────────────────────────────
  Future<void> _guardarRol() async {
    if (_rolSeleccionado == null) {
      setState(() {
        _exitoRol = false;
        _mensajeRol = 'Debes seleccionar un rol';
      });
      return;
    }
    setState(() {
      _guardandoRol = true;
      _mensajeRol = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final idEmple = widget.empleado['id_empleado'];
      final response = await http.put(
        Uri.parse('$_apiUrlFichaAdmin/empleados/$idEmple/rol'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'rol': _rolSeleccionado}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoRol = data['success'] == true;
        _mensajeRol = _exitoRol
            ? 'Rol actualizado correctamente a "$_rolSeleccionado"'
            : data['mensaje'] ?? 'Error al actualizar rol';
      });
    } catch (_) {
      setState(() {
        _exitoRol = false;
        _mensajeRol = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardandoRol = false);
    }
  }

  // ── Guardar edicion datos personales ─────────────────────
  Future<void> _guardarEdicion() async {
    if (_primerNombreCtrl.text.trim().isEmpty ||
        _apPaternoCtrl.text.trim().isEmpty) {
      setState(() {
        _exitoEdicion = false;
        _mensajeEdicion = 'Nombre y apellido paterno son obligatorios';
      });
      return;
    }
    if (_sueldoCtrl.text.trim().isNotEmpty) {
      final sueldo = int.tryParse(_sueldoCtrl.text.trim());
      if (sueldo == null || sueldo < _salarioMinimo) {
        setState(() {
          _exitoEdicion = false;
          _mensajeEdicion =
              'El sueldo no puede ser menor al salario minimo (\$$_salarioMinimo)';
        });
        return;
      }
    }
    setState(() {
      _guardandoEdicion = true;
      _mensajeEdicion = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final idEmple = widget.empleado['id_empleado'];
      final body = {
        'rut': widget.empleado['rut'] ?? '',
        'primer_nombre': _primerNombreCtrl.text.trim(),
        'segundo_nombre': _segundoNombreCtrl.text.trim(),
        'apellido_paterno': _apPaternoCtrl.text.trim(),
        'apellido_materno': _apMaternoCtrl.text.trim(),
        'correo': widget.empleado['correo'] ?? '',
        'telefono': _telefonoCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        'tipo_salud':
            _saludEdicion ?? widget.empleado['tipo_salud'] ?? 'Fonasa',
        'afp': _afpSeleccionada ?? widget.empleado['afp'] ?? 'AFP Capital',
        'cargo': _cargoCtrl.text.trim(),
        'tipo_contrato':
            _tipoContratoEdicion ??
            widget.empleado['tipo_contrato'] ??
            'Indefinido',
        'fecha_ingreso': _fechaIngresoEdicion != null
            ? _fechaIngresoEdicion!.toIso8601String().split('T')[0]
            : widget.empleado['fecha_ingreso'] ?? '',
        'sueldo_base':
            int.tryParse(_sueldoCtrl.text.trim()) ??
            widget.empleado['sueldo_base'] ??
            _salarioMinimo,
        'discapacidad': _discapacidadCtrl.text.trim(),
        if (_fechaNacimientoEdicion != null)
          'fecha_nacimiento': _fechaNacimientoEdicion!.toIso8601String().split(
            'T',
          )[0],
      };
      final response = await http.put(
        Uri.parse('$_apiUrlFichaAdmin/empleados/$idEmple'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exitoEdicion = data['success'] == true;
        _mensajeEdicion = _exitoEdicion
            ? 'Datos actualizados correctamente'
            : data['mensaje'] ?? 'Error';
      });
      if (_exitoEdicion) {
        await Future.delayed(const Duration(seconds: 1));
        _cerrarFormulario();
      }
    } catch (_) {
      setState(() {
        _exitoEdicion = false;
        _mensajeEdicion = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardandoEdicion = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.empleado;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${e['nombres'] ?? ''} ${e['apellidos'] ?? ''}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Datos del empleado (solo lectura) ──────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Datos del Trabajador',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF001E42),
                        ),
                      ),
                      const Divider(height: 20),
                      _FilaDato(
                        label: 'Nombre',
                        valor: '${e['nombres'] ?? ''} ${e['apellidos'] ?? ''}',
                      ),
                      _FilaDato(label: 'RUT', valor: e['rut'] ?? '—'),
                      _FilaDato(label: 'Cargo', valor: e['cargo'] ?? '—'),
                      _FilaDato(label: 'Correo', valor: e['correo'] ?? '—'),
                      _FilaDato(label: 'Telefono', valor: e['telefono'] ?? '—'),
                      _FilaDato(
                        label: 'Direccion',
                        valor: e['direccion'] ?? '—',
                      ),
                      _FilaDato(label: 'Salud', valor: e['tipo_salud'] ?? '—'),
                      _FilaDato(
                        label: 'Contrato',
                        valor: e['tipo_contrato'] ?? '—',
                      ),
                      _FilaDato(
                        label: 'Sueldo',
                        valor: e['sueldo_base'] != null
                            ? '\$${e['sueldo_base']}'
                            : '—',
                      ),
                      _FilaDato(
                        label: 'Ingreso',
                        valor: e['fecha_ingreso'] ?? '—',
                      ),
                      _FilaDato(
                        label: 'Meses en la clinica',
                        valor:
                            '$_mesesClinica meses (${_mesesClinica ~/ 12} anos)',
                      ),
                      const SizedBox(height: 16),

                      // Boton ingresar informacion
                      if (!_formularioVisible)
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _abrirFormulario,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text(
                              'Ingresar informacion al usuario',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF001E42),
                              side: const BorderSide(color: Color(0xFF001E42)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),

                      // Formulario desplegable
                      if (_formularioVisible) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Editar Informacion',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                color: Color(0xFF64748B),
                              ),
                              onPressed: _cerrarFormulario,
                              tooltip: 'Cerrar formulario',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Nombres
                        Row(
                          children: [
                            Expanded(
                              child: _CampoEdicion(
                                label: 'Primer nombre *',
                                controller: _primerNombreCtrl,
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Obligatorio';
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
                              child: _CampoEdicion(
                                label: 'Segundo nombre',
                                controller: _segundoNombreCtrl,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CampoEdicion(
                                label: 'Apellido paterno *',
                                controller: _apPaternoCtrl,
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Obligatorio';
                                  if (v.length < 2 || v.length > 30)
                                    return 'Entre 2 y 30 caracteres';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _CampoEdicion(
                                label: 'Apellido materno *',
                                controller: _apMaternoCtrl,
                                validator: (v) {
                                  if (v == null || v.isEmpty)
                                    return 'Obligatorio';
                                  if (v.length < 2 || v.length > 30)
                                    return 'Entre 2 y 30 caracteres';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Contacto
                        _CampoEdicion(
                          label: 'Telefono (+56 9 XXXX XXXX)',
                          controller: _telefonoCtrl,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        _CampoEdicion(
                          label: 'Direccion',
                          controller: _direccionCtrl,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),

                        // Cargo y sueldo
                        _CampoEdicion(label: 'Cargo *', controller: _cargoCtrl),
                        const SizedBox(height: 12),
                        _CampoEdicion(
                          label: 'Sueldo base (CLP)',
                          controller: _sueldoCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Salud
                        DropdownButtonFormField<String>(
                          value: _saludEdicion,
                          decoration: _dropDeco('Institucion de salud'),
                          items: _institucionesSalud
                              .map(
                                (s) =>
                                    DropdownMenuItem(value: s, child: Text(s)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _saludEdicion = v),
                        ),
                        const SizedBox(height: 12),

                        // Tipo contrato
                        DropdownButtonFormField<String>(
                          value: _tipoContratoEdicion,
                          decoration: _dropDeco('Tipo de contrato'),
                          items: _tiposContrato
                              .map(
                                (t) =>
                                    DropdownMenuItem(value: t, child: Text(t)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _tipoContratoEdicion = v),
                        ),
                        const SizedBox(height: 12),

                        // Fecha ingreso
                        _SelectorFechaEdicion(
                          label: 'Fecha de ingreso',
                          fecha: _fechaIngresoEdicion,
                          onTap: () async {
                            final f = await showDatePicker(
                              context: context,
                              initialDate:
                                  _fechaIngresoEdicion ?? DateTime.now(),
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
                            if (f != null)
                              setState(() => _fechaIngresoEdicion = f);
                          },
                        ),
                        const SizedBox(height: 12),

                        // Fecha nacimiento
                        _SelectorFechaEdicion(
                          label: 'Fecha de nacimiento (opcional)',
                          fecha: _fechaNacimientoEdicion,
                          onTap: () async {
                            final hoy = DateTime.now();
                            final limite = DateTime(
                              hoy.year - 18,
                              hoy.month,
                              hoy.day,
                            );
                            final f = await showDatePicker(
                              context: context,
                              initialDate: _fechaNacimientoEdicion ?? limite,
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
                            if (f != null)
                              setState(() => _fechaNacimientoEdicion = f);
                          },
                        ),
                        if (_fechaNacimientoEdicion != null) ...[
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

                        // Discapacidad
                        _CampoEdicion(
                          label:
                              'Informacion discapacidad (Ley 20.422) — opcional',
                          controller: _discapacidadCtrl,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 20),

                        // Mensaje edicion
                        if (_mensajeEdicion.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: _exitoEdicion
                                  ? Colors.green[50]
                                  : Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _exitoEdicion
                                    ? Colors.green[200]!
                                    : Colors.red[200]!,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _exitoEdicion
                                      ? Icons.check_circle_outline
                                      : Icons.error_outline,
                                  color: _exitoEdicion
                                      ? Colors.green
                                      : Colors.red,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _mensajeEdicion,
                                    style: TextStyle(
                                      color: _exitoEdicion
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Botones
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _guardandoEdicion
                                      ? null
                                      : _guardarEdicion,
                                  icon: _guardandoEdicion
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(
                                    _guardandoEdicion
                                        ? 'Guardando...'
                                        : 'Guardar Cambios',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF001E42),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              height: 48,
                              child: OutlinedButton(
                                onPressed: _cerrarFormulario,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF64748B),
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Cotizaciones previas ───────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.history_edu_outlined,
                            color: Color(0xFF001E42),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Cotizaciones Previas (Art. 68)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      const Text(
                        'Ingresa los meses cotizados antes de ingresar a la clinica, segun certificado AFP.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _mesesCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() => _calcularMeses()),
                        decoration: InputDecoration(
                          labelText: 'Meses de cotizaciones previas *',
                          hintText: 'Ej: 48 (equivale a 4 anos)',
                          helperText: 'Numero entero entre 0 y 600',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF001E42),
                              width: 1.8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _cumpleProgresivos
                              ? const Color(0xFFE6FFFB)
                              : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _cumpleProgresivos
                                ? const Color(0xFF5EEAD4)
                                : const Color(0xFFFBBF24),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Meses previos (max 120):',
                                  style: TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '${(int.tryParse(_mesesCtrl.text) ?? 0).clamp(0, 120)} meses',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Meses en la clinica:',
                                  style: TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '$_mesesClinica meses',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  '$_totalMeses meses',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  _cumpleProgresivos
                                      ? Icons.check_circle_outline
                                      : Icons.info_outline,
                                  color: _cumpleProgresivos
                                      ? const Color(0xFF0D9488)
                                      : const Color(0xFFF59E0B),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _cumpleProgresivos
                                        ? 'Cumple 120 meses — tiene derecho a dias progresivos (Art. 68)'
                                        : 'No cumple 120 meses aun — faltan ${120 - _totalMeses} meses',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _cumpleProgresivos
                                          ? const Color(0xFF0D9488)
                                          : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Certificado AFP (PDF, max 5 MB)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _seleccionarCertificado,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _certificadoBytes != null
                                ? const Color(0xFFE6FFFB)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _certificadoBytes != null
                                  ? const Color(0xFF5EEAD4)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _certificadoBytes != null
                                    ? Icons.picture_as_pdf
                                    : Icons.upload_file_outlined,
                                color: _certificadoBytes != null
                                    ? const Color(0xFF0D9488)
                                    : const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _certificadoBytes != null
                                      ? _nombreCertificado!
                                      : 'Haz clic para subir el certificado AFP',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _certificadoBytes != null
                                        ? const Color(0xFF0D9488)
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              if (_certificadoBytes != null)
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF0D9488),
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── AFP ───────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.account_balance_outlined,
                            color: Color(0xFF001E42),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'AFP del Trabajador',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      DropdownButtonFormField<String>(
                        value: _afpSeleccionada,
                        decoration: InputDecoration(
                          labelText: 'AFP *',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF001E42),
                              width: 1.8,
                            ),
                          ),
                        ),
                        items: _afpListAdmin
                            .map(
                              (a) => DropdownMenuItem(value: a, child: Text(a)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _afpSeleccionada = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Mensaje AFP/Cotizaciones
                if (_mensaje.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _exito ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
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
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mensaje,
                            style: TextStyle(
                              color: _exito ? Colors.green : Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Boton guardar AFP
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
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _guardando
                          ? 'Guardando...'
                          : 'Guardar AFP y Cotizaciones',
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
                const SizedBox(height: 24),

                // ── Asignacion de Rol ─────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.manage_accounts_outlined,
                            color: Color(0xFF001E42),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Asignacion de Rol',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Roles disponibles:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              '• Jefe: puede ver informacion de su area.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '• Usuario: solo ve su propia informacion.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _rolSeleccionado,
                        decoration: InputDecoration(
                          labelText: 'Rol del trabajador *',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF001E42),
                              width: 1.8,
                            ),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'usuario',
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.person_outline,
                                  size: 18,
                                  color: Color(0xFF2563EB),
                                ),
                                SizedBox(width: 8),
                                Text('Usuario'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'jefe',
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.supervisor_account_outlined,
                                  size: 18,
                                  color: Color(0xFF9333EA),
                                ),
                                SizedBox(width: 8),
                                Text('Jefe'),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _rolSeleccionado = v),
                      ),
                      const SizedBox(height: 16),
                      if (_mensajeRol.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _exitoRol
                                ? Colors.green[50]
                                : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _exitoRol
                                  ? Colors.green[200]!
                                  : Colors.red[200]!,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _exitoRol
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                color: _exitoRol ? Colors.green : Colors.red,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _mensajeRol,
                                  style: TextStyle(
                                    color: _exitoRol
                                        ? Colors.green
                                        : Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _guardandoRol ? null : _guardarRol,
                          icon: _guardandoRol
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.manage_accounts_outlined),
                          label: Text(
                            _guardandoRol ? 'Guardando...' : 'Guardar Rol',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D4ED8),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dropDeco(String label) => InputDecoration(
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
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

// ── Widgets auxiliares ────────────────────────────────────────

class _FilaDato extends StatelessWidget {
  final String label;
  final String valor;
  const _FilaDato({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoEdicion extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;

  const _CampoEdicion({
    required this.label,
    required this.controller,
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

class _SelectorFechaEdicion extends StatelessWidget {
  final String label;
  final DateTime? fecha;
  final VoidCallback onTap;
  const _SelectorFechaEdicion({
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
