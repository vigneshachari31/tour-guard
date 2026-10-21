import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/geofence_update.dart';
import 'api_service.dart';
import 'current_location.dart';

/// Foreground monitoring only. Never uploads planned route coordinates as GPS.
class TripMonitor extends ChangeNotifier {
  final ApiService api;
  final Future<LatLng> Function() locate;
  final Duration interval;
  Timer? _timer;
  int? _tripId;
  int _generation = 0;
  bool _busy = false, _disposed = false, _foreground = true;
  List<GeofenceHazard> hazards = [];
  String? error;
  bool get isChecking => _busy;
  DateTime? lastCheckedAt;

  TripMonitor({
    ApiService? api,
    Future<LatLng> Function()? locate,
    this.interval = const Duration(seconds: 10),
  }) : api = api ?? ApiService.instance,
       locate =
           locate ??
           (() async {
             final position = await requireCurrentLocation();
             return LatLng(position.latitude, position.longitude);
           });

  void setTrip(int? id) {
    if (id == _tripId) return;
    _generation++;
    _tripId = id;
    hazards = [];
    error = null;
    lastCheckedAt = null;
    _restart();
    notifyListeners();
  }

  void setForeground(bool value) {
    if (_foreground == value) return;
    _foreground = value;
    _generation++;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (_tripId != null && _foreground && !_disposed) {
      _timer = Timer.periodic(interval, (_) => poll());
      unawaited(poll());
    }
  }

  Future<void> poll() async {
    final id = _tripId, generation = _generation;
    if (_busy || _disposed || !_foreground || id == null) return;
    _busy = true;
    notifyListeners();
    var locating = true;
    try {
      final position = await locate();
      if (_disposed || generation != _generation) return;
      locating = false;
      final update = await api.recordTripLocation(
        id,
        position.latitude,
        position.longitude,
      );
      if (_disposed || generation != _generation) return;
      hazards = update.currentHazards;
      error = null;
      lastCheckedAt = DateTime.now();
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = locating
          ? 'Location unavailable. Check GPS and location permission.'
          : failure is ApiException && failure.statusCode == 401
          ? 'Session expired. Please sign in again.'
          : failure is ApiException &&
                (failure.statusCode == 404 || failure.statusCode == 409)
          ? 'This trip is no longer available. Start a new trip.'
          : 'Live updates unavailable. Retrying automatically.';
      // Retain the last warning while offline; do not report a false exit.
    } finally {
      _busy = false;
      if (!_disposed && generation == _generation) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
