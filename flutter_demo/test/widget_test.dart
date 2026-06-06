import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/main.dart';

void main() {
  testWidgets('counter increments (authenticated)', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(); // AuthCheckRequested → AuthUnauthenticated (no stored token)

    // Sans token persisté, l'app démarre sur LoginScreen.
    expect(find.byType(MyHomePage), findsNothing);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('MyHomePage counter increments', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: MyHomePage()),
    );

    expect(find.text('Hello Flutter'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inc')));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
