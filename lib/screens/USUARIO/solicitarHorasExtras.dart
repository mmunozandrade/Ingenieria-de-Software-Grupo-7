import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlHorasExtras = 'http://127.0.0.1:8000';

/// Pantalla del USUARIO para solicitar horas extras desde su perfil,
/// como REFERENCIA para el administrador. Esta solicitud NO calcula
/// ni suma ningun monto por si sola: el registro real que si afecta
/// la liquidacion (con el recargo del 50%, Art. 32) lo ingresa el
/// administrador aparte, en Calculo Liquidacion Total.
class SolicitarHorasExtrasScreen extends StatefulWidget {
  const SolicitarHorasExtrasScreen({super.key});

  @override
  State<SolicitarHorasExtrasScreen> createState() =>
      _SolicitarHorasExtrasScreenState();
}

class _SolicitarHorasExtrasScreenState
    extends State<SolicitarHorasExtrasScreen> {
  double? _horasSeleccionadas;
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  bool _guardando = false;
  String _mensaje = '';
  bool _exito = false;

  List<dynamic> _misSolicitudes = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlHorasExtras/usuario/mis-horas-extras'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _misSolicitudes = data['registros'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _solicitar() async {
    final horas = _horasSeleccionadas;
    if (horas == null) {
      setState(() {
        _exito = false;
        _mensaje = 'Selecciona la cantidad de horas extras';
      });
      return;
    }
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    final periodo =
        '${_mesSeleccionado.toString().padLeft(2, '0')}/$_anioSeleccionado';
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrlHorasExtras/usuario/solicitar-horas-extras'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'periodo': periodo, 'cantidad_horas': horas}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje =
            data['mensaje'] ??
            (_exito ? 'Solicitud enviada' : 'Error al solicitar');
        if (_exito) _horasSeleccionadas = null;
      });
      if (_exito) _cargarHistorial();
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'aprobada':
        return const Color(0xFF059669);
      case 'rechazada':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anioActual = DateTime.now().year;
    final anios = List<int>.generate(3, (i) => anioActual - i);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF009A8D),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Horas Extras',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF99F6E4)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solicitud de Horas Extras',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF115E59),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'En este apartado puedes registrar tus solicitudes de horas extras. Esto no calcula ningún pago por sí solo: '
                        'el administrador revisa tu solicitud y, si corresponde, ingresa el monto real al cerrar tu liquidación.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF115E59),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

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
                        'Nueva solicitud',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF001E42),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Periodo:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _mesSeleccionado,
                              decoration: InputDecoration(
                                labelText: 'Mes',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: List.generate(12, (i) => i + 1)
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m.toString().padLeft(2, '0')),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () => _mesSeleccionado = v ?? _mesSeleccionado,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _anioSeleccionado,
                              decoration: InputDecoration(
                                labelText: 'Año',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: anios
                                  .map(
                                    (a) => DropdownMenuItem(
                                      value: a,
                                      child: Text('$a'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(
                                () =>
                                    _anioSeleccionado = v ?? _anioSeleccionado,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Cantidad de horas extras (tope diario, Art. 31):',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: [0.5, 1.0, 1.5, 2.0].map((valor) {
                          final seleccionado = _horasSeleccionadas == valor;
                          return ChoiceChip(
                            label: Text(
                              valor == valor.roundToDouble()
                                  ? '${valor.toInt()} hora${valor == 1 ? '' : 's'}'
                                  : '$valor horas',
                            ),
                            selected: seleccionado,
                            onSelected: (_) =>
                                setState(() => _horasSeleccionadas = valor),
                            selectedColor: const Color(0xFF009A8D),
                            labelStyle: TextStyle(
                              color: seleccionado
                                  ? Colors.white
                                  : const Color(0xFF334155),
                              fontWeight: FontWeight.w600,
                            ),
                            backgroundColor: const Color(0xFFF8FAFC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: seleccionado
                                    ? const Color(0xFF009A8D)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      if (_mensaje.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _exito ? Colors.green[50] : Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _exito
                                  ? Colors.green[200]!
                                  : Colors.red[200]!,
                            ),
                          ),
                          child: Text(
                            _mensaje,
                            style: TextStyle(
                              color: _exito ? Colors.green : Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _guardando ? null : _solicitar,
                          icon: _guardando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined, size: 18),
                          label: Text(
                            _guardando
                                ? 'Enviando...'
                                : 'Solicitar Horas Extras',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF009A8D),
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
                      const Text(
                        'Mis solicitudes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF001E42),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_cargandoHistorial)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_misSolicitudes.isEmpty)
                        const Text(
                          'Aun no tienes solicitudes de horas extras.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        )
                      else
                        ..._misSolicitudes.map(
                          (s) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${s['cantidad_horas']} horas',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Periodo: ${s['periodo']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      if ((s['observacion'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        Text(
                                          s['observacion'],
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _colorEstado(
                                      s['estado'],
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (s['estado'] as String).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _colorEstado(s['estado']),
                                    ),
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
          ),
        ),
      ),
    );
  }
}
