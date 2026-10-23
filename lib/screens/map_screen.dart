import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/api_service.dart';
import '../services/hazard_catalog.dart';
import '../services/current_location.dart';
import '../models/route_response.dart';
import '../state/active_trip_state.dart';
import '../services/routing_service.dart';

// ==============================================================================
// 🗺️ MAP & LIVE GPS SAFE ROUTING SCREEN (TOUR GUARD)
// ------------------------------------------------------------------------------
// Original dual-location planner with optional GPS and authenticated route analysis.
// ==============================================================================

class _MapHazardItem {
  final int id, severity;
  final String name, hazardType;
  final bool isPolygon, isPoint;
  final List<List<List<double>>> polygonCoordinates;
  final List<double>? pointCoordinates;

  const _MapHazardItem({
    required this.id,
    required this.name,
    required this.hazardType,
    required this.severity,
    required this.isPolygon,
    required this.isPoint,
    required this.polygonCoordinates,
    this.pointCoordinates,
  });
}

class MapScreen extends StatefulWidget {
  final ActiveTripState? tripState;
  final String? initialDestination;
  final bool trackGpsOnStart;
  final ValueChanged<RouteResponse?>? onAnalyzed;
  final ApiService? api;
  final Future<List<LocationSearchResult>> Function(String)? searchPlaces;
  final TileProvider? tileProvider;
  final Future<Position> Function()? locate;
  const MapScreen({
    super.key,
    this.tripState,
    this.initialDestination,
    this.trackGpsOnStart = false,
    this.onAnalyzed,
    this.api,
    this.searchPlaces,
    this.tileProvider,
    this.locate,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  bool _cameraLockedToUser = true;
  bool _mapReady = false;
  late int _observedTripRevision;
  late final AnimationController _followAnimation;
  LatLng? _cameraFrom, _cameraTo;

  void _followUser({bool instantly = false}) {
    final point = _trips.position ?? _userGpsLocation;
    if (!_mapReady || point == null || !_cameraLockedToUser) return;
    _followAnimation.stop();
    if (instantly) {
      _mapController.rotate(
        0,
      ); // North-up map; arrow retains actual travel heading.
      _mapController.move(point, _mapController.camera.zoom);
    } else {
      _cameraFrom = _mapController.camera.center;
      _cameraTo = point;
      _followAnimation.forward(from: 0);
    }
  }

  Future<void> _recenterOnUser() async {
    _cameraLockedToUser = true;
    if (_trips.trip == null && _sourceLocation == null) {
      await _initMobileGpsTracking();
      return;
    }
    if (_trips.position != null || _userGpsLocation != null) {
      _followUser(instantly: true);
      return;
    }
    try {
      final gps = await (widget.locate ?? requireCurrentLocation)();
      if (!mounted) return;
      final point = LatLng(gps.latitude, gps.longitude);
      setState(() => _userGpsLocation = point);
      _trips.updatePosition(point, heading: gps.heading);
      _followUser(instantly: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Location unavailable. Check GPS permissions.',
            ),
          ),
        );
      }
    }
  }

  // ─── Map & Routing State Variables ──────────────────────────────────────────
  final MapController _mapController = MapController();
  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  ActiveTripState get _trips => widget.tripState ?? ActiveTripState.instance;

  // Coordinates
  LatLng? _userGpsLocation;
  LatLng? _sourceLocation;
  LatLng? _destinationLocation;

  String _sourceName = 'My Location';
  String? _destinationName;

  // Real-time GPS Stream & Debounce Timers
  Timer? _debounceTimer;
  int _searchRequestId = 0;

  // Route details
  List<LatLng> _routePoints = [];
  double _routeDistanceKm = 0.0;
  double _routeDurationMin = 0.0;
  RouteResponse? _routeRisk;
  String? _riskError;
  bool _isLoadingRisk = false;

  // Hazards from Backend
  List<HazardSummary> _nearbyHazards = [];
  List<AdminHazard> _activeHazards = [];
  bool _isLoadingHazards = false;
  int _gpsRequestId = 0;
  int _routeRequestId = 0;

  // Loading & State flags
  bool _isLoadingGps = false;
  bool _isSearching = false;
  bool _isCalculatingRoute = false;
  bool _showHazardOverlay = true;

  // Search suggestions dropdown state
  List<LocationSearchResult> _sourceSuggestions = [];
  List<LocationSearchResult> _destinationSuggestions = [];
  bool _isFocusedOnSource = false;

  // Default Tour Guard Demonstration Hub (Ooty / Nilgiris)
  static const LatLng _tourGuardDemoHub = LatLng(11.4102, 76.6950);

  @override
  void initState() {
    super.initState();
    _followAnimation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 350),
        )..addListener(() {
          if (!_mapReady ||
              !_cameraLockedToUser ||
              _cameraFrom == null ||
              _cameraTo == null) {
            return;
          }
          final t = Curves.easeOut.transform(_followAnimation.value);
          final lngDelta =
              ((_cameraTo!.longitude - _cameraFrom!.longitude + 540) % 360) -
              180;
          _mapController.move(
            LatLng(
              _cameraFrom!.latitude +
                  (_cameraTo!.latitude - _cameraFrom!.latitude) * t,
              ((_cameraFrom!.longitude + lngDelta * t + 540) % 360) - 180,
            ),
            _mapController.camera.zoom,
          );
        });
    _observedTripRevision = _trips.revision;
    final trip = _trips.trip;
    if (trip != null) {
      _sourceName = trip.originName;
      _destinationName = trip.destinationName;
      _sourceController.text = trip.originName;
      _destinationController.text = trip.destinationName;
      _sourceLocation = trip.origin;
      _destinationLocation = trip.destination;
      _routeRisk = trip.route;
      _routePoints = trip.route.points;
      _routeDistanceKm = trip.distance / 1000;
      _routeDurationMin = trip.duration / 60;
      _nearbyHazards = trip.route.hazards;
    }

    _userGpsLocation = _trips.position;
    _trips.addListener(_onTripCleared);
    if (widget.trackGpsOnStart ||
        (_sourceLocation == null &&
            widget.initialDestination != null &&
            widget.initialDestination!.isNotEmpty)) {
      _initMobileGpsTracking();
    }

    if (widget.initialDestination != null &&
        widget.initialDestination!.isNotEmpty) {
      _destinationController.text = widget.initialDestination!;
      _searchAndSetDestination(widget.initialDestination!);
    }

    if (widget.api == null) {
      HazardCatalog.instance.addListener(_catalogChanged);
      _loadActiveHazards();
    }
  }

  @override
  void dispose() {
    HazardCatalog.instance.removeListener(_catalogChanged);
    _trips.removeListener(_onTripCleared);
    _debounceTimer?.cancel();
    _followAnimation.dispose();
    _mapController.dispose();
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _onTripCleared() {
    if (!mounted) return;
    final lifecycleChanged = _observedTripRevision != _trips.revision;
    _observedTripRevision = _trips.revision;
    // Hazard refreshes also notify while planning. Only an explicit lifecycle
    // change (End Trip/logout) may clear the draft and cancel its request.
    if (_trips.trip == null && !lifecycleChanged) return;
    if (_trips.trip != null) {
      if (_routeRisk != null &&
          _trips.trip!.route.tripId == _routeRisk!.tripId) {
        setState(() {
          _routeRisk = _trips.trip!.route;
          _nearbyHazards = _routeRisk!.hazards;
          _userGpsLocation = _trips.position;
          if (_trips.distanceToDestination != null) {
            _routeDistanceKm = _trips.distanceToDestination! / 1000;
            _routeDurationMin = _trips.trip!.distance > 0
                ? _trips.trip!.duration *
                      (_trips.distanceToDestination! / _trips.trip!.distance) /
                      60
                : 0;
          }
        });
      }
      if (_trips.position != null &&
          !_trips.completed &&
          _routeRisk?.tripId == _trips.trip?.route.tripId &&
          _cameraTo != _trips.position) {
        _followUser();
      }
      return;
    }
    _followAnimation.stop();
    _cameraLockedToUser = true;
    _cameraTo = null;
    _gpsRequestId++;
    _searchRequestId++;
    _debounceTimer?.cancel();
    setState(() {
      _invalidateRoute();
      _sourceController.clear();
      _destinationController.clear();
      _sourceLocation = null;
      _destinationLocation = null;
      _sourceName = 'My Location';
      _destinationName = null;
      _sourceSuggestions = [];
      _destinationSuggestions = [];
      _isSearching = false;
      _isLoadingGps = false;
    });
  }

  Future<void> _loadActiveHazards() async {
    await HazardCatalog.instance.refresh();
    _catalogChanged();
  }

  void _catalogChanged() {
    final catalog = HazardCatalog.instance;
    if (!mounted || !catalog.hasLoaded) return;
    _trips.reconcileHazards(catalog.activeIds);
    setState(() {
      _activeHazards = catalog.items;
      _nearbyHazards = _nearbyHazards
          .where((h) => catalog.activeIds.contains(h.id))
          .toList();
    });
  }

  Color _hazardFillColor(int severity) {
    if (severity >= 4) {
      return const Color(0xFFDC2626).withValues(alpha: 0.28);
    } else if (severity == 3) {
      return const Color(0xFFEA580C).withValues(alpha: 0.25);
    } else {
      return const Color(0xFFEAB308).withValues(alpha: 0.22);
    }
  }

  Color _hazardStrokeColor(int severity) {
    if (severity >= 4) {
      return const Color(0xFFB91C1C);
    } else if (severity == 3) {
      return const Color(0xFFC2410C);
    } else {
      return const Color(0xFFA16207);
    }
  }

  void _showHazardInfo(String name, String type, int severity) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$name • ${type.toUpperCase()} (Severity $severity/5)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: severity >= 4
            ? const Color(0xFFDC2626)
            : const Color(0xFFEA580C),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  List<_MapHazardItem> _collectAllHazards() {
    final list = <_MapHazardItem>[];
    final seen = <int>{};
    for (final h in _nearbyHazards) {
      if (widget.api == null &&
          HazardCatalog.instance.hasLoaded &&
          !HazardCatalog.instance.activeIds.contains(h.id)) {
        continue;
      }
      if (seen.add(h.id)) {
        list.add(
          _MapHazardItem(
            id: h.id,
            name: h.name,
            hazardType: h.hazardType,
            severity: h.severity,
            isPolygon: h.isPolygon,
            isPoint: h.isPoint,
            polygonCoordinates: h.polygonCoordinates,
            pointCoordinates: h.pointCoordinates,
          ),
        );
      }
    }
    for (final h in _activeHazards) {
      if (seen.add(h.id)) {
        list.add(
          _MapHazardItem(
            id: h.id,
            name: h.name,
            hazardType: h.hazardType,
            severity: h.severity,
            isPolygon: h.isPolygon,
            isPoint: h.isPoint,
            polygonCoordinates: h.polygonCoordinates,
            pointCoordinates: h.pointCoordinates,
          ),
        );
      }
    }
    return list;
  }

  List<Polygon> _buildHazardPolygons() {
    if (!_showHazardOverlay) return const [];
    final polygons = <Polygon>[];
    for (final h in _collectAllHazards()) {
      if (h.isPolygon && h.polygonCoordinates.isNotEmpty) {
        for (final ring in h.polygonCoordinates) {
          if (ring.length >= 3) {
            polygons.add(
              Polygon(
                points: ring.map((pt) => LatLng(pt[1], pt[0])).toList(),
                color: _hazardFillColor(h.severity),
                borderColor: _hazardStrokeColor(h.severity),
                borderStrokeWidth: 2.5,
              ),
            );
          }
        }
      }
    }
    return polygons;
  }

  List<Marker> _buildHazardMarkers() {
    if (!_showHazardOverlay) return const [];
    final markers = <Marker>[];
    for (final h in _collectAllHazards()) {
      if (h.isPoint &&
          h.pointCoordinates != null &&
          h.pointCoordinates!.length >= 2) {
        final pt = h.pointCoordinates!;
        markers.add(
          Marker(
            point: LatLng(pt[1], pt[0]),
            width: 36,
            height: 36,
            child: GestureDetector(
              onTap: () => _showHazardInfo(h.name, h.hazardType, h.severity),
              child: Tooltip(
                message:
                    '${h.name} (${h.hazardType}, Severity ${h.severity}/5)',
                child: Container(
                  decoration: BoxDecoration(
                    color: h.severity >= 4
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFF97316),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      } else if (h.isPolygon &&
          h.polygonCoordinates.isNotEmpty &&
          h.polygonCoordinates.first.length >= 3) {
        final ring = h.polygonCoordinates.first;
        final avgLat =
            ring.map((p) => p[1]).reduce((a, b) => a + b) / ring.length;
        final avgLng =
            ring.map((p) => p[0]).reduce((a, b) => a + b) / ring.length;
        markers.add(
          Marker(
            point: LatLng(avgLat, avgLng),
            width: 32,
            height: 32,
            child: GestureDetector(
              onTap: () => _showHazardInfo(h.name, h.hazardType, h.severity),
              child: Tooltip(
                message:
                    '${h.name} (${h.hazardType}, Severity ${h.severity}/5)',
                child: Container(
                  decoration: BoxDecoration(
                    color: h.severity >= 4
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFEA580C),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  Future<List<LocationSearchResult>> _searchPlaces(String query) =>
      (widget.searchPlaces ?? RoutingService.searchDestination)(query);

  void _invalidateRoute() {
    _routeRequestId++;
    _routePoints = [];
    _routeRisk = null;
    _nearbyHazards = [];
    _riskError = null;
    _isCalculatingRoute = false;
    _isLoadingRisk = false;
    _isLoadingHazards = false;
    widget.onAnalyzed?.call(null);
  }

  Future<void> _initMobileGpsTracking() async {
    final id = ++_gpsRequestId;
    setState(() => _isLoadingGps = true);
    try {
      final position = await (widget.locate ?? requireCurrentLocation)();
      if (!mounted || id != _gpsRequestId) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _invalidateRoute();
        _userGpsLocation = point;
        _sourceLocation = point;
        _sourceName = 'Current Location';
        _sourceController.text = _sourceName;
      });
      _mapController.move(point, 14.5);
      await _calculateRoute();
    } catch (error) {
      if (mounted && id == _gpsRequestId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'GPS unavailable. Select a source manually.',
            ),
          ),
        );
      }
    } finally {
      if (mounted && id == _gpsRequestId) setState(() => _isLoadingGps = false);
    }
  }

  void _resetSourceToLiveGps() => _initMobileGpsTracking();

  // ─── 3. INTERACTIVE TAP TO SET DESTINATION ──────────────────────────────────
  Future<void> _onMapTapped(LatLng tappedPoint) async {
    setState(() {
      _destinationLocation = tappedPoint;
      _destinationName = 'Selected Pin';
      _destinationController.text = 'Dropped pin';
      _destinationSuggestions = [];
    });

    _calculateRoute();

    // Reverse geocode tapped spot in background
    final name = await RoutingService.reverseGeocode(
      tappedPoint.latitude,
      tappedPoint.longitude,
    );
    if (name != null && mounted && _destinationLocation == tappedPoint) {
      setState(() {
        _destinationName = name;
        _destinationController.text = name;
      });
      final trip = _trips.trip;
      if (trip != null &&
          identical(trip.route, _routeRisk) &&
          trip.destination == tappedPoint) {
        _trips.start(
          ActiveTrip(
            originName: trip.originName,
            destinationName: name,
            origin: trip.origin,
            destination: trip.destination,
            route: trip.route,
          ),
        );
      }
    }
  }

  // ─── 4. SEARCH SOURCE SUGGESTIONS WITH DEBOUNCE ─────────────────────────────
  void _onSourceTextChanged(String query) {
    _gpsRequestId++;
    _isLoadingGps = false;
    setState(() {
      _sourceLocation = null;
      _destinationSuggestions = [];
      _invalidateRoute();
    });
    _isFocusedOnSource = true;
    _debounceTimer?.cancel();
    final requestId = ++_searchRequestId;

    if (query.trim().isEmpty) {
      setState(() {
        _sourceSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await _searchPlaces(query);
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _sourceSuggestions = results;
          _isSearching = false;
        });
        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No places found. Check your connection or refine the search.',
              ),
            ),
          );
        }
      }
    });
  }

  // ─── 5. SEARCH DESTINATION SUGGESTIONS WITH DEBOUNCE ────────────────────────
  void _onDestinationTextChanged(String query) {
    setState(() {
      _destinationLocation = null;
      _sourceSuggestions = [];
      _invalidateRoute();
    });
    _isFocusedOnSource = false;
    _debounceTimer?.cancel();
    final requestId = ++_searchRequestId;

    if (query.trim().isEmpty) {
      setState(() {
        _destinationSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await _searchPlaces(query);
      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _destinationSuggestions = results;
          _isSearching = false;
        });
        if (results.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No places found. Check your connection or refine the search.',
              ),
            ),
          );
        }
      }
    });
  }

  Future<void> _searchAndSetDestination(String query) async {
    if (query.trim().isEmpty) return;

    _debounceTimer?.cancel();
    final requestId = ++_searchRequestId;
    setState(() {
      _invalidateRoute();
      _destinationLocation = null;
      _isSearching = true;
      _destinationSuggestions = [];
    });

    final results = await _searchPlaces(query);

    if (mounted && requestId == _searchRequestId) {
      setState(() => _isSearching = false);
      if (results.isNotEmpty) {
        _selectDestination(results.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No location results found for "$query"'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  // ─── 6. SELECT SOURCE & DESTINATION ─────────────────────────────────────────
  void _selectSource(LocationSearchResult place) {
    _gpsRequestId++;
    _isLoadingGps = false;
    _debounceTimer?.cancel();
    _searchRequestId++;
    setState(() {
      _isSearching = false;
      _sourceLocation = place.latLng;
      _sourceName = place.displayName.split(',').first;
      _sourceController.text = _sourceName;
      _sourceSuggestions = [];
    });
    FocusScope.of(context).unfocus();

    if (_destinationLocation != null) {
      _calculateRoute();
    } else {
      _mapController.move(_sourceLocation!, 14.0);
    }
  }

  void _selectDestination(LocationSearchResult place) {
    _debounceTimer?.cancel();
    _searchRequestId++;
    setState(() {
      _isSearching = false;
      _destinationLocation = place.latLng;
      _destinationName = place.displayName.split(',').first;
      _destinationController.text = place.displayName;
      _destinationSuggestions = [];
    });
    FocusScope.of(context).unfocus();

    _calculateRoute();
  }

  // ─── 7. SWAP SOURCE & DESTINATION (⇅) ───────────────────────────────────────
  void _swapSourceAndDestination() {
    _gpsRequestId++;
    _isLoadingGps = false;
    _debounceTimer?.cancel();
    _searchRequestId++;
    setState(() {
      _sourceSuggestions = [];
      _destinationSuggestions = [];
      _invalidateRoute();
    });
    if (_destinationLocation == null && _sourceLocation == null) return;

    setState(() {
      final tempLoc = _sourceLocation;
      final tempName = _sourceName;
      final tempText = _sourceController.text;

      _sourceLocation = _destinationLocation;
      _sourceName = _destinationName ?? 'Custom Location';
      _sourceController.text = _destinationController.text;

      _destinationLocation = tempLoc;
      _destinationName = tempName;
      _destinationController.text = tempText;
    });

    if (_sourceLocation != null && _destinationLocation != null) {
      _calculateRoute();
    }
  }

  // Display and assess the same route returned by FastAPI.
  Future<void> _calculateRoute({bool startTrip = false}) async {
    // Resolve the default current-location source instead of silently doing nothing.
    if (_sourceLocation == null &&
        _destinationLocation != null &&
        _sourceController.text.trim().isEmpty) {
      if (!_isLoadingGps) await _initMobileGpsTracking();
      return;
    }
    if (startTrip && _isCalculatingRoute) return;
    // Starting is a transition of the preview, not a new route search.
    // Keep its geometry and summary visible while GPS/backend work is pending.
    if (!startTrip) setState(_invalidateRoute);
    final start = _sourceLocation;
    final end = _destinationLocation;
    if (start == null || end == null) return;
    final requestId = ++_routeRequestId;
    final tripRevision = _trips.revision;
    setState(() {
      _riskError = null;
      _isCalculatingRoute = true;
      _isLoadingRisk = true;
      _isLoadingHazards = true;
    });
    try {
      LatLng? initialPosition;
      if (startTrip && (widget.api == null || widget.locate != null)) {
        final gps = await (widget.locate ?? requireCurrentLocation)();
        if (!mounted || requestId != _routeRequestId) return;
        initialPosition = LatLng(gps.latitude, gps.longitude);
      }
      final result = await (widget.api ?? ApiService.instance).analyzeRoute(
        startTrip: startTrip,
        initialLatitude: initialPosition?.latitude,
        initialLongitude: initialPosition?.longitude,
        originLat: start.latitude,
        originLng: start.longitude,
        destLat: end.latitude,
        destLng: end.longitude,
        originName: _sourceName,
        destinationName: _destinationName ?? _destinationController.text,
      );
      if (!mounted ||
          requestId != _routeRequestId ||
          tripRevision != _trips.revision) {
        if (result.tripId != null) {
          try {
            await (widget.api ?? ApiService.instance).endTrip(result.tripId!);
          } catch (_) {
            /* Can be reconciled on the next route search. */
          }
        }
        return;
      }
      setState(() {
        _routePoints = result.points;
        _routeDistanceKm = result.distanceMeters / 1000;
        _routeDurationMin = result.durationSeconds / 60;
        _routeRisk = result;
        _nearbyHazards = result.hazards;
      });
      if (startTrip) {
        _cameraLockedToUser = true;
        _cameraTo = null;
        _trips.start(
          ActiveTrip(
            originName: _sourceName,
            destinationName: _destinationName ?? _destinationController.text,
            origin: start,
            destination: end,
            route: result,
          ),
        );
      }
      _fitRouteBounds();
      widget.onAnalyzed?.call(result);
      // TripHazardMonitor publishes fresh device GPS and displays geofence warnings.
    } catch (error) {
      if (!mounted || requestId != _routeRequestId) return;
      setState(
        () => _riskError = error is ApiException
            ? error.message
            : 'Route analysis failed. Please retry.',
      );
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_riskError!)));
      if (error is ApiException && error.unauthorized) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } finally {
      if (mounted && requestId == _routeRequestId) {
        setState(() {
          _isCalculatingRoute = false;
          _isLoadingRisk = false;
          _isLoadingHazards = false;
        });
      }
    }
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;

    try {
      final bounds = LatLngBounds.fromPoints(_routePoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.only(
            top: 200,
            bottom: MediaQuery.sizeOf(context).height * .4,
            left: 50,
            right: 50,
          ),
        ),
      );
    } catch (_) {
      double minLat = _routePoints.first.latitude;
      double maxLat = _routePoints.first.latitude;
      double minLng = _routePoints.first.longitude;
      double maxLng = _routePoints.first.longitude;

      for (final point in _routePoints) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }

      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;
      _mapController.move(LatLng(centerLat, centerLng), 12.0);
    }
  }

  // ─── 9. DEMO SCENARIO PRESETS PICKER MODAL ──────────────────────────────────
  void _openDemoPresetsModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F3FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.travel_explore_rounded,
                        color: Color(0xFF087CF0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Live Demo Scenarios',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A2D4F),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DemoPresetTile(
                  title: '🌲 Ooty ➔ Pykara Waterfalls',
                  subtitle: 'Mountain Hill Road • Landslide & Rain Assessment',
                  onTap: () {
                    Navigator.pop(context);
                    _gpsRequestId++;
                    _isLoadingGps = false;
                    setState(() {
                      _sourceLocation = _tourGuardDemoHub;
                      _sourceName = 'Ooty Town';
                      _sourceController.text = '📍 Ooty Town';
                      _destinationLocation = const LatLng(11.4500, 76.6000);
                      _destinationName = 'Pykara Waterfalls';
                      _destinationController.text = 'Pykara Waterfalls';
                    });
                    _calculateRoute();
                  },
                ),
                _DemoPresetTile(
                  title: '⛰️ Coimbatore ➔ Ooty (Ghat Highway)',
                  subtitle: 'Hairpin Bends (NH181) • High Elevation Slope Risk',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _sourceLocation = const LatLng(11.0168, 76.9558);
                      _sourceName = 'Coimbatore';
                      _sourceController.text = 'Coimbatore';
                      _destinationLocation = _tourGuardDemoHub;
                      _destinationName = 'Ooty Hill Station';
                      _destinationController.text = 'Ooty Hill Station';
                    });
                    _calculateRoute();
                  },
                ),
                _DemoPresetTile(
                  title: '🌊 Munnar ➔ Mattupetty Dam',
                  subtitle: 'Dense Fog & Valley Corridor Analysis',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _sourceLocation = const LatLng(10.0889, 77.0595);
                      _sourceName = 'Munnar';
                      _sourceController.text = 'Munnar';
                      _destinationLocation = const LatLng(10.1062, 77.1247);
                      _destinationName = 'Mattupetty Dam';
                      _destinationController.text = 'Mattupetty Dam';
                    });
                    _calculateRoute();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSource = _sourceLocation ?? _tourGuardDemoHub;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: Stack(
        children: [
          // ─── 1. OPENSTREETMAP CANVAS WITH TAP TO ROUTE ─────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: effectiveSource,
              onMapReady: () {
                _mapReady = true;
                if (_trips.position != null && !_trips.completed) {
                  _followUser(instantly: true);
                } else {
                  _fitRouteBounds();
                }
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  _cameraLockedToUser = false;
                  _followAnimation.stop();
                }
              },
              initialZoom: 14.5,
              minZoom: 3.0,
              maxZoom: 18.0,
              onTap: (tapPosition, point) => _onMapTapped(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                tileProvider: widget.tileProvider,
                userAgentPackageName: 'com.tourguard.travelriskapp',
              ),

              // Hazard Polygons (Shaded Risk Zones)
              if (_showHazardOverlay)
                PolygonLayer(polygons: _buildHazardPolygons()),

              // Route Polyline (Safe Path)
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: const Color(0xFF087CF0).withValues(alpha: 0.3),
                      strokeWidth: 9.0,
                    ),
                    Polyline(
                      points: _routePoints,
                      color: const Color(0xFF087CF0),
                      strokeWidth: 5.5,
                    ),
                  ],
                ),

              // Markers for Hazards, Source & Destination
              MarkerLayer(
                markers: [
                  ..._buildHazardMarkers(),
                  // LIVE USER GPS / SOURCE MARKER
                  if (_sourceLocation != null)
                    Marker(
                      point: _sourceLocation!,
                      width: 54,
                      height: 54,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: const Color(0xFF087CF0)
                                  .withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF087CF0),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.navigation_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Google Maps style destination marker.
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 42,
                      height: 50,
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.place_rounded,
                          color: Color(0xFF4285F4),
                          size: 30,
                        ),
                      ),
                    ),
                  if (_userGpsLocation != null)
                    Marker(
                      point: _userGpsLocation!,
                      width: 54,
                      height: 54,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF087CF0)
                              .withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _trips.completed
                                ? Colors.green
                                : const Color(0xFF087CF0),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Transform.rotate(
                            key: const ValueKey('live-heading-arrow'),
                            angle: _trips.completed
                                ? 0
                                : _trips.currentHeading * math.pi / 180,
                            child: Icon(
                              _trips.completed
                                  ? Icons.flag
                                  : Icons.navigation_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          const Positioned(
            left: 8,
            bottom: 0,
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(fontSize: 10, backgroundColor: Colors.white),
            ),
          ),

          // ─── 2. TOP FLOATING SOURCE & DESTINATION ROUTING CARD ──────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  Material(
                    color: Colors.white,
                    elevation: 4,
                    shadowColor: const Color(0x26000000),
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _sourceController,
                                        onChanged: _onSourceTextChanged,
                                        onSubmitted: _onSourceTextChanged,
                                        textInputAction: TextInputAction.search,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF202124),
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Current location',
                                          filled: true,
                                          fillColor: const Color(0xFFF1F3F4),
                                          prefixIcon: const Icon(
                                            Icons.trip_origin_rounded,
                                            size: 18,
                                            color: Color(0xFF4285F4),
                                          ),
                                          suffixIcon: IconButton(
                                            tooltip: 'Use current location',
                                            onPressed: _resetSourceToLiveGps,
                                            icon: const Icon(
                                              Icons.my_location_rounded,
                                              size: 18,
                                            ),
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _destinationController,
                                        onChanged: _onDestinationTextChanged,
                                        onSubmitted: _searchAndSetDestination,
                                        textInputAction: TextInputAction.search,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF202124),
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Search destination',
                                          filled: true,
                                          fillColor: const Color(0xFFF1F3F4),
                                          prefixIcon: const Icon(
                                            Icons.search_rounded,
                                            size: 18,
                                            color: Color(0xFF4285F4),
                                          ),
                                          suffixIcon: IconButton(
                                            tooltip: 'Search destination',
                                            onPressed: () =>
                                                _searchAndSetDestination(
                                                  _destinationController.text,
                                                ),
                                            icon: const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18,
                                            ),
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_isLoadingGps ||
                                    _isSearching ||
                                    _isCalculatingRoute)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: LinearProgressIndicator(
                                      minHeight: 2,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Swap origin and destination',
                            onPressed: _swapSourceAndDestination,
                            icon: const Icon(Icons.swap_vert_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Autocomplete Search Results Dropdown
                  if (_sourceSuggestions.isNotEmpty ||
                      _destinationSuggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 230),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F0E4E91),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _isFocusedOnSource
                            ? _sourceSuggestions.length
                            : _destinationSuggestions.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        itemBuilder: (context, index) {
                          final result = _isFocusedOnSource
                              ? _sourceSuggestions[index]
                              : _destinationSuggestions[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                _isFocusedOnSource
                                    ? Icons.trip_origin_rounded
                                    : Icons.location_on_outlined,
                                color: _isFocusedOnSource
                                    ? const Color(0xFF087CF0)
                                    : const Color(0xFFDC2626),
                                size: 18,
                              ),
                              title: Text(
                                result.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1A2D4F),
                                ),
                              ),
                              onTap: () {
                                if (_isFocusedOnSource) {
                                  _selectSource(result);
                                } else {
                                  _selectDestination(result);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ─── 3. RIGHT SIDE CONTROLS (Demo Presets, GPS Re-center & Layers) ──
          Positioned(
            right: 16,
            bottom: _routePoints.isNotEmpty
                ? MediaQuery.sizeOf(context).height * .38 + 30
                : 30,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom_in',
                  tooltip: 'Zoom in',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom + 1).clamp(3, 18),
                  ),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'zoom_out',
                  tooltip: 'Zoom out',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom - 1).clamp(3, 18),
                  ),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 10),
                // Demo Presets Action Button
                FloatingActionButton.small(
                  heroTag: 'fab_demo_presets',
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  onPressed: _openDemoPresetsModal,
                  tooltip: 'Live Demo Scenarios',
                  child: const Icon(Icons.travel_explore_rounded, size: 20),
                ),
                const SizedBox(height: 10),

                // Hazard Layer Toggle
                FloatingActionButton.small(
                  heroTag: 'fab_hazards',
                  backgroundColor: _showHazardOverlay
                      ? const Color(0xFF1A2D4F)
                      : Colors.white,
                  foregroundColor: _showHazardOverlay
                      ? Colors.white
                      : const Color(0xFF1A2D4F),
                  onPressed: () {
                    setState(() => _showHazardOverlay = !_showHazardOverlay);
                    if (_showHazardOverlay &&
                        _activeHazards.isEmpty &&
                        widget.api == null) {
                      _loadActiveHazards();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _showHazardOverlay
                              ? 'Hazard zone overlay shown on map'
                              : 'Hazard overlay hidden',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  tooltip: 'Toggle hazard zones on map',
                  child: const Icon(Icons.layers_rounded, size: 20),
                ),
                const SizedBox(height: 10),

                // Re-center on Live User GPS Location
                FloatingActionButton.small(
                  heroTag: 'fab_gps',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF087CF0),
                  onPressed: _recenterOnUser,
                  tooltip: 'Center on Live Location',
                  child: _isLoadingGps
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 20),
                ),
              ],
            ),
          ),

          // ─── 4. BOTTOM ROUTE & RISK PREDICTION SHEET ────────────────────────
          if (_routePoints.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .38,
                ),
                child: SingleChildScrollView(
                  child: _RouteRiskSummaryCard(
                    sourceName: _sourceName,
                    liveEstimate: _trips.position != null,
                    destinationName: _destinationName ?? 'Destination',
                    distanceKm: _routeDistanceKm,
                    durationMin: _routeDurationMin,
                    risk: _routeRisk,
                    riskError: _riskError,
                    isLoadingRisk: _isLoadingRisk,
                    hazards: _nearbyHazards,
                    showHazards: _showHazardOverlay,
                    hazardError: _riskError,
                    isLoadingHazards: _isLoadingHazards,
                    tripStatus:
                        _routeRisk?.tripId != null &&
                            _routeRisk?.tripId == _trips.trip?.route.tripId
                        ? (_trips.completed
                              ? 'TRIP COMPLETED'
                              : 'TRIP IN PROGRESS')
                        : (_isCalculatingRoute
                              ? 'STARTING TRIP...'
                              : 'START TRIP'),
                    onStartTrip:
                        _isCalculatingRoute ||
                            (_routeRisk?.tripId != null &&
                                _routeRisk?.tripId == _trips.trip?.route.tripId)
                        ? null
                        : () => _calculateRoute(startTrip: true),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Demo Preset Tile Widget ─────────────────────────────────────────────────
class _DemoPresetTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DemoPresetTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A2D4F),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8A99AF)),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: Color(0xFF087CF0),
        ),
      ),
    );
  }
}

