import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockListPatientJournal extends Mock
    implements ListPatientJournalUseCase {}

class _MockGetMedicalRecord extends Mock implements GetMedicalRecordUseCase {}

class _MockFilePickerService extends Mock implements FilePickerService {}

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean.dupont@example.com',
  phone: '0600000001',
  createdAt: DateTime(2024, 1, 1),
);

void main() {
  late _MockFilePickerService filePicker;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    final listDocuments = _MockListPatientDocuments();
    when(() => listDocuments(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListPatientDocumentsUseCase>(() => listDocuments);

    final listJournal = _MockListPatientJournal();
    when(() => listJournal(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance
        .registerFactory<ListPatientJournalUseCase>(() => listJournal);

    final getMedicalRecord = _MockGetMedicalRecord();
    when(() => getMedicalRecord(any())).thenAnswer(
      (_) async =>
          const Right(MedicalRecordSummary(allergies: [], treatments: [])),
    );
    GetIt.instance
        .registerFactory<GetMedicalRecordUseCase>(() => getMedicalRecord);

    filePicker = _MockFilePickerService();
    when(() => filePicker.saveFile(
          bytes: any(named: 'bytes'),
          fileName: any(named: 'fileName'),
        )).thenAnswer((_) async => '/tmp/patient_pat-1.pdf');
    GetIt.instance.registerFactory<FilePickerService>(() => filePicker);

    addTearDown(GetIt.instance.reset);
  });

  // #4983, maquette design-v2 — sur desktop, l'export PDF déclenche un
  // téléchargement/enregistrement (FilePickerService.saveFile) plutôt que
  // la feuille de partage système (Share.shareXFiles, incohérente/non
  // implémentée sur desktop).
  testWidgets(
      "sur desktop, l'export PDF enregistre le fichier au lieu de le partager",
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        MaterialApp(
            theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('export_pdf_button')));
      await tester.pumpAndSettle();

      verify(() => filePicker.saveFile(
            bytes: any(named: 'bytes', that: isA<Uint8List>()),
            fileName: 'patient_pat-1.pdf',
          )).called(1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
