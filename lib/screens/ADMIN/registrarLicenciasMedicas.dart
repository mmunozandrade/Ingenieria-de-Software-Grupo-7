import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class RegistrarLicenciasMedicas extends StatefulWidget {
  const RegistrarLicenciasMedicas({super.key});

  @override
  State<RegistrarLicenciasMedicas> createState() =>
      _RegistrarLicenciasMedicasState();
}

class _RegistrarLicenciasMedicasState extends State<RegistrarLicenciasMedicas> {
  // Busqueda de empleado
  final _busquedaController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  // Formulario
  final _tipoLicenciaController = TextEditingController(
    text: 'Licencia medica comun',
  );
  final _entidadEmisoraController = TextEditingController();
  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  bool _enviando = false;
  String _mensaje = '';
  bool _exito = false;

  // Historial
  List<dynamic> _licencias = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _tipoLicenciaController.dispose();
    _entidadEmisoraController.dispose();
    super.dispose();
  }

  int get _diasCalculados {
    if (_fechaInicio == null || _fechaFin == null) return 0;
    if (_fechaFin!.isBefore(_fechaInicio!)) return 0;
    return _fechaFin!.difference(_fechaInicio!).inDays + 1;
  }

  double? get _sueldoBaseSeleccionado {
    if (_empleadoSeleccionado == null) return null;
    final s = _empleadoSeleccionado!['sueldo_base'];
    if (s == null) return null;
    return (s as num).toDouble();
  }

  double get _descuentoCalculado {
    final sueldo = _sueldoBaseSeleccionado;
    if (sueldo == null || _diasCalculados == 0) return 0;
    return (sueldo / 30) * _diasCalculados;
  }

  Future<void> _buscarEmpleado(String texto) async {
    if (texto.trim().length < 3) {
      setState(() => _resultadosBusqueda = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse(
          '$_apiUrl/buscar-empleados?apellido=${Uri.encodeComponent(texto)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _resultadosBusqueda = data['empleados'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _buscando = false);
    }
  }

  void _seleccionarEmpleado(Map<String, dynamic> empleado) {
    setState(() {
      _empleadoSeleccionado = empleado;
      _resultadosBusqueda = [];
      _busquedaController.text =
          '${empleado['nombres']} ${empleado['apellidos']}';
    });
  }

  Future<void> _seleccionarFechaInicio() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF001E42)),
        ),
        child: child!,
      ),
    );
    if (fecha != null) {
      setState(() {
        _fechaInicio = fecha;
        if (_fechaFin != null && _fechaFin!.isBefore(fecha)) {
          _fechaFin = null;
        }
      });
    }
  }

  Future<void> _seleccionarFechaFin() async {
    if (_fechaInicio == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona primero la fecha de inicio';
      });
      return;
    }
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaInicio!,
      firstDate: _fechaInicio!,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF001E42)),
        ),
        child: child!,
      ),
    );
    if (fecha != null) {
      setState(() => _fechaFin = fecha);
    }
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/admin/licencias-medicas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _licencias = data['licencias'] ?? []);
      }
    } catch (_) {
      // silencioso
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _registrarLicencia() async {
    if (_empleadoSeleccionado == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona un trabajador';
      });
      return;
    }
    if (_fechaInicio == null || _fechaFin == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona la fecha de inicio y de fin';
      });
      return;
    }
    if (_fechaFin!.isBefore(_fechaInicio!)) {
      setState(() {
        _exito = false;
        _mensaje = 'La fecha de fin debe ser igual o posterior a la de inicio';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _mensaje = '';
    });

    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrl/admin/licencias-medicas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'persona_id': _empleadoSeleccionado!['id_empleado'],
          'fecha_inicio': _fechaInicio!.toIso8601String().split('T')[0],
          'fecha_fin': _fechaFin!.toIso8601String().split('T')[0],
          'tipo_de_licencia': _tipoLicenciaController.text.trim(),
          'entidad_emisora': _entidadEmisoraController.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Licencia registrada: ${data['dias_licencia']} dia(s), descuento de \$${data['descuento_proporcional']} CLP aplicado al periodo ${data['periodo']}'
            : (data['mensaje'] ?? 'Error al registrar la licencia');
      });
      if (_exito) {
        setState(() {
          _empleadoSeleccionado = null;
          _busquedaController.clear();
          _entidadEmisoraController.clear();
          _tipoLicenciaController.text = 'Licencia medica comun';
          _fechaInicio = null;
          _fechaFin = null;
        });
        _cargarHistorial();
      }
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _enviando = false);
    }
  }

  String _formatFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Licencias Médicas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                const Text(
                  'Nueva Licencia Médica',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'El descuento proporcional se calcula automaticamente: (sueldo base ÷ 30) × dias de licencia',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),

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
                      // Buscar trabajador
                      const Text(
                        'Trabajador:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _busquedaController,
                        onChanged: (v) {
                          _empleadoSeleccionado = null;
                          _buscarEmpleado(v);
                        },
                        decoration: InputDecoration(
                          hintText:
                              'Buscar por apellido (minimo 3 caracteres)...',
                          suffixIcon: _buscando
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      if (_resultadosBusqueda.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _resultadosBusqueda.length,
                            itemBuilder: (ctx, i) {
                              final e = _resultadosBusqueda[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  '${e['nombres']} ${e['apellidos']}',
                                ),
                                subtitle: Text('${e['rut']} · ${e['cargo']}'),
                                onTap: () => _seleccionarEmpleado(e),
                              );
                            },
                          ),
                        ),
                      if (_empleadoSeleccionado != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: Color(0xFF1D4ED8),
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} (${_empleadoSeleccionado!['rut']})'
                                  '${_sueldoBaseSeleccionado != null ? " · Sueldo base: \$${_sueldoBaseSeleccionado!.toStringAsFixed(0)}" : ""}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Tipo de licencia
                      const Text(
                        'Tipo de licencia:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _tipoLicenciaController,
                        maxLength: 50,
                        decoration: InputDecoration(
                          hintText: 'Ej: Licencia medica comun',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Entidad emisora
                      const Text(
                        'Entidad emisora (opcional):',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _entidadEmisoraController,
                        maxLength: 100,
                        decoration: InputDecoration(
                          hintText: 'Ej: Fonasa, Isapre Colmena...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Fechas
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Fecha de inicio:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: _seleccionarFechaInicio,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_month,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _fechaInicio == null
                                              ? 'Seleccionar...'
                                              : _formatFecha(_fechaInicio!),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _fechaInicio == null
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Fecha de fin:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: _seleccionarFechaFin,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFCBD5E1),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_month,
                                          size: 18,
                                          color: Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _fechaFin == null
                                              ? 'Seleccionar...'
                                              : _formatFecha(_fechaFin!),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _fechaFin == null
                                                ? const Color(0xFF94A3B8)
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Preview del calculo
                      if (_diasCalculados > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F3FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDDD6FE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dias de licencia: $_diasCalculados dia(s)',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF5B21B6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_sueldoBaseSeleccionado != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Descuento estimado: (\$${_sueldoBaseSeleccionado!.toStringAsFixed(0)} ÷ 30) × $_diasCalculados = \$${_descuentoCalculado.toStringAsFixed(0)} CLP',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF5B21B6),
                                  ),
                                ),
                              ] else
                                const Text(
                                  'Selecciona un trabajador con sueldo base activo para ver el descuento estimado',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 20),

                      if (_mensaje.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: _exito ? Colors.green[50] : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _exito
                                  ? Colors.green[200]!
                                  : Colors.red[200]!,
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

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _enviando ? null : _registrarLicencia,
                          icon: _enviando
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.medical_services_outlined,
                                  size: 18,
                                ),
                          label: const Text('Registrar Licencia'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF001E42),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                const Text(
                  'Historial de Licencias',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF001E42),
                  ),
                ),
                const SizedBox(height: 12),
                if (_cargandoHistorial)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_licencias.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Text(
                        'No hay licencias registradas',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  )
                else
                  ..._licencias.map(
                    (l) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                l['nombre_trabajador'] ?? '—',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '\$${l['descuento_proporcional']} CLP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${l['rut']} · ${l['tipo_de_licencia']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                          Text(
                            '${l['fecha_inicio']} - ${l['fecha_fin']} (${l['dias_licencia']} dias) · Periodo: ${l['periodo']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            'Registrado por: ${l['nombre_admin']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
