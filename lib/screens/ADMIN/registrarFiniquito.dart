import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlFin = 'http://127.0.0.1:8000';

const Map<String, String> _causalesFiniquito = {
  '159-1': 'Art. 159 N°1 - Mutuo acuerdo de las partes',
  '159-2': 'Art. 159 N°2 - Renuncia voluntaria del trabajador',
  '159-3': 'Art. 159 N°3 - Muerte del trabajador',
  '159-4': 'Art. 159 N°4 - Vencimiento del plazo convenido',
  '159-5': 'Art. 159 N°5 - Conclusión del trabajo o servicio',
  '160': 'Art. 160 - Causal imputable al trabajador',
  '161': 'Art. 161 - Necesidades de la empresa',
};

/// Requisito 1 de Finiquito: registrar la fecha de termino y causal,
/// calcular el desglose (Paso 1, sin guardar nada), revisarlo, y
/// recien ahi aprobar (Paso 2, que guarda definitivamente).
class RegistrarFiniquitoScreen extends StatefulWidget {
  const RegistrarFiniquitoScreen({super.key});

  @override
  State<RegistrarFiniquitoScreen> createState() =>
      _RegistrarFiniquitoScreenState();
}

class _RegistrarFiniquitoScreenState extends State<RegistrarFiniquitoScreen> {
  final _busquedaController = TextEditingController();
  final _montoVoluntarioController = TextEditingController();
  List<dynamic> _resultadosBusqueda = [];
  Map<String, dynamic>? _empleadoSeleccionado;
  bool _buscando = false;

  DateTime? _fechaTermino;
  String? _causalSeleccionada;
  bool _avisoPrevioDado = true;
  final List<Map<String, dynamic>> _descuentosManuales = [];

  bool _calculando = false;
  bool _aprobando = false;
  String _error = '';
  Map<String, dynamic>? _desglose;

  @override
  void dispose() {
    _busquedaController.dispose();
    _montoVoluntarioController.dispose();
    super.dispose();
  }

