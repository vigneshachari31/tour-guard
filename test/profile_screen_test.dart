import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travel_risk_app/screens/dashboard_screen.dart';
import 'package:travel_risk_app/screens/profile_screen.dart';
import 'package:travel_risk_app/services/tourist_profile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Profile edits are saved locally', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('MY PROFILE'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Taylor Tourist');
    await tester.ensureVisible(find.text('SAVE PROFILE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVE PROFILE'));
    await tester.pumpAndSettle();

    expect(find.text('Profile saved on this device.'), findsOneWidget);
    final savedProfile = await TouristProfile.load();
    expect(savedProfile.name, 'Taylor Tourist');
  });

  testWidgets('Dashboard Profile tab opens the profile screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('MY PROFILE'), findsOneWidget);
  });
}
