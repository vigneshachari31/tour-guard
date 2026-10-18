import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_response.dart';

/// A successfully assessed trip. Distances are metres; durations are seconds.
class ActiveTrip {
  final String originName, destinationName;
  final LatLng origin, destination;
  final RouteResponse route;
  const ActiveTrip({
    required this.originName,
    required this.destinationName,
    required this.origin,
    required this.destination,
    required this.route,
  });
  double get distance => route.distanceMeters;
  double get duration => route.durationSeconds;
  String get riskLevel => route.riskLevel;
  List<String> get hazardNotes => List.unmodifiable([
    ...route.reasons,
    for (final hazard in route.hazards)
      '${hazard.name}: ${hazard.hazardType} (severity ${hazard.severity}/5)',
  ]);
}

/// Session-scoped state shared by the dashboard and route planner.
/// It survives navigation, but is cleared at logout or End Trip.
class ActiveTripState extends ChangeNotifier {
  static final instance = ActiveTripState();
  ActiveTrip? _trip;
  int _revision = 0;
  ActiveTrip? get trip => _trip;
  int get revision => _revision;
  void start(ActiveTrip trip) {
    _trip = trip;
    _revision++;
    notifyListeners();
  }

  void clear() {
    _trip = null;
    _revision++;
    notifyListeners();
  }
}
