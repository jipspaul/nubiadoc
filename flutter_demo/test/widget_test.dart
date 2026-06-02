import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_demo/main.dart';

void main() {
  testWidgets('counter increments', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Hello Flutter'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inc')));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
