import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/models/route_response.dart';
import 'package:travel_risk_app/widgets/route_safety_details.dart';

void main() {
  testWidgets('Weather is readable and technical source stays collapsed', (tester) async {
    const route = RouteResponse(points: [], distanceMeters: 1, durationSeconds: 1,
      bufferMeters: 250, riskLevel: 'CAUTION', method: 'heuristic_v1',
      hazards: [], weatherUsed: true,
      reasons: ['Weather at route origin: rain 0 mm/h, wind 7.8 km/h. Source: Open-Meteo'],
      limitations: ['Hazard coverage has not been verified.']);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: RouteSafetyDetails(route: route)))));
    expect(find.text('Rain 0 mm/h · Wind 7.8 km/h'), findsOneWidget);
    expect(find.textContaining('Source: Open-Meteo'), findsNothing);
    expect(find.textContaining('not a safety guarantee'), findsOneWidget);
    await tester.tap(find.text('Sources & assessment notes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Source: Open-Meteo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
