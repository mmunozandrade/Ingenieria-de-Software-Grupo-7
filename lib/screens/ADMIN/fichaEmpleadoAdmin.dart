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

class FichaEmpleadoAdmin extends StatefulWidget {
  final Map<String, dynamic> empleado;
  const FichaEmpleadoAdmin({super.key, required this.empleado});

  @override
  State<FichaEmpleadoAdmin> createState() => _FichaEmpleadoAdminState();
}

class _FichaEmpleadoAdminState extends State<FichaEmpleadoAdmin> {
  final _mesesCtrl = TextEditingController();
  String? _afpSeleccionada;

  // Certificado PDF
  String?    _nombreCertificado;
  Uint8List? _certificadoBytes;

  bool   _guardando = false;
  String _mensaje   = '';
  bool   _exito     = false;

  // Datos calculados
  int _mesesClinica       = 0;
  int _totalMeses         = 0;
  bool _cumpleProgresivos = false;

  @override
  void initState() {
    super.initState();
    final previos = widget.empleado['meses_cotizados_previos'] ?? 0;
    _mesesCtrl.text = previos.toString();
    _afpSeleccionada = widget.empleado['afp'];
    // Si la AFP guardada no esta en la lista la dejamos null
    if (_afpSeleccionada != null && !_afpListAdmin.contains(_afpSeleccionada)) {
      _afpSeleccionada = null;
    }
    _calcularMeses();
  }

  @override
  void dispose() {
    _mesesCtrl.dispose();
    super.dispose();
  }

