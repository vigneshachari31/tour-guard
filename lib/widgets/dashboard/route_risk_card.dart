import 'package:flutter/material.dart';

import '../../models/route_response.dart';

class RouteRiskCard extends StatelessWidget {
  final RouteResponse? route;
  const RouteRiskCard({super.key, this.route});

  @override
  Widget build(BuildContext context) {
    final result = route;
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
            Text(
              result?.riskLevel ?? 'Route not assessed',
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (result == null)
              const Text('Search for a destination to assess your route.')
            else ...[
              Text(
                '${(result.distanceMeters / 1000).toStringAsFixed(1)} km • ${(result.durationSeconds / 60).ceil()} min',
              ),
              const Text('Heuristic assessment of available hazard data'),
              for (final reason in result.reasons) Text(reason),
              for (final hazard in result.hazards)
                Text(
                  '${hazard.name}: ${hazard.hazardType} (severity ${hazard.severity}/5)',
                ),
              if (!result.weatherUsed)
                const Text('Weather was not included in this assessment.'),
              for (final limitation in result.limitations) Text(limitation),
            ],
          ],
        ),
      ),
    );
  }
}
