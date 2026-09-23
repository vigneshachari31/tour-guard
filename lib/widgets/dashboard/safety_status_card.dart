import 'package:flutter/material.dart';

// ==============================================================================
// 🛡️ SAFETY STATUS CARD WIDGET
// Displays the AI Risk Score (e.g. 12% Low), Safe Zone status, and Live
// environmental metrics (Weather, Slope/Terrain Risk, Rainfall).
// ==============================================================================
class SafetyStatusCard extends StatelessWidget {
  const SafetyStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0E4E91),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Shield Icon & AI Risk Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F3FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 28,
                  color: Color(0xFF087CF0),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EE),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFC3EED3)),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(radius: 4, backgroundColor: Color(0xFF1EAA55)),
                    SizedBox(width: 6),
                    Text(
                      'AI Risk: 12% (Low)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1EAA55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Title & Verdict
          const Text(
            'CURRENT SAFETY STATUS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF8A99AF),
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            children: [
              Text(
                'SAFE ZONE',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1EAA55),
                  letterSpacing: 0.3,
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, color: Color(0xFF1EAA55), size: 24),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'No active landslide, flood, or roadblock threats detected nearby.',
            style: TextStyle(fontSize: 14, color: Color(0xFF53647F), height: 1.4),
          ),

          const SizedBox(height: 18),
          const Divider(color: Color(0xFFEDF2F7), thickness: 1),
          const SizedBox(height: 14),

          // Environmental Metrics Row
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(
                icon: Icons.wb_sunny_outlined,
                label: 'Weather',
                value: '21°C Clear',
              ),
              _StatItem(
                icon: Icons.terrain_outlined,
                label: 'Slope Risk',
                value: 'Stable',
              ),
              _StatItem(
                icon: Icons.water_drop_outlined,
                label: 'Rainfall',
                value: '0.2 mm/h',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Stat Item Helper Widget ─────────────────────────────────────────────────
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF087CF0)),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Color(0xFF8A99AF),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A2D4F),
          ),
        ),
      ],
    );
  }
}

