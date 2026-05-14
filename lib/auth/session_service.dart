import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String _tokenKey = 'access_token';
  static const String _rolKey = 'rol';
  static const String _nombreKey = 'nombre_completo';
  static const String _cargoKey = 'cargo';
  static const String _idKey = 'id_usuario';

  // Guardar sesión después del login
  static Future<void> guardarSesion({
    required String token,
    required String rol,
    required String nombreCompleto,
    required String cargo,
    required int idUsuario,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_rolKey, rol);
    await prefs.setString(_nombreKey, nombreCompleto);
    await prefs.setString(_cargoKey, cargo);
    await prefs.setInt(_idKey, idUsuario);
  }

  // Obtener token guardado
  static Future<String?> obtenerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Obtener rol guardado
  static Future<String?> obtenerRol() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rolKey);
  }

  // Obtener nombre completo
  static Future<String?> obtenerNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nombreKey);
  }

  // Verificar si hay sesión activa
  static Future<bool> haySesionActiva() async {
    final token = await obtenerToken();
    return token != null && token.isNotEmpty;
  }

  // Cerrar sesión (borrar todo)
  static Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
