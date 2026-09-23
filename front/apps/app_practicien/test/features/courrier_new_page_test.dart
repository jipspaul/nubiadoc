import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/courriers/courrier_new_page.dart';
import 'package:app_practicien/features/courriers/letter_compose_cubit.dart';
import 'package:app_practicien/features/courriers/letter_compose_state.dart';

class MockLetterComposeCubit extends MockCubit<LetterComposeState>
    implements LetterComposeCubit {}

class MockFilePickerService extends Mock implements FilePickerService {}

const template = LetterTemplate(
  id: 'tmpl1',
  name: 'Convocation',
  kind: 'convocation',
  bodyTemplate: 'Bonjour {{patient.prenom}}, contactez {{correspondant.nom}}.',
  placeholders: ['patient.prenom', 'correspondant.nom'],
);

CabinetPatient patient() => CabinetPatient(
      id: 'pat1',
      cabinetId: 'cab1',
      firstName: 'Léa',
      lastName: 'Dupont',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockLetterComposeCubit cubit;
  late MockFilePickerService filePicker;

  setUpAll(() {
    registerFallbackValue(<String, String>{});
  });

  setUp(() {
    cubit = MockLetterComposeCubit();
    filePicker = MockFilePickerService();
    GetIt.instance.registerFactory<FilePickerService>(() => filePicker);
    addTearDown(GetIt.instance.reset);
    when(() => cubit.load(any())).thenAnswer((_) async {});
    when(() => cubit.generate(any(),
        templateId: any(named: 'templateId'),
        overrides: any(named: 'overrides'))).thenAnswer((_) async {});
  });

  Future<void> pump(WidgetTester tester) => tester.pumpApp(
        BlocProvider<LetterComposeCubit>.value(
          value: cubit,
          child: const Scaffold(body: CourrierComposeBody(patientId: 'pat1')),
        ),
      );

  group('CourrierComposeBody', () {
    testWidgets('affiche un indicateur de chargement', (tester) async {
      when(() => cubit.state).thenReturn(const LetterComposeLoading());

      await pump(tester);

      expect(find.byKey(const Key('courrier_loading')), findsOneWidget);
    });

    testWidgets('erreur de chargement → widget d\'erreur avec relance',
        (tester) async {
      when(() => cubit.state)
          .thenReturn(const LetterComposeError('Erreur serveur.'));

      await pump(tester);

      expect(find.byKey(const Key('courrier_error')), findsOneWidget);
      expect(find.text('Erreur serveur.'), findsOneWidget);
    });

    testWidgets('aucun modèle → état vide', (tester) async {
      when(() => cubit.state).thenReturn(
          LetterComposeReady(templates: const [], patient: patient()));

      await pump(tester);

      expect(find.byKey(const Key('courrier_templates_empty')), findsOneWidget);
    });

    testWidgets('choix du modèle → champs libres + aperçu + génération',
        (tester) async {
      when(() => cubit.state).thenReturn(
          LetterComposeReady(templates: const [template], patient: patient()));

      await pump(tester);

      expect(find.byKey(const Key('courrier_field_correspondant.nom')),
          findsNothing);

      await tester.tap(find.byKey(const Key('courrier_template_tmpl1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('courrier_field_correspondant.nom')),
          findsOneWidget);
      expect(find.byKey(const Key('letter_preview_body')), findsOneWidget);
      expect(find.textContaining('[correspondant.nom]'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('courrier_field_correspondant.nom')),
        'Dr Martin',
      );
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('letter_preview_body')),
          matching: find.textContaining('Dr Martin'),
        ),
        findsOneWidget,
      );

      await tester
          .ensureVisible(find.byKey(const Key('submit_courrier_button')));
      await tester.tap(find.byKey(const Key('submit_courrier_button')));
      await tester.pumpAndSettle();

      verify(() => cubit.generate('pat1',
          templateId: 'tmpl1',
          overrides: {'correspondant.nom': 'Dr Martin'})).called(1);
    });

    testWidgets('courrier généré → confirmation', (tester) async {
      when(() => cubit.state).thenReturn(const LetterComposeGenerated(
        GeneratedLetter(
          documentId: 'doc1',
          filename: 'courrier-convocation-doc1.pdf',
          sizeBytes: 42,
          body: 'Bonjour Léa.',
        ),
      ));

      await pump(tester);

      expect(find.byKey(const Key('courrier_generated_confirmation')),
          findsOneWidget);
      expect(
          find.textContaining('courrier-convocation-doc1.pdf'), findsOneWidget);
    });

    testWidgets(
        'import docx réussi → sélectionne le modèle et affiche les placeholders',
        (tester) async {
      when(() => cubit.state).thenReturn(
          LetterComposeReady(templates: const [], patient: patient()));
      when(() => filePicker.pickFile(
              allowedExtensions: any(named: 'allowedExtensions')))
          .thenAnswer((_) async => PickedFile(
                path: null,
                name: 'relance.docx',
                mimeType: 'application/vnd.openxmlformats-officedocument'
                    '.wordprocessingml.document',
                bytes: Uint8List.fromList([1, 2, 3]),
              ));
      when(() => cubit.importTemplate(
            name: any(named: 'name'),
            kind: any(named: 'kind'),
            bytes: any(named: 'bytes'),
            filename: any(named: 'filename'),
          )).thenAnswer((_) async => const Right(LetterTemplateImportResult(
            templateId: 'tmpl2',
            placeholders: ['patient.nom'],
          )));

      await pump(tester);

      await tester.tap(find.byKey(const Key('import_letter_template_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('import_letter_template_name')),
        'Relance impayé',
      );
      await tester
          .tap(find.byKey(const Key('import_letter_template_pick_file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_letter_template_confirm')));
      await tester.pumpAndSettle();

      verify(() => cubit.importTemplate(
            name: 'Relance impayé',
            kind: 'autre',
            bytes: any(named: 'bytes', that: equals([1, 2, 3])),
            filename: 'relance.docx',
          )).called(1);
      expect(
          find.byKey(const Key('import_letter_template_dialog')), findsNothing);
      expect(
          find.byKey(const Key('courrier_field_patient.nom')), findsOneWidget);
      expect(find.textContaining('1 placeholder(s) détecté'), findsOneWidget);
    });

    testWidgets('import docx en échec → message d\'erreur, dialog conservé',
        (tester) async {
      when(() => cubit.state).thenReturn(
          LetterComposeReady(templates: const [], patient: patient()));
      when(() => filePicker.pickFile(
              allowedExtensions: any(named: 'allowedExtensions')))
          .thenAnswer((_) async => PickedFile(
                path: null,
                name: 'relance.docx',
                mimeType: 'application/vnd.openxmlformats-officedocument'
                    '.wordprocessingml.document',
                bytes: Uint8List.fromList([1, 2, 3]),
              ));
      when(() => cubit.importTemplate(
            name: any(named: 'name'),
            kind: any(named: 'kind'),
            bytes: any(named: 'bytes'),
            filename: any(named: 'filename'),
          )).thenAnswer((_) async => const Left(ValidationFailure(
            message: 'Placeholder(s) inconnu(s) : foo.bar',
            fieldErrors: {'foo.bar': 'Placeholder(s) inconnu(s)'},
          )));

      await pump(tester);

      await tester.tap(find.byKey(const Key('import_letter_template_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('import_letter_template_name')),
        'Relance impayé',
      );
      await tester
          .tap(find.byKey(const Key('import_letter_template_pick_file')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('import_letter_template_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import_letter_template_dialog')),
          findsOneWidget);
      expect(find.textContaining('Placeholder(s) inconnu(s) : foo.bar'),
          findsOneWidget);
    });
  });
}
