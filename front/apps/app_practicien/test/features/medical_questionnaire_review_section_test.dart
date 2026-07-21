//! Tests widget : `MedicalQuestionnaireReviewSection` (#4110) — état vide,
//! soumission en attente, validation + import avec confirmation.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/medical_questionnaire_review_section.dart';

class _MockGet extends Mock implements GetCabinetMedicalQuestionnaireUseCase {}

class _MockReview extends Mock implements ReviewMedicalQuestionnaireUseCase {}

const _pending = MedicalQuestionnaire(
  id: 'q-1',
  cabinetId: 'cab-1',
  payload: {
    'antecedents': 'Diabète type 2',
    'allergies': 'Pénicilline',
    'traitements_en_cours': 'Metformine',
    'ald': true,
  },
  status: 'submitted',
);

void main() {
  late _MockGet get;
  late _MockReview review;

  setUp(() {
    get = _MockGet();
    review = _MockReview();
    GetIt.instance
        .registerFactory<GetCabinetMedicalQuestionnaireUseCase>(() => get);
    GetIt.instance
        .registerFactory<ReviewMedicalQuestionnaireUseCase>(() => review);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const MedicalQuestionnaireReviewSection(patientId: 'pat-1'),
        ),
      );

  testWidgets('aucune soumission en attente — message vide', (tester) async {
    when(() => get('pat-1')).thenAnswer((_) async => const Right(null));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('medical_questionnaire_review_empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('medical_questionnaire_review_button')),
      findsNothing,
    );
  });

  testWidgets('soumission déjà reviewed — traitée comme aucune en attente',
      (tester) async {
    when(() => get('pat-1')).thenAnswer(
      (_) async => const Right(
        MedicalQuestionnaire(
          id: 'q-1',
          cabinetId: 'cab-1',
          payload: {},
          status: 'reviewed',
        ),
      ),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('medical_questionnaire_review_empty')),
      findsOneWidget,
    );
  });

  testWidgets('soumission en attente — affiche l\'aperçu et le bouton',
      (tester) async {
    when(() => get('pat-1')).thenAnswer((_) async => const Right(_pending));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('medical_questionnaire_review_pending')),
      findsOneWidget,
    );
    expect(find.textContaining('Diabète type 2'), findsOneWidget);
    expect(
      find.byKey(const Key('medical_questionnaire_review_button')),
      findsOneWidget,
    );
  });

  testWidgets('valider et importer — annuler ne déclenche pas la review',
      (tester) async {
    when(() => get('pat-1')).thenAnswer((_) async => const Right(_pending));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('medical_questionnaire_review_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('questionnaire_review_dialog_cancel')),
    );
    await tester.pumpAndSettle();

    verifyNever(() => review('pat-1'));
  });

  testWidgets(
      'valider et importer — confirmer appelle review puis recharge la section',
      (tester) async {
    when(() => get('pat-1')).thenAnswer((_) async => const Right(_pending));
    when(() => review('pat-1')).thenAnswer(
      (_) async => Right(
        MedicalQuestionnaire(
          id: _pending.id,
          cabinetId: _pending.cabinetId,
          payload: _pending.payload,
          status: 'reviewed',
        ),
      ),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('medical_questionnaire_review_button')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('questionnaire_review_dialog_confirm')),
    );
    await tester.pumpAndSettle();

    verify(() => review('pat-1')).called(1);
    expect(
      find.text('Questionnaire importé au dossier médical.'),
      findsOneWidget,
    );
    // La section recharge après import : get() est rappelé (état à jour).
    verify(() => get('pat-1')).called(2);
  });
}
