import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/models/route_response.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/services/trip_monitor.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';
import 'package:travel_risk_app/widgets/trip_hazard_monitor.dart';

class MemorySession implements SessionStore {
  @override
  Future<String?> read() async =>
      '{"access_token":"test","token_type":"bearer"}';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets(
    'GPS response displays persistent warning, exit clears it, offline retains it',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var inside = true, failed = false, count = 0;
      final api = ApiService(
        store: MemorySession(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/trips/42/locations');
          expect(request.headers['Authorization'], 'Bearer test');
          expect(jsonDecode(request.body), {
            'latitude': 19.0440,
            'longitude': 72.8565,
          });
          count++;
          if (failed) return http.Response('{"detail":"Offline test"}', 503);
          final hazard = {
            'hazard_id': 9,
            'name': 'dangerous zone',
            'hazard_type': 'landslide',
            'severity': 4,
          };
          return http.Response(
            jsonEncode({
              'current_hazards': inside ? [hazard] : [],
              'alerts': count == 1 ? [hazard] : [],
            }),
            201,
          );
        }),
      );
      final monitor = TripMonitor(
        api: api,
        locate: () async => const LatLng(19.0440, 72.8565),
        interval: const Duration(days: 1),
      );
      final trips = ActiveTripState();
      trips.start(
        const ActiveTrip(
          originName: 'Origin',
          destinationName: 'Destination',
          origin: LatLng(19, 72),
          destination: LatLng(20, 73),
          route: RouteResponse(
            tripId: 42,
            points: [LatLng(19, 72), LatLng(20, 73)],
            distanceMeters: 10,
            durationSeconds: 10,
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
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TripHazardMonitor(
            monitor: monitor,
            tripState: trips,
            child: child!,
          ),
          home: const Scaffold(body: Text('Tour Guard')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('dangerous zone'), findsOneWidget);
      expect(find.textContaining('landslide'), findsOneWidget);
      expect(find.textContaining('Severity 4/5'), findsOneWidget);
      final dashboardBounds = tester.getRect(find.byType(Scaffold));
      expect(dashboardBounds.top, 0);
      expect(dashboardBounds.height, 844);
      expect(tester.takeException(), isNull);
      await tester.longPress(find.byTooltip('Show hazard details'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Show hazard details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Stay alert'), findsOneWidget);
      expect(tester.getRect(find.byType(Scaffold)), dashboardBounds);
      await tester.tap(find.byTooltip('Hide hazard details'));
      await tester.pumpAndSettle();
      await monitor.poll();
      await tester.pump();
      expect(find.textContaining('dangerous zone'), findsOneWidget);
      inside = false;
      await monitor.poll();
      await tester.pump();
      expect(find.textContaining('dangerous zone'), findsNothing);
      expect(tester.getRect(find.byType(Scaffold)), dashboardBounds);
      inside = true;
      await monitor.poll();
      await tester.pump();
      expect(find.textContaining('dangerous zone'), findsOneWidget);
      failed = true;
      await monitor.poll();
      await tester.pump();
      expect(find.textContaining('Live updates unavailable'), findsOneWidget);
      expect(find.textContaining('Last known hazard'), findsOneWidget);
      expect(find.byTooltip('Retry live updates'), findsOneWidget);
      expect(find.textContaining('CORS'), findsNothing);
      expect(find.textContaining('dangerous zone'), findsOneWidget);
      failed = false;
      await tester.tap(find.byTooltip('Retry live updates'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Live updates unavailable'), findsNothing);
      final beforePause = count;
      monitor.setForeground(false);
      await monitor.poll();
      expect(count, beforePause);
      trips.clear();
      await tester.pump();
      expect(find.textContaining('dangerous zone'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      trips.dispose();
    },
  );

  test(
    'Ending a trip while GPS is pending does not send its location',
    () async {
      final position = Completer<LatLng>();
      var calls = 0;
      final monitor = TripMonitor(
        api: ApiService(
          store: MemorySession(),
          client: MockClient((_) async {
            calls++;
            return http.Response('{}', 201);
          }),
        ),
        locate: () => position.future,
      );
      monitor.setTrip(42);
      monitor.setTrip(null);
      position.complete(const LatLng(19, 72));
      await pumpEventQueue();
      expect(calls, 0);
      expect(monitor.hazards, isEmpty);
      monitor.dispose();
    },
  );
}
