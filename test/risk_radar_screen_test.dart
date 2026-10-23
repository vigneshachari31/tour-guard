import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/screens/risk_radar_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';

import 'map_screen_test.dart' show MemorySession;

void main() {
  for (final entry in [
    (20, 'LOW', Colors.green),
    (50, 'MODERATE', Colors.amber),
    (100, 'HIGH', Colors.red),
  ]) {
    testWidgets('Radar renders ${entry.$2} score and factors', (tester) async {
      final api = ApiService(
        store: MemorySession(),
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/radar/assess');
          expect(request.url.queryParameters['latitude'], '19.0');
          expect(request.headers['Authorization'], 'Bearer test');
          return http.Response(
            jsonEncode({
              'score': entry.$1,
              'risk_level': entry.$2,
              'factors': ['Nearby reports'],
              'checked_at': '2026-10-23',
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RiskRadarScreen(
            api: api,
            locate: () async => Position(
              latitude: 19,
              longitude: 72,
              timestamp: DateTime.now(),
              accuracy: 5,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('${entry.$1}%'), findsOneWidget);
      expect(find.text(entry.$2), findsOneWidget);
      final badge = tester.widget<Chip>(
        find.byKey(const ValueKey('radar-status-badge')),
      );
      expect(badge.side?.color, entry.$3);
      expect(find.text('\u2022 Nearby reports'), findsOneWidget);
      expect(find.textContaining('Nearby reports'), findsOneWidget);
      final gauge = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(gauge.color, entry.$3);
      expect(gauge.value, entry.$1 / 100);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }
}
