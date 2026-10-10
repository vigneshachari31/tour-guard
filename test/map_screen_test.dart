import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/screens/map_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/services/routing_service.dart';

class MemorySession implements SessionStore {
  @override
  Future<String?> read() async =>
      '{"access_token":"test","token_type":"bearer"}';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
      );
}

void main() {
  for (final fails in [false, true]) {
    testWidgets(
      'Manual source/destination; API failure=$fails keeps map truthful',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        Map<String, dynamic>? sent;
        final api = ApiService(
          store: MemorySession(),
          client: MockClient((request) async {
            sent = jsonDecode(request.body) as Map<String, dynamic>;
            if (fails) {
              return http.Response('{"detail":"Routing unavailable"}', 503);
            }
            return http.Response(
              jsonEncode({
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [76.695, 11.4102],
                    [76.65, 11.43],
                    [76.60, 11.45],
                  ],
                },
                'distance_meters': 12000,
                'duration_seconds': 1800,
                'buffer_meters': 250,
                'hazards': [
                  {
                    'id': 1,
                    'name': 'Test slope',
                    'hazard_type': 'landslide',
                    'severity': 4,
                    'source': 'Test',
                  },
                ],
                'assessment': {
                  'level': 'HIGH RISK',
                  'method': 'heuristic_v1',
                  'reasons': ['Hazard near route'],
                  'limitations': ['Weather unavailable'],
                  'weather_used': false,
                },
              }),
              200,
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: MapScreen(
              api: api,
              tileProvider: BlankTiles(),
              searchPlaces: (query) async => [
                LocationSearchResult(
                  displayName: query == 'Ooty'
                      ? 'Ooty Source'
                      : 'Pykara Destination',
                  latitude: query == 'Ooty' ? 11.4102 : 11.45,
                  longitude: query == 'Ooty' ? 76.695 : 76.60,
                ),
              ],
            ),
          ),
        );
        expect(find.byType(FlutterMap), findsOneWidget);
        expect(find.byType(TextField), findsNWidgets(2));
        expect(find.byTooltip('Use Current Location'), findsOneWidget);
        expect(find.byType(PolylineLayer), findsNothing);
        await tester.enterText(find.byType(TextField).at(0), 'Ooty');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.tap(find.text('Ooty Source'));
        await tester.pump();
        await tester.enterText(find.byType(TextField).at(1), 'Pykara');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.tap(find.text('Pykara Destination'));
        await tester.pumpAndSettle();
        expect(sent, {
          'origin_lat': 11.4102,
          'origin_lng': 76.695,
          'dest_lat': 11.45,
          'dest_lng': 76.60,
        });
        expect(find.byType(FlutterMap), findsOneWidget);
        if (fails) {
          expect(find.text('Routing unavailable'), findsOneWidget);
          expect(find.byType(PolylineLayer), findsNothing);
          expect(find.text('SAFE'), findsNothing);
        } else {
          final layer = tester.widget<PolylineLayer>(
            find.byType(PolylineLayer),
          );
          expect(layer.polylines.first.points.length, 3);
          expect(layer.polylines.first.points[1].longitude, 76.65);
          expect(find.text('HIGH RISK'), findsOneWidget);
          expect(find.textContaining('Test slope'), findsOneWidget);
          final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
          expect(markers.markers.length, 2);
          await tester.enterText(
            find.byType(TextField).at(0),
            'Changed source',
          );
          await tester.pump();
          expect(find.byType(PolylineLayer), findsNothing);
          expect(find.text('HIGH RISK'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.takeException(), isNull);
        api.close();
      },
    );
  }
}
