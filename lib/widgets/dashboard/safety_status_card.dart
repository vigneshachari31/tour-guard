import 'package:flutter/material.dart';

// ==============================================================================
// 🛡️ COMPACT SAFETY STATUS CARD WIDGET
// Dashboard entry point for route-based risk estimates from the backend.
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
          // ─── Top Row: Route Risk Status ────────────────────────────────────
          Row(
            children: [
              // Left: Shield Icon + Safe Zone Text
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F3FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 20,
                        color: Color(0xFF087CF0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ROUTE SAFETY',
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
                                'PLAN A ROUTE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF087CF0),
                                  letterSpacing: 0.2,
                                ),
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
                  color: const Color(0xFFE8F3FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFC7E2FF)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: Color(0xFF087CF0),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Risk on route',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF087CF0),
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
            'Choose a destination to request a prototype risk estimate and nearby hazard reports.',
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

          const Text(
            'Live weather and verified hazard feeds are not connected.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8A99AF),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
