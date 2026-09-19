import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _blue = Color(0xFF087CF0);

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _hidePass = true, _hideConfirm = true, _agreed = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _mobile, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _register() {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _mobile.text.trim().isEmpty ||
        _pass.text.isEmpty) {
      return _snack('Please fill in all fields.', ok: false);
    }
    if (_mobile.text.trim().length < 10) {
      return _snack('Enter a valid mobile number.', ok: false);
    }
    if (_pass.text != _confirm.text) {
      return _snack('Passwords do not match.', ok: false);
    }
    if (_pass.text.length < 8) {
      return _snack('Password must be at least 8 characters.', ok: false);
    }
    if (!_agreed) {
      return _snack('Please agree to the Terms & Privacy Policy.', ok: false);
    }
    _snack('Account created successfully! 🎉', ok: true);
  }

  void _snack(String msg, {required bool ok}) => ScaffoldMessenger.of(context)
      .showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );

  Widget _eyeIcon(bool hidden, VoidCallback onTap) => IconButton(
    onPressed: onTap,
    icon: Icon(
      hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      color: const Color(0xFF53647F),
    ),
  );

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
                    // ── Header
                    const Column(
                      children: [
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: Image(
                            image: AssetImage(
                              'assets/images/tour_guard_logo.png',
                            ),
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Create Your Account',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A2D4F),
                            letterSpacing: 0.2,
                          ),
                        ),
                        SizedBox(height: 6),
                        SizedBox(
                          width: 70,
                          height: 3,
                          child: ColoredBox(color: Color(0xFF8BC8F7)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // ── Card
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _field(
                              _name,
                              'Full Name',
                              Icons.person_outline_rounded,
                              type: TextInputType.name,
                            ),
                            const SizedBox(height: 14),
                            _field(
                              _email,
                              'Email',
                              Icons.mail_outline_rounded,
                              type: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 14),
                            _field(
                              _mobile,
                              'Mobile Number',
                              Icons.phone_outlined,
                              type: TextInputType.phone,
                              formatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                            const SizedBox(height: 14),
                            _field(
                              _pass,
                              'Password',
                              Icons.lock_outline_rounded,
                              obscure: _hidePass,
                              suffix: _eyeIcon(
                                _hidePass,
                                () => setState(() => _hidePass = !_hidePass),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _field(
                              _confirm,
                              'Confirm Password',
                              Icons.lock_outline_rounded,
                              obscure: _hideConfirm,
                              suffix: _eyeIcon(
                                _hideConfirm,
                                () => setState(
                                  () => _hideConfirm = !_hideConfirm,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Terms checkbox
                            GestureDetector(
                              onTap: () => setState(() => _agreed = !_agreed),
                              behavior: HitTestBehavior.translucent,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _agreed,
                                      onChanged: (v) =>
                                          setState(() => _agreed = v ?? false),
                                      activeColor: _blue,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFFD4DBE5),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: RichText(
                                      text: const TextSpan(
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF61708A),
                                        ),
                                        children: [
                                          TextSpan(text: 'I agree to the '),
                                          TextSpan(
                                            text: 'Terms of Service',
                                            style: TextStyle(
                                              color: _blue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(text: ' & '),
                                          TextSpan(
                                            text: 'Privacy Policy',
                                            style: TextStyle(
                                              color: _blue,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Create Account button
                            SizedBox(
                              width: double.infinity,
                              height: 62,
                              child: ElevatedButton(
                                onPressed: _register,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _blue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: const StadiumBorder(),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Create Account',
                                      style: TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(width: 14),
                                    Icon(Icons.arrow_forward_rounded, size: 26),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Sign in row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Already have an account? ',
                                  style: TextStyle(
                                    color: Color(0xFF61708A),
                                    fontSize: 16,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                  ),
                                  child: const Text(
                                    'Sign In',
                                    style: TextStyle(
                                      color: _blue,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    Widget? suffix,
    TextInputType? type,
    List<TextInputFormatter>? formatters,
  }) => TextField(
    controller: ctrl,
    obscureText: obscure,
    keyboardType: type,
    inputFormatters: formatters,
    style: const TextStyle(fontSize: 17),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF71809A), fontSize: 18),
      prefixIcon: Icon(icon, color: const Color(0xFF53647F)),
      suffixIcon: suffix,
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
