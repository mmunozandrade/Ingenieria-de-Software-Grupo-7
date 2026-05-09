import 'package:flutter/material.dart';
import 'package:aconcagua/inicial.dart';

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
      home: const DashboardScreen(),
    );
  }
}

//tamano de pantalla
class ResponsiveLayout extends StatelessWidget {
  final Widget mobileScaffold;
  final Widget tabletScaffold;
  final Widget desktopScaffold;

  const ResponsiveLayout({
    super.key,
    required this.mobileScaffold,
    required this.tabletScaffold,
    required this.desktopScaffold,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 400) {
          return mobileScaffold;
        } else if (constraints.maxWidth < 800) {
          return tabletScaffold;
        } else {
          return desktopScaffold;
        }
      },
    );
  }
}
