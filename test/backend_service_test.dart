import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/services/backend_service.dart';

void main() {
  group('BackendService & Models Unit Tests', () {
    test('RiskResult.fromJson parses risk prediction response correctly', () {
      final json = {
        'risk_level': 2,
        'risk_label': 'High',
        'risk_score': 73,
        'color': '#EF4444',
        'advice': 'High risk detected. Avoid exposed ridges.',
      };

      final result = RiskResult.fromJson(json);

      expect(result.riskLevel, equals(2));
      expect(result.riskLabel, equals('High'));
      expect(result.riskScore, equals(73));
      expect(result.color, equals('#EF4444'));
      expect(result.advice, contains('High risk detected'));
    });

    test('Hazard.fromJson parses hazard GIS marker correctly', () {
      final json = {
        'id': 1,
        'type': 'landslide',
        'severity': 'high',
        'lat': 11.4102,
        'lon': 76.6950,
        'title': 'Landslide Risk Zone',
        'description': 'Heavy rains reported; road crumbling near km 42',
        'distance_km': 3.45,
      };

      final hazard = Hazard.fromJson(json);

      expect(hazard.id, equals(1));
      expect(hazard.type, equals('landslide'));
      expect(hazard.severity, equals('high'));
      expect(hazard.lat, equals(11.4102));
      expect(hazard.lon, equals(76.6950));
      expect(hazard.title, equals('Landslide Risk Zone'));
      expect(hazard.distanceKm, equals(3.45));
    });

    test('SosDispatchResult.fromJson parses rescue dispatch payload', () {
      final json = {
        'incident_id': 'SOS-A1B2C3D4',
        'status': 'dispatched',
        'eta_minutes': 12,
        'nearest_unit': 'Ooty Mountain Rescue Unit #3',
        'emergency_contacts': [
          'Police: 112',
          'Disaster: 1077',
          'Ambulance: 108',
        ],
        'message': 'Emergency received!',
        'timestamp': '2026-10-04T10:00:00Z',
      };

      final result = SosDispatchResult.fromJson(json);

      expect(result.incidentId, equals('SOS-A1B2C3D4'));
      expect(result.status, equals('dispatched'));
      expect(result.etaMinutes, equals(12));
      expect(result.nearestUnit, contains('Ooty Mountain Rescue'));
      expect(result.emergencyContacts.length, equals(3));
      expect(result.timestamp, equals('2026-10-04T10:00:00Z'));
    });
  });
}
