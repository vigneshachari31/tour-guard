import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/screens/risk_radar_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';

import 'map_screen_test.dart' show MemorySession;

void main() {
  testWidgets('Movement queues latest coordinates and discards stale response', (tester) async {
    Position point(double lat) => Position(latitude: lat, longitude: 72, timestamp: DateTime.now(),
        accuracy: 5, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
    final positions = StreamController<Position>();
    final first = Completer<http.Response>();
    final requested = <String>[];
    http.Response response(int score) => http.Response(jsonEncode({
      'score': score, 'risk_level': score == 20 ? 'LOW' : 'HIGH', 'factors': [], 'checked_at': 'test',
    }), 200);
    final api = ApiService(store: MemorySession(), client: MockClient((request) async {
      requested.add(request.url.queryParameters['latitude']!);
      if (requested.length == 1) return first.future;
      return response(20);
    }));
    await tester.pumpWidget(MaterialApp(home: RiskRadarScreen(
      api: api, locate: () async => point(19), positions: positions.stream)));
    await tester.pump();
    positions.add(point(19.01));
    await tester.pump();
    positions.add(point(19.02));
    await tester.pump();
    first.complete(response(100));
    await tester.pumpAndSettle();
    expect(requested, ['19.0', '19.02']);
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.textContaining('19.02000'), findsOneWidget);
    positions.add(point(19.02001));
    await tester.pump();
    expect(requested.length, 2);
    await tester.pumpWidget(const SizedBox());
    expect(positions.hasListener, isFalse);
    unawaited(positions.close());
    api.close();
  });
  for (final entry in [
    (20, 'LOW', Colors.green),
    (50, 'MODERATE', Colors.amber),
    (100, 'HIGH', Colors.red),
  ]) {
    testWidgets('Radar renders ${entry.$2} score and factors', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
              'weather': {'temperature_c': 27.3, 'wind_kmh': 4.5,
                'rainfall_mm_h': 0.0, 'at': '2026-10-24T02:00:00Z',
                'source': 'Open-Meteo hourly forecast'},
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
      await tester.scrollUntilVisible(find.text('Local weather'), 150);
      await tester.pumpAndSettle();
      expect(find.text('27.3 °C'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.close();
    });
  }
}
