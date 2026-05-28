import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../auth/session_service.dart';

const String _apiUrlBusq = 'http://127.0.0.1:8000';

class BusquedaEmpleados extends StatefulWidget {
  const BusquedaEmpleados({super.key});

  @override
  State<BusquedaEmpleados> createState() => _BusquedaEmpleadosState();
}

class _BusquedaEmpleadosState extends State<BusquedaEmpleados> {
  final _busquedaCtrl = TextEditingController();

  List<Map<String, dynamic>> _resultados = [];
  bool   _buscando = false;
  bool   _buscado  = false;
  String _error    = '';
  String _tipoBusq = 'apellido';

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    setState(() {
      if (value.contains('.') || value.contains('-')) {
        _tipoBusq = 'rut';
      } else {
        _tipoBusq = 'apellido';
      }
    });
  }

  Future<void> _buscar() async {
    final query = _busquedaCtrl.text.trim();

    if (query.isEmpty) {
      setState(() => _error = 'Ingresa un apellido (minimo 3 letras) o un RUT');
      return;
    }

    if (_tipoBusq == 'apellido' && query.length < 3) {
      setState(() => _error = 'Ingresa al menos 3 caracteres para buscar por apellido');
      return;
    }

    setState(() { _buscando = true; _error = ''; _resultados = []; });

    try {
      final token = await SessionService.obtenerToken();
      final uri = Uri.parse('$_apiUrlBusq/buscar-empleados').replace(
        queryParameters: {_tipoBusq: query},
      );

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      setState(() {
        _buscado = true;
        if (data['success'] == true) {
          _resultados = List<Map<String, dynamic>>.from(data['empleados'] ?? []);
        } else {
          _error = data['mensaje'] ?? 'Error al buscar';
        }
      });
    } catch (e) {
      setState(() => _error = 'No se pudo conectar al servidor');
    } finally {
      setState(() => _buscando = false);
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
          'Busqueda de Empleados',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Titulo
                const Text('Buscar Empleados',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 8),
                const Text(
                  'Busca por apellido (minimo 3 letras) o por RUT exacto (xx.xxx.xxx-x).',
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),

                // Indicador tipo busqueda
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _tipoBusq == 'rut'
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _tipoBusq == 'rut'
                          ? const Color(0xFFBFDBFE)
                          : const Color(0xFFBBF7D0),
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      _tipoBusq == 'rut'
                          ? Icons.badge_outlined
                          : Icons.person_search_outlined,
                      size: 16,
                      color: _tipoBusq == 'rut'
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _tipoBusq == 'rut'
                          ? 'Modo: Busqueda por RUT'
                          : 'Modo: Busqueda por Apellido',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _tipoBusq == 'rut'
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF16A34A),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // Campo de busqueda
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _busquedaCtrl,
                      onChanged: _onTextChanged,
                      onSubmitted: (_) => _buscar(),
                      decoration: InputDecoration(
                        hintText: 'Ej: Guerra   o   18.679.609-8',
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF001E42), width: 1.8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _buscando ? null : _buscar,
                      icon: _buscando
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.search),
                      label: const Text('Buscar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF001E42),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                const Text(
                  'El modo se detecta automaticamente: escribe letras para buscar por apellido, o escribe con puntos/guion para buscar por RUT.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 24),

                // Error
                if (_error.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error,
                              style: const TextStyle(color: Colors.red))),
                    ]),
                  ),

                // Sin resultados
                if (_buscado && _resultados.isEmpty && _error.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Column(children: [
                      Icon(Icons.person_search, size: 48, color: Color(0xFF94A3B8)),
                      SizedBox(height: 12),
                      Text('No se encontraron empleados',
                          style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
                      SizedBox(height: 4),
                      Text('Intenta con otro apellido o RUT',
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                    ]),
                  ),

                // Tabla resultados
                if (_resultados.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_resultados.length} resultado${_resultados.length == 1 ? '' : 's'} encontrado${_resultados.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Encabezado tabla
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF001E42),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        Expanded(
                            flex: 3,
                            child: Text('Nombre Completo',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13))),
                        Expanded(
                            flex: 2,
                            child: Text('RUT',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13))),
                        Expanded(
                            flex: 2,
                            child: Text('Cargo',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13))),
                        Expanded(
                            flex: 2,
                            child: Text('Fecha Ingreso',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Filas
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _resultados.length,
                    itemBuilder: (context, index) {
                      final e = _resultados[index];
                      final bool esPar = index % 2 == 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: esPar ? Colors.white : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(children: [
                            // Nombre
                            Expanded(
                              flex: 3,
                              child: Row(children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      const Color(0xFF001E42).withOpacity(0.1),
                                  child: Text(
                                    (e['nombres'] ?? '?')[0].toUpperCase(),
                                    style: const TextStyle(
                                        color: Color(0xFF001E42),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${e['nombres'] ?? ''} ${e['apellidos'] ?? ''}',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ]),
                            ),

                            // RUT
                            Expanded(
                              flex: 2,
                              child: Text(
                                e['rut'] ?? '—',
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF475569)),
                              ),
                            ),

                            // Cargo
                            Expanded(
                              flex: 2,
                              child: Text(
                                e['cargo'] ?? '—',
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF475569)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Fecha ingreso
                            Expanded(
                              flex: 2,
                              child: Text(
                                e['fecha_ingreso'] ?? '—',
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF475569)),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}