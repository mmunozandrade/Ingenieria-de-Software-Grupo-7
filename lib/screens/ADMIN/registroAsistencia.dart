import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlAsistencia = 'http://127.0.0.1:8000';

const List<String> _mesesNombres = [
  'Enero',
  'Febrero',
  'Marzo',
  'Abril',
  'Mayo',
  'Junio',
  'Julio',
  'Agosto',
  'Septiembre',
  'Octubre',
  'Noviembre',
  'Diciembre',
];

const List<String> _estadosAsistencia = [
  'Presente',
  'Ausente',
  'Licencia medica',
  'Vacaciones',
  'Feriado',
];

/// Pantalla de Registro de Asistencia Diaria — el administrador
/// busca un trabajador, elige un periodo (mes/ano), y va registrando
/// el estado de cada dia (Presente/Ausente/Licencia medica/
/// Vacaciones/Feriado), con hora de entrada/salida solo si esta
/// Presente. Este registro es el insumo base para deducciones por
/// ausencias, horas extras y Semana Corrida.
class RegistroAsistenciaScreen extends StatefulWidget {
  const RegistroAsistenciaScreen({super.key});

  @override
  State<RegistroAsistenciaScreen> createState() =>
      _RegistroAsistenciaScreenState();
}

class _RegistroAsistenciaScreenState extends State<RegistroAsistenciaScreen> {
  // ── Busqueda de trabajador ─────────────────────────────────
  final _busquedaCtrl = TextEditingController();
  List<Map<String, dynamic>> _resultadosBusqueda = [];
  bool _buscando = false;
  String _errorBusqueda = '';

  Map<String, dynamic>? _trabajadorSeleccionado;

  // ── Periodo ────────────────────────────────────────────────
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  // ── Dias registrados del periodo ──────────────────────────
  List<dynamic> _dias = [];
  bool _cargandoDias = false;
  String _errorDias = '';

