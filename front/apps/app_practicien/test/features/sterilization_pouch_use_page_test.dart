//! Tests widget : `SterilizationPouchUsePage` (#7180) — scan (saisie
//! manuelle, pas de caméra dans le harness de test, cf.
//! `sterilization_scan_page_test.dart`) d'un sachet stérilisé déjà étiqueté
//! rattache le sachet à la consultation en cours ; un sachet déjà utilisé
//! sur un autre patient affiche une erreur.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/sterilization_pouch_use_page.dart';

class _MockConfirmSterilizedPouchUse extends Mock
    implements ConfirmSterilizedPouchUseUseCase {}

void main() {
  late _MockConfirmSterilizedPouchUse confirmUse;

  setUp(() {
    confirmUse = _MockConfirmSterilizedPouchUse();
    GetIt.instance.registerFactory<ConfirmSterilizedPouchUseUseCase>(
      () => confirmUse,
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const SterilizationPouchUsePage(
          patientId: 'pat-1',
          consultationId: 'session-1',
        ),
      );

  testWidgets(
      'scan réussi (saisie manuelle) rattache le sachet à la consultation et affiche une confirmation',
      (tester) async {
    when(() => confirmUse(
          'DM-000042',
          patientId: 'pat-1',
          consultationId: 'session-1',
        )).thenAnswer(
      (_) async => Right(
        SterilizedPouchUse(
          pouchId: 'pouch-1',
          code: 'DM-000042',
          cycleId: 'cycle-1',
          patientId: 'pat-1',
          consultationId: 'session-1',
          usedAt: DateTime(2026, 9, 20),
          alreadyUsed: false,
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sterilization_pouch_use_manual_code_field')),
      'DM-000042',
    );
    await tester
        .tap(find.byKey(const Key('sterilization_pouch_use_manual_submit')));
    await tester.pumpAndSettle();

    verify(() => confirmUse(
          'DM-000042',
          patientId: 'pat-1',
          consultationId: 'session-1',
        )).called(1);
    expect(
      find.byKey(const Key('sterilization_pouch_use_success')),
      findsOneWidget,
    );
    expect(find.text('DM-000042'), findsOneWidget);
  });

  testWidgets('sachet déjà utilisé sur un autre patient affiche une erreur',
      (tester) async {
    when(() => confirmUse(
          'DM-USED',
          patientId: 'pat-1',
          consultationId: 'session-1',
        )).thenAnswer(
      (_) async => const Left(
        ServerFailure(
          message: 'Ce sachet a déjà été utilisé sur un autre patient ou '
              'une autre séance.',
          statusCode: 409,
          code: 'pouch_already_used',
        ),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sterilization_pouch_use_manual_code_field')),
      'DM-USED',
    );
    await tester
        .tap(find.byKey(const Key('sterilization_pouch_use_manual_submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sterilization_pouch_use_error')),
      findsOneWidget,
    );
    expect(
      find.text('Ce sachet a déjà été utilisé sur un autre patient ou '
          'une autre séance.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sterilization_pouch_use_success')),
      findsNothing,
    );
  });
}
