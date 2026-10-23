import 'package:flutter/material.dart';

import '../../models/route_response.dart';
import '../../models/geofence_update.dart';
import '../hazard_alert_details.dart';
import '../../state/active_trip_state.dart';

class RouteRiskCard extends StatelessWidget {
  final RouteResponse? route;
  final ActiveTrip? trip;
  final List<GeofenceHazard> activeHazards;
  final VoidCallback? onEndTrip;
  final VoidCallback? onOpenMap;
  const RouteRiskCard({
    super.key,
    this.route,
    this.trip,
    this.activeHazards = const [],
    this.onEndTrip,
    this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final result = trip?.route ?? route;
    if (result == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF102B50), Color(0xFF145DA0)]),
          borderRadius: BorderRadius.circular(18),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          const heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Where are you heading?', style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              SizedBox(height: 4),
              Text('Check routes, reports and weather before you go.',
                style: TextStyle(color: Color(0xFFD4E5F7), fontSize: 13, height: 1.4)),
            ],
          );
          final action = onOpenMap == null ? null : FilledButton.icon(
            onPressed: onOpenMap,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white, foregroundColor: const Color(0xFF145DA0)),
            icon: const Icon(Icons.alt_route, size: 18),
            label: const Text('Plan your journey'),
          );
          if (constraints.maxWidth >= 600) {
            return Row(children: [
              const Expanded(child: heading),
              if (action != null) ...[const SizedBox(width: 20), action],
            ]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [heading, if (action != null) ...[const SizedBox(height: 10), action]],
          );
        }),
      );
    }
    final color = switch (result.riskLevel) {
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
                ActiveTripState.instance.arrived
                    ? 'You’ve arrived!'
                    : 'Trip in progress',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (ActiveTripState.instance.distanceToDestination != null)
                Text(
                  '${(ActiveTripState.instance.distanceToDestination! / 1000).toStringAsFixed(2)} km to destination (straight-line)',
                ),
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
                    result.riskLevel,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${(result.distanceMeters / 1000).toStringAsFixed(1)} km • ${(result.durationSeconds / 60).ceil()} mins',
                ),
              ],
            ),
            ...[
              HazardAlertDetails(
                activeHazards: activeHazards.where((h) => h.id > 0).toList(),
                // Backend reserves negative IDs for tourist reports.
                routeHazards: result.hazards
                    .where(
                      (h) => h.id > 0 && h.source != 'Verified tourist report',
                    )
                    .toList(),
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
              if (trip != null && onEndTrip != null) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('OPEN MAP'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Finish this trip?'),
                            content: const Text('Trip monitoring will stop.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Finish trip'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) onEndTrip?.call();
                      },
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(
                        ActiveTripState.instance.arrived
                            ? 'FINISH TRIP'
                            : 'END TRIP',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
