//! Tests widget : `SterilizationScanPage` (#4139) — scan réussi associe la
//! pochette à l'acte en cours et affiche une confirmation ; un code déjà
//! utilisé affiche une erreur. Saisie manuelle utilisée (pas de caméra en
//! environnement de test, `_ScannerView.isSupported` dépend de
//! `defaultTargetPlatform`, non garanti dans le harness de test — la
//! saisie manuelle est le chemin fonctionnellement équivalent, toujours
//! visible, cf. commentaire de `_ManualCodeField`).

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/sterilization_scan_page.dart';

class _MockListSterilizationCycles extends Mock
    implements ListSterilizationCyclesUseCase {}

class _MockAddSterilizedPouch extends Mock
    implements AddSterilizedPouchUseCase {}

final _cycle = SterilizationCycle(
  id: 'cycle-1',
  autoclaveRef: 'Autoclave-1',
  cycleNumber: 12,
  startedAt: DateTime(2026, 1, 1),
  testKind: 'bowie_dick',
  testResult: 'virage complet',
  status: 'conforme',
);

void main() {
  late _MockListSterilizationCycles listCycles;
  late _MockAddSterilizedPouch addPouch;

  setUp(() {
    listCycles = _MockListSterilizationCycles();
    addPouch = _MockAddSterilizedPouch();
    GetIt.instance
        .registerFactory<ListSterilizationCyclesUseCase>(() => listCycles);
    GetIt.instance.registerFactory<AddSterilizedPouchUseCase>(() => addPouch);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const SterilizationScanPage(consultationActId: 'act-1'),
      );

  testWidgets(
      'scan réussi (saisie manuelle) associe la pochette à l\'acte en cours et affiche une confirmation',
      (tester) async {
    when(() => listCycles()).thenAnswer((_) async => Right([_cycle]));
    when(() => addPouch(
          'cycle-1',
          code: 'DM-000042',
          consultationActId: 'act-1',
        )).thenAnswer((_) async => const Right('pouch-1'));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sterilization_scan_manual_code_field')),
      'DM-000042',
    );
    await tester.tap(find.byKey(const Key('sterilization_scan_manual_submit')));
    await tester.pumpAndSettle();

    verify(() => addPouch(
          'cycle-1',
          code: 'DM-000042',
          consultationActId: 'act-1',
        )).called(1);
    expect(
      find.byKey(const Key('sterilization_scan_success')),
      findsOneWidget,
    );
  });

  testWidgets('code déjà utilisé affiche une erreur', (tester) async {
    when(() => listCycles()).thenAnswer((_) async => Right([_cycle]));
    when(() => addPouch(
          'cycle-1',
          code: 'DM-DUP-001',
          consultationActId: 'act-1',
        )).thenAnswer(
      (_) async => const Left(
        ServerFailure(message: 'Ce code a déjà été scanné.', statusCode: 409),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('sterilization_scan_manual_code_field')),
      'DM-DUP-001',
    );
    await tester.tap(find.byKey(const Key('sterilization_scan_manual_submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sterilization_scan_error')), findsOneWidget);
    expect(find.text('Ce code a déjà été scanné.'), findsOneWidget);
    expect(
      find.byKey(const Key('sterilization_scan_success')),
      findsNothing,
    );
  });

  testWidgets('aucun cycle enregistré → message dédié, pas de champ de scan',
      (tester) async {
    when(() => listCycles()).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sterilization_scan_no_cycle')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('sterilization_scan_manual_code_field')),
      findsNothing,
    );
  });
}
