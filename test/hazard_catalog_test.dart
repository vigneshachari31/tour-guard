import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/services/hazard_catalog.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';
import 'package:travel_risk_app/models/route_response.dart';

void main() {
  test(
    'Successful removal prunes route cache; server failure preserves it',
    () async {
      var fail = false, deleted = false;
      final catalog = HazardCatalog(
        api: ApiService(
          client: MockClient((request) async {
            expect(request.url.path, '/api/v1/hazards/active');
            if (fail) return http.Response('{"detail":"Unavailable"}', 503);
            return http.Response(
              jsonEncode({
                'type': 'FeatureCollection',
                'features': deleted
                    ? []
                    : [
                        {
                          'type': 'Feature',
                          'id': 9,
                          'properties': {
                            'id': 9,
                            'name': 'Test hazard',
                            'hazard_type': 'flood',
                            'severity': 4,
                            'is_active': true,
                          },
                          'geometry': {
                            'type': 'Point',
                            'coordinates': [72.85, 19.04],
                          },
                        },
                      ],
              }),
              200,
            );
          }),
        ),
      );
      final route = RouteResponse.fromJson({
        'trip_id': 1,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [72.85, 19.04],
            [72.86, 19.05],
          ],
        },
        'distance_meters': 100,
        'duration_seconds': 30,
        'buffer_meters': 250,
        'hazards': [
          {
            'id': 9,
            'name': 'Test hazard',
            'hazard_type': 'flood',
            'severity': 4,
            'source': 'test',
          },
        ],
        'assessment': {
          'level': 'HIGH RISK',
          'method': 'heuristic_v1',
          'weather_used': false,
          'reasons': ['Old assessment'],
          'limitations': [],
        },
      });
      final trips = ActiveTripState()
        ..start(
          ActiveTrip(
            originName: 'A',
            destinationName: 'B',
            origin: const LatLng(19.04, 72.85),
            destination: const LatLng(19.05, 72.86),
            route: route,
          ),
        );
      catalog.addListener(() => trips.reconcileHazards(catalog.activeIds));
      await catalog.refresh();
      expect(catalog.activeIds, {9});
      fail = true;
      await catalog.refresh();
      expect(catalog.activeIds, {9});
      expect(trips.trip!.route.hazards, hasLength(1));
      fail = false;
      deleted = true;
      await catalog.refresh();
      expect(catalog.items, isEmpty);
      expect(trips.trip!.route.hazards, isEmpty);
      expect(trips.trip!.route.reasons.single, contains('Recheck'));
      expect(trips.trip!.route.riskLevel, 'CAUTION');
      catalog.dispose();
      trips.dispose();
    },
  );
}
