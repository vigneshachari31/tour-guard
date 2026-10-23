import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'trip_socket.dart';

import 'package:latlong2/latlong.dart';

import '../models/geofence_update.dart';
import 'api_service.dart';
import 'current_location.dart';

/// Foreground monitoring only. Never uploads planned route coordinates as GPS.
class TripMonitor extends ChangeNotifier {
  final ApiService api;
  final bool useStreaming;
  final bool useWebSocket;
  final Stream<LatLng> Function()? positions;
  StreamSubscription<({LatLng point, double? heading})>? _positions;
  TripSocket? _socket;
  LatLng? _pendingPosition;
  VoidCallback? onCompleted;
  void Function(LatLng)? onPosition;
  void Function(LatLng, double?)? onNavigationPosition;
  double? _pendingHeading;
  void Function(List<GeofenceHazard>)? onHazards;
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
  Set<int>? _activeHazardIds;
  void reconcileHazards(Set<int> activeIds) {
    _activeHazardIds = activeIds;
    hazards = hazards.where((h) => activeIds.contains(h.id)).toList();
    onHazards?.call(hazards);
    if (!_disposed) notifyListeners();
  }

  TripMonitor({
    ApiService? api,
    Future<LatLng> Function()? locate,
    this.interval = const Duration(seconds: 10),
    this.positions,
    this.useWebSocket = true,
  }) : useStreaming = locate == null || positions != null,
       api = api ?? ApiService.instance,
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
    onHazards?.call(hazards);
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
    _positions?.cancel();
    _positions = null;
    _socket?.dispose();
    _socket = null;
    _pendingPosition = null;
    if (_tripId != null && _foreground && !_disposed) {
      _timer = Timer.periodic(interval, (_) => poll());
      unawaited(_startUpdates(_generation));
    }
  }

  Future<void> _startUpdates(int generation) async {
    await poll(); // Requests permission and publishes the initial real observation.
    if (!useStreaming ||
        _disposed ||
        !_foreground ||
        generation != _generation ||
        _tripId == null) {
      return;
    }
    final stream =
        positions?.call().map((p) => (point: p, heading: null as double?)) ??
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).map(
          (p) => (
            point: LatLng(p.latitude, p.longitude),
            heading: p.heading as double?,
          ),
        );
    _positions = stream.listen(
      (point) {
        if (generation == _generation) {
          unawaited(poll(point.point, point.heading));
        }
      },
      onError: (_) {
        if (!_disposed && generation == _generation) {
          error = 'GPS stream unavailable. Retrying location checks.';
          notifyListeners();
        }
      },
    );
  }

  Future<void> poll([LatLng? sample, double? heading]) async {
    final id = _tripId, generation = _generation;
    if (_disposed || !_foreground || id == null) return;
    if (sample != null) {
      onNavigationPosition?.call(sample, heading);
    }
    if (_busy) {
      if (sample != null) {
        _pendingPosition = sample;
        _pendingHeading = heading;
      }
      return;
    }
    _busy = true;
    notifyListeners();
    var locating = true;
    try {
      final position = sample ?? await locate();
      if (_disposed || generation != _generation) return;
      locating = false;
      onPosition?.call(position);
      if (sample == null && _pendingPosition == null) {
        onNavigationPosition?.call(position, null);
      }
      GeofenceUpdate update;
      try {
        if (!useStreaming || !useWebSocket) throw StateError('HTTP transport');
        _socket ??= TripSocket(api, id);
        update = await _socket!.send(position.latitude, position.longitude);
      } catch (_) {
        _socket?.dispose();
        _socket = null;
        if (_disposed || generation != _generation) return;
        update = await api.recordTripLocation(
          id,
          position.latitude,
          position.longitude,
        );
      }
      if (_disposed || generation != _generation) return;
      hazards = update.currentHazards
          .where(
            (h) => _activeHazardIds == null || _activeHazardIds!.contains(h.id),
          )
          .toList();
      error = null;
      lastCheckedAt = DateTime.now();
      onHazards?.call(hazards);
      if (update.status == "COMPLETED") {
        setTrip(null);
        onCompleted?.call();
      }
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
      if (!_disposed && generation == _generation) {
        notifyListeners();
        final pending = _pendingPosition;
        _pendingPosition = null;
        if (pending != null) unawaited(poll(pending, _pendingHeading));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _positions?.cancel();
    _socket?.dispose();
    super.dispose();
  }
}
