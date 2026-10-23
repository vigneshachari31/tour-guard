import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/widgets/sos_alert_card.dart';

void main() {
  for (final entry in [('OPEN', 'Open'), ('RESOLVED', 'Resolved'), ('CANCELLED', 'Cancelled')]) {
    testWidgets('SOS activity renders ${entry.$2} without exposing raw details', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SosAlertCard(event: {
        'id': 24, 'workflow_status': entry.$1, 'status': 'active',
        'tourist_id': 'TG-TEST', 'latitude': 19.04, 'longitude': 72.85,
        'created_at': '2026-10-23T16:30:00Z',
      }))));
      expect(find.text(entry.$2), findsOneWidget);
      expect(find.textContaining('TG-TEST'), findsNothing);
      expect(find.textContaining('2026-10-23T'), findsNothing);
      await tester.tap(find.text('SOS #24'));
      await tester.pumpAndSettle();
      expect(find.textContaining('TG-TEST'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
