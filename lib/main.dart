import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'auth/iniciosesion.dart'; // Ruta actualizada según tu imagen
import 'auth/verificarCuenta.dart';

void main() {
  // Sin esto, Flutter Web usa URLs con "#" (como localhost:5000/#/algo)
  // en vez de URLs "limpias" (localhost:5000/algo). El enlace de
  // activacion que se manda por correo usa una URL limpia, asi que
  // esto es obligatorio para que el enlace del correo funcione.
  usePathUrlStrategy();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clínica Aconcagua - RRHH',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF009A8D)),
      ),
      // En vez de "home" fijo, usamos onGenerateRoute para poder leer
      // la URL real que abrio el navegador. Esto es lo que permite que
      // el enlace de activacion (.../verificar-cuenta/{token}) abra la
      // pantalla correcta con el token correspondiente, en vez de
      // ir siempre al Login sin importar la direccion visitada.
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');

        // La URL tiene el formato /verificar-cuenta/<token>
        if (uri.pathSegments.length == 2 &&
            uri.pathSegments.first == 'verificar-cuenta') {
          final token = uri.pathSegments[1];
          return MaterialPageRoute(
            builder: (_) => VerificarCuentaScreen(token: token),
          );
        }

        // Cualquier otra direccion (o la raiz "/") abre el Login,
        // igual que antes.
        return MaterialPageRoute(builder: (_) => const IniciarSesionPage());
      },
    );
  }
}
