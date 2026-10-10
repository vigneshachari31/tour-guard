import 'package:latlong2/latlong.dart';

class HazardSummary {
  final int id, severity;
  final String name, hazardType, source;
  const HazardSummary({
    required this.id,
    required this.name,
    required this.hazardType,
    required this.severity,
    required this.source,
  });
  factory HazardSummary.fromJson(Map<String, dynamic> json) => HazardSummary(
    id: json['id'] as int,
    name: json['name'] as String,
    hazardType: json['hazard_type'] as String,
    severity: json['severity'] as int,
    source: json['source'] as String,
  );
}

class RouteResponse {
  final List<LatLng> points;
  final double distanceMeters, durationSeconds, bufferMeters;
  final String riskLevel, method;
  final List<String> reasons, limitations;
  final List<HazardSummary> hazards;
  final bool weatherUsed;
  const RouteResponse({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.bufferMeters,
    required this.riskLevel,
    required this.method,
    required this.reasons,
    required this.limitations,
    required this.hazards,
    required this.weatherUsed,
  });

  factory RouteResponse.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    if (geometry['type'] != 'LineString') {
      throw const FormatException('Expected LineString');
    }
    final points = (geometry['coordinates'] as List)
        .map((pair) {
          final lng = (pair[0] as num).toDouble();
          final lat = (pair[1] as num).toDouble();
          if (!lat.isFinite ||
              !lng.isFinite ||
              lat.abs() > 90 ||
              lng.abs() > 180) {
            throw const FormatException('Invalid route coordinates');
          }
          return LatLng(lat, lng); // GeoJSON is longitude first.
        })
        .toList(growable: false);
    if (points.length < 2) throw const FormatException('Route is empty');
    final assessment = json['assessment'] as Map<String, dynamic>;
    final level = assessment['level'] as String;
    if (!['SAFE', 'CAUTION', 'HIGH RISK'].contains(level)) {
      throw const FormatException('Invalid risk level');
    }
    double metric(String key) {
      final value = (json[key] as num).toDouble();
      if (!value.isFinite || value < 0) throw FormatException('Invalid $key');
      return value;
    }

    return RouteResponse(
      points: points,
      distanceMeters: metric('distance_meters'),
      durationSeconds: metric('duration_seconds'),
      bufferMeters: metric('buffer_meters'),
      riskLevel: level,
      method: assessment['method'] as String,
      reasons: List<String>.from(assessment['reasons'] as List),
      limitations: List<String>.from(assessment['limitations'] as List),
      weatherUsed: assessment['weather_used'] as bool,
      hazards: (json['hazards'] as List)
          .map((h) => HazardSummary.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

class WeatherObservation {
  final double rainfallMmH, windKmh;
  final DateTime observedAt;
  final String source;
  const WeatherObservation({
    required this.rainfallMmH,
    required this.windKmh,
    required this.observedAt,
    required this.source,
  });
  Map<String, dynamic> toJson() => {
    'rainfall_mm_h': rainfallMmH,
    'wind_kmh': windKmh,
    'observed_at': observedAt.toUtc().toIso8601String(),
    'source': source,
  };
}
