import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_risk_app/screens/register_screen.dart';

void main() {
  testWidgets(
    'Password can be extended, corrected and cleared after validation',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Test User');
      await tester.enterText(fields.at(1), 'test@example.com');
      await tester.enterText(fields.at(2), '9876543210');
      await tester.enterText(fields.at(3), 'abcdefghij');
      await tester.enterText(fields.at(4), 'abcdefghij');
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pump();
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      await tester.enterText(fields.at(3), 'abcdefghijklmnop');
      await tester.pump();
      expect(find.text('Use at least 12 characters.'), findsNothing);
      expect(find.text('Passwords do not match.'), findsOneWidget);
      await tester.enterText(fields.at(4), 'abcdefghijklmnop');
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsNothing);
      await tester.enterText(fields.at(3), '');
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(3)).controller!.text, isEmpty);
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
