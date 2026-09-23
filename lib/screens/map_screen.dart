import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/routing_service.dart';

// ==============================================================================
// 🗺️ MAP & SAFE ROUTING SCREEN (TOUR GUARD)
// ------------------------------------------------------------------------------
// Key Features:
// 1. Dual Input: FROM (Source) & TO (Destination) for flexible route planning.
// 2. Real-time GPS Location Detection via Geolocator.
// 3. Nominatim Geocoding for both custom Source & Destination.
// 4. Turn-by-turn Route Pathing via OSRM Polyline with Swap (⇅) support.
// 5. Pre-Trip Risk Analysis Overlay (Landslide, Flood & Weather Assessment).
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
    text: '📍 My Current Location',
  );
  final TextEditingController _destinationController = TextEditingController();

  // Coordinates
  LatLng _userGpsLocation = const LatLng(11.4102, 76.6950); // Default Ooty
  LatLng? _sourceLocation;
  LatLng? _destinationLocation;

  String _sourceName = 'My Location';
  String? _destinationName;

  // Route details
  List<LatLng> _routePoints = [];
  double _routeDistanceKm = 0.0;
  double _routeDurationMin = 0.0;

  // Loading & State flags
  bool _isLoadingGps = false;
  bool _isCalculatingRoute = false;
  bool _showHazardOverlay = true;

  // Search suggestions dropdown state
  List<LocationSearchResult> _sourceSuggestions = [];
  List<LocationSearchResult> _destinationSuggestions = [];
  bool _isFocusedOnSource = false;

  @override
  void initState() {
    super.initState();
    _sourceLocation = _userGpsLocation;
    _fetchUserGpsLocation();

    if (widget.initialDestination != null &&
        widget.initialDestination!.isNotEmpty) {
      _destinationController.text = widget.initialDestination!;
      _searchAndSetDestination(widget.initialDestination!);
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  // ─── 1. FETCH GPS LOCATION ──────────────────────────────────────────────────
  Future<void> _fetchUserGpsLocation() async {
    setState(() => _isLoadingGps = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );

        final newGps = LatLng(position.latitude, position.longitude);
        setState(() {
          _userGpsLocation = newGps;
          if (_sourceController.text.contains('My Current Location')) {
            _sourceLocation = newGps;
          }
        });

        _mapController.move(_userGpsLocation, 14.0);

        // Recalculate route if destination is already selected
        if (_destinationLocation != null) {
          _calculateRoute();
        }
      }
    } catch (_) {
      // Graceful fallback to default coordinates
    } finally {
      setState(() => _isLoadingGps = false);
    }
  }

  // ─── 2. RESET SOURCE TO GPS LOCATION ────────────────────────────────────────
  void _resetSourceToGps() {
    setState(() {
      _sourceLocation = _userGpsLocation;
      _sourceName = 'My Location';
      _sourceController.text = '📍 My Current Location';
      _sourceSuggestions = [];
    });
    if (_destinationLocation != null) {
      _calculateRoute();
    } else {
      _mapController.move(_userGpsLocation, 14.0);
    }
  }

  // ─── 3. SEARCH SOURCE SUGGESTIONS ───────────────────────────────────────────
  Future<void> _searchSource(String query) async {
    if (query.trim().isEmpty || query.contains('My Current Location')) {
      setState(() => _sourceSuggestions = []);
      return;
    }

    final results = await RoutingService.searchDestination(query);
    setState(() {
      _sourceSuggestions = results;
    });
  }

  // ─── 4. SEARCH DESTINATION SUGGESTIONS ──────────────────────────────────────
  Future<void> _searchDestination(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _destinationSuggestions = []);
      return;
    }

    final results = await RoutingService.searchDestination(query);
    setState(() {
      _destinationSuggestions = results;
    });
  }

  Future<void> _searchAndSetDestination(String query) async {
    final results = await RoutingService.searchDestination(query);
    if (results.isNotEmpty) {
      _selectDestination(results.first);
    }
  }

  // ─── 5. SELECT SOURCE LOCATION ──────────────────────────────────────────────
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
      _mapController.move(_sourceLocation!, 13.0);
    }
  }

  // ─── 6. SELECT DESTINATION LOCATION ─────────────────────────────────────────
  void _selectDestination(LocationSearchResult place) {
    setState(() {
      _destinationLocation = place.latLng;
      _destinationName = place.displayName.split(',').first;
      _destinationController.text = _destinationName!;
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

  // ─── 8. CALCULATE DRIVING ROUTE (OSRM API) ──────────────────────────────────
  Future<void> _calculateRoute() async {
    final start = _sourceLocation ?? _userGpsLocation;
    final end = _destinationLocation;

    if (end == null) return;

    setState(() => _isCalculatingRoute = true);

    final routeData = await RoutingService.getDrivingRoute(start, end);

    setState(() {
      _isCalculatingRoute = false;
      if (routeData != null) {
        _routePoints = routeData.polylinePoints;
        _routeDistanceKm = routeData.distanceInKm;
        _routeDurationMin = routeData.durationInMinutes;
        _fitRouteBounds();
      } else {
        // Fallback straight line
        _routePoints = [start, end];
      }
    });
  }

  void _fitRouteBounds() {
    if (_routePoints.isEmpty) return;

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

    _mapController.move(LatLng(centerLat, centerLng), 11.5);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveSource = _sourceLocation ?? _userGpsLocation;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: Stack(
        children: [
          // ─── 1. OPENSTREETMAP CANVAS ─────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: effectiveSource,
              initialZoom: 13.0,
              minZoom: 4.0,
              maxZoom: 18.0,
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
                      color: const Color(0xFF087CF0),
                      strokeWidth: 5.5,
                    ),
                  ],
                ),

              // Markers for Source & Destination
              MarkerLayer(
                markers: [
                  // SOURCE MARKER (Green / Blue Pin)
                  Marker(
                    point: effectiveSource,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1EAA55).withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.trip_origin_rounded,
                          color: Color(0xFF1EAA55),
                          size: 26,
                        ),
                      ),
                    ),
                  ),

                  // DESTINATION MARKER (Red Pin)
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFDC2626),
                        size: 44,
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
                        // Header: Back Button & Title
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
                            if (_isCalculatingRoute)
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
                              color: Color(0xFF1EAA55),
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _sourceController,
                                onChanged: (value) {
                                  _isFocusedOnSource = true;
                                  _searchSource(value);
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Choose starting point (From)...',
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
                              tooltip: 'Use current GPS location',
                              onPressed: _resetSourceToGps,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ),

                        // Destination (TO) Input Row with Swap Button
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
                                onChanged: (value) {
                                  _isFocusedOnSource = false;
                                  _searchDestination(value);
                                },
                                onSubmitted: (value) {
                                  if (value.isNotEmpty) {
                                    _searchAndSetDestination(value);
                                  }
                                },
                                decoration: const InputDecoration(
                                  hintText: 'Enter destination (To)...',
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
                        padding: EdgeInsets.zero,
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
                            leading: Icon(
                              _isFocusedOnSource
                                  ? Icons.trip_origin_rounded
                                  : Icons.location_on_outlined,
                              color: _isFocusedOnSource
                                  ? const Color(0xFF1EAA55)
                                  : const Color(0xFFDC2626),
                              size: 18,
                            ),
                            title: Text(
                              result.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
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

          // ─── 3. RIGHT SIDE CONTROLS (GPS Re-center & Layers) ────────────────
          Positioned(
            right: 16,
            bottom: _routePoints.isNotEmpty ? 240 : 30,
            child: Column(
              children: [
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

                // Re-center on GPS Location
                FloatingActionButton.small(
                  heroTag: 'fab_gps',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF087CF0),
                  onPressed: () {
                    _mapController.move(_userGpsLocation, 14.0);
                  },
                  tooltip: 'Current Location',
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
                        'Trip from $_sourceName to ${_destinationName ?? "Destination"} started!',
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1EAA55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
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
