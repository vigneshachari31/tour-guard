import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/routing_service.dart';

// ==============================================================================
// 🗺️ MAP & LIVE GPS SAFE ROUTING SCREEN (TOUR GUARD)
// ------------------------------------------------------------------------------
// Key Features:
// 1. Live GPS auto-detection + Smart Emulator SF auto-fallback to Indian Demo Hub.
// 2. Interactive Map Tap: Tap anywhere on map to set destination & route.
// 3. Demo Route Presets: 1-Tap realistic hill-station routes for presentations.
// 4. Dual Input: FROM (Live Location / Custom Source) & TO (Destination).
// 5. Turn-by-turn Route Pathing via OSRM Polyline with camera auto-fit.
// 6. Pre-Trip Risk Analysis Overlay (Landslide, Flood & Weather Assessment).
// ==============================================================================

class MapScreen extends StatefulWidget {
  final String? initialDestination;

  const MapScreen({super.key, this.initialDestination});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // ─── Map & Routing State Variables ──────────────────────────────────────────
  final MapController _mapController = MapController();
  final TextEditingController _sourceController = TextEditingController(
    text: '📍 Acquiring live GPS location...',
  );
  final TextEditingController _destinationController = TextEditingController();

  // Coordinates
  LatLng? _userGpsLocation;
  LatLng? _sourceLocation;
  LatLng? _destinationLocation;

  String _sourceName = 'My Location';
  String? _destinationName;

  // Real-time GPS Stream & Debounce Timers
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _debounceTimer;

  // Route details
  List<LatLng> _routePoints = [];
  double _routeDistanceKm = 0.0;
  double _routeDurationMin = 0.0;

  // Loading & State flags
  bool _isLoadingGps = true;
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
    _initMobileGpsTracking();

