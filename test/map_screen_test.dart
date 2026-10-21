import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/screens/map_screen.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';
import 'package:travel_risk_app/screens/dashboard_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/models/route_response.dart';
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
  testWidgets(
    'Ending a trip cancels a pending analysis and clears map fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final trips = ActiveTripState();
      final response = Completer<http.Response>();
      var requested = false;
      final api = ApiService(
        store: MemorySession(),
        client: MockClient((_) {
          requested = true;
          return response.future;
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            api: api,
            tripState: trips,
            tileProvider: BlankTiles(),
            searchPlaces: (query) async => [
              LocationSearchResult(
                displayName: '$query Place',
                latitude: query == 'Origin' ? 11.4 : 11.5,
                longitude: 76.7,
              ),
            ],
          ),
        ),
      );
      for (var i = 0; i < 2; i++) {
        final name = i == 0 ? 'Origin' : 'Destination';
        await tester.enterText(find.byType(TextField).at(i), name);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        await tester.tap(find.text('$name Place'));
        await tester.pump();
      }
      expect(requested, isTrue);
      trips.clear();
      response.complete(
        http.Response(
          jsonEncode({
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [76.7, 11.4],
                [76.7, 11.5],
              ],
            },
            'distance_meters': 3300,
            'duration_seconds': 300,
            'buffer_meters': 250,
            'hazards': [],
            'assessment': {
              'level': 'SAFE',
              'method': 'heuristic_v1',
              'reasons': [],
              'limitations': [],
              'weather_used': false,
            },
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(trips.trip, isNull);
      expect(find.byType(PolylineLayer), findsNothing);
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'Manual source/destination; API failure=$fails keeps map truthful',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final trips = ActiveTripState();
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
              tripState: trips,
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
          'origin_name': 'Ooty Source',
          'destination_name': 'Pykara Destination',
        });
        expect(find.byType(FlutterMap), findsOneWidget);
        if (fails) {
          expect(trips.trip, isNull);
          expect(find.text('Routing unavailable'), findsOneWidget);
          expect(find.byType(PolylineLayer), findsNothing);
          expect(find.text('SAFE'), findsNothing);
        } else {
          final layer = tester.widget<PolylineLayer>(
            find.byType(PolylineLayer),
          );
          expect(trips.trip?.originName, 'Ooty Source');
          expect(trips.trip?.destinationName, 'Pykara Destination');
          expect(trips.trip?.riskLevel, 'HIGH RISK');
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
        if (!fails) {
          // Draft edits must not discard the last successfully assessed trip.
          expect(trips.trip?.originName, 'Ooty Source');
          await tester.pumpWidget(
            MaterialApp(
              home: MapScreen(
                api: api,
                tripState: trips,
                tileProvider: BlankTiles(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Ooty Source'), findsWidgets);
          expect(find.text('Pykara Destination'), findsWidgets);
          expect(find.byType(PolylineLayer), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            MaterialApp(home: DashboardScreen(tripState: trips)),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('Ooty Source \u2794 Pykara Destination'),
            findsOneWidget,
          );
          expect(find.text('HIGH RISK'), findsOneWidget);
          expect(find.text('12.0 km \u2022 30 mins'), findsOneWidget);
          final fields = tester
              .widgetList<TextField>(find.byType(TextField))
              .toList();
          expect(fields[0].controller!.text, 'Ooty Source');
          expect(fields[1].controller!.text, 'Pykara Destination');
          await tester.ensureVisible(find.text('END TRIP'));
          await tester.tap(find.text('END TRIP'));
          await tester.pumpAndSettle();
          expect(trips.trip, isNull);
          expect(fields[0].controller!.text, isEmpty);
          expect(fields[1].controller!.text, isEmpty);
          expect(find.text('HIGH RISK'), findsNothing);
          await tester.pumpWidget(const SizedBox());
        }
        expect(tester.takeException(), isNull);
        api.close();
      },
    );

  }
  testWidgets(
    'Hazard polygons and markers render on map and toggle with overlay button',
    (tester) async {
      final trips = ActiveTripState();
      final routeWithHazard = RouteResponse(
        tripId: 42,
        points: const [LatLng(11.41, 76.69), LatLng(11.45, 76.60)],
        distanceMeters: 5000,
        durationSeconds: 600,
        bufferMeters: 250,
        riskLevel: 'HIGH RISK',
        method: 'heuristic_v1',
        reasons: const ['Landslide zone active'],
        limitations: const [],
        weatherUsed: false,
        hazards: const [
          HazardSummary(
            id: 101,
            name: 'Avalanche Point',
            hazardType: 'landslide',
            severity: 4,
            source: 'District Administration',
            geometryType: 'Polygon',
            polygonCoordinates: [
              [
                [76.65, 11.42],
                [76.67, 11.42],
                [76.67, 11.44],
                [76.65, 11.44],
                [76.65, 11.42],
              ]
            ],
          ),
          HazardSummary(
            id: 102,
            name: 'Flash Flood Point',
            hazardType: 'flood',
            severity: 3,
            source: 'Tourist Report',
            geometryType: 'Point',
            pointCoordinates: [76.66, 11.43],
          ),
        ],
      );

      final api = ApiService(
        store: MemorySession(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      trips.start(
        ActiveTrip(
          originName: 'Start',
          destinationName: 'End',
          origin: const LatLng(11.41, 76.69),
          destination: const LatLng(11.45, 76.60),
          route: routeWithHazard,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            api: api,
            tripState: trips,
            tileProvider: BlankTiles(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check polygon layer is present
      expect(find.byType(PolygonLayer), findsOneWidget);
      final polygonLayer = tester.widget<PolygonLayer>(find.byType(PolygonLayer));
      expect(polygonLayer.polygons.length, 1);
      expect(polygonLayer.polygons.first.points.length, 5);

      // Check markers
      final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      // 2 hazard markers (1 centroid for polygon + 1 point marker) + 2 route markers = 4 markers
      expect(markerLayer.markers.length, 4);

      // Toggle hazard overlay off
      await tester.tap(find.byTooltip('Toggle hazard zones on map'));
      await tester.pumpAndSettle();

      // Polygons should be hidden
      expect(find.byType(PolygonLayer), findsNothing);
      final hiddenMarkers = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      expect(hiddenMarkers.markers.length, 2); // only origin & destination pins

      api.close();
    },
  );
}
