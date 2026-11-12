import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/screens/dashboard_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';

void main() {
  testWidgets('Dashboard SOS banner updates without waiting for polling', (
    tester,
  ) async {
    final api = ApiService();
    final trips = ActiveTripState();
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(api: api, tripState: trips),
      ),
    );
    expect(find.text('Active SOS #32'), findsNothing);
    api.sosOperation.value = 'Sending SOS';
    await tester.pump();
    expect(find.text('Sending SOS'), findsOneWidget);
    api.sosOperation.value = null;
    api.cachedSosEvents = [
      {'id': 32, 'workflow_status': 'OPEN'},
    ];
    await tester.pump();
    expect(find.text('Active SOS #32'), findsOneWidget);
    api.sosOperation.value = 'Cancelling SOS';
    await tester.pump();
    expect(find.text('Cancelling SOS'), findsOneWidget);
    api.cachedSosEvents = [
      {'id': 32, 'workflow_status': 'CANCELLED'},
    ];
    api.sosOperation.value = null;
    await tester.pump();
    expect(find.text('Active SOS #32'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    trips.dispose();
    api.sosEvents.dispose();
  });
}
