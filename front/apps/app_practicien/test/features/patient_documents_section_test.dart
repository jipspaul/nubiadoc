//! Tests widget : `PatientDocumentsSection` (#4042/#4133) — liste vide/
//! remplie, filtre catégorie, upload.

import 'dart:typed_data';

import 'package:dartz/dartz.dart';
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

class _MockUploadPatientDocument extends Mock
    implements UploadPatientDocumentUseCase {}

class _MockFilePickerService extends Mock implements FilePickerService {}

PatientDocument _doc(String suffix, {String category = 'ordonnance'}) =>
    PatientDocument(
      id: 'doc-$suffix',
      category: category,
      filename: 'document_$suffix.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 54321,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late _MockListPatientDocuments listDocs;
  late _MockUploadPatientDocument uploadDoc;
  late _MockFilePickerService filePicker;

  setUp(() {
    listDocs = _MockListPatientDocuments();
    uploadDoc = _MockUploadPatientDocument();
    filePicker = _MockFilePickerService();
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocs,
    );
    GetIt.instance.registerFactory<UploadPatientDocumentUseCase>(
      () => uploadDoc,
    );
    GetIt.instance.registerFactory<FilePickerService>(() => filePicker);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const SingleChildScrollView(
            child: PatientDocumentsSection(patientId: 'patient-1'),
          ),
        ),
      );

  testWidgets('liste vide — affiche le message vide', (tester) async {
    when(() => listDocs('patient-1', category: null))
        .thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_documents_empty')), findsOneWidget);
    expect(find.byType(ListRow), findsNothing);
  });

  testWidgets('liste remplie — affiche les documents', (tester) async {
    when(() => listDocs('patient-1', category: null)).thenAnswer(
      (_) async => Right([_doc('a'), _doc('b'), _doc('c')]),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNWidgets(3));
    expect(find.byKey(const Key('patient_documents_empty')), findsNothing);
  });

  testWidgets('filtre catégorie radio → relance la liste avec ?category=radio',
      (tester) async {
    when(() => listDocs('patient-1', category: null))
        .thenAnswer((_) async => Right([_doc('a')]));
    when(() => listDocs('patient-1', category: 'radio'))
        .thenAnswer((_) async => Right([_doc('b', category: 'radio')]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();
    expect(find.byType(ListRow), findsNWidgets(1));

    await tester.tap(find.byKey(const Key('patient_documents_filter_radio')));
    await tester.pumpAndSettle();

    verify(() => listDocs('patient-1', category: 'radio')).called(1);
    expect(find.byType(ListRow), findsNWidgets(1));
  });

  testWidgets('upload : sélection fichier + catégorie appelle le use case',
      (tester) async {
    when(() => listDocs('patient-1', category: null))
        .thenAnswer((_) async => const Right([]));
    when(() => filePicker.pickFile()).thenAnswer(
      (_) async => PickedFile(
        path: null,
        name: 'radio.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );
    when(() => uploadDoc(
          'patient-1',
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
          mimeType: any(named: 'mimeType'),
          category: any(named: 'category'),
        )).thenAnswer((_) async => const Right('new-doc-id'));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('patient_documents_upload_button')));
    await tester.pumpAndSettle();

    // #4981 : choix de la catégorie en place, plus de bottom sheet.
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const Key('patient_documents_category_picker')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('upload_cat_radio')));
    await tester.pumpAndSettle();

    verify(() => uploadDoc(
          'patient-1',
          bytes: any(named: 'bytes', that: equals([1, 2, 3])),
          filename: 'radio.jpg',
          mimeType: 'image/jpeg',
          category: 'radio',
        )).called(1);
    expect(
      find.byKey(const Key('patient_documents_category_picker')),
      findsNothing,
    );
  });

  testWidgets('upload : annuler la sélection referme le choix sans uploader',
      (tester) async {
    when(() => listDocs('patient-1', category: null))
        .thenAnswer((_) async => const Right([]));
    when(() => filePicker.pickFile()).thenAnswer(
      (_) async => PickedFile(
        path: null,
        name: 'radio.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('patient_documents_upload_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('patient_documents_category_cancel')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('patient_documents_category_picker')),
      findsNothing,
    );
    verifyNever(() => uploadDoc(
          any(),
          bytes: any(named: 'bytes'),
          filename: any(named: 'filename'),
          mimeType: any(named: 'mimeType'),
          category: any(named: 'category'),
        ));
  });
}
