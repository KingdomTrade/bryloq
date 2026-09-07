import 'package:flutter_test/flutter_test.dart';
import 'package:saydo_ai/main.dart';

void main() {
  testWidgets(
    'SayDo app loads successfully',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const SayDoApp(),
      );

      expect(
        find.text("What's on your mind?"),
        findsOneWidget,
      );

      expect(
        find.text('SayDo'),
        findsOneWidget,
      );
    },
  );
}