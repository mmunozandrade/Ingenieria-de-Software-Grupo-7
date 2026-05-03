import 'package:flutter/material.dart';
import 'package:aconcagua/login.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema de Personal',
      home: const RegistroPage(), // Aquí llamas a la clase que creaste
    );
  }
}
