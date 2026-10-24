import 'package:flutter/material.dart';

import '../services/api_service.dart';

class SplashScreen extends StatefulWidget {
  final ApiService? api;
  const SplashScreen({super.key, this.api});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _logoSlideAnimation;
  String? _storageError;

  Future<void> _restoreSession() async {
    try {
      final session = await (widget.api ?? ApiService.instance).getSession();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(session == null ? '/login' : '/dashboard');
    } catch (_) {
      if (mounted) setState(() => _storageError = 'Could not read your saved login. Please retry.');
    }
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _logoSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    Future.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;

      _restoreSession();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _storageError != null ? Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_storageError!),
          TextButton(onPressed: _restoreSession, child: const Text('Retry')),
        ]) : SlideTransition(
          position: _logoSlideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Image.asset(
              'assets/images/tour_guard_logo.png',
              width: 245,
              fit: BoxFit.contain,
              semanticLabel: 'Tour Guard logo',
            ),
          ),
        ),
      ),
    );
  }
}