  Future<void> _buscarEmpleado(String texto) async {
    if (texto.trim().length < 3) {
      setState(() => _resultadosBusqueda = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final token = await SessionService.obtenerToken();
      // Si el texto contiene un guion (formato tipico de RUT, ej.
      // "12345678-9"), se busca por RUT; si no, por apellido.
      final pareceRut = texto.contains('-');
      final parametro = pareceRut ? 'rut' : 'apellido';
      final response = await http.get(
        Uri.parse(
          '$_apiUrlFin/buscar-empleados?$parametro=${Uri.encodeComponent(texto.trim())}',
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
    } finally {
      setState(() => _buscando = false);
    }
  }

  void _seleccionarEmpleado(Map<String, dynamic> e) {
    setState(() {
      _empleadoSeleccionado = e;
      _resultadosBusqueda = [];
      _busquedaController.text = '${e['nombres']} ${e['apellidos']}';
      _desglose = null;
      _error = '';
    });
  }

  Future<void> _seleccionarFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF001E42)),
          ),
          child: child!,
        );
      },
    );
    if (fecha != null) {
      setState(() {
        _fechaTermino = fecha;
        _desglose = null;
      });
    }
  }

  Future<void> _agregarDescuento() async {
    final conceptoCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Agregar descuento'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: conceptoCtrl,
              decoration: const InputDecoration(
                labelText: 'Concepto',
                hintText: 'Ej: Préstamo interno pendiente',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: montoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monto (CLP)',
                prefixText: '\$ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final concepto = conceptoCtrl.text.trim();
              final monto = int.tryParse(
                montoCtrl.text.replaceAll('.', '').trim(),
              );
              if (concepto.isEmpty || monto == null || monto < 0) return;
              Navigator.pop(ctx, {'concepto': concepto, 'monto': monto});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              foregroundColor: Colors.white,
            ),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (resultado != null) {
      setState(() {
        _descuentosManuales.add(resultado);
        _desglose = null;
      });
    }
  }

  Map<String, dynamic> _armarBody() {
    final fechaStr =
        '${_fechaTermino!.year}-${_fechaTermino!.month.toString().padLeft(2, '0')}-${_fechaTermino!.day.toString().padLeft(2, '0')}';
    final montoVoluntario =
        int.tryParse(
          _montoVoluntarioController.text.replaceAll('.', '').trim(),
        ) ??
        0;
    return {
      'persona_id': _empleadoSeleccionado!['id_empleado'],
      'fecha_termino': fechaStr,
      'causal_codigo': _causalSeleccionada,
      'aviso_previo_dado': _causalSeleccionada == '161'
          ? _avisoPrevioDado
          : true,
      'monto_indemnizacion_voluntaria':
          (_causalSeleccionada == '159-1' || _causalSeleccionada == '159-3')
          ? montoVoluntario
          : 0,
      'descuentos_manuales': _descuentosManuales,
    };
  }

  Future<void> _calcular() async {
    setState(() {
      _calculando = true;
      _error = '';
      _desglose = null;
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrlFin/admin/finiquito/calcular'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(_armarBody()),
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _desglose = data);
      } else {
        setState(
          () => _error = data['mensaje'] ?? 'Error al calcular el finiquito',
        );
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _calculando = false);
    }
  }

  Future<void> _descargarPdfFiniquito(int documentoId, String? token) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrlFin/admin/documentos/$documentoId/descargar'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200 &&
          response.headers['content-type']?.contains('json') != true) {
        final blob = html.Blob([response.bodyBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: url)
          ..setAttribute('download', 'finiquito_$documentoId.pdf')
          ..click();
        html.Url.revokeObjectUrl(url);
      }
    } catch (_) {
      // si la descarga automatica falla, el PDF sigue disponible
      // igual en la seccion "Documentos" del perfil del trabajador
    }
  }

  Future<void> _aprobar() async {
    setState(() {
      _aprobando = true;
      _error = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrlFin/admin/finiquito/aprobar'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(_armarBody()),
      );
      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['mensaje'] ?? 'Finiquito aprobado'),
            backgroundColor: Colors.green,
          ),
        );
        if (data['documento_id'] != null) {
          await _descargarPdfFiniquito(data['documento_id'], token);
        }
        Navigator.pop(context);
      } else {
        setState(
          () => _error = data['mensaje'] ?? 'Error al aprobar el finiquito',
        );
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _aprobando = false);
    }
  }

  String _formatearMiles(dynamic valor) {
    final soloDigitos = valor.toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) return '0';
    final buffer = StringBuffer();
    for (int i = 0; i < soloDigitos.length; i++) {
      final posicionDesdeDerecha = soloDigitos.length - i;
      buffer.write(soloDigitos[i]);
      if (posicionDesdeDerecha > 1 && posicionDesdeDerecha % 3 == 1)
        buffer.write('.');
    }
    return buffer.toString();
  }

  bool get _puedeCalcular =>
      _empleadoSeleccionado != null &&
      _fechaTermino != null &&
      _causalSeleccionada != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Registrar Finiquito',
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
                              'Buscar por apellido o RUT (mínimo 3 caracteres)...',
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
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Seleccionado: ${_empleadoSeleccionado!['nombres']} ${_empleadoSeleccionado!['apellidos']} (${_empleadoSeleccionado!['rut']})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      const Text(
                        'Fecha de término:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _seleccionarFecha,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _fechaTermino == null
                                    ? 'Seleccionar fecha...'
                                    : '${_fechaTermino!.day.toString().padLeft(2, '0')}/${_fechaTermino!.month.toString().padLeft(2, '0')}/${_fechaTermino!.year}',
                                style: TextStyle(
                                  color: _fechaTermino == null
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Causal de desvinculación:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _causalSeleccionada,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        hint: const Text('Selecciona una causal'),
                        items: _causalesFiniquito.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() {
                          _causalSeleccionada = v;
                          _desglose = null;
                        }),
                      ),

                      if (_causalSeleccionada == '161') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '¿Se dio aviso previo de 30 días?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Sí, se avisó con 30 días de anticipación',
                                  style: TextStyle(fontSize: 13),
                                ),
                                value: true,
                                groupValue: _avisoPrevioDado,
                                onChanged: (v) => setState(() {
                                  _avisoPrevioDado = v!;
                                  _desglose = null;
                                }),
                              ),
                              RadioListTile<bool>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'No, se despidió sin aviso previo',
                                  style: TextStyle(fontSize: 13),
                                ),
                                value: false,
                                groupValue: _avisoPrevioDado,
                                onChanged: (v) => setState(() {
                                  _avisoPrevioDado = v!;
                                  _desglose = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_causalSeleccionada == '159-1' ||
                          _causalSeleccionada == '159-3') ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDFA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF99F6E4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Indemnización voluntaria (opcional)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: Color(0xFF115E59),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _causalSeleccionada == '159-3'
                                    ? 'Monto voluntario a pagar a los herederos del trabajador, si corresponde. Déjalo en \$0 si no aplica.'
                                    : 'Monto pactado libremente entre las partes como parte del acuerdo de término. Déjalo en \$0 si no aplica.',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF115E59),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _montoVoluntarioController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) =>
                                    setState(() => _desglose = null),
                                decoration: InputDecoration(
                                  hintText: '0',
                                  prefixText: '\$ ',
                                  filled: true,
                                  fillColor: Colors.white,
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Descuentos manuales (opcional):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _agregarDescuento,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text(
                              'Agregar',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (_descuentosManuales.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Sin descuentos agregados.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        )
                      else
                        ..._descuentosManuales.asMap().entries.map((entry) {
                          final i = entry.key;
                          final d = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    d['concepto'],
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                Text(
                                  '-\$${_formatearMiles(d['monto'])}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => setState(() {
                                    _descuentosManuales.removeAt(i);
                                    _desglose = null;
                                  }),
                                ),
                              ],
                            ),
                          );
                        }),

                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: (!_puedeCalcular || _calculando)
                              ? null
                              : _calcular,
                          icon: _calculando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.calculate_outlined, size: 18),
                          label: const Text('Calcular Desglose'),
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

                if (_error.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),

                if (_desglose != null) ...[
                  const SizedBox(height: 20),
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
                        Text(
                          '${_desglose!['nombre']} · ${_desglose!['rut']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${_desglose!['cargo'] ?? '—'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ingreso: ${_desglose!['fecha_ingreso']}  →  Término: ${_desglose!['fecha_termino']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          'Causal: ${_desglose!['causal_texto']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const Divider(height: 28),
                        const Text(
                          'DESGLOSE (provisional)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _filaDesglose(
                          'Vacaciones proporcionales (${_desglose!['dias_vacaciones_normales_habiles']} días hábiles → ${_desglose!['dias_vacaciones_normales_corridos']} días corridos)',
                          _desglose!['vacaciones_proporcionales_clp'],
                        ),
                        _filaDesglose(
                          'Vacaciones progresivas (${_desglose!['dias_vacaciones_progresivas_habiles']} días hábiles → ${_desglose!['dias_vacaciones_progresivas_corridos']} días corridos)',
                          _desglose!['vacaciones_progresivas_clp'],
                        ),
                        if ((_desglose!['indemnizacion_voluntaria'] ?? 0) > 0)
                          _filaDesglose(
                            'Indemnización voluntaria',
                            _desglose!['indemnizacion_voluntaria'],
                          ),
                        if (_desglose!['aplica_indemnizacion'] == true) ...[
                          if (_desglose!['desglose_sueldo_bruto_indemnizacion'] !=
                              null) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Base de cálculo (última remuneración mensual):',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _filaDesgloseChico(
                                    'Sueldo base',
                                    _desglose!['desglose_sueldo_bruto_indemnizacion']['sueldo_base'],
                                  ),
                                  _filaDesgloseChico(
                                    'Gratificación',
                                    _desglose!['desglose_sueldo_bruto_indemnizacion']['gratificacion'],
                                  ),
                                  _filaDesgloseChico(
                                    'Colación mensual',
                                    _desglose!['desglose_sueldo_bruto_indemnizacion']['colacion_mensual'],
                                  ),
                                  _filaDesgloseChico(
                                    'Locomoción mensual',
                                    _desglose!['desglose_sueldo_bruto_indemnizacion']['locomocion_mensual'],
                                  ),
                                  _filaDesgloseChico(
                                    'Promedio bonos (últimos 3 meses)',
                                    _desglose!['desglose_sueldo_bruto_indemnizacion']['promedio_bonos_3_meses'],
                                  ),
                                  if (_desglose!['desglose_sueldo_bruto_indemnizacion']['tope_90_uf_aplicado'] ==
                                      true) ...[
                                    const Divider(height: 16),
                                    _filaDesgloseChico(
                                      'Sin tope (referencia)',
                                      _desglose!['desglose_sueldo_bruto_indemnizacion']['sueldo_bruto_sin_tope'],
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        'Se aplicó el tope legal de 90 UF (Art. 172)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFD97706),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (_desglose!['desglose_sueldo_bruto_indemnizacion']['tope_90_uf_disponible'] ==
                                      false)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        'No se pudo verificar el tope de 90 UF: falta cargar el valor de la UF de este período.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFFDC2626),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  const Divider(height: 16),
                                  _filaDesgloseChico(
                                    'Base total',
                                    _desglose!['desglose_sueldo_bruto_indemnizacion']['sueldo_bruto_total'],
                                    destacado: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_desglose!['indemnizacion_aviso_previo'] > 0)
                            _filaDesglose(
                              'Indemnización por falta de aviso previo',
                              _desglose!['indemnizacion_aviso_previo'],
                            ),
                          _filaDesglose(
                            'Indemnización años de servicio (${_desglose!['anios_completos_servicio']} año(s)${_desglose!['tope_11_anios_aplicado'] == true ? ', tope aplicado' : ''})',
                            _desglose!['indemnizacion_anios_servicio'],
                          ),
                        ],
                        const Divider(height: 24),
                        _filaDesglose(
                          'Total finiquito (bruto)',
                          _desglose!['total_finiquito'],
                        ),
                        if ((_desglose!['descuentos_manuales'] as List)
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'DESCUENTOS',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                              letterSpacing: 1,
                            ),
                          ),
                          ...(_desglose!['descuentos_manuales'] as List).map(
                            (d) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '- ${d['concepto']}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '-\$${_formatearMiles(d['monto'])} CLP',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const Divider(height: 24),
                        _filaDesglose(
                          'LÍQUIDO FINAL A PAGAR',
                          _desglose!['liquido_a_pagar_finiquito'],
                          destacado: true,
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _aprobando ? null : _aprobar,
                            icon: _aprobando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                  ),
                            label: const Text('Aprobar Finiquito'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
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
                ],
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaDesgloseChico(
    String titulo,
    dynamic monto, {
    bool destacado = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            titulo,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: destacado ? FontWeight.bold : FontWeight.normal,
              color: destacado
                  ? const Color(0xFF001E42)
                  : const Color(0xFF64748B),
            ),
          ),
          Text(
            '\$${_formatearMiles(monto)}',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: destacado
                  ? const Color(0xFF001E42)
                  : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaDesglose(String titulo, dynamic monto, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: destacado ? 15 : 13,
                fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
                color: destacado
                    ? const Color(0xFF001E42)
                    : const Color(0xFF475569),
              ),
            ),
          ),
          Text(
            '\$${_formatearMiles(monto)} CLP',
            style: TextStyle(
              fontSize: destacado ? 16 : 13,
              fontWeight: FontWeight.bold,
              color: destacado
                  ? const Color(0xFF059669)
                  : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
