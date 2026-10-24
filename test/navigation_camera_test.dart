import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/models/route_response.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';
import 'package:travel_risk_app/screens/map_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';

import 'map_screen_test.dart' show BlankTiles;

ActiveTripState tripState() => ActiveTripState()
  ..start(
    const ActiveTrip(
      originName: 'Origin',
      destinationName: 'Destination',
      origin: LatLng(19, 72),
      destination: LatLng(20, 73),
      route: RouteResponse(
        tripId: 7,
        points: [LatLng(19, 72), LatLng(20, 73)],
        distanceMeters: 100000,
        durationSeconds: 10000,
        bufferMeters: 100,
        riskLevel: 'CAUTION',
        method: 'heuristic_v1',
        reasons: [],
        limitations: [],
        hazards: [],
        weatherUsed: false,
      ),
    ),
  );

void main() {
  test('Heading uses GPS, falls back to travel bearing, and ignores stationary jitter', () {
    final state = tripState();
    state.updatePosition(const LatLng(19, 72), heading: 270);
    expect(state.currentHeading, 270);
    state.updatePosition(const LatLng(19, 72.001), heading: 0);
    expect(state.currentHeading, closeTo(90, 0.01));
    state.updatePosition(const LatLng(19, 72.001), heading: double.nan);
    expect(state.currentHeading, closeTo(90, 0.01));
    state.updatePosition(const LatLng(19.001, 72.001), heading: -1);
    expect(state.currentHeading, closeTo(0, 0.01));
    state.clear();
    expect(state.currentHeading, 0);
    state.dispose();
  });

  testWidgets(
    'Camera follows GPS, pauses on drag, and target restores follow and arrow bearing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final state = tripState()
        ..updatePosition(const LatLng(19, 72), heading: 90);
      final api = ApiService();
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            tripState: state,
            api: api,
            tileProvider: BlankTiles(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final map = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      expect(map.camera.center.latitude, closeTo(19, 0.00001));
      state.updatePosition(const LatLng(19.001, 72.002), heading: 135);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(map.camera.center.latitude, closeTo(19.001, 0.00001));
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        hasLength(2),
      );
      final arrow = tester.widget<Transform>(
        find.byKey(const ValueKey('live-heading-arrow')),
      );
      expect(
        math.atan2(arrow.transform.entry(1, 0), arrow.transform.entry(0, 0)),
        closeTo(135 * math.pi / 180, 0.00001),
      );
      await tester.dragFrom(const Offset(600, 450), const Offset(150, 0));
      await tester.pumpAndSettle();
      final unlocked = map.camera.center;
      state.updatePosition(const LatLng(19.002, 72.003), heading: 180);
      await tester.pumpAndSettle();
      expect(map.camera.center, unlocked);
      map.rotate(45);
      await tester.tap(find.byTooltip('Center on Live Location'));
      await tester.pumpAndSettle();
      expect(map.camera.rotation, 0);
      expect(map.camera.center.latitude, closeTo(19.002, 0.00001));
      state.updatePosition(const LatLng(19.003, 72.004), heading: 200);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(map.camera.center.latitude, closeTo(19.003, 0.00001));
      state.markCompleted();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.flag), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
      state.dispose();
      api.close();
    },
  );
}
