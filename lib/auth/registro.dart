import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'iniciosesion.dart';

const String apiUrl = 'http://127.0.0.1:8000';

class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key});
  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  // Controladores
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();

  // Estado
  bool _obscureText = true;
  bool _obscureConfirmar = true;
  bool _cargando = false;
  String _error = '';
  String _exito = '';

  // Validaciones en tiempo real
  bool get _tiene8Caracteres => _contrasenaController.text.length >= 8;
  bool get _tieneMayuscula =>
      _contrasenaController.text.contains(RegExp(r'[A-Z]'));
  bool get _tieneMinuscula =>
      _contrasenaController.text.contains(RegExp(r'[a-z]'));
  bool get _tieneNumero =>
      _contrasenaController.text.contains(RegExp(r'[0-9]'));
  bool get _tieneEspecial =>
      _contrasenaController.text.contains(RegExp(r'[!@#\$%^&*]'));
  bool get _contrasenaValida =>
      _tiene8Caracteres &&
      _tieneMayuscula &&
      _tieneMinuscula &&
      _tieneNumero &&
      _tieneEspecial;

  // Nivel de seguridad de la contraseña
  String get _nivelSeguridad {
    int puntos = [
      _tiene8Caracteres,
      _tieneMayuscula,
      _tieneMinuscula,
      _tieneNumero,
      _tieneEspecial,
    ].where((v) => v).length;
    if (puntos <= 2) return 'Débil';
    if (puntos <= 3) return 'Media';
    return 'Fuerte';
  }

  Color get _colorSeguridad {
    switch (_nivelSeguridad) {
      case 'Débil':
        return const Color(0xFFDC2626);
      case 'Media':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF059669);
    }
  }

  // ── Llamada a la API ────────────────────────────────────────
  Future<void> _registrar() async {
    final correo = _correoController.text.trim();
    final contrasena = _contrasenaController.text.trim();
    final confirmar = _confirmarController.text.trim();

    // Validaciones locales
    if (correo.isEmpty || contrasena.isEmpty || confirmar.isEmpty) {
      setState(() => _error = 'Por favor completa todos los campos.');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9.\-]+@accaconcagua\.cl$').hasMatch(correo)) {
      setState(
        () => _error = 'Debes usar tu correo institucional @accaconcagua.cl',
      );
      return;
    }
    if (correo.length > 100) {
      setState(() => _error = 'El correo no puede superar 100 caracteres');
      return;
    }
    if (contrasena.contains(' ')) {
      setState(() => _error = 'La contraseña no puede contener espacios');
      return;
    }
    if (contrasena.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (contrasena.length > 64) {
      setState(() => _error = 'La contraseña no puede superar 64 caracteres');
      return;
    }
    if (!_contrasenaValida) {
      setState(
        () =>
            _error = 'La contraseña no cumple con los requisitos de seguridad.',
      );
      return;
    }
    if (contrasena != confirmar) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = '';
      _exito = '';
    });

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/registro'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'correo': correo, 'contrasena': contrasena}),
      );

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(
          () => _exito =
              data['mensaje'] ??
              'Cuenta creada exitosamente. Revisa tu correo institucional para activarla antes de iniciar sesión.',
        );
        await Future.delayed(const Duration(seconds: 5));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
        );
      } else {
        setState(() => _error = data['mensaje'] ?? 'Error al crear la cuenta.');
      }
    } catch (e) {
      setState(
        () => _error =
            'No se pudo establecer conexión con el servidor. Por favor, verifica tu conexión.',
      );
    } finally {
      setState(() => _cargando = false);
    }
  }

  @override
  void dispose() {
    _correoController.dispose();
    _contrasenaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool esAncho = constraints.maxWidth >= 920;
          final panelFormulario = _PanelFormularioRegistro(
            correoController: _correoController,
            contrasenaController: _contrasenaController,
            confirmarController: _confirmarController,
            obscureText: _obscureText,
            obscureConfirmar: _obscureConfirmar,
            cargando: _cargando,
            error: _error,
            exito: _exito,
            nivelSeguridad: _nivelSeguridad,
            colorSeguridad: _colorSeguridad,
            tiene8Caracteres: _tiene8Caracteres,
            tieneMayuscula: _tieneMayuscula,
            tieneMinuscula: _tieneMinuscula,
            tieneNumero: _tieneNumero,
            tieneEspecial: _tieneEspecial,
            onToggleObscure: () => setState(() => _obscureText = !_obscureText),
            onToggleObscureConfirmar: () =>
                setState(() => _obscureConfirmar = !_obscureConfirmar),
            onCambio: () => setState(() {}),
            onRegistrar: _registrar,
            onIrALogin: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const IniciarSesionPage()),
            ),
          );

          if (esAncho) {
            return Row(
              children: [
                Expanded(flex: 5, child: _PanelMarcaRegistro()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 40,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: panelFormulario,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                _PanelMarcaRegistro(compacto: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                  child: panelFormulario,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Panel izquierdo (o superior en movil): marca institucional
// ══════════════════════════════════════════════════════════════
class _PanelMarcaRegistro extends StatelessWidget {
  final bool compacto;
  const _PanelMarcaRegistro({this.compacto = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: compacto ? 260 : double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF001E42), Color(0xFF0B3B5C)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -90,
            top: -90,
            child: _AroDecorativoRegistro(
              diametro: 320,
              grosor: 1.4,
              opacidad: 0.10,
            ),
          ),
          Positioned(
            right: -40,
            bottom: -120,
            child: _AroDecorativoRegistro(
              diametro: 260,
              grosor: 1.4,
              opacidad: 0.08,
            ),
          ),
          Positioned(
            left: -60,
            bottom: 40,
            child: _AroDecorativoRegistro(
              diametro: 140,
              grosor: 1.2,
              opacidad: 0.08,
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compacto ? 28 : 64,
              vertical: compacto ? 28 : 56,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (!compacto)
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 2,
                        color: const Color(0xFF0F9F8F),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Sistema de Gestión de Personal',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: compacto ? 16 : 28),
                if (!compacto) const Spacer(flex: 3),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Aconcagua Centro Clínico',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compacto ? 30 : 46,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!compacto)
                      SizedBox(
                        width: 360,
                        child: Text(
                          'Moderno centro de salud que brinda a las provincias de Los Andes y San Felipe acceso a más de 18 especialidades médicas, con un equipo de más de 45 especialistas altamente calificados.',
                          textAlign: TextAlign.justify,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),

                if (!compacto) const Spacer(flex: 4),
                if (!compacto)
                  Row(
                    children: const [
                      _MarcaPuntoRegistro(texto: 'Seguridad'),
                      SizedBox(width: 22),
                      _MarcaPuntoRegistro(texto: 'Confianza'),
                      SizedBox(width: 22),
                      _MarcaPuntoRegistro(texto: 'Compromiso'),
                    ],
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AroDecorativoRegistro extends StatelessWidget {
  final double diametro;
  final double grosor;
  final double opacidad;
  const _AroDecorativoRegistro({
    required this.diametro,
    required this.grosor,
    required this.opacidad,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diametro,
      height: diametro,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(opacidad),
          width: grosor,
        ),
      ),
    );
  }
}

class _MarcaPuntoRegistro extends StatelessWidget {
  final String texto;
  const _MarcaPuntoRegistro({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Color(0xFF0F9F8F),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          texto,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Panel derecho (o inferior en movil): formulario de registro
// ══════════════════════════════════════════════════════════════
class _PanelFormularioRegistro extends StatelessWidget {
  final TextEditingController correoController;
  final TextEditingController contrasenaController;
  final TextEditingController confirmarController;
  final bool obscureText;
  final bool obscureConfirmar;
  final bool cargando;
  final String error;
  final String exito;
  final String nivelSeguridad;
  final Color colorSeguridad;
  final bool tiene8Caracteres;
  final bool tieneMayuscula;
  final bool tieneMinuscula;
  final bool tieneNumero;
  final bool tieneEspecial;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleObscureConfirmar;
  final VoidCallback onCambio;
  final VoidCallback onRegistrar;
  final VoidCallback onIrALogin;

  const _PanelFormularioRegistro({
    required this.correoController,
    required this.contrasenaController,
    required this.confirmarController,
    required this.obscureText,
    required this.obscureConfirmar,
    required this.cargando,
    required this.error,
    required this.exito,
    required this.nivelSeguridad,
    required this.colorSeguridad,
    required this.tiene8Caracteres,
    required this.tieneMayuscula,
    required this.tieneMinuscula,
    required this.tieneNumero,
    required this.tieneEspecial,
    required this.onToggleObscure,
    required this.onToggleObscureConfirmar,
    required this.onCambio,
    required this.onRegistrar,
    required this.onIrALogin,
  });

  InputDecoration _decoracion({
    required String hint,
    required IconData icono,
    Widget? suffix,
    Color? colorBorde,
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorBorde ?? const Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0F9F8F), width: 1.6),
      ),
      prefixIcon: Icon(icono, color: const Color(0xFF94A3B8), size: 20),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool confirmarNoCoincide =
        confirmarController.text.isNotEmpty &&
        confirmarController.text != contrasenaController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CREAR CUENTA',
          style: TextStyle(
            color: Color(0xFF0F9F8F),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Regístrate',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Crea tu cuenta con tu correo institucional.',
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 32),

        const Text(
          'Correo institucional',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: correoController,
          keyboardType: TextInputType.emailAddress,
          onChanged: (_) => onCambio(),
          decoration: _decoracion(
            hint: 'usuario@accaconcagua.cl',
            icono: Icons.mail_outline,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Debe usar su correo institucional @accaconcagua.cl',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
          ),
        ),
        const SizedBox(height: 18),

        const Text(
          'Contraseña',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: contrasenaController,
          obscureText: obscureText,
          onChanged: (_) => onCambio(),
          decoration: _decoracion(
            hint: 'Ingresa tu contraseña',
            icono: Icons.lock_outline,
            suffix: IconButton(
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF94A3B8),
                size: 20,
              ),
              onPressed: onToggleObscure,
            ),
          ),
        ),

        if (contrasenaController.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Seguridad: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Text(
                nivelSeguridad,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorSeguridad,
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 12),
        _itemValidacion('Mínimo 8 caracteres', tiene8Caracteres),
        _itemValidacion('Al menos una mayúscula', tieneMayuscula),
        _itemValidacion('Al menos una minúscula', tieneMinuscula),
        _itemValidacion('Al menos un número', tieneNumero),
        _itemValidacion(
          'Al menos un carácter especial (!@#\$%^&*)',
          tieneEspecial,
        ),
        const SizedBox(height: 18),

        const Text(
          'Confirmar contraseña',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: confirmarController,
          obscureText: obscureConfirmar,
          onChanged: (_) => onCambio(),
          decoration: _decoracion(
            hint: 'Confirma tu contraseña',
            icono: Icons.lock_outline,
            colorBorde: confirmarNoCoincide
                ? const Color(0xFFDC2626)
                : const Color(0xFFE2E8F0),
            suffix: IconButton(
              icon: Icon(
                obscureConfirmar
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF94A3B8),
                size: 20,
              ),
              onPressed: onToggleObscureConfirmar,
            ),
          ),
        ),
        if (confirmarNoCoincide)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Las contraseñas no coinciden',
              style: TextStyle(color: Color(0xFFDC2626), fontSize: 12),
            ),
          ),

        if (error.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (exito.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: Color(0xFF059669),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exito,
                    style: const TextStyle(
                      color: Color(0xFF047857),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: cargando ? null : onRegistrar,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF001E42),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: cargando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Registrar cuenta',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '¿Ya tienes una cuenta? ',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
            ),
            InkWell(
              onTap: onIrALogin,
              child: const Text(
                'Iniciar sesión',
                style: TextStyle(
                  color: Color(0xFF0F9F8F),
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemValidacion(String texto, bool cumple) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            cumple ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: cumple ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
          ),
          const SizedBox(width: 7),
          Text(
            texto,
            style: TextStyle(
              fontSize: 12,
              color: cumple ? const Color(0xFF059669) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
