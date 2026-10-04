import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/screens/sos_screen.dart';

void main() {
  group('Smart Rescue & SOS Screen Widget Tests', () {
    testWidgets('Renders SOS Screen title, beacon, and official helplines',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );

      // Advance past geolocator timeout timer
      await tester.pump(const Duration(seconds: 7));

      // Verify Screen Header and Beacon
      expect(find.text('SMART RESCUE COMMAND'), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget);

      // Verify Telemetry and Medical Card Headers
      expect(find.text('LIVE RESCUE TELEMETRY'), findsOneWidget);
      expect(find.text('TOURIST EMERGENCY CONTEXT'), findsOneWidget);

      // Verify Official Helplines
      expect(find.text('112'), findsOneWidget);
      expect(find.text('1077'), findsOneWidget);
      expect(find.text('108'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Tapping SOS starts countdown timer and allows aborting',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SosScreen(),
        ),
      );

      await tester.pump(const Duration(seconds: 7));

      // Tap the central SOS Button
      await tester.tap(find.text('SOS'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Countdown begins and shows Abort prompt
      expect(find.text('TAP TO ABORT'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // Tap again to Abort (Cancel False Alarm)
      await tester.tap(find.text('TAP TO ABORT'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify reset back to standard SOS
      expect(find.text('SOS'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
