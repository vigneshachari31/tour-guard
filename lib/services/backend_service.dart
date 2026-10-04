// lib/services/backend_service.dart
//
// Connects Flutter to the Tour Guard FastAPI backend.
// Base URL: http://10.0.2.2:8000  (emulator alias for PC localhost)

import 'dart:convert';

import 'package:http/http.dart' as http;

class BackendServiceException implements Exception {
  final String message;

  const BackendServiceException(this.message);

  @override
  String toString() => message;
}

class BackendService {
  // Override for a physical device or web with:
  // --dart-define=API_BASE_URL=http://<computer-ip>:8000
  static const String _base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  // ── Risk Prediction ──────────────────────────────────────────────────────

  /// Calls POST /api/predict-risk with environmental data.
  /// Returns the model response or throws [BackendServiceException].
  static Future<RiskResult> predictRisk({
    required double rainfallMmH,
    required double slopeDegrees,
    required double elevationM,
    required double windKmh,
    double visibilityKm = 8.0,
    double touristDensity = 0.3,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final payload = <String, Object?>{
        'rainfall_mm_h': rainfallMmH,
        'slope_degrees': slopeDegrees,
        'elevation_m': elevationM,
        'wind_kmh': windKmh,
        'visibility_km': visibilityKm,
        'tourist_density': touristDensity,
      };
      if (latitude != null) payload['latitude'] = latitude;
      if (longitude != null) payload['longitude'] = longitude;
      final body = jsonEncode(payload);

      final res = await http
          .post(
            Uri.parse('$_base/api/predict-risk'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        throw BackendServiceException(
          'Risk API returned HTTP ${res.statusCode}.',
        );
      }
      return RiskResult.fromJson(jsonDecode(res.body));
    } on BackendServiceException {
      rethrow;
    } catch (error) {
      throw BackendServiceException('Risk API request failed: $error');
    }
  }

  // ── Nearby Hazards ───────────────────────────────────────────────────────

  /// Returns nearby hazards or throws [BackendServiceException].
  static Future<List<Hazard>> getNearbyHazards({
    required double lat,
    required double lon,
    double radiusKm = 50,
  }) async {
    try {
      final uri = Uri.parse('$_base/api/hazards/nearby').replace(
        queryParameters: {
          'lat': lat.toString(),
          'lon': lon.toString(),
          'radius': radiusKm.toString(),
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        throw BackendServiceException(
          'Nearby hazards API returned HTTP ${res.statusCode}.',
        );
      }
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Hazard.fromJson(e)).toList();
    } on BackendServiceException {
      rethrow;
    } catch (error) {
      throw BackendServiceException('Nearby hazards request failed: $error');
    }
  }

  // ── SOS Dispatch ─────────────────────────────────────────────────────────

  /// Calls POST /api/sos/dispatch with tourist profile + GPS.
  /// Returns the backend acknowledgement or throws [BackendServiceException].
  static Future<SosDispatchResult> dispatchSos({
    required double latitude,
    required double longitude,
    double? altitudeM,
    required String userName,
    String? bloodGroup,
    String? medicalNotes,
    String? allergies,
    String? emergencyContact,
    String? locationName,
  }) async {
    try {
      final payload = <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'user_name': userName,
      };
      if (altitudeM != null) payload['altitude_m'] = altitudeM;
      if (bloodGroup != null) payload['blood_group'] = bloodGroup;
      if (medicalNotes != null) payload['medical_notes'] = medicalNotes;
      if (allergies != null) payload['allergies'] = allergies;
      if (emergencyContact != null) {
        payload['emergency_contact'] = emergencyContact;
      }
      if (locationName != null) payload['location_name'] = locationName;
      final body = jsonEncode(payload);

      final res = await http
          .post(
            Uri.parse('$_base/api/sos/dispatch'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw BackendServiceException(
          'SOS API returned HTTP ${res.statusCode}.',
        );
      }
      return SosDispatchResult.fromJson(jsonDecode(res.body));
    } on BackendServiceException {
      rethrow;
    } catch (error) {
      throw BackendServiceException('SOS dispatch request failed: $error');
    }
  }
}

// ── Data Models ──────────────────────────────────────────────────────────────

class RiskResult {
  final int riskLevel; // 0-3
  final String riskLabel; // Low / Medium / High / Critical
  final int riskScore; // 0-100
  final String color; // hex colour e.g. "#EF4444"
  final String advice;

  const RiskResult({
    required this.riskLevel,
    required this.riskLabel,
    required this.riskScore,
    required this.color,
    required this.advice,
  });

  factory RiskResult.fromJson(Map<String, dynamic> j) => RiskResult(
    riskLevel: j['risk_level'],
    riskLabel: j['risk_label'],
    riskScore: j['risk_score'],
    color: j['color'],
    advice: j['advice'],
  );
}

class Hazard {
  final int id;
  final String type;
  final String severity;
  final double lat;
  final double lon;
  final String title;
  final String description;
  final double distanceKm;

  const Hazard({
    required this.id,
    required this.type,
    required this.severity,
    required this.lat,
    required this.lon,
    required this.title,
    required this.description,
    required this.distanceKm,
  });

  factory Hazard.fromJson(Map<String, dynamic> j) => Hazard(
    id: j['id'],
    type: j['type'],
    severity: j['severity'],
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    title: j['title'],
    description: j['description'],
    distanceKm: (j['distance_km'] as num).toDouble(),
  );
}

class SosDispatchResult {
  final String incidentId;
  final String status;
  final int etaMinutes;
  final String nearestUnit;
  final List<String> emergencyContacts;
  final String message;
  final String timestamp;

  const SosDispatchResult({
    required this.incidentId,
    required this.status,
    required this.etaMinutes,
    required this.nearestUnit,
    required this.emergencyContacts,
    required this.message,
    required this.timestamp,
  });

  factory SosDispatchResult.fromJson(Map<String, dynamic> j) =>
      SosDispatchResult(
        incidentId: j['incident_id'],
        status: j['status'],
        etaMinutes: j['eta_minutes'],
        nearestUnit: j['nearest_unit'],
        emergencyContacts: List<String>.from(j['emergency_contacts']),
        message: j['message'],
        timestamp: j['timestamp'],
      );
}
