import 'package:flutter_test/flutter_test.dart';
import 'package:advanced_assistant/app/app.dart';

void main() {
  testWidgets('application shell renders Arabic product title', (tester) async {
    await tester.pumpWidget(const AdvancedAssistantApp());
    expect(find.text('المساعد الذكي PRO'), findsOneWidget);
  });
}
