import 'package:flutter/material.dart';

// ==============================================================================
// 🏷️ DASHBOARD HEADER WIDGET
// Displays the App Title, Subtitle, and Notification Bell icon.
// ==============================================================================
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOUR GUARD',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A2D4F), // Dark navy
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Your safety is our priority.',
              style: TextStyle(fontSize: 14, color: Color(0xFF8A99AF)),
            ),
          ],
        ),
        IconButton(
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
    );
  }
}