// ─── Route & Risk Assessment Bottom Card Widget ─────────────────────────────
class _RouteRiskSummaryCard extends StatelessWidget {
  final String sourceName;
  final String destinationName;
  final double distanceKm;
  final double durationMin;
  final RouteResponse? risk;
  final String? riskError;
  final bool isLoadingRisk;
  final List<HazardSummary> hazards;
  final bool showHazards;
  final String? hazardError;
  final bool isLoadingHazards;
  final VoidCallback? onStartTrip;
  final String tripStatus;
  final bool liveEstimate;

  const _RouteRiskSummaryCard({
    required this.sourceName,
    required this.destinationName,
    required this.distanceKm,
    required this.durationMin,
    required this.risk,
    required this.riskError,
    required this.isLoadingRisk,
    required this.hazards,
    required this.showHazards,
    required this.hazardError,
    required this.isLoadingHazards,
    required this.onStartTrip,
    required this.tripStatus,
    required this.liveEstimate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0E4E91),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Source -> Destination Header & Safety Badge
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            sourceName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF087CF0),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: Color(0xFF8A99AF),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            destinationName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A2D4F),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km${liveEstimate ? ' direct' : ''}  \u2022  ${durationMin.toStringAsFixed(0)} mins${liveEstimate ? ' estimated' : ' drive'}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A99AF),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: risk == null
                      ? const Color(0xFFF1F5F9)
                      : _riskColor(risk!.riskLevel).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: risk == null
                        ? const Color(0xFFE2E8F0)
                        : _riskColor(risk!.riskLevel).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    if (isLoadingRisk)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(
                        Icons.shield_rounded,
                        size: 14,
                        color: risk == null
                            ? const Color(0xFF64748B)
                            : _riskColor(risk!.riskLevel),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      risk?.riskLevel ??
                          (riskError == null ? 'RISK PENDING' : 'UNAVAILABLE'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: risk == null
                            ? const Color(0xFF64748B)
                            : _riskColor(risk!.riskLevel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (risk != null || riskError != null) ...[
            const SizedBox(height: 8),
            Text(
              risk != null
                  ? [...risk!.reasons, ...risk!.limitations].join(' ')
                  : riskError ?? 'Risk service unavailable.',
              style: const TextStyle(
                fontSize: 11,
                height: 1.3,
                color: Color(0xFF64748B),
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: Color(0xFFF97316),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !showHazards
                      ? 'Hazard details hidden'
                      : isLoadingHazards
                      ? 'Loading nearby hazard reports...'
                      : hazardError != null
                      ? hazardError!
                      : '${hazards.length} nearby hazard report${hazards.length == 1 ? '' : 's'}${hazards.isEmpty ? '' : ': ${hazards.map((h) => '${h.name} (${h.hazardType}, ${h.severity}/5)').join('; ')}'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF53647F),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Start Trip Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onStartTrip,
              icon: const Icon(Icons.navigation_rounded, size: 20),
              label: Text(
                tripStatus,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF087CF0),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _riskColor(String level) => switch (level) {
  'SAFE' => const Color(0xFF1EAA55),
  'CAUTION' => const Color(0xFFF97316),
  'HIGH RISK' => const Color(0xFFDC2626),
  _ => const Color(0xFF64748B),
};
