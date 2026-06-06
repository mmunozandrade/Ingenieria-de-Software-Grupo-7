import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlBalance = 'http://127.0.0.1:8000';

class BalanceVacaciones extends StatefulWidget {
  const BalanceVacaciones({super.key});

  @override
  State<BalanceVacaciones> createState() => _BalanceVacacionesState();
}

class _BalanceVacacionesState extends State<BalanceVacaciones> {
  Map<String, dynamic>? _balance;
  bool   _cargando = true;
  String _error    = '';

  @override
  void initState() {
    super.initState();
    _cargarBalance();
  }

  Future<void> _cargarBalance() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final token = await SessionService.obtenerToken();
      final response = await http.get(
        Uri.parse('$_apiUrlBalance/mi-balance-vacaciones'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() => _balance = data);
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al cargar');
      }
    } catch (_) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001E42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Balance de Vacaciones',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _cargarBalance,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF001E42)))
          : _error.isNotEmpty
              ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
              : _balance == null
                  ? const Center(child: Text('Sin datos disponibles'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 700),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // Titulo
                              const Text('Mi Balance de Vacaciones',
                                  style: TextStyle(fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF001E42))),
                              const SizedBox(height: 4),
                              Text(
                                'Art. 67 Codigo del Trabajo · Factor 1.25 por mes trabajado',
                                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 24),

                              // Alerta saldo excedido
                              if (_balance!['saldo_excedido'] == true)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.red[200]!),
                                  ),
                                  child: Row(children: [
                                    const Icon(Icons.warning_amber_outlined,
                                        color: Colors.red, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Saldo excedido: los dias utilizados superan los dias acumulados. Contacte a Recursos Humanos.',
                                        style: TextStyle(color: Colors.red[800], fontSize: 13),
                                      ),
                                    ),
                                  ]),
                                ),

                              // Tarjetas de resumen
                              Row(children: [
                                Expanded(child: _TarjetaBalance(
                                  titulo: 'Dias Acumulados',
                                  valor: '${_balance!['dias_acumulados']}',
                                  subtitulo: '${_balance!['acumulado_4dec']} exacto',
                                  color: const Color(0xFF1D4ED8),
                                  bgColor: const Color(0xFFEFF6FF),
                                  borderColor: const Color(0xFFBFDBFE),
                                  icono: Icons.calendar_month_outlined,
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _TarjetaBalance(
                                  titulo: 'Dias Utilizados',
                                  valor: '${_balance!['dias_utilizados']}',
                                  subtitulo: 'Vacaciones tomadas',
                                  color: const Color(0xFFD97706),
                                  bgColor: const Color(0xFFFFFBEB),
                                  borderColor: const Color(0xFFFDE68A),
                                  icono: Icons.beach_access_outlined,
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _TarjetaBalance(
                                  titulo: 'Dias Disponibles',
                                  valor: '${_balance!['dias_disponibles']}',
                                  subtitulo: _balance!['saldo_excedido'] == true
                                      ? 'Saldo excedido'
                                      : 'Para usar',
                                  color: _balance!['saldo_excedido'] == true
                                      ? Colors.red
                                      : const Color(0xFF059669),
                                  bgColor: _balance!['saldo_excedido'] == true
                                      ? const Color(0xFFFEF2F2)
                                      : const Color(0xFFECFDF5),
                                  borderColor: _balance!['saldo_excedido'] == true
                                      ? const Color(0xFFFECACA)
                                      : const Color(0xFFA7F3D0),
                                  icono: _balance!['saldo_excedido'] == true
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                )),
                              ]),
                              const SizedBox(height: 24),

                              // Detalle del calculo
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
                                      Icon(Icons.calculate_outlined,
                                          color: Color(0xFF001E42), size: 20),
                                      SizedBox(width: 8),
                                      Text('Detalle del Calculo',
                                          style: TextStyle(fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF001E42))),
                                    ]),
                                    const Divider(height: 24),

                                    _FilaDetalle(
                                      label: 'Fecha de ingreso:',
                                      valor: _balance!['fecha_ingreso'] ?? '—',
                                    ),
                                    const SizedBox(height: 10),
                                    _FilaDetalle(
                                      label: 'Meses en la clinica:',
                                      valor: '${_balance!['meses_clinica']} meses',
                                    ),
                                    const SizedBox(height: 10),
                                    _FilaDetalle(
                                      label: 'Meses cotizaciones previas:',
                                      valor: '${_balance!['meses_previos']} meses',
                                    ),
                                    const SizedBox(height: 10),
                                    _FilaDetalle(
                                      label: 'Total meses considerados:',
                                      valor: '${_balance!['total_meses']} meses',
                                      destacado: true,
                                    ),
                                    const Divider(height: 20),
                                    _FilaDetalle(
                                      label: 'Factor de acumulacion:',
                                      valor: '${_balance!['factor_acumulacion']} dias/mes (Art. 67)',
                                    ),
                                    const SizedBox(height: 10),
                                    _FilaDetalle(
                                      label: 'Calculo interno (4 decimales):',
                                      valor: '${_balance!['total_meses']} × 1.25 = ${_balance!['acumulado_4dec']}',
                                    ),
                                    const SizedBox(height: 10),
                                    _FilaDetalle(
                                      label: 'Dias acumulados (redondeado):',
                                      valor: '${_balance!['dias_acumulados']} dias',
                                      destacado: true,
                                    ),
                                    const Divider(height: 20),
                                    _FilaDetalle(
                                      label: 'Dias utilizados:',
                                      valor: '${_balance!['dias_utilizados']} dias',
                                    ),
                                    const SizedBox(height: 10),
                                    _FilaDetalle(
                                      label: 'Dias disponibles:',
                                      valor: '${_balance!['dias_disponibles']} dias',
                                      destacado: true,
                                      colorValor: _balance!['saldo_excedido'] == true
                                          ? Colors.red
                                          : const Color(0xFF059669),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Nota actualizacion
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.update_outlined,
                                      size: 16, color: Color(0xFF64748B)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Ultima actualizacion: ${_balance!['ultima_actualizacion']}',
                                      style: const TextStyle(
                                          fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ),
                                ]),
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

// ── Tarjeta resumen ───────────────────────────────────────────
class _TarjetaBalance extends StatelessWidget {
  final String  titulo;
  final String  valor;
  final String  subtitulo;
  final Color   color;
  final Color   bgColor;
  final Color   borderColor;
  final IconData icono;

  const _TarjetaBalance({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(height: 10),
          Text(valor,
              style: TextStyle(fontSize: 36,
                  fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(titulo,
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
          const SizedBox(height: 2),
          Text(subtitulo,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ],
      ),
    );
  }
}

// ── Fila detalle ──────────────────────────────────────────────
class _FilaDetalle extends StatelessWidget {
  final String label;
  final String valor;
  final bool   destacado;
  final Color? colorValor;

  const _FilaDetalle({
    required this.label,
    required this.valor,
    this.destacado  = false,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: const Color(0xFF475569),
                fontWeight: destacado ? FontWeight.w600 : FontWeight.normal)),
        Text(valor,
            style: TextStyle(
                fontSize: 13,
                fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
                color: colorValor ?? const Color(0xFF0F172A))),
      ],
    );
  }
}