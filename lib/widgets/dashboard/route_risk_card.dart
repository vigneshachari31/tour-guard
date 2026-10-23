import 'package:flutter/material.dart';

import '../../models/geofence_update.dart';
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
              _buildHazardAlertSection(
                context,
                ActiveTripState.instance.activeHazards,
                result.hazards,
              ),
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

  Color _severityColor(int severity) {
    if (severity >= 4) return const Color(0xFFDC2626);
    if (severity == 3) return const Color(0xFFEA580C);
    return const Color(0xFFD97706);
  }

  Color _severityBgColor(int severity) {
    if (severity >= 4) return const Color(0xFFFEF2F2);
    if (severity == 3) return const Color(0xFFFFF7ED);
    return const Color(0xFFFFFBEB);
  }

  IconData _hazardIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('flood')) return Icons.water_drop_rounded;
    if (lower.contains('landslide')) return Icons.terrain_rounded;
    if (lower.contains('weather') || lower.contains('storm')) {
      return Icons.thunderstorm_rounded;
    }
    if (lower.contains('tide')) return Icons.waves_rounded;
    return Icons.warning_amber_rounded;
  }

  String _hazardAdvice(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('flood')) {
      return 'Avoid low-lying areas. Never drive or walk through flood waters.';
    }
    if (lower.contains('landslide')) {
      return 'Watch for falling rocks/debris. Move away from steep slopes.';
    }
    if (lower.contains('weather') || lower.contains('storm')) {
      return 'Seek sturdy indoor shelter. Stay away from windows.';
    }
    if (lower.contains('tide')) {
      return 'Stay clear of low beaches and coastal breakwaters.';
    }
    return 'Stay alert, follow local instructions, and consider detouring.';
  }

  Widget _buildHazardRow({
    required String name,
    required String type,
    required int severity,
    required bool isLiveActive,
  }) {
    final sevColor = _severityColor(severity);
    final icon = _hazardIcon(type);
    final advice = _hazardAdvice(type);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sevColor.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _severityBgColor(severity),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: sevColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          type.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: sevColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Severity $severity/5',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: sevColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: sevColor),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    advice,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF334155),
                      height: 1.3,
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

  Widget _buildHazardAlertSection(
    BuildContext context,
    List<GeofenceHazard> activeHazards,
    List<HazardSummary> routeHazards,
  ) {
    final hasActive = activeHazards.isNotEmpty;
    final hasRoute = routeHazards.isNotEmpty;

    if (!hasActive && !hasRoute) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Route clear: No hazard zones reported on path.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF15803D),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isCritical = hasActive || routeHazards.any((h) => h.severity >= 4);
    final borderColor = isCritical ? const Color(0xFFFECACA) : const Color(0xFFFED7AA);
    final bgColor = isCritical ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7ED);
    final headerColor = isCritical ? const Color(0xFFDC2626) : const Color(0xFFEA580C);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.1),
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Icon(
                    hasActive ? Icons.warning_rounded : Icons.shield_outlined,
                    color: headerColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasActive
                          ? 'CRITICAL ALERT: IN HAZARD ZONE'
                          : 'HAZARDS ON ROUTE (${routeHazards.length})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: headerColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: headerColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      hasActive ? 'ACTIVE NOW' : 'ON ROUTE',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasActive) ...[
                    for (final hazard in activeHazards)
                      _buildHazardRow(
                        name: hazard.name,
                        type: hazard.type,
                        severity: hazard.severity,
                        isLiveActive: true,
                      ),
                  ] else ...[
                    for (final hazard in routeHazards)
                      _buildHazardRow(
                        name: hazard.name,
                        type: hazard.hazardType,
                        severity: hazard.severity,
                        isLiveActive: false,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
