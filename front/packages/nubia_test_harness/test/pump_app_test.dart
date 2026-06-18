import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

void main() {
  group('pumpApp', () {
    testWidgets('affiche le widget enfant dans MaterialApp + thème Nubia',
        (tester) async {
      await tester.pumpApp(const Text('Nubia test'));

      expect(find.text('Nubia test'), findsOneWidget);
    });

    testWidgets('applique le thème Nubia clair', (tester) async {
      await tester.pumpApp(
        Builder(
          builder: (context) => Text(
            'theme',
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );

      final BuildContext ctx = tester.element(find.text('theme'));
      expect(
        Theme.of(ctx).colorScheme.primary,
        NubiaColors.brand700,
      );
    });

    testWidgets('pumpApp accepte un widget arbitraire sans erreur',
        (tester) async {
      await tester.pumpApp(
        const Column(
          children: [
            Text('ligne 1'),
            Text('ligne 2'),
          ],
        ),
      );

      expect(find.text('ligne 1'), findsOneWidget);
      expect(find.text('ligne 2'), findsOneWidget);
    });
  });

  group('Mock repositories', () {
    test('MockAccountRepository est instanciable', () {
      final repo = MockAccountRepository();
      expect(repo, isA<MockAccountRepository>());
    });

    test('MockAppointmentRepository est instanciable', () {
      final repo = MockAppointmentRepository();
      expect(repo, isA<MockAppointmentRepository>());
    });

    test('MockAuthRepository est instanciable', () {
      final repo = MockAuthRepository();
      expect(repo, isA<MockAuthRepository>());
    });

    test('MockDocumentRepository est instanciable', () {
      final repo = MockDocumentRepository();
      expect(repo, isA<MockDocumentRepository>());
    });

    test('MockMessageRepository est instanciable', () {
      final repo = MockMessageRepository();
      expect(repo, isA<MockMessageRepository>());
    });
  });
}
