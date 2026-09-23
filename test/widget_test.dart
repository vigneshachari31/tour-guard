import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TravelRiskApp());
    // Advance splash screen timer and settle animations
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byType(TravelRiskApp), findsOneWidget);
  });
}
