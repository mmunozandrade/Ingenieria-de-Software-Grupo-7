import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrl = 'http://127.0.0.1:8000';

class VacacionesProgresivas extends StatefulWidget {
  const VacacionesProgresivas({super.key});

  @override
  State<VacacionesProgresivas> createState() => _VacacionesProgresivasState();
}

class _VacacionesProgresivasState extends State<VacacionesProgresivas> {
  bool _cargando = true;
  bool _guardando = false;
  String _mensaje = '';
  bool _exito = false;

  // ── Datos que vienen directo de /mi-balance-vacaciones ──────
  // (el calculo ya se hizo en el servidor con calcular_dias_progresivos)
  String _fechaIngreso = '—';
  int _mesesClinica = 0;
  int _mesesPrevios = 0;
  int _totalMeses = 0;
  int _diasProgresivos = 0;
  bool _cumpleProgresivos = false;
  int _anosDesdeInicio = 0;
  int _mesesFaltantes = 0;
  String _fechaInicioBeneficio = '—';

  bool get cumpleClinica => _mesesClinica >= 36;
  bool get cumpleTotal => _totalMeses >= 120;
  bool get puedeProgresivos => _cumpleProgresivos;

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
        Uri.parse('$_apiUrl/mi-balance-vacaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _fechaIngreso = data['fecha_ingreso'] ?? '—';
          _mesesClinica = data['meses_clinica'] ?? 0;
          _mesesPrevios = data['meses_previos'] ?? 0;
          _totalMeses = data['total_meses'] ?? 0;
          _diasProgresivos = data['dias_progresivos'] ?? 0;
          _cumpleProgresivos = data['cumple_progresivos'] ?? false;
          _anosDesdeInicio = data['anos_desde_inicio'] ?? 0;
          _mesesFaltantes = data['meses_faltantes'] ?? 0;
          _fechaInicioBeneficio = data['fecha_inicio_beneficio'] ?? '—';
        });
      } else {
        setState(() {
          _exito = false;
          _mensaje =
              data['mensaje'] ?? 'No se pudo obtener el balance de vacaciones';
        });
      }
    } catch (_) {
      setState(() {
        _exito = false;
        _mensaje = 'No se pudo conectar al servidor';
      });
    } finally {
      setState(() => _cargando = false);
    }
  }

  // El backend ya autoactualiza saldo_vacaciones.dias_progresivos cada vez
  // que se consulta /mi-balance-vacaciones, asi que este boton ahora solo
  // refresca la pantalla en vez de recalcular y volver a empujar valores.
  Future<void> _refrescarSaldo() async {
    setState(() {
      _guardando = true;
      _mensaje = '';
    });
    await _cargarDatos();
    setState(() {
      _guardando = false;
      _exito = true;
      _mensaje = 'Saldo actualizado: $_diasProgresivos dia(s) progresivo(s).';
    });
  }

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          final bool esEscritorio = ancho >= 1280;
          final bool esTablet = ancho >= 768 && ancho < 1280;
          final double paddingHorizontal = esEscritorio
              ? 40
              : (esTablet ? 28 : 24);
          final double maxWidthContenido = esEscritorio
              ? 900
              : (esTablet ? 720 : double.infinity);

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: paddingHorizontal,
              vertical: 30,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidthContenido),
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
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),

                      // Tarjeta detalle calculo
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

                            _filaDato(
                              titulo: 'Meses de cotizaciones previas:',
                              valor: '$_mesesPrevios meses',
                            ),
                            const SizedBox(height: 14),

                            _filaDato(
                              titulo: 'Meses trabajados en la clinica:',
                              valor:
                                  '$_mesesClinica meses (${_mesesClinica ~/ 12} anos)',
                              nota: cumpleClinica
                                  ? 'Cumple minimo 3 anos de antiguedad (Art. 68)'
                                  : 'Requiere al menos 36 meses en la clinica (faltan ${36 - _mesesClinica} meses)',
                              notaPositiva: cumpleClinica,
                            ),
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 14),

                            _filaDato(
                              titulo: 'Total de meses de cotizacion:',
                              valor: '$_totalMeses meses',
                              nota: cumpleTotal
                                  ? 'Cumple 120 meses minimos requeridos (Art. 68)'
                                  : 'Requiere 120 meses en total (faltan ${_mesesFaltantes} meses)',
                              notaPositiva: cumpleTotal,
                            ),

                            if (_fechaIngreso != '—') ...[
                              const SizedBox(height: 14),
                              _filaDato(
                                titulo: 'Fecha de ingreso a la clinica:',
                                valor: _fechaIngreso,
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

                      // Boton refrescar
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _guardando ? null : _refrescarSaldo,
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
            ),
          );
        },
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
          _cumpleProgresivos,
          'Inicio beneficio: $_fechaInicioBeneficio · $_anosDesdeInicio anos completos',
        ),
        const SizedBox(height: 10),
        _validacion(
          true,
          '1 dia adicional por cada 3 anos desde fecha de inicio beneficio',
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
          '$_diasProgresivos dia${_diasProgresivos == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.w300,
            color: puedeProgresivos
                ? const Color(0xFF0D9488)
                : const Color(0xFFF59E0B),
          ),
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
