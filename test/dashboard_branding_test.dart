import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/widgets/dashboard/dashboard_header.dart';
import 'package:travel_risk_app/widgets/dashboard/route_risk_card.dart';

void main() {
  for (final width in [320.0, 1200.0]) {
    testWidgets('Branded dashboard fits $width and retains map action', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = false;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          const DashboardHeader(),
          const SizedBox(height: 16),
          RouteRiskCard(onOpenMap: () => opened = true),
        ])),
      ))));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Route not assessed'), findsNothing);
      await tester.tap(find.text('Plan your journey'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
