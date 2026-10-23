import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:travel_risk_app/services/trip_socket.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:travel_risk_app/widgets/trip_hazard_monitor.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/services/trip_monitor.dart';
import 'package:travel_risk_app/state/active_trip_state.dart';
import 'package:travel_risk_app/models/route_response.dart';

class Store implements SessionStore {
  @override
  Future<String?> read() async =>
      '{"access_token":"test","token_type":"bearer"}';
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  test(
    'WebSocket sends token in first frame and receives completion',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final served = Completer<void>();
      server.listen((request) async {
        expect(request.uri.path, '/ws/trips/7/track');
        expect(request.uri.query, isEmpty);
        final ws = await WebSocketTransformer.upgrade(request);
        var authenticated = false;
        await for (final raw in ws) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          if (!authenticated) {
            expect(frame, {'token': 'test'});
            authenticated = true;
            ws.add('{"event":"READY"}');
          } else {
            expect(frame, {'lat': 19.05, 'lng': 72.86});
            ws.add(
              '{"event":"TRIP_COMPLETED","status":"COMPLETED","current_hazards":[],"alerts":[]}',
            );
            served.complete();
            break;
          }
        }
        await ws.close();
      });
      final api = ApiService(
        store: Store(),
        baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
      );
      final socket = TripSocket(api, 7);
      final result = await socket.send(19.05, 72.86);
      expect(result.status, 'COMPLETED');
      await served.future;
      socket.dispose();
      api.close();
      await server.close(force: true);
    },
  );

  test('Stream moves marker, confirms arrival once and stops publishing', () async {
    final positions = StreamController<LatLng>();
    final calls = <String>[];
    final updated = Completer<void>();
    final done = Completer<void>();
    final api = ApiService(
      store: Store(),
      client: MockClient((request) async {
        calls.add(request.body);
        final completed = calls.length == 2;
        if (!updated.isCompleted) updated.complete();
        return http.Response(
          '{"status":"${completed ? 'COMPLETED' : 'IN_PROGRESS'}","current_hazards":[],"alerts":[]}',
          201,
        );
      }),
    );
    LatLng? marker;
    var completions = 0;
    final monitor = TripMonitor(
      api: api,
      locate: () async => const LatLng(19, 72),
      positions: () => positions.stream,
      useWebSocket: false,
      interval: const Duration(days: 1),
    );
    monitor.onPosition = (point) => marker = point;
    monitor.onCompleted = () {
      completions++;
      done.complete();
    };
    monitor.setTrip(42);
    await updated.future;
    await Future<void>.delayed(Duration.zero);
    expect(marker, const LatLng(19, 72));
    positions.add(const LatLng(19.1, 72.1));
    await done.future;
    positions.add(const LatLng(20, 73));
    await Future<void>.delayed(Duration.zero);
    expect(marker, const LatLng(19.1, 72.1));
    expect(completions, 1);
    expect(calls, hasLength(2));
    expect(positions.hasListener, isFalse);
    monitor.dispose();
    await positions.close();
    api.close();
  });

  testWidgets('Confirmed arrival displays success alert and can be dismissed', (
    tester,
  ) async {
    final state = ActiveTripState();
    state.start(
      const ActiveTrip(
        originName: 'A',
        destinationName: 'B',
        origin: LatLng(19, 72),
        destination: LatLng(19.1, 72.1),
        route: RouteResponse(
          tripId: 1,
          points: [],
          distanceMeters: 1000,
          durationSeconds: 100,
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
    final api = ApiService(
      store: Store(),
      client: MockClient(
        (_) async => http.Response(
          '{"status":"COMPLETED","current_hazards":[],"alerts":[]}',
          201,
        ),
      ),
    );
    final monitor = TripMonitor(
      api: api,
      locate: () async => const LatLng(19.1, 72.1),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TripHazardMonitor(
          monitor: monitor,
          tripState: state,
          child: child!,
        ),
        home: const Scaffold(body: Text('Dashboard')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trip Completed!'), findsOneWidget);
    expect(
      find.text('You have safely reached your destination.'),
      findsOneWidget,
    );
    expect(state.completed, isTrue);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Trip Completed!'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    api.close();
  });

  test('Local proximity alone cannot mark a trip completed', () {
    final state = ActiveTripState();
    state.start(
      const ActiveTrip(
        originName: 'A',
        destinationName: 'B',
        origin: LatLng(19, 72),
        destination: LatLng(19.1, 72.1),
        route: RouteResponse(
          tripId: 1,
          points: [],
          distanceMeters: 1000,
          durationSeconds: 100,
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
    state.updatePosition(const LatLng(19.1, 72.1));
    expect(state.distanceToDestination, 0);
    expect(state.completed, isFalse);
    state.markCompleted();
    expect(state.completed, isTrue);
    state.clear();
    expect(state.completed, isFalse);
    expect(state.position, isNull);
    state.dispose();
  });
}
