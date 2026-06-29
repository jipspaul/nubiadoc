import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/register/pro_register_cubit.dart';
import 'package:app_practicien/features/register/pro_register_page.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockProRegisterCubit extends MockCubit<ProRegisterState>
    implements ProRegisterCubit {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildPage(ProRegisterCubit cubit) => BlocProvider<ProRegisterCubit>.value(
      value: cubit,
      child: const ProRegisterPage(),
    );

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextField, 'Prénom'), 'Alice');
  await tester.pump();
  await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Martin');
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextField, 'E-mail professionnel'),
      'alice@cabinet.fr');
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextField, 'Mot de passe').first, 'Secret1!');
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextField, 'Confirmer le mot de passe'), 'Secret1!');
  await tester.pump();

  // Scroll and fill RPPS
  await tester.ensureVisible(
      find.widgetWithText(TextField, 'RPPS (11 chiffres)'));
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextField, 'RPPS (11 chiffres)'), '12345678901');
  await tester.pump();

  // Scroll and fill raison sociale
  await tester.ensureVisible(
      find.widgetWithText(TextField, 'Raison sociale'));
  await tester.pump();
  await tester.enterText(
      find.widgetWithText(TextField, 'Raison sociale'), 'Cabinet Test');
  await tester.pump();

  // Select specialite — scroll then tap
  await tester.ensureVisible(find.byKey(const Key('specialite_dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('specialite_dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Chirurgie dentaire').last);
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProRegisterPage', () {
    testWidgets('bouton désactivé quand formulaire invalide (vide)', (tester) async {
      final cubit = MockProRegisterCubit();
      whenListen(cubit, Stream<ProRegisterState>.empty(),
          initialState: const ProRegisterIdle());

      await tester.pumpApp(_buildPage(cubit));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('bouton activé quand formulaire valide', (tester) async {
      final cubit = MockProRegisterCubit();
      whenListen(cubit, Stream<ProRegisterState>.empty(),
          initialState: const ProRegisterIdle());

      await tester.pumpApp(_buildPage(cubit));
      await _fillValidForm(tester);

      // Scroll to the submit button
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('snackbar affiché sur ProRegisterFailure', (tester) async {
      const erreur = 'Erreur serveur.';
      final cubit = MockProRegisterCubit();
      whenListen(
        cubit,
        Stream.fromIterable([const ProRegisterFailure(erreur)]),
        initialState: const ProRegisterIdle(),
      );

      await tester.pumpApp(_buildPage(cubit));
      await tester.pump(); // déclenche le listener

      expect(find.text(erreur), findsOneWidget);
    });

    testWidgets('erreur inline RPPS si moins de 11 chiffres', (tester) async {
      final cubit = MockProRegisterCubit();
      whenListen(cubit, Stream<ProRegisterState>.empty(),
          initialState: const ProRegisterIdle());

      await tester.pumpApp(_buildPage(cubit));
      await tester.enterText(
          find.widgetWithText(TextField, 'RPPS (11 chiffres)'), '123');
      await tester.pump();

      expect(find.text('11 chiffres requis.'), findsOneWidget);
    });

    testWidgets('erreur inline SIRET si différent de 14 chiffres', (tester) async {
      final cubit = MockProRegisterCubit();
      whenListen(cubit, Stream<ProRegisterState>.empty(),
          initialState: const ProRegisterIdle());

      await tester.pumpApp(_buildPage(cubit));
      await tester.enterText(
          find.widgetWithText(TextField, 'SIRET (14 chiffres, optionnel)'), '123');
      await tester.pump();

      expect(find.text('14 chiffres requis.'), findsOneWidget);
    });

    testWidgets('erreur mot de passe si < 8 caractères', (tester) async {
      final cubit = MockProRegisterCubit();
      whenListen(cubit, Stream<ProRegisterState>.empty(),
          initialState: const ProRegisterIdle());

      await tester.pumpApp(_buildPage(cubit));
      await tester.enterText(
          find.widgetWithText(TextField, 'Mot de passe').first, 'Ab1!');
      await tester.pump();

      expect(find.text('Au moins 8 caractères.'), findsOneWidget);
    });
  });
}
