import 'package:flutter/material.dart';

import '../../models/route_response.dart';
import '../../state/active_trip_state.dart';

class RouteRiskCard extends StatelessWidget {
  final RouteResponse? route;
  final ActiveTrip? trip;
  final VoidCallback? onEndTrip;
  final VoidCallback? onOpenMap;
  const RouteRiskCard({super.key, this.route, this.trip, this.onEndTrip, this.onOpenMap});

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
              Text(ActiveTripState.instance.arrived ? 'You’ve arrived!' : 'Trip in progress', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              if (ActiveTripState.instance.distanceToDestination != null)
                Text('${(ActiveTripState.instance.distanceToDestination! / 1000).toStringAsFixed(2)} km to destination (straight-line)'),
              const Text('Original route estimate below', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
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
              Text(
                result.hazards.isEmpty
                    ? 'No hazards reported along this route.'
                    : '${result.hazards.length} reported hazard zone(s) along your route.',
              ),
              if (!result.weatherUsed)
                const Text(
                  'Live weather not assessed.',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              const Text(
                'Route estimate, not a live safety guarantee.',
                style: TextStyle(color: Colors.blueGrey, fontSize: 12),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: const Text(
                  'Safety details',
                  style: TextStyle(fontSize: 14),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final hazard in result.hazards)
                          Text(
                            '${hazard.name}: ${hazard.hazardType.replaceAll('_', ' ')} (severity ${hazard.severity}/5)',
                          ),
                        for (final reason in result.reasons) Text(reason),
                        for (final limitation in result.limitations)
                          Text(limitation),
                      ],
                    ),
                  ),
                ],
              ),
              if (trip != null && onEndTrip != null) ...[
                TextButton.icon(onPressed: onOpenMap, icon: const Icon(Icons.map_outlined), label: const Text('OPEN MAP')),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                      title: const Text('Finish this trip?'),
                      content: const Text('Trip monitoring will stop.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Finish trip')),
                      ],
                    ));
                    if (confirmed == true) onEndTrip?.call();
                  },
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(ActiveTripState.instance.arrived ? 'FINISH TRIP' : 'END TRIP'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
