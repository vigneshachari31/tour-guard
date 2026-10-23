import 'package:flutter/material.dart';

// ==============================================================================
// 🏷️ DASHBOARD HEADER WIDGET
// Displays the App Title, Subtitle, and Notification Bell icon.
// ==============================================================================
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2EAF4)),
      ),
      child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: 66, height: 66,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: const Color(0xFFF1F7FF), borderRadius: BorderRadius.circular(16)),
          child: Image.asset('assets/images/tour_guard_logo.png', fit: BoxFit.contain,
              semanticLabel: 'Tour Guard logo'),
        ),
        const SizedBox(width: 14),
        const Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOUR GUARD',
              style: TextStyle(
                fontSize: 21,
                letterSpacing: 0.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2D4F), // Dark navy
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Explore with confidence.',
              style: TextStyle(fontSize: 13, color: Color(0xFF657A96)),
            ),
          ],
        )),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () {
            // TODO: Open Notifications / Advisories drawer
          },
          icon: const Icon(
            Icons.notifications_none_rounded,
            size: 28,
            color: Color(0xFF1A2D4F),
          ),
        ),
      ],
      ),
    );
  }
}

