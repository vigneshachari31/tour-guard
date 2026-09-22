import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    final isValid =
        _emailController.text.trim() == 'viggy@gmail.com' &&
        _passwordController.text == '12345678';

    if (isValid) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid email or password'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _MountainPainter())),
        SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 400,
                height: 930,
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    const _BrandHeader(),
                    const SizedBox(height: 26),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _LoginCard(
                        emailController: _emailController,
                        passwordController: _passwordController,
                        obscurePassword: _obscurePassword,
                        onTogglePassword: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onLogin: _login,
                        onCreateAccount: () => Navigator.push(
                          context,
                          PageRouteBuilder(
                            transitionDuration: const Duration(
                              milliseconds: 400,
                            ),
                            reverseTransitionDuration: const Duration(
                              milliseconds: 100,
                            ),
                            pageBuilder: (
                              context,
                              animation,
                              secondaryAnimation,
                            ) => const RegisterScreen(),
                            transitionsBuilder:
                                (
                                  context,
                                  animation,
                                  secondaryAnimation,
                                  child,
                                ) => FadeTransition(
                                  opacity: CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeInOut,
                                  ),
                                  child: child,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(
        width: 250,
        height: 250,
        child: Image(image: AssetImage('assets/images/tour_guard_logo.png')),
      ),
      SizedBox(height: 12),
      SizedBox(
        width: 90,
        height: 3,
        child: ColoredBox(color: Color(0xFF8BC8F7)),
      ),
      SizedBox(height: 16),
      Text(
        'AI-Powered Travel Risk Prediction\n& Smart Rescue System',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          height: 1.4,
          color: Color(0xFF53647F),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onCreateAccount,
  });

  static const blue = Color(0xFF087CF0);
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onTogglePassword;
  final VoidCallback onLogin;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 30, 20, 26),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .97),
      borderRadius: BorderRadius.circular(30),
      boxShadow: const [
        BoxShadow(
          color: Color(0x160E4E91),
          blurRadius: 30,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      children: [
        _InputField(
          controller: emailController,
          hint: 'Email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),
        _InputField(
          controller: passwordController,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          trailing: IconButton(
            onPressed: onTogglePassword,
            icon: Icon(
              obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: const Color(0xFF53647F),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
            child: const Text(
              'Forgot Password?',
              style: TextStyle(color: blue, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 62,
          child: ElevatedButton(
            onPressed: onLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const StadiumBorder(),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Login',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 14),
                Icon(Icons.arrow_forward_rounded, size: 28),
              ],
            ),
          ),
        ),
        const SizedBox(height: 29),
        const _SocialSection(),
        const SizedBox(height: 23),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'New here? ',
              style: TextStyle(color: Color(0xFF61708A), fontSize: 16),
            ),
            TextButton(
              onPressed: onCreateAccount,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
              ),
              child: const Text(
                'Create an account',
                style: TextStyle(
                  color: blue,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SocialSection extends StatelessWidget {
  const _SocialSection();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      Row(
        children: [
          Expanded(child: Divider(color: Color(0xFFD4DBE5))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'Or continue with',
              style: TextStyle(color: Color(0xFF61708A), fontSize: 15),
            ),
          ),
          Expanded(child: Divider(color: Color(0xFFD4DBE5))),
        ],
      ),
      SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SocialButton(label: 'G', color: Color(0xFF4285F4)),
          SizedBox(width: 28),
          _SocialButton(label: 'A', color: Colors.black),
          SizedBox(width: 28),
          _SocialButton(icon: Icons.phone_rounded, color: _LoginCard.blue),
        ],
      ),
    ],
  );
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.trailing,
    this.obscureText = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Widget? trailing;
  final bool obscureText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    style: const TextStyle(fontSize: 17),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF71809A), fontSize: 18),
      prefixIcon: Icon(icon, color: const Color(0xFF53647F)),
      suffixIcon: trailing,
      filled: true,
      fillColor: const Color(0xFFFCFDFF),
      contentPadding: const EdgeInsets.symmetric(vertical: 20),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFFE1E6ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFF087CF0), width: 1.5),
      ),
    ),
  );
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({this.label, this.icon, required this.color});

  final String? label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 62,
    height: 62,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0xFFE1E6ED), width: 1.5),
    ),
    child: Center(
      child: icon != null
          ? Icon(icon, color: color, size: 27)
          : Text(
              label!,
              style: TextStyle(
                color: color,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
    ),
  );
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * .46)
        ..lineTo(size.width * .16, size.height * .40)
        ..lineTo(size.width * .34, size.height * .50)
        ..lineTo(size.width * .53, size.height * .45)
        ..lineTo(size.width * .70, size.height * .52)
        ..lineTo(size.width, size.height * .39)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = const Color(0xFFE3F4FF),
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * .60)
        ..lineTo(size.width * .18, size.height * .52)
        ..lineTo(size.width * .42, size.height * .61)
        ..lineTo(size.width * .70, size.height * .55)
        ..lineTo(size.width, size.height * .49)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = const Color(0xFFCFEBFC),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
