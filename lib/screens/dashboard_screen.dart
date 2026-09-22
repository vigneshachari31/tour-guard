import 'package:flutter/material.dart';

import '../widgets/dashboard/dashboard_header.dart';
import '../widgets/dashboard/safety_services_grid.dart';
import '../widgets/dashboard/safety_status_card.dart';
import '../widgets/dashboard/search_destination_bar.dart';
import '../widgets/dashboard/smart_rescue_card.dart';

// ==============================================================================
// 📱 MAIN DASHBOARD SCREEN (TOUR GUARD)
// Modular, clean, and composed of 5 dedicated safety components.
// ==============================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Current active tab index in the Bottom Navigation Bar
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC), // Modern off-white / slate
      // Main Scrollable Body
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. App Title & Notifications Header
              DashboardHeader(),
              SizedBox(height: 25),

              // 2. AI Safety Status & Live Environmental Card
              SafetyStatusCard(),
              SizedBox(height: 26),

              // 3. Destination Search Bar & Quick Suggestion Chips
              SearchDestinationBar(),
              SizedBox(height: 28),

              // 4. 2x2 Core Safety Services Grid (AI Radar, Route, Sharing, Reports)
              SafetyServicesGrid(),
              SizedBox(height: 28),

              // 5. Emergency SOS Beacon & Official Helplines (112, 1077)
              SmartRescueCard(),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),

      // 6. Bottom Navigation Bar (Home, Safe Route, SOS, Alerts, Profile)
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x0A0E4E91),
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE8F3FF),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF087CF0)),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.alt_route_outlined),
              selectedIcon: Icon(
                Icons.alt_route_rounded,
                color: Color(0xFF087CF0),
              ),
              label: 'Safe Route',
            ),
            NavigationDestination(
              icon: Icon(Icons.emergency_outlined),
              selectedIcon: Icon(
                Icons.emergency_rounded,
                color: Color(0xFFDC2626),
              ),
              label: 'SOS Rescue',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(
                Icons.notifications_rounded,
                color: Color(0xFF087CF0),
              ),
              label: 'Alerts',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: Color(0xFF087CF0),
              ),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
