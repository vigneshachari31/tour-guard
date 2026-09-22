import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TravelRiskApp());
    expect(find.byType(TravelRiskApp), findsOneWidget);
  });
}