  // ── Formulario de registro/edicion de un dia ──────────────
  DateTime? _fechaFormulario;
  String? _estadoFormulario;
  final _horaEntradaCtrl = TextEditingController();
  final _horaSalidaCtrl = TextEditingController();
  bool _guardando = false;
  String _mensajeGuardar = '';
  bool _exitoGuardar = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _horaEntradaCtrl.dispose();
    _horaSalidaCtrl.dispose();
    super.dispose();
  }

  Future<void> _buscarTrabajador() async {
    final query = _busquedaCtrl.text.trim();
    if (query.length < 3) {
      setState(
        () => _errorBusqueda = 'Ingresa al menos 3 caracteres para buscar',
      );
      return;
    }
    setState(() {
      _buscando = true;
      _errorBusqueda = '';
      _resultadosBusqueda = [];
    });
    try {
      final token = await SessionService.obtenerToken();
      final esRut = query.contains('.') || query.contains('-');
      final uri = Uri.parse(
        '$_apiUrlAsistencia/buscar-empleados',
      ).replace(queryParameters: {esRut ? 'rut' : 'apellido': query});
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _resultadosBusqueda = List<Map<String, dynamic>>.from(
            data['empleados'] ?? [],
          );
        });
      } else {
        setState(() => _errorBusqueda = data['mensaje'] ?? 'Error al buscar');
      }
    } catch (_) {
      setState(() => _errorBusqueda = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _buscando = false);
    }
  }

  void _seleccionarTrabajador(Map<String, dynamic> t) {
    setState(() {
      _trabajadorSeleccionado = t;
      _resultadosBusqueda = [];
      _busquedaCtrl.clear();
      _dias = [];
    });
    _cargarDias();
  }

  String get _periodoActual =>
      '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';

  Future<void> _cargarDias() async {
    if (_trabajadorSeleccionado == null) return;
    setState(() {
      _cargandoDias = true;
      _errorDias = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final trabajadorId = _trabajadorSeleccionado!['trabajador_id'];
      final uri = Uri.parse('$_apiUrlAsistencia/admin/asistencia').replace(
        queryParameters: {
          'trabajador_id': '$trabajadorId',
          'periodo': _periodoActual,
        },
      );
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _dias = data['dias'] ?? []);
      } else {
        setState(
          () => _errorDias = data['mensaje'] ?? 'Error al cargar los dias',
        );
      }
    } catch (_) {
      setState(() => _errorDias = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargandoDias = false);
    }
  }

  String _fmtFecha(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _guardarDia() async {
    if (_trabajadorSeleccionado == null) return;
    if (_fechaFormulario == null) {
      setState(() {
        _exitoGuardar = false;
        _mensajeGuardar = 'Selecciona la fecha';
      });
      return;
    }
    if (_estadoFormulario == null) {
      setState(() {
        _exitoGuardar = false;
        _mensajeGuardar = 'Selecciona el estado del dia';
      });
      return;
    }
    if (_estadoFormulario == 'Presente') {
      if (_horaEntradaCtrl.text.trim().isEmpty ||
          _horaSalidaCtrl.text.trim().isEmpty) {
        setState(() {
          _exitoGuardar = false;
          _mensajeGuardar = 'Ingresa hora de entrada y salida (formato HH:MM)';
        });
        return;
      }
    }
    await _enviarGuardado(confirmarReemplazo: false);
  }

  Future<void> _enviarGuardado({required bool confirmarReemplazo}) async {
    setState(() {
      _guardando = true;
      _mensajeGuardar = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final trabajadorId = _trabajadorSeleccionado!['trabajador_id'];
      final body = {
        'trabajador_id': trabajadorId,
        'fecha': _fmtFecha(_fechaFormulario!),
        'estado_dia': _estadoFormulario,
        if (_estadoFormulario == 'Presente')
          'hora_entrada': _horaEntradaCtrl.text.trim(),
        if (_estadoFormulario == 'Presente')
          'hora_salida': _horaSalidaCtrl.text.trim(),
        'confirmar_reemplazo': confirmarReemplazo,
      };
      final response = await http.post(
        Uri.parse('$_apiUrlAsistencia/admin/asistencia'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
      final data = jsonDecode(response.body);

      if (data['success'] != true && data['requiere_confirmacion'] == true) {
        setState(() => _guardando = false);
        final registro = data['registro_existente'] ?? {};
        final confirmado = await _mostrarDialogoConfirmacion(registro);
        if (confirmado == true) {
          await _enviarGuardado(confirmarReemplazo: true);
        }
        return;
      }

      setState(() {
        _exitoGuardar = data['success'] == true;
        _mensajeGuardar = _exitoGuardar
            ? 'Dia registrado correctamente'
            : data['mensaje'] ?? 'Error al guardar';
        if (_exitoGuardar) {
          _fechaFormulario = null;
          _estadoFormulario = null;
          _horaEntradaCtrl.clear();
          _horaSalidaCtrl.clear();
        }
      });
      if (_exitoGuardar) _cargarDias();
    } catch (_) {
      setState(() {
        _exitoGuardar = false;
        _mensajeGuardar = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
    }
  }

  Future<bool?> _mostrarDialogoConfirmacion(Map registro) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Ya existe un registro para este día'),
        content: Text(
          'Este trabajador ya tiene un registro para esta fecha:\n\n'
          'Estado: ${registro['estado_dia'] ?? '—'}\n'
          '${registro['hora_entrada'] != null ? 'Entrada: ${registro['hora_entrada']}\nSalida: ${registro['hora_salida']}\n' : ''}'
          '\n¿Deseas reemplazarlo con los nuevos datos ingresados?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              foregroundColor: Colors.white,
            ),
            child: const Text('Reemplazar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Registro de Asistencia',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_trabajadorSeleccionado == null) ...[
                  _buildBuscador(),
                ] else ...[
                  _buildTrabajadorSeleccionado(),
                  const SizedBox(height: 20),
                  _buildSelectorPeriodo(),
                  const SizedBox(height: 20),
                  _buildListaDias(),
                  const SizedBox(height: 20),
                  _buildFormularioDia(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBuscador() {
    return Container(
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
            'Busca el trabajador',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF001E42),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Por apellido (minimo 3 letras) o RUT exacto.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busquedaCtrl,
                  onSubmitted: (_) => _buscarTrabajador(),
                  decoration: InputDecoration(
                    hintText: 'Ej: Guerra o 18.679.609-8',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _buscando ? null : _buscarTrabajador,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF001E42),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _buscando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.search),
                ),
              ),
            ],
          ),
          if (_errorBusqueda.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _errorBusqueda,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
          if (_resultadosBusqueda.isNotEmpty) ...[
            const SizedBox(height: 14),
            ..._resultadosBusqueda.map(
              (t) => InkWell(
                onTap: () => _seleccionarTrabajador(t),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t['nombres'] ?? ''} ${t['apellidos'] ?? ''}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        t['rut'] ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrabajadorSeleccionado() {
    final t = _trabajadorSeleccionado!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: Color(0xFF16A34A)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${t['nombres'] ?? ''} ${t['apellidos'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'RUT: ${t['rut'] ?? '—'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _trabajadorSeleccionado = null;
              _dias = [];
            }),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorPeriodo() {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(6, (i) => anioActual - i);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _mesSeleccionado,
              decoration: const InputDecoration(labelText: 'Mes'),
              items: List.generate(
                12,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(_mesesNombres[i]),
                ),
              ),
              onChanged: (v) {
                setState(() => _mesSeleccionado = v!);
                _cargarDias();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _anioSeleccionado,
              decoration: const InputDecoration(labelText: 'Ano'),
              items: anios
                  .map((a) => DropdownMenuItem(value: a, child: Text('$a')))
                  .toList(),
              onChanged: (v) {
                setState(() => _anioSeleccionado = v!);
                _cargarDias();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListaDias() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dias registrados en $_periodoActual',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF001E42),
            ),
          ),
          const SizedBox(height: 12),
          if (_cargandoDias)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_errorDias.isNotEmpty)
            Text(
              _errorDias,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            )
          else if (_dias.isEmpty)
            const Text(
              'Aun no hay dias registrados en este periodo.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            )
          else
            ..._dias.map(
              (d) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        d['fecha'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        d['estado_dia'] ?? '',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (d['hora_entrada'] != null)
                      Text(
                        '${d['hora_entrada']} - ${d['hora_salida']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFormularioDia() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Registrar / editar un dia',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF001E42),
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              final primerDia = DateTime(
                _anioSeleccionado,
                _mesSeleccionado,
                1,
              );
              final ultimoDia = DateTime(
                _anioSeleccionado,
                _mesSeleccionado + 1,
                0,
              );
              final f = await showDatePicker(
                context: context,
                initialDate: _fechaFormulario ?? primerDia,
                firstDate: primerDia,
                lastDate: ultimoDia,
              );
              if (f != null) setState(() => _fechaFormulario = f);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _fechaFormulario != null
                        ? _fmtFecha(_fechaFormulario!)
                        : 'Selecciona la fecha',
                    style: TextStyle(
                      color: _fechaFormulario != null
                          ? Colors.black
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _estadoFormulario,
            decoration: const InputDecoration(labelText: 'Estado del dia'),
            items: _estadosAsistencia
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _estadoFormulario = v),
          ),
          if (_estadoFormulario == 'Presente') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _horaEntradaCtrl,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Hora entrada (HH:MM)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _horaSalidaCtrl,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Hora salida (HH:MM)',
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (_mensajeGuardar.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _exitoGuardar ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _mensajeGuardar,
                style: TextStyle(
                  color: _exitoGuardar ? Colors.green : Colors.red,
                  fontSize: 13,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _guardando ? null : _guardarDia,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_guardando ? 'Guardando...' : 'Guardar Dia'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
