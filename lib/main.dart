import 'package:flutter/material.dart';
import 'auth/iniciosesion.dart'; // Ruta actualizada según tu imagen

void main() {
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
      // Obligamos a que la app inicie siempre en el Login
      home: const IniciarSesionPage(),
    );
  }
}
