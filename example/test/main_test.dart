import 'package:flutter_test/flutter_test.dart';
import 'package:iran_iap_example/main.dart' as app;

const _storeName = String.fromEnvironment('IRAN_IAP_STORE');

void main() {
  testWidgets('shows missing Myket configuration', (tester) async {
    app.main();
    await tester.pump();

    await tester.tap(find.text('Initialize'));
    await tester.pump();

    expect(find.text('IAP_PUBLIC_KEY is required for Myket.'), findsOneWidget);
  }, skip: _storeName != 'myket');
}
