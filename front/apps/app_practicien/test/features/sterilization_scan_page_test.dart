//! Tests widget : `SterilizationScanPage` (#4139) — scan réussi associe la
//! pochette à l'acte en cours et affiche une confirmation ; un code déjà
//! utilisé affiche une erreur. Saisie manuelle utilisée (pas de caméra en
//! environnement de test, `NubiaQrScannerView.isSupported` dépend de
//! `defaultTargetPlatform`, non garanti dans le harness de test — la
//! saisie manuelle est le chemin fonctionnellement équivalent, toujours
//! visible, cf. commentaire de `_ManualCodeField`).
//! Bouton « Imprimer les étiquettes » (#7180) : mêmes conventions que
//! `patient_fiche_export_pdf_test.dart` — desktop forcé
//! (`debugDefaultTargetPlatformOverride`) pour vérifier
//! `FilePickerService.saveFile` sans dépendre du canal de plateforme
//! `share_plus`, non mocké dans le harness de test.

import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/sterilization_scan_page.dart';

class _MockListSterilizationCycles extends Mock
    implements ListSterilizationCyclesUseCase {}

class _MockAddSterilizedPouch extends Mock
    implements AddSterilizedPouchUseCase {}

class _MockGetSterilizationLabelsPdf extends Mock
    implements GetSterilizationLabelsPdfUseCase {}

class _MockFilePickerService extends Mock implements FilePickerService {}

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
  late _MockGetSterilizationLabelsPdf getLabelsPdf;
  late _MockFilePickerService filePicker;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    listCycles = _MockListSterilizationCycles();
    addPouch = _MockAddSterilizedPouch();
    getLabelsPdf = _MockGetSterilizationLabelsPdf();
    filePicker = _MockFilePickerService();
    GetIt.instance
        .registerFactory<ListSterilizationCyclesUseCase>(() => listCycles);
    GetIt.instance.registerFactory<AddSterilizedPouchUseCase>(() => addPouch);
    GetIt.instance
        .registerFactory<GetSterilizationLabelsPdfUseCase>(() => getLabelsPdf);
    GetIt.instance.registerFactory<FilePickerService>(() => filePicker);
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

  testWidgets('aucun cycle enregistré → pas de bouton « Imprimer les étiquettes »',
      (tester) async {
    when(() => listCycles()).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('sterilization_print_labels_button')),
      findsNothing,
    );
  });

  testWidgets(
      "« Imprimer les étiquettes » (desktop) enregistre le PDF via FilePickerService",
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      when(() => listCycles()).thenAnswer((_) async => Right([_cycle]));
      when(() => getLabelsPdf('cycle-1'))
          .thenAnswer((_) async => Right([1, 2, 3]));
      when(() => filePicker.saveFile(
            bytes: any(named: 'bytes'),
            fileName: any(named: 'fileName'),
          )).thenAnswer((_) async => '/tmp/etiquettes.pdf');

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('sterilization_print_labels_button')));
      await tester.pumpAndSettle();

      verify(() => getLabelsPdf('cycle-1')).called(1);
      verify(() => filePicker.saveFile(
            bytes: any(named: 'bytes', that: isA<Uint8List>()),
            fileName: 'etiquettes-sterilisation-Autoclave-1-12.pdf',
          )).called(1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      "« Imprimer les étiquettes » — échec API affiche un snackbar d'erreur",
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      when(() => listCycles()).thenAnswer((_) async => Right([_cycle]));
      when(() => getLabelsPdf('cycle-1')).thenAnswer(
        (_) async => const Left(
          ServerFailure(message: 'Impossible de générer les étiquettes.'),
        ),
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('sterilization_print_labels_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Impossible de générer les étiquettes.'),
        findsOneWidget,
      );
      verifyNever(() => filePicker.saveFile(
            bytes: any(named: 'bytes'),
            fileName: any(named: 'fileName'),
          ));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
