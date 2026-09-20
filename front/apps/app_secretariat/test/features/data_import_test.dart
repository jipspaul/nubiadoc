//! Test : `DataImportPage` (#7178, DP-F14.c) — upload, analyse à blanc
//! (rapport ligne à ligne), lancement, rapport final téléchargeable. Pas de
//! bloc ici (parcours séquentiel ponctuel) : use cases injectés via `GetIt`,
//! même convention que `stock_import_test.dart`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/data_import/data_import_page.dart';

class _MockUploadDataImportUseCase extends Mock
    implements UploadDataImportUseCase {}

class _MockDryRunDataImportUseCase extends Mock
    implements DryRunDataImportUseCase {}

class _MockRunDataImportUseCase extends Mock
    implements RunDataImportUseCase {}

class _MockGetDataImportStatusUseCase extends Mock
    implements GetDataImportStatusUseCase {}

class _MockFilePickerService extends Mock implements FilePickerService {}

DataImportJob _job({
  required String status,
  required String mode,
  int total = 0,
  int? created,
  int? updated,
  int? unchanged,
  int errors = 0,
  int importedCount = 0,
  int skippedCount = 0,
  int errorCount = 0,
  List<DataImportReportLine> lines = const [],
}) =>
    DataImportJob(
      id: 'job-1',
      kind: DataImportKind.csvPatients,
      sourceSystem: 'csv',
      fileName: 'patients.csv',
      status: DataImportStatus.values.byName(status),
      totalCount: total,
      importedCount: importedCount,
      skippedCount: skippedCount,
      errorCount: errorCount,
      createdAt: DateTime.utc(2026, 1, 1),
      report: DataImportReport(
        mode: mode,
        total: total,
        created: created,
        updated: updated,
        unchanged: unchanged,
        errors: errors,
        lines: lines,
      ),
    );

