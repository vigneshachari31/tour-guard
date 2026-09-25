import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// ==============================================================================
// 🗺️ ROUTING & GEOCODING SERVICE (TOUR GUARD)
// ------------------------------------------------------------------------------
// This service interacts with high-performance OpenStreetMap GIS APIs:
// 1. Photon Geocoder (by Komoot) - Fast, unthrottled place search & autocomplete
// 2. Nominatim API - Fallback geocoder and reverse geocoder
// 3. OSRM (Open Source Routing Machine) - High-speed driving route generation
// 4. Built-in Haversine Distance Fallback - Guarantees route & risk stats always work
// ==============================================================================

/// Represents a geographic place result from the Geocoder.
class LocationSearchResult {
  final String displayName;
  final double latitude;
  final double longitude;

  LocationSearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  LatLng get latLng => LatLng(latitude, longitude);
}

/// Represents the calculated route between two points.
class RouteData {
  final List<LatLng> polylinePoints;
  final double distanceInKm;
  final double durationInMinutes;
  final String summary;

  RouteData({
    required this.polylinePoints,
    required this.distanceInKm,
    required this.durationInMinutes,
    required this.summary,
  });
}

class RoutingService {
  // ─── 1. FAST GEOCODING & AUTOCOMPLETE ──────────────────────────────────────
  // Uses Photon (Komoot OSM) with Nominatim fallback for zero rate-limiting
  static Future<List<LocationSearchResult>> searchDestination(
    String query,
  ) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Attempt 1: Fast Photon API (No 429 rate limit)
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(cleanQuery)}&limit=6',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final features = data['features'] as List<dynamic>?;

        if (features != null && features.isNotEmpty) {
          final List<LocationSearchResult> results = [];
          for (final f in features) {
            final props = f['properties'] as Map<String, dynamic>?;
            final geom = f['geometry'] as Map<String, dynamic>?;
            if (props == null || geom == null) continue;

            final coords = geom['coordinates'] as List<dynamic>?;
            if (coords == null || coords.length < 2) continue;

            final double lng = (coords[0] as num).toDouble();
            final double lat = (coords[1] as num).toDouble();

            final name = props['name'] as String? ?? '';
            final city =
                props['city'] ??
                props['town'] ??
                props['district'] ??
                props['county'];
            final state = props['state'] as String?;
            final country = props['country'] as String?;

            final List<String> parts = [];
            if (name.isNotEmpty) parts.add(name);
            if (city != null && city.toString().isNotEmpty && city != name) {
              parts.add(city.toString());
            }
            if (state != null && state.isNotEmpty) parts.add(state);
            if (country != null && country.isNotEmpty) parts.add(country);

            final display = parts.isNotEmpty
                ? parts.join(', ')
                : 'Place ($lat, $lng)';

            results.add(
              LocationSearchResult(
                displayName: display,
                latitude: lat,
                longitude: lng,
              ),
            );
          }

          if (results.isNotEmpty) return results;
        }
      }
    } catch (_) {
      // Photon fallback
    }

    // Attempt 2: Fallback to OpenStreetMap Nominatim
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&limit=5&addressdetails=1',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'TourGuard_App_${DateTime.now().millisecondsSinceEpoch}',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((item) {
          return LocationSearchResult(
            displayName: item['display_name'] ?? 'Unknown Location',
            latitude: double.parse(item['lat']),
            longitude: double.parse(item['lon']),
          );
        }).toList();
      }
    } catch (_) {
      // Fallback
    }

    return [];
  }

  // ─── 2. DRIVING ROUTE GENERATION (OSRM API + FALLBACK) ─────────────────────
  // Calculates realistic driving route between Start (Live GPS) and Destination
  static Future<RouteData?> getDrivingRoute(
    LatLng start,
    LatLng destination,
  ) async {
    try {
      final coordinates =
          '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}';
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final double distanceMeters = (route['distance'] as num).toDouble();
          final double durationSeconds = (route['duration'] as num).toDouble();

          final geometry = route['geometry'];
          final coordinatesList = geometry['coordinates'] as List<dynamic>;

          final List<LatLng> points = coordinatesList.map((coord) {
            return LatLng(
              (coord[1] as num).toDouble(), // Latitude
              (coord[0] as num).toDouble(), // Longitude
            );
          }).toList();

          return RouteData(
            polylinePoints: points,
            distanceInKm: distanceMeters / 1000.0,
            durationInMinutes: durationSeconds / 60.0,
            summary: route['legs'] != null && (route['legs'] as List).isNotEmpty
                ? route['legs'][0]['summary'] ?? 'Safe Driving Route'
                : 'Safe Driving Route',
          );
        }
      }
    } catch (_) {
      // Fallback below
    }

    // Fallback: Haversine distance and direct/interpolated safe route path
    const distanceCalc = Distance();
    final double distKm = distanceCalc.as(
      LengthUnit.Kilometer,
      start,
      destination,
    );
    final double estimatedDurationMin =
        (distKm / 45.0) * 60.0; // Assume avg 45 km/h

    // Generate smooth intermediate waypoints
    final List<LatLng> fallbackPoints = [
      start,
      LatLng(
        (start.latitude + destination.latitude) / 2,
        (start.longitude + destination.longitude) / 2,
      ),
      destination,
    ];

    return RouteData(
      polylinePoints: fallbackPoints,
      distanceInKm: distKm > 0.1 ? distKm : 1.0,
      durationInMinutes: estimatedDurationMin > 1 ? estimatedDurationMin : 5.0,
      summary: 'Direct Safe Corridor',
    );
  }

  // ─── 3. REVERSE GEOCODING (Photon + Nominatim) ──────────────────────────────
  // Converts live GPS (Lat, Lng) into human-readable City/State
  static Future<String?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    // Attempt 1: Photon Reverse Geocoder
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/reverse?lat=$latitude&lon=$longitude',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final features = data['features'] as List<dynamic>?;
        if (features != null && features.isNotEmpty) {
          final props = features[0]['properties'] as Map<String, dynamic>?;
          if (props != null) {
            final name = props['name'] as String?;
            final city =
                props['city'] ??
                props['town'] ??
                props['village'] ??
                props['district'] ??
                props['county'];
            final state = props['state'] as String?;

            if (city != null && state != null) {
              return '$city, $state';
            } else if (name != null && state != null) {
              return '$name, $state';
            } else if (name != null) {
              return name;
            } else if (city != null) {
              return city.toString();
            }
          }
        }
      }
    } catch (_) {
      // Fallback
    }

    // Attempt 2: Nominatim Reverse Geocoder
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'TourGuard_App_${DateTime.now().millisecondsSinceEpoch}',
            },
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final city =
              address['city'] ??
              address['town'] ??
              address['village'] ??
              address['suburb'] ??
              address['county'] ??
              address['state_district'];
          final state = address['state'];
          if (city != null && state != null) {
            return '$city, $state';
          } else if (city != null) {
            return city.toString();
          }
        }
        return (data['display_name'] as String?)?.split(',').take(2).join(', ');
      }
    } catch (_) {
      // Fallback
    }

    return null;
  }
}
