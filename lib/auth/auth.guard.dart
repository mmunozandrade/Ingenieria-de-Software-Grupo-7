import 'package:flutter/material.dart';
import 'session_service.dart';
import 'iniciosesion.dart';

class AuthGuard extends StatefulWidget {
  final Widget child;
  final String? rolRequerido; // 'admin', 'usuario', o null (cualquier rol)

  const AuthGuard({super.key, required this.child, this.rolRequerido});

  @override
  State<AuthGuard> createState() => _AuthGuardState();
}

class _AuthGuardState extends State<AuthGuard> {
  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    final token = await SessionService.obtenerToken();
    final rol = await SessionService.obtenerRol();

    if (!mounted) return;

    // Si no hay token → ir al login
    if (token == null || token.isEmpty) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
        (route) => false,
      );
      return;
    }

    // Si se requiere un rol específico y no coincide → ir al login
    if (widget.rolRequerido != null && rol != widget.rolRequerido) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