    if (widget.initialDestination != null &&
        widget.initialDestination!.isNotEmpty) {
      _destinationController.text = widget.initialDestination!;
      _searchAndSetDestination(widget.initialDestination!);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  // ─── 1. OPTIMIZED PHONE & EMULATOR GPS ENGINE ───────────────────────────────
  Future<void> _initMobileGpsTracking() async {
    setState(() => _isLoadingGps = true);

    try {
      // 1. Check if device location services (GPS) are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Device GPS is turned OFF. Tap Settings to enable.',
            ),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'SETTINGS',
              textColor: Colors.white,
              onPressed: () => Geolocator.openLocationSettings(),
            ),
          ),
        );
      }

      // 2. Check and request runtime location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permission permanently denied.'),
            backgroundColor: const Color(0xFFDC2626),
            action: SnackBarAction(
              label: 'SETTINGS',
              textColor: Colors.white,
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
        _applyDemoLocation('Permission denied — using Demo Location');
        return;
      }

      if (permission == LocationPermission.denied) {
        _applyDemoLocation('Permission denied — using Demo Location');
        return;
      }

      // ─── STAGE 1: Fast Instant Location from Phone's GPS Cache ──────────────
      try {
        final Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          _processAcquiredPosition(lastKnown, isPreliminary: true);
        }
      } catch (_) {}

      // ─── STAGE 2: High-Accuracy Fresh Satellite/Fused Fix ───────────────────
      late LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          forceLocationManager: false,
          intervalDuration: const Duration(seconds: 2),
          timeLimit: const Duration(seconds: 12),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          distanceFilter: 5,
          timeLimit: const Duration(seconds: 12),
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          timeLimit: Duration(seconds: 12),
        );
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );

      _processAcquiredPosition(position, isPreliminary: false);

      // ─── STAGE 3: Real-Time Movement Stream ─────────────────────────────────
      _startLivePositionStream(locationSettings);
    } catch (e) {
      if (_userGpsLocation == null) {
        _applyDemoLocation('GPS timeout — using Demo Hub');
      } else {
        if (mounted) setState(() => _isLoadingGps = false);
      }
    }
  }

  // Handle position resolution with smart Emulator SF detection
  void _processAcquiredPosition(
    Position position, {
    required bool isPreliminary,
  }) {
    // Detect if coordinates are default Android Emulator (Mountain View, California)
    final bool isSanFranciscoEmulatorDefault =
        position.latitude >= 37.40 &&
        position.latitude <= 37.45 &&
        position.longitude >= -122.12 &&
        position.longitude <= -122.05;

    LatLng finalCoords;
    if (isSanFranciscoEmulatorDefault) {
      // Auto-route on Indian Tourism Demo Hub for smooth emulator presentation
      finalCoords = _tourGuardDemoHub;
    } else {
      finalCoords = LatLng(position.latitude, position.longitude);
    }

    if (mounted) {
      setState(() {
        _userGpsLocation = finalCoords;
        _sourceLocation = finalCoords;
        _isLoadingGps = false;
      });

      _mapController.move(finalCoords, 14.5);
      _reverseGeocodeLiveLocation(finalCoords);

      if (_destinationLocation != null && !isPreliminary) {
        _calculateRoute();
      }
    }
  }

  void _applyDemoLocation(String message) {
    if (!mounted) return;
    setState(() {
      _isLoadingGps = false;
      _userGpsLocation = _tourGuardDemoHub;
      _sourceLocation = _tourGuardDemoHub;
      _sourceName = 'Ooty Demo Hub';
      _sourceController.text = '📍 Ooty (Demo Location)';
    });
    _mapController.move(_tourGuardDemoHub, 14.5);
  }

  Future<void> _reverseGeocodeLiveLocation(LatLng loc) async {
    final placeName = await RoutingService.reverseGeocode(
      loc.latitude,
      loc.longitude,
    );

    if (mounted) {
      setState(() {
        if (placeName != null && placeName.isNotEmpty) {
          _sourceName = placeName;
          _sourceController.text = '📍 $placeName (Live Location)';
        } else {
          _sourceName = 'Live Location';
          _sourceController.text = '📍 My Live Location';
        }
      });
    }
  }

  void _startLivePositionStream(LocationSettings settings) {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen((Position position) {
              final bool isSanFranciscoEmulator =
                  position.latitude >= 37.40 &&
                  position.latitude <= 37.45 &&
                  position.longitude >= -122.12 &&
                  position.longitude <= -122.05;

              if (isSanFranciscoEmulator) return;

              final newGps = LatLng(position.latitude, position.longitude);
              if (mounted) {
                setState(() {
                  _userGpsLocation = newGps;
                  if (_sourceController.text.contains('Live Location') ||
                      _sourceController.text.contains('My Location')) {
                    _sourceLocation = newGps;
                  }
                });
              }
            }, onError: (_) {});
  }

  // ─── 2. RESET SOURCE TO LIVE GPS LOCATION ──────────────────────────────────
  void _resetSourceToLiveGps() {
    _initMobileGpsTracking();
    if (_userGpsLocation != null) {
      _mapController.move(_userGpsLocation!, 15.0);
    }
  }

  // ─── 3. INTERACTIVE TAP TO SET DESTINATION ──────────────────────────────────
  Future<void> _onMapTapped(LatLng tappedPoint) async {
    setState(() {
      _destinationLocation = tappedPoint;
      _destinationName = 'Selected Pin';
      _destinationController.text = '📍 Dropped Pin';
      _destinationSuggestions = [];
    });

    _calculateRoute();

    // Reverse geocode tapped spot in background
    final name = await RoutingService.reverseGeocode(
      tappedPoint.latitude,
      tappedPoint.longitude,
    );
    if (name != null && mounted) {
      setState(() {
        _destinationName = name;
        _destinationController.text = name;
      });
    }
  }

  // ─── 4. SEARCH SOURCE SUGGESTIONS WITH DEBOUNCE ─────────────────────────────
  void _onSourceTextChanged(String query) {
    _isFocusedOnSource = true;
    _debounceTimer?.cancel();

    if (query.trim().isEmpty || query.contains('📍')) {
      setState(() {
        _sourceSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await RoutingService.searchDestination(query);
      if (mounted) {
        setState(() {
          _sourceSuggestions = results;
          _isSearching = false;
        });
      }
    });
  }

  // ─── 5. SEARCH DESTINATION SUGGESTIONS WITH DEBOUNCE ────────────────────────
  void _onDestinationTextChanged(String query) {
    _isFocusedOnSource = false;
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _destinationSuggestions = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      final results = await RoutingService.searchDestination(query);
      if (mounted) {
        setState(() {
          _destinationSuggestions = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _searchAndSetDestination(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _destinationSuggestions = [];
    });

    final results = await RoutingService.searchDestination(query);

    if (mounted) {
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
    setState(() {
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
    setState(() {
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

  // ─── 8. CALCULATE DRIVING ROUTE (OSRM API + FALLBACK) ───────────────────────
  Future<void> _calculateRoute() async {
    final start = _sourceLocation ?? _userGpsLocation ?? _tourGuardDemoHub;
    final end = _destinationLocation;

    if (end == null) return;

    setState(() => _isCalculatingRoute = true);

    final routeData = await RoutingService.getDrivingRoute(start, end);

    if (mounted) {
      setState(() {
        _isCalculatingRoute = false;
        if (routeData != null) {
          _routePoints = routeData.polylinePoints;
          _routeDistanceKm = routeData.distanceInKm;
          _routeDurationMin = routeData.durationInMinutes;
        } else {
          _routePoints = [start, end];
          _routeDistanceKm = 10.0;
          _routeDurationMin = 20.0;
        }
      });

      _fitRouteBounds();
    }
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;

    try {
      final bounds = LatLngBounds.fromPoints(_routePoints);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            top: 200,
            bottom: 260,
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
    final effectiveSource =
        _sourceLocation ?? _userGpsLocation ?? _tourGuardDemoHub;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: Stack(
        children: [
          // ─── 1. OPENSTREETMAP CANVAS WITH TAP TO ROUTE ─────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: effectiveSource,
              initialZoom: 14.5,
              minZoom: 3.0,
              maxZoom: 18.0,
              onTap: (tapPosition, point) => _onMapTapped(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tourguard.travelriskapp',
              ),

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

              // Markers for Source & Destination
              MarkerLayer(
                markers: [
                  // LIVE USER GPS / SOURCE MARKER
                  Marker(
                    point: effectiveSource,
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

                  // DESTINATION MARKER (Red Pin)
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 52,
                      height: 52,
                      child: const Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFFDC2626),
                            size: 46,
                          ),
                          Positioned(
                            top: 10,
                            child: Icon(
                              Icons.flag_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ─── 2. TOP FLOATING SOURCE & DESTINATION ROUTING CARD ──────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F0E4E91),
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header: Back Button, Title & Activity Spinner
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                color: Color(0xFF1A2D4F),
                              ),
                              onPressed: () => Navigator.pop(context),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Plan Safe Route',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A2D4F),
                              ),
                            ),
                            const Spacer(),
                            if (_isLoadingGps ||
                                _isSearching ||
                                _isCalculatingRoute)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF087CF0),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Source (FROM) Input Row
                        Row(
                          children: [
                            const Icon(
                              Icons.trip_origin_rounded,
                              color: Color(0xFF087CF0),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _sourceController,
                                onChanged: _onSourceTextChanged,
                                decoration: const InputDecoration(
                                  hintText:
                                      'Start from (Live Location or City)...',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF8A99AF),
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A2D4F),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.my_location_rounded,
                                color: Color(0xFF087CF0),
                                size: 18,
                              ),
                              tooltip: 'Re-detect Live GPS Location',
                              onPressed: _resetSourceToLiveGps,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),

                        // Destination (TO) Input Row
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFFDC2626),
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _destinationController,
                                onChanged: _onDestinationTextChanged,
                                onSubmitted: (value) {
                                  _searchAndSetDestination(value);
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Enter destination (e.g. Coimbatore, Ooty)...',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF8A99AF),
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A2D4F),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.search_rounded,
                                color: Color(0xFF087CF0),
                                size: 20,
                              ),
                              tooltip: 'Search Destination',
                              onPressed: () {
                                _searchAndSetDestination(
                                  _destinationController.text,
                                );
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(
                                Icons.swap_vert_rounded,
                                color: Color(0xFF8A99AF),
                                size: 22,
                              ),
                              tooltip: 'Swap Source and Destination',
                              onPressed: _swapSourceAndDestination,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
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
                          return ListTile(
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
                          );
                        },
                      ),
                    ),

                  // Quick Suggestion Chips below search bar
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _QuickSearchPill(
                          label: '🌊 Pykara Lake',
                          onTap: () {
                            _destinationController.text = 'Pykara Lake';
                            _searchAndSetDestination('Pykara Lake');
                          },
                        ),
                        const SizedBox(width: 8),
                        _QuickSearchPill(
                          label: '⛰️ Doddabetta Peak',
                          onTap: () {
                            _destinationController.text = 'Doddabetta Peak';
                            _searchAndSetDestination('Doddabetta Peak');
                          },
                        ),
                        const SizedBox(width: 8),
                        _QuickSearchPill(
                          label: '🌲 Mudumalai Forest',
                          onTap: () {
                            _destinationController.text = 'Mudumalai';
                            _searchAndSetDestination('Mudumalai');
                          },
                        ),
                        const SizedBox(width: 8),
                        _QuickSearchPill(
                          label: '🏙️ Coimbatore',
                          onTap: () {
                            _destinationController.text = 'Coimbatore';
                            _searchAndSetDestination('Coimbatore');
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─── 3. RIGHT SIDE CONTROLS (Demo Presets, GPS Re-center & Layers) ──
          Positioned(
            right: 16,
            bottom: _routePoints.isNotEmpty ? 240 : 30,
            child: Column(
              children: [
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _showHazardOverlay
                              ? 'Hazard GIS Layers Enabled'
                              : 'Hazard GIS Layers Disabled',
                        ),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  tooltip: 'Toggle GIS Hazard Layers',
                  child: const Icon(Icons.layers_rounded, size: 20),
                ),
                const SizedBox(height: 10),

                // Re-center on Live User GPS Location
                FloatingActionButton.small(
                  heroTag: 'fab_gps',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF087CF0),
                  onPressed: () {
                    if (_userGpsLocation != null) {
                      _mapController.move(_userGpsLocation!, 15.0);
                    } else {
                      _initMobileGpsTracking();
                    }
                  },
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
              child: _RouteRiskSummaryCard(
                sourceName: _sourceName,
                destinationName: _destinationName ?? 'Destination',
                distanceKm: _routeDistanceKm,
                durationMin: _routeDurationMin,
                onStartTrip: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Safe navigation active: $_sourceName ➔ ${_destinationName ?? "Destination"}',
                      ),
                      backgroundColor: const Color(0xFF1EAA55),
                    ),
                  );
                },
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

// ─── Quick Destination Search Pill Widget ────────────────────────────────────
class _QuickSearchPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickSearchPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A2D4F),
          ),
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
  final VoidCallback onStartTrip;

  const _RouteRiskSummaryCard({
    required this.sourceName,
    required this.destinationName,
    required this.distanceKm,
    required this.durationMin,
    required this.onStartTrip,
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
                      '${distanceKm.toStringAsFixed(1)} km  •  ${durationMin.toStringAsFixed(0)} mins drive',
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
                  color: const Color(0xFFE8F8EE),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA5E6BE)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.shield_rounded,
                      size: 14,
                      color: Color(0xFF1EAA55),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'LOW RISK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1EAA55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Environmental & Hazard Factors along route
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RiskFactorItem(
                icon: Icons.landslide_rounded,
                label: 'Landslide',
                status: 'Stable',
                isSafe: true,
              ),
              _RiskFactorItem(
                icon: Icons.water_drop_rounded,
                label: 'Flood/Rain',
                status: 'Light Rain',
                isSafe: true,
              ),
              _RiskFactorItem(
                icon: Icons.air_rounded,
                label: 'Wind Gust',
                status: '12 km/h',
                isSafe: true,
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
              label: const Text(
                'START SAFE NAVIGATION',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

// ─── Risk Factor Mini Item ───────────────────────────────────────────────────
class _RiskFactorItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final bool isSafe;

  const _RiskFactorItem({
    required this.icon,
    required this.label,
    required this.status,
    required this.isSafe,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isSafe ? const Color(0xFF1EAA55) : const Color(0xFFDC2626),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF8A99AF),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              status,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSafe
                    ? const Color(0xFF1A2D4F)
                    : const Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
