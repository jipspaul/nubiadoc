import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

void main() {
  testWidgets('pumpApp affiche le widget enfant', (tester) async {
    await tester.pumpApp(const Text('app_practicien smoke'));
    expect(find.text('app_practicien smoke'), findsOneWidget);
  });
}
