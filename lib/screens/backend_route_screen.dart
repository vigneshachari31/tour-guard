import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/route_response.dart';
import '../services/api_service.dart';
import '../services/current_location.dart';
import '../services/routing_service.dart';
import '../widgets/dashboard/route_risk_card.dart';

/// Uses geocoding only for place selection; the authenticated backend owns routing.
class BackendRouteScreen extends StatefulWidget {
  final String? initialDestination;
  final ValueChanged<RouteResponse>? onAnalyzed;
  const BackendRouteScreen({
    super.key,
    this.initialDestination,
    this.onAnalyzed,
  });
  @override
  State<BackendRouteScreen> createState() => _BackendRouteScreenState();
}

class _BackendRouteScreenState extends State<BackendRouteScreen> {
  final _query = TextEditingController();
  List<LocationSearchResult> _places = [];
  RouteResponse? _route;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialDestination ?? '';
    if (_query.text.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_busy || _query.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _route = null;
      _places = [];
    });
    try {
      final places = await RoutingService.searchDestination(_query.text);
      if (!mounted) return;
      setState(() {
        _places = places;
        if (places.isEmpty) _error = 'No places found. Check your connection or try a more specific place name.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Place search failed. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze(LocationSearchResult destination) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _route = null;
    });
    try {
      final origin = await requireCurrentLocation();
      final route = await ApiService.instance.analyzeRoute(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destLat: destination.latitude,
        destLng: destination.longitude,
      );
      if (!mounted) return;
      setState(() {
        _route = route;
        _places = [];
      });
      widget.onAnalyzed?.call(route);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is ApiException
            ? error.message
            : 'Unable to obtain GPS or analyze route. Please retry.',
      );
      if (error is ApiException && error.unauthorized) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _route;
    return Scaffold(
      appBar: AppBar(title: const Text('Route safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _query,
            enabled: !_busy,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Destination',
              suffixIcon: IconButton(
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Select a destination. Your current GPS location is the starting point.',
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          for (final place in _places)
            ListTile(
              title: Text(place.displayName),
              leading: const Icon(Icons.place),
              onTap: _busy ? null : () => _analyze(place),
            ),
          if (route != null) ...[
            SizedBox(
              height: 320,
              child: FlutterMap(
                key: ValueKey(route),
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(route.points),
                    padding: const EdgeInsets.all(32),
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.tour_guard',
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route.points,
                        color: Colors.blue,
                        strokeWidth: 5,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: route.points.first,
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                        ),
                      ),
                      Marker(
                        point: route.points.last,
                        child: const Icon(Icons.place, color: Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Text('© OpenStreetMap contributors'),
            RouteRiskCard(route: route),
          ],
        ],
      ),
    );
  }
}
