import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/screens/dashboard_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';

import 'map_screen_test.dart' show MemorySession;

void main() {
  for (final fails in [false, true]) {
    testWidgets('Alerts request survives live updates; failure=$fails', (
      tester,
    ) async {
      final trips = ActiveTripState();
      final pending = Completer<http.Response>();
      var requests = 0;
      final api = ApiService(
        store: MemorySession(),
        client: MockClient((request) {
          expect(request.url.path, '/api/v1/sos/events');
          requests++;
          return requests == 1
              ? pending.future
              : Future.value(http.Response('{"events":[],"total":0}', 200));
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(
            api: api,
            tripState: trips,
            reportLocation: () async =>
                throw const ApiException('Location unavailable'),
          ),
        ),
      );
      await tester.tap(find.text('Alerts'));
      await tester.pump();
      await tester.pump();
      expect(requests, 1);
      for (var i = 0; i < 5; i++) {
        trips.updateActiveHazards([]);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(requests, 1);
      pending.complete(
        http.Response(
          fails ? '{"detail":"Alerts unavailable"}' : '{"events":[],"total":0}',
          fails ? 503 : 200,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      if (fails) {
        expect(find.text('Alerts unavailable'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(requests, 2);
      }
      expect(find.text('No SOS activity yet'), findsOneWidget);
      trips.updateActiveHazards([]);
      await tester.pumpAndSettle();
      expect(requests, fails ? 2 : 1);
      await tester.pumpWidget(const SizedBox());
      trips.dispose();
      api.close();
    });
  }
}