  void _calcularMeses() {
    final fechaIngresoStr = widget.empleado['fecha_ingreso'];
    if (fechaIngresoStr != null) {
      try {
        // fecha_ingreso viene como dd/mm/yyyy desde la BD
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
        int meses = (hoy.year - fechaIngreso.year) * 12 +
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

  Future<void> _seleccionarCertificado() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (resultado == null) return;

    final archivo = resultado.files.single;
    if ((archivo.size) > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El certificado no puede superar 5 MB'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() {
      _nombreCertificado = archivo.name;
      _certificadoBytes  = archivo.bytes;
    });
  }

  Future<void> _guardar() async {
    final meses = int.tryParse(_mesesCtrl.text.trim());
    if (meses == null || meses < 0 || meses > 600) {
      setState(() {
        _exito   = false;
        _mensaje = 'Los meses deben ser un numero entre 0 y 600';
      });
      return;
    }
    if (_afpSeleccionada == null) {
      setState(() {
        _exito   = false;
        _mensaje = 'Debes seleccionar la AFP del trabajador';
      });
      return;
    }
    if (_certificadoBytes == null &&
        (widget.empleado['meses_cotizados_previos'] ?? 0) == 0 &&
        meses > 0) {
      setState(() {
        _exito   = false;
        _mensaje = 'Debes adjuntar el certificado AFP para registrar meses previos';
      });
      return;
    }

    setState(() { _guardando = true; _mensaje = ''; });

    try {
      final token   = await SessionService.obtenerToken();
      final idEmple = widget.empleado['id_empleado'];

      // Si hay certificado PDF, subirlo primero
      if (_certificadoBytes != null) {
        final reqPdf = http.MultipartRequest(
          'POST',
          Uri.parse('$_apiUrlFichaAdmin/empleados/$idEmple/certificado-afp'),
        );
        reqPdf.headers['Authorization'] = 'Bearer $token';
        reqPdf.files.add(http.MultipartFile.fromBytes(
          'certificado',
          _certificadoBytes!,
          filename: _nombreCertificado ?? 'certificado_afp.pdf',
        ));
        await reqPdf.send();
      }

      // Actualizar meses y AFP
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
        _exito   = data['success'] == true;
        _mensaje = _exito
            ? 'Datos actualizados correctamente'
            : data['mensaje'] ?? 'Error al guardar';
      });

      if (_exito) _calcularMeses();
    } catch (e) {
      setState(() {
        _exito   = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
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
              color: Colors.white, fontWeight: FontWeight.bold),
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

                // Datos del empleado (solo lectura)
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
                      const Text('Datos del Trabajador',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF001E42))),
                      const Divider(height: 20),
                      _FilaDato(label: 'Nombre', valor: '${e['nombres'] ?? ''} ${e['apellidos'] ?? ''}'),
                      _FilaDato(label: 'Cargo',  valor: e['cargo'] ?? '—'),
                      _FilaDato(label: 'Ingreso', valor: e['fecha_ingreso'] ?? '—'),
                      _FilaDato(label: 'Contrato', valor: e['tipo_contrato'] ?? '—'),
                      _FilaDato(
                        label: 'Meses en la clinica',
                        valor: '$_mesesClinica meses (${_mesesClinica ~/ 12} anos)',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Seccion cotizaciones previas
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
                      const Row(children: [
                        Icon(Icons.history_edu_outlined,
                            color: Color(0xFF001E42), size: 20),
                        SizedBox(width: 8),
                        Text('Cotizaciones Previas (Art. 68)',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42))),
                      ]),
                      const Divider(height: 20),
                      const Text(
                        'Ingresa los meses cotizados antes de ingresar a la clinica, segun certificado AFP.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 16),

                      // Campo meses
                      TextFormField(
                        controller: _mesesCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() => _calcularMeses()),
                        decoration: InputDecoration(
                          labelText: 'Meses de cotizaciones previas *',
                          hintText: 'Ej: 48 (equivale a 4 anos)',
                          helperText: 'Numero entero entre 0 y 600',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFF001E42), width: 1.8)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Calculo en tiempo real
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
                        child: Column(children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Meses previos (max 120):',
                                  style: TextStyle(fontSize: 13)),
                              Text(
                                '${(int.tryParse(_mesesCtrl.text) ?? 0).clamp(0, 120)} meses',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Meses en la clinica:',
                                  style: TextStyle(fontSize: 13)),
                              Text('$_mesesClinica meses',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                              Text('$_totalMeses meses',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
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
                                    : 'No cumple 120 meses aun — faltan ${120 - _totalMeses} meses para dias progresivos',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _cumpleProgresivos
                                      ? const Color(0xFF0D9488)
                                      : const Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 16),

                      // Subir certificado AFP
                      const Text('Certificado AFP (PDF, max 5 MB) *',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF475569))),
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
                          child: Row(children: [
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
                              const Icon(Icons.check_circle_outline,
                                  color: Color(0xFF0D9488), size: 18),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Seccion AFP
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
                      const Row(children: [
                        Icon(Icons.account_balance_outlined,
                            color: Color(0xFF001E42), size: 20),
                        SizedBox(width: 8),
                        Text('AFP del Trabajador',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF001E42))),
                      ]),
                      const Divider(height: 20),
                      DropdownButtonFormField<String>(
                        value: _afpSeleccionada,
                        decoration: InputDecoration(
                          labelText: 'AFP *',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Color(0xFF001E42), width: 1.8)),
                        ),
                        items: _afpListAdmin
                            .map((a) => DropdownMenuItem(
                                value: a, child: Text(a)))
                            .toList(),
                        onChanged: (v) => setState(() => _afpSeleccionada = v),
                        validator: (v) =>
                            v == null ? 'Selecciona una AFP' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Mensaje
                if (_mensaje.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _exito ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            _exito ? Colors.green[200]! : Colors.red[200]!,
                      ),
                    ),
                    child: Row(children: [
                      Icon(
                        _exito
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: _exito ? Colors.green : Colors.red,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_mensaje,
                            style: TextStyle(
                                color: _exito ? Colors.green : Colors.red,
                                fontSize: 13)),
                      ),
                    ]),
                  ),

                // Boton guardar
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
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _guardando ? 'Guardando...' : 'Guardar Cambios',
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
    );
  }
}

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
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A))),
          ),
        ],
      ),
    );
  }
}