import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/widgets/tourist_report_alerts.dart';
import 'package:travel_risk_app/widgets/dashboard/route_risk_card.dart';
import 'package:travel_risk_app/models/route_response.dart';

import 'map_screen_test.dart' show MemorySession;

void main() {
  testWidgets('Nearby reports show without a trip and refresh new reports', (
    tester,
  ) async {
    var calls = 0;
    final api = ApiService(
      store: MemorySession(),
      client: MockClient((r) async {
        expect(r.url.path, '/api/v1/hazards/reports/nearby');
        calls++;
        return http.Response(
          jsonEncode({
            'reports': [
              {
                'id': 1,
                'name': 'Fallen tree',
                'hazard_type': 'road',
                'severity': 3,
                'status': calls == 1 ? 'pending' : 'verified',
              },
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TouristReportAlerts(
            api: api,
            locate: () async => const LatLng(19, 72),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fallen tree'), findsOneWidget);
    expect(find.textContaining('Awaiting verification'), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh tourist reports'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Admin verified'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  testWidgets('Dashboard shows official zones but excludes tourist reports', (
    tester,
  ) async {
    const hazard = HazardSummary(
      id: -1,
      name: 'Fallen tree',
      hazardType: 'road',
      severity: 3,
      source: 'Verified tourist report',
    );
    const route = RouteResponse(
      points: [],
      distanceMeters: 1000,
      durationSeconds: 60,
      bufferMeters: 100,
      riskLevel: 'CAUTION',
      method: 'test',
      reasons: [],
      limitations: [],
      hazards: [
        hazard,
        HazardSummary(
          id: 2,
          name: 'Official flood zone',
          hazardType: 'flood',
          severity: 3,
          source: 'Admin',
        ),
      ],
      weatherUsed: false,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RouteRiskCard(route: route)),
        ),
      ),
    );
    expect(find.text('Fallen tree'), findsNothing);
    expect(find.text('CAUTION'), findsOneWidget);
    expect(find.text('Official flood zone'), findsOneWidget);
  });
}
