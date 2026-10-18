import 'package:flutter/material.dart';

import '../../models/route_response.dart';
import '../../state/active_trip_state.dart';

class RouteRiskCard extends StatelessWidget {
  final RouteResponse? route;
  final ActiveTrip? trip;
  final VoidCallback? onEndTrip;
  const RouteRiskCard({super.key, this.route, this.trip, this.onEndTrip});

  @override
  Widget build(BuildContext context) {
    final result = trip?.route ?? route;
    final color = switch (result?.riskLevel) {
      'SAFE' => Colors.green,
      'CAUTION' => Colors.orange,
      'HIGH RISK' => Colors.red,
      _ => Colors.blueGrey,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trip != null) ...[
              Text(
                '${trip!.originName} ➔ ${trip!.destinationName}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  backgroundColor: color.withValues(alpha: .12),
                  label: Text(
                    result?.riskLevel ?? 'Route not assessed',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                if (result != null)
                  Text(
                    '${(result.distanceMeters / 1000).toStringAsFixed(1)} km • ${(result.durationSeconds / 60).ceil()} mins',
                  ),
              ],
            ),
            if (result == null)
              const Text('Search for a destination to assess your route.')
            else ...[
              const Text('Heuristic assessment of available hazard data'),
              for (final reason in result.reasons) Text(reason),
              for (final hazard in result.hazards)
                Text(
                  '${hazard.name}: ${hazard.hazardType} (severity ${hazard.severity}/5)',
                ),
              if (!result.weatherUsed)
                const Text('Weather was not included in this assessment.'),
              for (final limitation in result.limitations) Text(limitation),
              if (trip != null && onEndTrip != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onEndTrip,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('END TRIP'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
