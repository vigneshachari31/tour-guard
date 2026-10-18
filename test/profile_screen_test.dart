import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:travel_risk_app/screens/profile_screen.dart';
import 'package:travel_risk_app/services/api_service.dart';

import 'api_service_test.dart' show MemoryStore;

void main() {
  testWidgets('Avatar selection uploads and displays the saved image', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY1sAAAAASUVORK5CYII=',
    );
    final store = MemoryStore()
      ..value = '{"access_token":"jwt","token_type":"bearer"}';
    var uploaded = false;
    final api = ApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer jwt');
        if (request.url.path.endsWith('/upload-avatar')) {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body)['image_base64'], base64Encode(bytes));
          uploaded = true;
          return http.Response(
            '{"profile_picture_url":"/api/v1/profile/avatar/0123456789abcdef0123456789abcdef"}',
            200,
          );
        }
        if (request.url.path.contains('/avatar/')) {
          return http.Response.bytes(bytes, 200);
        }
        return http.Response(
          '{"full_name":"Tourist","email":"test@example.com"}',
          200,
        );
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(api: api, pickAvatar: () async => bytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit profile photo'));
    await tester.pumpAndSettle();
    expect(uploaded, isTrue);
    expect(find.text('Profile photo saved.'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Profile loads, saves all fields and reloads backend data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var profile = <String, dynamic>{
      'full_name': 'Original',
      'email': 'test@example.com',
      'phone_number': '+12025550123',
    };
    var saves = 0;
    final store = MemoryStore()
      ..value = '{"access_token":"jwt","token_type":"bearer"}';
    final api = ApiService(
      store: store,
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer jwt');
        expect(request.url.path, '/api/v1/profile/me');
        if (request.method == 'PUT') {
          saves++;
          profile = jsonDecode(request.body) as Map<String, dynamic>;
        } else {
          expect(request.method, 'GET');
        }
        return http.Response(jsonEncode(profile), 200);
      }),
    );
    Widget screen() => MaterialApp(
      home: Scaffold(body: ProfileScreen(api: api)),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsWidgets);
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    final values = [
      'Taylor Tourist',
      'updated@example.com',
      '+919876543210',
      'O+',
      'Contact +919876543211',
      'Medication',
      'Pollen',
    ];
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(find.byType(TextFormField).at(i), values[i]);
    }
    await tester.ensureVisible(find.text('SAVE PROFILE'));
    await tester.tap(find.text('SAVE PROFILE'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(profile['full_name'], values[0]);
    expect(profile['phone_number'], values[2]);
    expect(profile['allergies'], 'Pollen');
    expect(find.text('Profile saved to your account.'), findsOneWidget);
    expect(find.textContaining('Changing your email also changes your sign-in email'), findsNothing);
    expect(find.text('SAVE PROFILE'), findsNothing);
    expect(find.text('Edit Profile'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('Taylor Tourist'), findsWidgets);
    expect(find.text('Medication'), findsOneWidget);
  });

  testWidgets(
    'Failed profile loading offers retry without an empty save form',
    (tester) async {
      final store = MemoryStore()
        ..value = '{"access_token":"jwt","token_type":"bearer"}';
      final api = ApiService(
        store: store,
        client: MockClient(
          (_) async => http.Response('{"detail":"Unavailable"}', 503),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('SAVE PROFILE'), findsNothing);
    },
  );
}
