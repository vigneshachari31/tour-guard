import 'package:flutter/material.dart';

// ==============================================================================
// ⚡ SAFETY SERVICES 2x2 GRID WIDGET
// Provides quick access to AI Risk Radar, Safe Routes, Live Sharing, & Reports.
// ==============================================================================
class SafetyServicesGrid extends StatelessWidget {
  final VoidCallback? onRiskRadarTap;
  final VoidCallback? onSafeRouteTap;
  final VoidCallback? onLiveSharingTap;
  final VoidCallback? onReportHazardTap;

  const SafetyServicesGrid({
    super.key,
    this.onRiskRadarTap,
    this.onSafeRouteTap,
    this.onLiveSharingTap,
    this.onReportHazardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SAFETY SERVICES',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF1A2D4F),
          ),
        ),
        const SizedBox(height: 14),

        // Row 1
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.auto_awesome_rounded,
                iconBgColor: const Color(0xFFE8F3FF),
                iconColor: const Color(0xFF087CF0),
                title: 'AI Risk Radar',
                subtitle: 'Predict terrain & weather hazards',
                onTap: onRiskRadarTap ?? () {},
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ActionCard(
                icon: Icons.alt_route_rounded,
                iconBgColor: const Color(0xFFE8F8EE),
                iconColor: const Color(0xFF1EAA55),
                title: 'Safe Route',
                subtitle: 'Avoid red landslide & flood zones',
                onTap: onSafeRouteTap ?? () {},
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Row 2
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.share_location_rounded,
                iconBgColor: const Color(0xFFF3E8FF),
                iconColor: const Color(0xFF8B5CF6),
                title: 'Live Sharing',
                subtitle: 'Share real-time GPS with family',
                onTap: onLiveSharingTap ?? () {},
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _ActionCard(
                icon: Icons.report_problem_outlined,
                iconBgColor: const Color(0xFFFFF4E5),
                iconColor: const Color(0xFFFF9800),
                title: 'Report Hazard',
                subtitle: 'Alert others on roadblocks',
                onTap: onReportHazardTap ?? () {},
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Action Card Helper Widget ───────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0E4E91),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 24, color: iconColor),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2D4F),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8A99AF),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

