import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/services/routing_service.dart';

void main() {
  group('Routing & GIS Models Unit Tests', () {
    test('LocationSearchResult creates valid LatLng', () {
      final result = LocationSearchResult(
        displayName: 'Pykara Waterfalls, Nilgiris',
        latitude: 11.4500,
        longitude: 76.6000,
      );

      expect(result.displayName, contains('Pykara'));
      expect(result.latLng.latitude, equals(11.4500));
      expect(result.latLng.longitude, equals(76.6000));
    });

    test('RouteData encapsulates navigation and distance stats', () {
      final points = [
        const LatLng(11.4102, 76.6950),
        const LatLng(11.4500, 76.6000),
      ];

      final route = RouteData(
        polylinePoints: points,
        distanceInKm: 18.5,
        durationInMinutes: 32.0,
        summary: 'NH181 Ooty - Gudalur Rd',
      );

      expect(route.polylinePoints.length, equals(2));
      expect(route.distanceInKm, equals(18.5));
      expect(route.durationInMinutes, equals(32.0));
      expect(route.summary, equals('NH181 Ooty - Gudalur Rd'));
    });
  });
}
