import 'package:flutter/material.dart';

// ==============================================================================
// 🚨 SMART RESCUE & SOS BEACON WIDGET
// High-visibility emergency section with one-touch SOS and helpline quick-dials.
// ==============================================================================
class SmartRescueCard extends StatelessWidget {
  final VoidCallback? onTriggerSos;
  final VoidCallback? onPoliceDial;
  final VoidCallback? onDisasterDial;

  const SmartRescueCard({
    super.key,
    this.onTriggerSos,
    this.onPoliceDial,
    this.onDisasterDial,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFDC2626),
            Color(0xFF991B1B),
          ], // Deep Emergency Crimson
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33DC2626),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with GPS Beacon Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'SMART RESCUE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: Colors.greenAccent,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'GPS Active',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Description
          const Text(
            'In distress? The SOS demo logs your GPS to the app backend; it does not contact rescue services. Call an emergency number directly for real help.',
            style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
          ),

          const SizedBox(height: 14),

          // Trigger Emergency SOS Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed:
                  onTriggerSos ??
                  () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          '🚨 SOS Alert Dispatched to Rescue Command Center!',
                        ),
                        backgroundColor: Color(0xFFDC2626),
                        duration: Duration(seconds: 4),
                      ),
                    );
                  },
              icon: const Icon(
                Icons.sos_rounded,
                size: 26,
                color: Color(0xFFDC2626),
              ),
              label: const Text(
                'TRIGGER EMERGENCY SOS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Color(0xFFDC2626),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Direct Helplines (Fitted to prevent overflow on narrow screens)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onPoliceDial ?? () {},
                  icon: const Icon(
                    Icons.phone_in_talk_rounded,
                    size: 15,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'Police: 112',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('•', style: TextStyle(color: Colors.white54)),
                ),
                TextButton.icon(
                  onPressed: onDisasterDial ?? () {},
                  icon: const Icon(
                    Icons.support_agent_rounded,
                    size: 15,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'Disaster Helpline: 1077',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
