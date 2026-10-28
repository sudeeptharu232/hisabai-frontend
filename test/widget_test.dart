import 'package:flutter_test/flutter_test.dart';
import 'package:hisabai/app.dart';

import 'support/test_support.dart';

// Named widget_test.dart on purpose: `flutter create` would otherwise generate
// a default counter-app test with this name that does not match this app.
void main() {
  testWidgets('app starts on the sign-in screen when signed out', (tester) async {
    final app = TestApp((_) async => jsonResponse(500));

    await tester.pumpWidget(
      HisabAiApp(
        auth: app.auth,
        healthClient: app.healthClient,
        expenseRepository: app.expenseRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Check server connection'), findsOneWidget);
  });
}
