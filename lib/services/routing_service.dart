import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// ==============================================================================
// 🗺️ ROUTING & GEOCODING SERVICE (TOUR GUARD)
// ------------------------------------------------------------------------------
// This service interacts with free, open-source GIS APIs:
// 1. OpenStreetMap Nominatim API - Geocodes place names to GPS (Lat, Lng)
// 2. OSRM (Open Source Routing Machine) API - Calculates realistic driving routes
// ==============================================================================

/// Represents a geographic place result from Nominatim Geocoder.
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
  // ─── 1. GEOCODING (Nominatim API) ──────────────────────────────────────────
  // Converts user search text (e.g., "Pykara Lake", "Matheran") into Lat/Lng
  static Future<List<LocationSearchResult>> searchDestination(
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=1',
      );

      // Nominatim requires a user-agent header per usage policy
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'TourGuard_TravelRiskApp/1.0'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) {
          return LocationSearchResult(
            displayName: item['display_name'] ?? 'Unknown Location',
            latitude: double.parse(item['lat']),
            longitude: double.parse(item['lon']),
          );
        }).toList();
      }
    } catch (e) {
      // In case of network error or parsing error, return empty list gracefully
      // debugPrint('Nominatim Geocoding Error: $e');
    }
    return [];
  }

  // ─── 2. ROUTE GENERATION (OSRM API) ────────────────────────────────────────
  // Fetches a driving path between start (GPS) and destination coordinates
  static Future<RouteData?> getDrivingRoute(
    LatLng start,
    LatLng destination,
  ) async {
    try {
      // OSRM expects coordinates in "longitude,latitude" format
      final coordinates =
          '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}';
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordinates?overview=full&geometries=geojson',
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok' && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final double distanceMeters = (route['distance'] as num).toDouble();
          final double durationSeconds = (route['duration'] as num).toDouble();

          // Extract GeoJSON coordinates [longitude, latitude] and map to LatLng
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
                ? route['legs'][0]['summary'] ?? 'Standard Route'
                : 'Standard Route',
          );
        }
      }
    } catch (e) {
      // debugPrint('OSRM Route Error: $e');
    }
    return null;
  }
}
