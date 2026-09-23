import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/register_screen.dart';
import 'screens/splash_screen.dart';

// ==============================================================================
// 🚀 APPLICATION ENTRY POINT (TOUR GUARD)
// AI-Powered Travel Risk Prediction & Smart Rescue System
// ==============================================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TravelRiskApp());
}

class TravelRiskApp extends StatelessWidget {
  const TravelRiskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tour Guard',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087CF0),
          primary: const Color(0xFF087CF0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F9FC),
      ),
      // App starts at SplashScreen -> navigates to LoginScreen -> DashboardScreen
      home: const SplashScreen(),
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/map': (context) => const MapScreen(),
      },
    );
  }
}
