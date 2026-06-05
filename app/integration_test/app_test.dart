// Integration test entry point.
// Run with: flutter test integration_test/ --flavor dev
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nubia_patient/bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App smoke test', () {
    testWidgets('App starts without crash', (tester) async {
      await bootstrap();
      await tester.pumpAndSettle();
      // App launched — detailed flows in integration_test/flows/
      expect(find.byType(tester.widget.runtimeType), findsWidgets);
    });
  });
}
