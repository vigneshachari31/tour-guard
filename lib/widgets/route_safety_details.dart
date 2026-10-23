import 'package:flutter/material.dart';
import '../models/route_response.dart';

String routeSummary(RouteResponse route) {
  final text = route.reasons.join(' ');
  if (text.contains('Only one route available')) return 'No alternative route available.';
  if (text.contains('Original fastest route')) return 'Fastest route. Compare routes to check for fewer hazards.';
  if (text.contains('Original route is already')) return 'This route has the lowest reported hazard level of the options checked.';
  if (text.contains('Compared')) {
    return route.hazards.isEmpty
      ? 'Selected a route with no reported hazards nearby.'
      : 'Selected the lowest-hazard option. Stay alert for reported hazards.';
  }
  if (text.contains('out of date') || text.contains('Hazard data changed')) return 'Hazard information changed. Check your route again.';
  return 'Based on available hazard reports and weather.';
}

class RouteSafetyDetails extends StatelessWidget {
  final RouteResponse route;
  const RouteSafetyDetails({super.key, required this.route});

  Widget section(IconData icon, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 22, color: const Color(0xFF087CF0)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(body, style: const TextStyle(fontSize: 13, height: 1.4)),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final weather = RegExp(r'Weather at route origin: rain ([\d.]+) mm/h, wind ([\d.]+) km/h').firstMatch(route.reasons.join(' '));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      section(Icons.alt_route, 'Your route', routeSummary(route)),
      section(Icons.warning_amber_rounded, 'Reported hazards', route.hazards.isEmpty
          ? 'None reported nearby. Unreported hazards may still exist.'
          : route.hazards.map((h) => '${h.name} — ${h.severity >= 4 ? 'High' : h.severity >= 2 ? 'Moderate' : 'Low'} severity').join('\n')),
      section(Icons.cloud_outlined, 'Weather near your starting point', !route.weatherUsed
          ? 'Weather unavailable. Check local conditions before leaving.'
          : weather == null ? 'Weather included in this assessment.'
          : 'Rain ${weather.group(1)} mm/h · Wind ${weather.group(2)} km/h'),
      if (route.weatherUsed && route.reasons.any((r) => r.startsWith('Weather exceeds')))
        section(Icons.umbrella_outlined, 'Weather warning', 'Rain or wind is elevated. Check local advisories before travelling.'),
      const Text('Conditions can change and some hazards may be unreported. This is an estimate, not a safety guarantee.',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4)),
      if (route.weatherUsed)
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Weather covers your starting point, not the whole journey.',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey))),
      Material(color: Colors.transparent, child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Sources & assessment notes', style: TextStyle(fontSize: 12)),
        children: [Align(alignment: Alignment.centerLeft, child: Text(
          [...route.reasons, ...route.limitations].join('\n\n'),
          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
        ))],
      )),
    ]);
  }
}
