import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/models/route_response.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';
import 'package:travel_risk_app/screens/map_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/widgets/route_safety_details.dart';
import 'map_screen_test.dart' show BlankTiles, MemorySession;

const incident = HazardSummary(id: -7, name: 'Road accident', hazardType: 'accident', severity: 4,
  source: 'Verified tourist report', geometryType: 'Point', pointCoordinates: [72, 19]);
RouteResponse route(List<HazardSummary> hazards) => RouteResponse(points: const [LatLng(19,72),LatLng(19.1,72)],
  distanceMeters: 1000, durationSeconds: 100, bufferMeters: 250, riskLevel: hazards.isEmpty ? 'CAUTION' : 'HIGH RISK',
  method: 'heuristic_v1', reasons: const [], limitations: const ['Hazard coverage has not been verified.'],
  hazards: hazards, weatherUsed: true);
ActiveTrip trip(RouteResponse r) => ActiveTrip(originName: 'Start', destinationName: 'End',
  origin: const LatLng(19,72), destination: const LatLng(19.1,72), route: r);

void main() {
  test('Rejected incident disappears from saved route after verified refresh', () {
    final state = ActiveTripState()..start(trip(route([incident])));
    state.reconcileIncidentReports({});
    expect(state.trip!.route.hazards, isEmpty);
    expect(state.trip!.route.limitations.join(), contains('out of date'));
    final preview = route([incident]).reconcileVerifiedIncidents({});
    expect(preview.hazards, isEmpty);
    expect(routeSummary(preview), contains('Recheck'));
    state.dispose();
  });
  test('Official zone refresh preserves verified route incidents and risk', () {
    final state = ActiveTripState()..start(trip(route([incident])));
    state.reconcileHazards({});
    expect(state.trip!.route.hazards.single.id, -7);
    expect(state.trip!.riskLevel, 'HIGH RISK');
    expect(routeHazardDescription([incident]), contains('1 verified incident'));
    expect(routeSummary(route([])), contains('coverage is incomplete'));
    state.dispose();
  });
  testWidgets('Map shows nearby verified incident but excludes distant one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200,1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = ActiveTripState()..start(trip(route([])));
    final api = ApiService(store: MemorySession(), client: MockClient((_) async => http.Response(jsonEncode({
      'features': [for (final entry in [(8,19.005),(9,20.0)]) {
        'id': -entry.$1, 'geometry': {'type':'Point','coordinates':[72,entry.$2]},
        'properties': {'id': -entry.$1,'name':'Incident ${entry.$1}','hazard_type':'accident',
          'severity':3,'source':'Verified tourist report','is_active':true},
      }],
    }),200)));
    await tester.pumpWidget(MaterialApp(home: MapScreen(api:api, tripState:state,tileProvider:BlankTiles())));
    await tester.pumpAndSettle();
    final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
    expect(markers.any((m) => m.point.latitude == 19.005), isTrue);
    expect(markers.any((m) => m.point.latitude == 20.0), isFalse);
    expect(state.trip!.route.hazards, isEmpty); // Nearby alone must not affect route score.
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose(); api.close();
  });
}