PickedFile _pickedCsv() => PickedFile(
      path: null,
      name: 'patients.csv',
      mimeType: 'text/csv',
      bytes: Uint8List.fromList(utf8.encode('nom;prenom\nDurand;Alice')),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(DataImportKind.csvPatients);
    registerFallbackValue(Uint8List(0));
  });

  late _MockUploadDataImportUseCase upload;
  late _MockDryRunDataImportUseCase dryRun;
  late _MockRunDataImportUseCase run;
  late _MockGetDataImportStatusUseCase getStatus;
  late _MockFilePickerService filePicker;

  setUp(() {
    upload = _MockUploadDataImportUseCase();
    dryRun = _MockDryRunDataImportUseCase();
    run = _MockRunDataImportUseCase();
    getStatus = _MockGetDataImportStatusUseCase();
    filePicker = _MockFilePickerService();
    GetIt.instance
      ..registerFactory<UploadDataImportUseCase>(() => upload)
      ..registerFactory<DryRunDataImportUseCase>(() => dryRun)
      ..registerFactory<RunDataImportUseCase>(() => run)
      ..registerFactory<GetDataImportStatusUseCase>(() => getStatus)
      ..registerFactory<FilePickerService>(() => filePicker);
    addTearDown(GetIt.instance.reset);

    when(() => filePicker.pickFile(allowedExtensions: ['csv']))
        .thenAnswer((_) async => _pickedCsv());
    when(() => getStatus(any()))
        .thenAnswer((_) async => const Left(NotFoundFailure()));
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: const DataImportPage(),
      );

  testWidgets(
      "le bouton d'import est désactivé tant qu'aucun fichier n'est choisi",
      (tester) async {
    await tester.pumpWidget(buildPage());
    final button = tester.widget<NubiaButton>(
      find.byKey(const Key('data_import_upload_button')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const Key('data_import_pick_file_button')));
    await tester.pump();
    final enabled = tester.widget<NubiaButton>(
      find.byKey(const Key('data_import_upload_button')),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('upload puis analyse à blanc affichent le rapport ligne à ligne',
      (tester) async {
    when(() => upload(
          kind: any(named: 'kind'),
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
        )).thenAnswer(
      (_) async => Right(_job(
        status: 'pending',
        mode: 'upload',
        total: 2,
        errors: 1,
        lines: const [
          DataImportReportLine(
              line: 2, action: 'error', message: 'nom manquant'),
        ],
      )),
    );

    await tester.pumpWidget(buildPage());
    await tester.tap(find.byKey(const Key('data_import_pick_file_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('data_import_upload_button')));
    await tester.pump();

    expect(
      find.text('2 ligne(s) au total · 1 OK · 1 en erreur'),
      findsOneWidget,
    );
    expect(find.textContaining('nom manquant'), findsOneWidget);

    when(() => dryRun('job-1')).thenAnswer(
      (_) async => Right(_job(
        status: 'pending',
        mode: 'dry_run',
        total: 2,
        created: 1,
        updated: 0,
        unchanged: 0,
        errors: 1,
        lines: const [
          DataImportReportLine(line: 1, action: 'created'),
          DataImportReportLine(
              line: 2, action: 'error', message: 'nom manquant'),
        ],
      )),
    );
    await tester.tap(find.byKey(const Key('data_import_dry_run_button')));
    await tester.pump();

    expect(
      find.text(
        '2 ligne(s) · 1 à créer · 0 à mettre à jour · '
        '0 inchangée(s) · 1 en erreur',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('data_import_run_button')), findsOneWidget);
  });

  testWidgets("lance l'import et permet de télécharger le rapport final",
      (tester) async {
    when(() => upload(
          kind: any(named: 'kind'),
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
        )).thenAnswer(
      (_) async => Right(_job(status: 'pending', mode: 'upload', total: 1)),
    );
    when(() => dryRun('job-1')).thenAnswer(
      (_) async => Right(_job(
        status: 'pending',
        mode: 'dry_run',
        total: 1,
        created: 1,
      )),
    );
    when(() => run('job-1')).thenAnswer(
      (_) async => Right(_job(
        status: 'completed',
        mode: 'run',
        total: 1,
        importedCount: 1,
      )),
    );
    when(() => filePicker.saveFile(
          bytes: any(named: 'bytes'),
          fileName: any(named: 'fileName'),
        )).thenAnswer((_) async => '/tmp/rapport-import-job-1.json');

    await tester.pumpWidget(buildPage());
    await tester.tap(find.byKey(const Key('data_import_pick_file_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('data_import_upload_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('data_import_dry_run_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('data_import_run_button')));
    await tester.pump();

    expect(
      find.text('1 importée(s) · 0 inchangée(s) · 0 en erreur'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('data_import_download_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('data_import_download_button')));
    await tester.pump();
    verify(() => filePicker.saveFile(
          bytes: any(named: 'bytes'),
          fileName: 'rapport-import-job-1.json',
        )).called(1);
  });

  testWidgets(
      "fichier invalide à l'upload affiche l'erreur et permet de recommencer",
      (tester) async {
    when(() => upload(
          kind: any(named: 'kind'),
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
        )).thenAnswer(
      (_) async => Right(_job(
        status: 'failed',
        mode: 'upload',
        errors: 1,
        lines: const [
          DataImportReportLine(
              line: 1, action: 'error', message: 'en-tête CSV invalide'),
        ],
      )),
    );

    await tester.pumpWidget(buildPage());
    await tester.tap(find.byKey(const Key('data_import_pick_file_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('data_import_upload_button')));
    await tester.pump();

    expect(find.text('en-tête CSV invalide'), findsOneWidget);

    await tester.tap(find.byKey(const Key('data_import_reset_button')));
    await tester.pump();
    expect(find.byKey(const Key('data_import_upload_form')), findsOneWidget);
  });

  testWidgets("échec réseau à l'upload affiche l'erreur", (tester) async {
    when(() => upload(
          kind: any(named: 'kind'),
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
        )).thenAnswer(
      (_) async => const Left(
        ServerFailure(message: "Impossible d'envoyer le fichier."),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.tap(find.byKey(const Key('data_import_pick_file_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('data_import_upload_button')));
    await tester.pump();

    expect(find.text("Impossible d'envoyer le fichier."), findsOneWidget);
    expect(find.byKey(const Key('data_import_upload_form')), findsOneWidget);
  });
}
