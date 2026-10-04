import 'package:flutter/material.dart';

// ==============================================================================
// 🛡️ COMPACT SAFETY STATUS CARD WIDGET
// Sleek, compact overview displaying the AI Risk Score, Safe Zone verdict,
// and responsive environmental metrics with zero RenderFlex overflow.
// ==============================================================================
class SafetyStatusCard extends StatelessWidget {
  const SafetyStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8EFF7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0E4E91),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Top Row: Safe Zone Badge + AI Risk Pill ────────────────────────
          Row(
            children: [
              // Left: Shield Icon + Safe Zone Text
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F8EE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 20,
                        color: Color(0xFF1EAA55),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CURRENT STATUS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: Color(0xFF8A99AF),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'SAFE ZONE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1EAA55),
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF1EAA55),
                                size: 16,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Right: AI Risk Score Pill
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EE),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC3EED3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: Color(0xFF1EAA55),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'AI Risk: 12%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1EAA55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ─── One-line status description ───────────────────────────────────
          const Text(
            'No active landslide, flood, or roadblock alerts in your area.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF53647F),
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // ─── Responsive Environmental Stats Row ────────────────────────────
          const Row(
            children: [
              Expanded(
                child: _CompactStatItem(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Weather',
                  value: '21°C',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _CompactStatItem(
                  icon: Icons.terrain_outlined,
                  label: 'Slope',
                  value: 'Stable',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _CompactStatItem(
                  icon: Icons.water_drop_outlined,
                  label: 'Rainfall',
                  value: '0.2 mm',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Compact Stat Item Widget (Scales down gracefully without overflow) ───────
class _CompactStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CompactStatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEDF2F7)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF087CF0)),
            const SizedBox(width: 4),
            Text(
              '$label: ',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF8A99AF),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2D4F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
