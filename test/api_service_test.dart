import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/services/api_service.dart';

class MemoryStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  test(
    'Signup sends name and personal phone in emergency_contact_phone',
    () async {
      final api = ApiService(
        store: MemoryStore(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/register');
          expect(jsonDecode(request.body), {
            'email': 'test@example.com',
            'password': 'long-password',
            'full_name': 'Test Tourist',
            'emergency_contact_phone': '+12025550123',
          });
          return http.Response(
            '{"access_token":"jwt","token_type":"bearer","tourist_id":"TG-12345678"}',
            201,
          );
        }),
      );
      await api.register(
        email: 'test@example.com',
        password: 'long-password',
        fullName: ' Test Tourist ',
        emergencyContactPhone: '+12025550123',
      );
    },
  );

  test(
    'login persists session and SOS sends bearer token and tourist ID',
    () async {
      final store = MemoryStore();
      final client = MockClient((request) async {
        final body = jsonDecode(request.body);
        if (request.url.path.endsWith('/auth/login')) {
          expect(body, {'email': 'a@example.com', 'password': 'long-password'});
          return http.Response(
            jsonEncode({
              'access_token': 'jwt',
              'token_type': 'bearer',
              'tourist_id': 'TG-12345678',
            }),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer jwt');
        expect(body, {
          'tourist_id': 'TG-12345678',
          'latitude': 11.4,
          'longitude': 76.7,
        });
        return http.Response(
          '{"id":1,"status":"active","message":"Recorded"}',
          201,
        );
      });
      final api = ApiService(client: client, store: store);
      await api.login(email: ' a@example.com ', password: 'long-password');
      final restored = ApiService(client: client, store: store);
      expect(await restored.getToken(), 'jwt');
      expect(
        (await restored.triggerSOS(latitude: 11.4, longitude: 76.7)).id,
        1,
      );
    },
  );

  test('protected 401 removes expired session', () async {
    final store = MemoryStore();
    await store.write('{"access_token":"old","token_type":"bearer"}');
    final api = ApiService(
      store: store,
      client: MockClient((_) async => http.Response('', 401)),
    );
    await expectLater(
      api.analyzeRoute(originLat: 11, originLng: 76, destLat: 12, destLng: 77),
      throwsA(
        isA<ApiException>().having((e) => e.unauthorized, 'unauthorized', true),
      ),
    );
    expect(await api.getToken(), isNull);
  });

  test('route parses GeoJSON longitude first and preserves warnings', () async {
    final store = MemoryStore();
    await store.write('{"access_token":"jwt","token_type":"bearer"}');
    final api = ApiService(
      store: store,
      client: MockClient((request) async {
        expect(jsonDecode(request.body).containsKey('weather'), false);
        return http.Response(
          jsonEncode({
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [76.7, 11.4],
                [76.8, 11.5],
              ],
            },
            'distance_meters': 15000,
            'duration_seconds': 1200,
            'buffer_meters': 250,
            'hazards': [
              {
                'id': 1,
                'name': 'Slope',
                'hazard_type': 'landslide',
                'severity': 4,
                'source': 'survey',
              },
            ],
            'assessment': {
              'level': 'HIGH RISK',
              'method': 'heuristic_v1',
              'reasons': ['Landslide nearby'],
              'limitations': ['Weather unavailable'],
              'weather_used': false,
            },
          }),
          200,
        );
      }),
    );
    final route = await api.analyzeRoute(
      originLat: 11.4,
      originLng: 76.7,
      destLat: 11.5,
      destLng: 76.8,
    );
    expect(route.points.first.latitude, 11.4);
    expect(route.points.first.longitude, 76.7);
    expect(route.riskLevel, 'HIGH RISK');
    expect(route.hazards.single.severity, 4);
    expect(route.limitations, ['Weather unavailable']);
  });

  test('network failures produce an actionable API error', () async {
    final api = ApiService(
      store: MemoryStore(),
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      api.login(email: 'a@example.com', password: 'x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Cannot reach'),
        ),
      ),
    );
  });

  test('Pydantic validation details reach the UI', () async {
    final api = ApiService(
      store: MemoryStore(),
      client: MockClient(
        (_) async => http.Response(
          '{"detail":[{"loc":["body","password"],"msg":"Too short"}]}',
          422,
        ),
      ),
    );
    await expectLater(
      api.register(email: 'a@example.com', password: 'x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'password: Too short',
        ),
      ),
    );
  });
}
