import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/courriers/letter_compose_cubit.dart';
import 'package:app_practicien/features/courriers/letter_compose_state.dart';

class MockLetterTemplatesRepository extends Mock
    implements LetterTemplatesRepository {}

class MockCabinetPatientsRepository extends Mock
    implements CabinetPatientsRepository {}

class MockLettersRepository extends Mock implements LettersRepository {}

const template = LetterTemplate(
  id: 'tmpl1',
  name: 'Convocation',
  kind: 'convocation',
  bodyTemplate: 'Bonjour {{patient.prenom}}, RDV le {{rdv.date}}.',
  placeholders: ['patient.prenom', 'rdv.date'],
);

CabinetPatient patient() => CabinetPatient(
      id: 'pat1',
      cabinetId: 'cab1',
      firstName: 'Léa',
      lastName: 'Dupont',
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late MockLetterTemplatesRepository templates;
  late MockCabinetPatientsRepository patients;
  late MockLettersRepository letters;

  setUp(() {
    templates = MockLetterTemplatesRepository();
    patients = MockCabinetPatientsRepository();
    letters = MockLettersRepository();
    registerFallbackValue(<String, String>{});
  });

  LetterComposeCubit buildCubit() => LetterComposeCubit(
        listTemplates: ListLetterTemplatesUseCase(templates),
        getPatient: GetCabinetPatientUseCase(patients),
        generateLetter: GenerateLetterUseCase(letters),
        importTemplate: ImportLetterTemplateUseCase(templates),
      );

  group('LetterComposeCubit', () {
    blocTest<LetterComposeCubit, LetterComposeState>(
      'charge les modèles et le patient',
      build: () {
        when(() => templates.list())
            .thenAnswer((_) async => const Right([template]));
        when(() => patients.getById('pat1'))
            .thenAnswer((_) async => Right(patient()));
        return buildCubit();
      },
      act: (cubit) => cubit.load('pat1'),
      expect: () => [
        const LetterComposeLoading(),
        LetterComposeReady(templates: const [template], patient: patient()),
      ],
    );

    blocTest<LetterComposeCubit, LetterComposeState>(
      'échec du chargement des modèles → erreur bloquante',
      build: () {
        when(() => templates.list()).thenAnswer(
            (_) async => const Left(ServerFailure(message: 'Erreur serveur.')));
        return buildCubit();
      },
      act: (cubit) => cubit.load('pat1'),
      expect: () => [
        const LetterComposeLoading(),
        const LetterComposeError('Erreur serveur.'),
      ],
      verify: (_) => verifyNever(() => patients.getById(any())),
    );

    blocTest<LetterComposeCubit, LetterComposeState>(
      'échec du chargement du patient → reste utilisable (patient null)',
      build: () {
        when(() => templates.list())
            .thenAnswer((_) async => const Right([template]));
        when(() => patients.getById('pat1')).thenAnswer(
            (_) async => const Left(NotFoundFailure('Patient introuvable.')));
        return buildCubit();
      },
      act: (cubit) => cubit.load('pat1'),
      expect: () => [
        const LetterComposeLoading(),
        const LetterComposeReady(templates: [template]),
      ],
    );

    blocTest<LetterComposeCubit, LetterComposeState>(
      'génère le courrier avec les champs libres saisis',
      build: () {
        when(() => letters.generate('pat1',
                templateId: 'tmpl1', overrides: {'rdv.date': '12/10/2026'}))
            .thenAnswer((_) async => const Right(GeneratedLetter(
                  documentId: 'doc1',
                  filename: 'courrier-convocation-doc1.pdf',
                  sizeBytes: 1234,
                  body: 'Bonjour Léa, RDV le 12/10/2026.',
                )));
        return buildCubit();
      },
      seed: () =>
          LetterComposeReady(templates: const [template], patient: patient()),
      act: (cubit) => cubit.generate('pat1',
          templateId: 'tmpl1', overrides: {'rdv.date': '12/10/2026'}),
      expect: () => [
        LetterComposeReady(
            templates: const [template], patient: patient(), submitting: true),
        isA<LetterComposeGenerated>(),
      ],
      verify: (_) => verify(() => letters.generate('pat1',
          templateId: 'tmpl1',
          overrides: {'rdv.date': '12/10/2026'})).called(1),
    );

    blocTest<LetterComposeCubit, LetterComposeState>(
      'importe un modèle docx et recharge la liste des modèles',
      build: () {
        when(() => templates.importDocx(
              name: any(named: 'name'),
              kind: any(named: 'kind'),
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
            )).thenAnswer((_) async => const Right(LetterTemplateImportResult(
              templateId: 'tmpl2',
              placeholders: ['patient.nom'],
            )));
        when(() => templates.list()).thenAnswer((_) async => const Right([
              template,
              LetterTemplate(
                id: 'tmpl2',
                name: 'Relance',
                kind: 'relance',
                placeholders: ['patient.nom'],
                sourceFormat: 'docx',
              ),
            ]));
        return buildCubit();
      },
      seed: () =>
          LetterComposeReady(templates: const [template], patient: patient()),
      act: (cubit) => cubit.importTemplate(
        name: 'Relance',
        kind: 'relance',
        bytes: const [1, 2, 3],
        filename: 'modele.docx',
      ),
      expect: () => [
        isA<LetterComposeReady>()
            .having((s) => s.templates.length, 'templates.length', 2),
      ],
      verify: (_) => verify(() => templates.list()).called(1),
    );

    blocTest<LetterComposeCubit, LetterComposeState>(
      "échec de l'import docx (placeholder inconnu) → liste inchangée",
      build: () {
        when(() => templates.importDocx(
              name: any(named: 'name'),
              kind: any(named: 'kind'),
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
            )).thenAnswer((_) async => const Left(ValidationFailure(
              message: 'Placeholder(s) inconnu(s) : foo.bar',
              fieldErrors: {'foo.bar': 'Placeholder(s) inconnu(s)'},
            )));
        return buildCubit();
      },
      seed: () =>
          LetterComposeReady(templates: const [template], patient: patient()),
      act: (cubit) => cubit.importTemplate(
        name: 'Relance',
        kind: 'relance',
        bytes: const [1, 2, 3],
        filename: 'modele.docx',
      ),
      expect: () => [],
      verify: (_) => verifyNever(() => templates.list()),
    );

    blocTest<LetterComposeCubit, LetterComposeState>(
      'échec de génération (placeholder manquant) → erreur, formulaire conservé',
      build: () {
        when(() => letters.generate(any(),
                templateId: any(named: 'templateId'),
                overrides: any(named: 'overrides')))
            .thenAnswer((_) async => const Left(ValidationFailure(
                  message: 'Champ(s) requis : rdv.date',
                  fieldErrors: {'rdv.date': 'Champ(s) requis'},
                )));
        return buildCubit();
      },
      seed: () =>
          LetterComposeReady(templates: const [template], patient: patient()),
      act: (cubit) =>
          cubit.generate('pat1', templateId: 'tmpl1', overrides: const {}),
      expect: () => [
        LetterComposeReady(
            templates: const [template], patient: patient(), submitting: true),
        LetterComposeReady(
          templates: const [template],
          patient: patient(),
          error: 'Champ(s) requis : rdv.date',
        ),
      ],
    );
  });
}
