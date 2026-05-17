import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

const int _maxMesesPreviosLegal = 120;
const int _minMesesClinica = 36;
const int _minTotalMeses = 120;

class VacacionesProgresivas extends StatefulWidget {
  const VacacionesProgresivas({super.key});

  @override
  State<VacacionesProgresivas> createState() => _VacacionesProgresivasState();
}

class _VacacionesProgresivasState extends State<VacacionesProgresivas> {
  DateTime? _fechaIngreso;
  int _mesesPrevios = 0;
  bool _cargando = true;
  bool _guardando = false;
  String _mensaje = '';
  bool _exito = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrl/mi-ficha'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final fechaStr = data['fecha_ingreso'];
        if (fechaStr != null) {
          _fechaIngreso = DateTime.tryParse(fechaStr);
        }
        _mesesPrevios = data['meses_cotizados_previos'] ?? 0;
      }
    } catch (_) {
      _fechaIngreso = DateTime(2010, 1, 1);
      _mesesPrevios = 80;
    } finally {
      setState(() => _cargando = false);
    }
  }

  int get mesesPreviosLimitados =>
      _mesesPrevios.clamp(0, _maxMesesPreviosLegal);

  int get mesesClinica {
    if (_fechaIngreso == null) return 0;
    final hoy = DateTime.now();
    int meses =
        (hoy.year - _fechaIngreso!.year) * 12 +
        (hoy.month - _fechaIngreso!.month);
    if (hoy.day < _fechaIngreso!.day) meses--;
    return meses < 0 ? 0 : meses;
  }

  int get aniosClinica => mesesClinica ~/ 12;
  int get totalMeses => mesesPreviosLimitados + mesesClinica;
  bool get cumpleTotal => totalMeses >= _minTotalMeses;
  bool get cumpleClinica => mesesClinica >= _minMesesClinica;
  bool get puedeProgresivos => cumpleTotal && cumpleClinica;

  double get diasProgresivosInterno {
    if (!puedeProgresivos || aniosClinica < 10) return 0.0;
    final double dias = ((aniosClinica - 10) / 3).floorToDouble();
    return double.parse(dias.toStringAsFixed(4));
  }

  int get diasProgresivosVisual => diasProgresivosInterno.round();

  Future<void> _actualizarSaldo() async {
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.put(
        Uri.parse('$_apiUrl/actualizar-vacaciones-progresivas'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'dias_adicionales': diasProgresivosVisual,
          'dias_totales': 15 + diasProgresivosVisual,
        }),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _exito = data['success'] == true;
        _mensaje = _exito
            ? 'Saldo actualizado: $diasProgresivosVisual dia(s) progresivo(s).'
            : data['mensaje'] ?? 'Error al actualizar';
      });
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _guardando = false);
    }
  }

  String _formatFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0D9488)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Vacaciones Progresivas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset('assets/Logo.png', height: 80),
              const SizedBox(height: 20),
              const Text(
                'Calculo de Vacaciones Progresivas',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Art. 68 Codigo del Trabajo - Sistema de Personal Institucional',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),

              // Tarjeta detalle calculo (ancho completo)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Detalle del Calculo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Meses cotizaciones previas
                    _filaDato(
                      titulo: 'Meses de cotizaciones previas:',
                      valor: '$mesesPreviosLimitados meses',
                      nota: _mesesPrevios > _maxMesesPreviosLegal
                          ? 'Limitado a 120 meses (10 anos) por Art. 68'
                          : null,
                      notaPositiva: false,
                    ),
                    const SizedBox(height: 14),

                    // Meses trabajados en clinica
                    _filaDato(
                      titulo: 'Meses trabajados en la clinica:',
                      valor: '$mesesClinica meses ($aniosClinica anos)',
                      nota: cumpleClinica
                          ? 'Cumple minimo 3 anos de antiguedad (Art. 68)'
                          : 'Requiere al menos 36 meses en la clinica (faltan ${_minMesesClinica - mesesClinica} meses)',
                      notaPositiva: cumpleClinica,
                    ),
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 14),

                    // Total meses
                    _filaDato(
                      titulo: 'Total de meses de cotizacion:',
                      valor: '$totalMeses meses',
                      nota: cumpleTotal
                          ? 'Cumple 120 meses minimos requeridos (Art. 68)'
                          : 'Requiere 120 meses en total (faltan ${_minTotalMeses - totalMeses} meses)',
                      notaPositiva: cumpleTotal,
                    ),

                    if (_fechaIngreso != null) ...[
                      const SizedBox(height: 14),
                      _filaDato(
                        titulo: 'Fecha de ingreso a la clinica:',
                        valor: _formatFecha(_fechaIngreso!),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tarjeta resultado
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: puedeProgresivos
                      ? const Color(0xFFE6FFFB)
                      : const Color(0xFFFFF7ED),
                  border: Border.all(
                    color: puedeProgresivos
                        ? const Color(0xFF5EEAD4)
                        : const Color(0xFFFBBF24),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: puedeProgresivos
                                ? const Color(0xFF99F6E4)
                                : const Color(0xFFFCD34D),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Dias Progresivos Calculados',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: puedeProgresivos
                                    ? const Color(0xFF0F766E)
                                    : const Color(0xFF92400E),
                              ),
                            ),
                          ),
                          Icon(
                            puedeProgresivos
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: puedeProgresivos
                                ? const Color(0xFF0D9488)
                                : const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final bool esPantallaChica =
                              constraints.maxWidth < 600;
                          final validaciones = _detalleValidaciones();
                          final resultado = _resultadoDias();
                          if (esPantallaChica) {
                            return Column(
                              children: [
                                validaciones,
                                const SizedBox(height: 20),
                                resultado,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(flex: 2, child: validaciones),
                              Container(
                                height: 100,
                                width: 1,
                                color: puedeProgresivos
                                    ? const Color(0xFF99F6E4)
                                    : const Color(0xFFFCD34D),
                              ),
                              Expanded(child: resultado),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Mensaje exito/error
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

              // Boton actualizar
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _actualizarSaldo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    disabledBackgroundColor: Colors.grey[300],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _guardando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Actualizar Saldo de Vacaciones',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaDato({
    required String titulo,
    required String valor,
    String? nota,
    bool? notaPositiva,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
              ),
            ),
            Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        if (nota != null) ...[
          const SizedBox(height: 4),
          Text(
            nota,
            style: TextStyle(
              fontSize: 12,
              color: notaPositiva == null
                  ? const Color(0xFFF59E0B)
                  : notaPositiva
                  ? const Color(0xFF059669)
                  : const Color(0xFFDC2626),
            ),
          ),
        ],
      ],
    );
  }

  Widget _detalleValidaciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _validacion(
          cumpleTotal,
          'Total supera 120 meses de cotizacion Art. 68',
        ),
        const SizedBox(height: 10),
        _validacion(cumpleClinica, 'Minimo 3 anos de antiguedad en la clinica'),
        const SizedBox(height: 10),
        _validacion(
          aniosClinica >= 10,
          'Anos desde el ano 10: ${aniosClinica >= 10 ? aniosClinica - 10 : 0} anos completos',
        ),
        const SizedBox(height: 10),
        _validacion(true, '1 dia habil por cada 3 anos desde el ano 10'),
        const SizedBox(height: 10),
        _validacion(
          true,
          'Precision interna: 4 decimales; visualizacion redondeada',
        ),
      ],
    );
  }

  Widget _resultadoDias() {
    return Column(
      children: [
        Text(
          'Total dias progresivos disponibles:',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: puedeProgresivos
                ? const Color(0xFF475569)
                : const Color(0xFF92400E),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$diasProgresivosVisual dia${diasProgresivosVisual == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w300,
            color: puedeProgresivos
                ? const Color(0xFF0D9488)
                : const Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Valor interno: ${diasProgresivosInterno.toStringAsFixed(4)}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _validacion(bool cumple, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          cumple ? Icons.check : Icons.close,
          size: 18,
          color: cumple ? const Color(0xFF0D9488) : Colors.red,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
