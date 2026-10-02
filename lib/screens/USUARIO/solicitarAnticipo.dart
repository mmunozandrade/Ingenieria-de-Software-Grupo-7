import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlAnticipo = 'http://127.0.0.1:8000';

/// Pantalla del USUARIO para solicitar un Anticipo de Sueldo
/// Excepcional desde su propio perfil. Queda "pendiente" hasta que
/// el administrador decida; el sistema valida automaticamente los
/// dias trabajados, el bloqueo por licencias/inasistencias, y el
/// tope del 30% de la remuneracion tributable del mes.
class SolicitarAnticipoScreen extends StatefulWidget {
  const SolicitarAnticipoScreen({super.key});

  @override
  State<SolicitarAnticipoScreen> createState() =>
      _SolicitarAnticipoScreenState();
}

class _SolicitarAnticipoScreenState extends State<SolicitarAnticipoScreen> {
  final _montoCtrl = TextEditingController();
  bool _guardando = false;
  String _mensaje = '';
  bool _exito = false;

  List<dynamic> _misAnticipos = [];
  bool _cargandoHistorial = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlAnticipo/usuario/mis-anticipos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _misAnticipos = data['anticipos'] ?? []);
      }
    } catch (_) {
    } finally {
      setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _solicitar() async {
    final montoTexto = _montoCtrl.text.replaceAll('.', '').trim();
    final monto = int.tryParse(montoTexto);
    if (monto == null || monto <= 0) {
      setState(() {
        _exito = false;
        _mensaje = 'Ingresa un monto valido, mayor a 0';
      });
      return;
    }
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.post(
        Uri.parse('$_apiUrlAnticipo/usuario/solicitar-anticipo'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'monto_clp': monto}),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Solicitud enviada correctamente, queda pendiente de aprobacion'
            : data['mensaje'] ?? 'Error al solicitar';
        if (_exito) _montoCtrl.clear();
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
      case 'aprobado':
        return const Color(0xFF059669);
      case 'rechazado':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  String _formatearMiles(String valor) {
    final soloDigitos = valor.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < soloDigitos.length; i++) {
      final posicionDesdeDerecha = soloDigitos.length - i;
      buffer.write(soloDigitos[i]);
      if (posicionDesdeDerecha > 1 && posicionDesdeDerecha % 3 == 1) {
        buffer.write('.');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF009A8D),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Anticipo de Sueldo',
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
                        'Anticipo de Sueldo Excepcional',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF115E59),
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Puedes solicitar un anticipo excepcional si cuentas con al menos 15 dias trabajados en el mes. '
                        'El monto maximo es el 30% de tu remuneracion tributable del periodo. Queda pendiente de aprobacion del administrador, '
                        'y solo puedes tener 1 solicitud excepcional activa por mes.',
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
                      TextField(
                        controller: _montoCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final texto = _formatearMiles(newValue.text);
                            return TextEditingValue(
                              text: texto,
                              selection: TextSelection.collapsed(
                                offset: texto.length,
                              ),
                            );
                          }),
                        ],
                        decoration: InputDecoration(
                          labelText: 'Monto del anticipo (CLP)',
                          prefixText: '\$ ',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
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
                            _guardando ? 'Enviando...' : 'Solicitar Anticipo',
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
                      else if (_misAnticipos.isEmpty)
                        const Text(
                          'Aun no tienes solicitudes de anticipo.',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        )
                      else
                        ..._misAnticipos.map(
                          (a) => Container(
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
                                        '\$${_formatearMiles(a['monto_clp'].toString())} CLP',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'Periodo: ${a['periodo']}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
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
                                      a['estado'],
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (a['estado'] as String).toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _colorEstado(a['estado']),
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
