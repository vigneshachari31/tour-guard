import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/geofence_update.dart';
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
  LatLng? position;
  double? distanceToDestination;
  bool arrived = false;
  List<GeofenceHazard> activeHazards = [];
  bool get completed => arrived;
  void markCompleted() {
    arrived = true;
    distanceToDestination = 0;
    notifyListeners();
  }

  void updatePosition(LatLng point) {
    if (_trip == null || arrived) return;
    position = point;
    distanceToDestination = Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      _trip!.destination.latitude,
      _trip!.destination.longitude,
    );
    notifyListeners();
  }

  void updateActiveHazards(List<GeofenceHazard> hazards) {
    activeHazards = List.unmodifiable(hazards);
    notifyListeners();
  }

  ActiveTrip? get trip => _trip;
  int get revision => _revision;
  void start(ActiveTrip trip) {
    _trip = trip;
    position = null;
    distanceToDestination = null;
    arrived = false;
    activeHazards = [];

    _revision++;
    notifyListeners();
  }

  void clear() {
    _trip = null;
    position = null;
    distanceToDestination = null;
    arrived = false;
    activeHazards = [];
    _revision++;
    notifyListeners();
  }

  void reconcileHazards(Set<int> activeIds) {
    final current = _trip;
    if (current == null) return;
    final route = current.route;
    final remaining = route.hazards
        .where((h) => activeIds.contains(h.id))
        .toList();
    if (remaining.length == route.hazards.length) return;
    _trip = ActiveTrip(
      originName: current.originName,
      destinationName: current.destinationName,
      origin: current.origin,
      destination: current.destination,
      route: RouteResponse(
        tripId: route.tripId,
        points: route.points,
        distanceMeters: route.distanceMeters,
        durationSeconds: route.durationSeconds,
        bufferMeters: route.bufferMeters,
        riskLevel: 'CAUTION',
        method: route.method,
        reasons: const [
          'Hazard data changed. Recheck the route for an updated assessment.',
        ],
        limitations: const ['The previous route assessment is out of date.'],
        hazards: remaining,
        weatherUsed: route.weatherUsed,
      ),
    );
    notifyListeners();
  }
}
