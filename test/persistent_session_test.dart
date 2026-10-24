import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/services/api_service.dart';
import 'package:travel_risk_app/screens/splash_screen.dart';

class SavedSession implements SessionStore {
  String? value;
  SavedSession({bool saved = true}) : value = saved ? jsonEncode({
    'access_token': 'old', 'refresh_token': 'saved-refresh', 'token_type': 'bearer', 'tourist_id': 'TG-test',
  }) : null;
  @override Future<String?> read() async => value;
  @override Future<void> write(String next) async { value = next; }
  @override Future<void> clear() async { value = null; }
}

void main() {
  for (final saved in [true, false]) {
    testWidgets('Startup restores saved session: $saved', (tester) async {
      final api = ApiService(store: SavedSession(saved: saved));
      await tester.pumpWidget(MaterialApp(home: SplashScreen(api: api), routes: {
        '/dashboard': (_) => const Scaffold(body: Text('Signed in')),
        '/login': (_) => const Scaffold(body: Text('Sign in')),
      }));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text(saved ? 'Signed in' : 'Sign in'), findsOneWidget);
      api.close();
    });
  }
  test('Expired token renews and retries without asking for login', () async {
    final store = SavedSession();
    var refreshes = 0;
    final api = ApiService(store: store, client: MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh')) {
        refreshes++;
        return http.Response(jsonEncode({'access_token': 'new', 'refresh_token': 'new-refresh',
          'token_type': 'bearer', 'tourist_id': 'TG-test'}), 200);
      }
      if (request.headers['Authorization'] == 'Bearer old') return http.Response('{}', 401);
      return http.Response('[]', 200);
    }));
    await Future.wait([api.getActiveSosEvents(), api.getActiveSosEvents()]);
    expect(refreshes, 1);
    expect((await api.getSession())!.accessToken, 'new');
    final reopened = ApiService(store: store);
    expect((await reopened.getSession())!.refreshToken, 'new-refresh');
    reopened.close(); api.close();
  });
  test('Refresh server failure preserves saved session', () async {
    final store = SavedSession();
    final api = ApiService(store: store, client: MockClient((request) async =>
      http.Response('{}', request.url.path.endsWith('/auth/refresh') ? 503 : 401)));
    await expectLater(api.getActiveSosEvents(), throwsA(isA<ApiException>()));
    expect(store.value, isNotNull);
    api.close();
  });
  test('Logout clears local credentials even offline', () async {
    final store = SavedSession();
    final api = ApiService(store: store, client: MockClient((_) async => throw http.ClientException('offline')));
    await api.logout();
    expect(await api.getSession(), isNull);
    api.close();
  });
}
