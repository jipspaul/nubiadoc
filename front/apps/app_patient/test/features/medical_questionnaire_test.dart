//! Tests widget : `MedicalQuestionnairePage` (#4109) — saisie, enregistrement
//! de brouillon (avec bascule 409→PATCH), soumission (avec bascule 404→POST).

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/medical_questionnaire/medical_questionnaire_page.dart';

class _MockCreate extends Mock implements CreateMedicalQuestionnaireUseCase {}

class _MockPatch extends Mock implements PatchMedicalQuestionnaireUseCase {}

class _MockGet extends Mock implements GetMedicalQuestionnaireUseCase {}

const _draft = MedicalQuestionnaire(
  id: 'q-1',
  cabinetId: 'cab-1',
  payload: {},
  status: 'draft',
);

const _submitted = MedicalQuestionnaire(
  id: 'q-1',
  cabinetId: 'cab-1',
  payload: {},
  status: 'submitted',
);

void main() {
  late _MockCreate create;
  late _MockPatch patch;
  late _MockGet get_;

  setUp(() {
    create = _MockCreate();
    patch = _MockPatch();
    get_ = _MockGet();
    when(() => get_(cabinetId: any(named: 'cabinetId')))
        .thenAnswer((_) async => const Right(null));
    GetIt.instance
        .registerFactory<CreateMedicalQuestionnaireUseCase>(() => create);
    GetIt.instance
        .registerFactory<PatchMedicalQuestionnaireUseCase>(() => patch);
    GetIt.instance.registerFactory<GetMedicalQuestionnaireUseCase>(() => get_);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildPage() {
    final router = GoRouter(
      initialLocation: '/q',
      routes: [
        GoRoute(
          path: '/q',
          builder: (_, __) =>
              const MedicalQuestionnairePage(cabinetId: 'cab-1'),
        ),
      ],
    );
    return MaterialApp.router(theme: NubiaTheme.light, routerConfig: router);
  }

  testWidgets('affiche les 4 champs du questionnaire', (tester) async {
    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('medical_questionnaire_antecedents')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('medical_questionnaire_allergies')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('medical_questionnaire_traitements')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('medical_questionnaire_ald')), findsOneWidget);
  });

  testWidgets('saisie + enregistrer brouillon → snackbar de confirmation',
      (tester) async {
    when(() => create(
            cabinetId: any(named: 'cabinetId'), payload: any(named: 'payload')))
        .thenAnswer((_) async => const Right(_draft));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('medical_questionnaire_allergies')),
      'Pénicilline',
    );
    final saveDraftButton =
        find.byKey(const Key('medical_questionnaire_save_draft_button'));
    await tester.ensureVisible(saveDraftButton);
    await tester.tap(saveDraftButton);
    await tester.pumpAndSettle();

    expect(find.text('Brouillon enregistré'), findsOneWidget);
    verify(() => create(
          cabinetId: 'cab-1',
          payload: any(
            named: 'payload',
            that: containsPair('allergies', 'Pénicilline'),
          ),
        )).called(1);
  });

  testWidgets(
      'enregistrer brouillon quand un brouillon existe déjà (409) → bascule sur PATCH',
      (tester) async {
    when(() => create(
        cabinetId: any(named: 'cabinetId'),
        payload: any(named: 'payload'))).thenAnswer(
      (_) async => const Left(
        ServerFailure(message: 'Un brouillon existe déjà.', statusCode: 409),
      ),
    );
    when(() => patch(
          cabinetId: any(named: 'cabinetId'),
          payload: any(named: 'payload'),
          submit: any(named: 'submit'),
        )).thenAnswer((_) async => const Right(_draft));

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final saveDraftButton =
        find.byKey(const Key('medical_questionnaire_save_draft_button'));
    await tester.ensureVisible(saveDraftButton);
    await tester.tap(saveDraftButton);
    await tester.pumpAndSettle();

    expect(find.text('Brouillon enregistré'), findsOneWidget);
    verify(() => patch(
          cabinetId: 'cab-1',
          payload: any(named: 'payload'),
          submit: false,
        )).called(1);
  });

  testWidgets(
      'envoyer au cabinet → PATCH submit:true réussit, la page se ferme',
      (tester) async {
    when(() => patch(
          cabinetId: any(named: 'cabinetId'),
          payload: any(named: 'payload'),
          submit: any(named: 'submit'),
        )).thenAnswer((_) async => const Right(_submitted));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open_questionnaire'),
                onPressed: () => context.push('/q'),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/q',
          builder: (_, __) =>
              const MedicalQuestionnairePage(cabinetId: 'cab-1'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_questionnaire')));
    await tester.pumpAndSettle();

    final submitButton =
        find.byKey(const Key('medical_questionnaire_submit_button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Ouvrir'), findsOneWidget);
    verify(() => patch(
          cabinetId: 'cab-1',
          payload: any(named: 'payload'),
          submit: true,
        )).called(1);
  });

  testWidgets(
      'envoyer au cabinet sans brouillon existant (404) → bascule sur create puis PATCH submit',
      (tester) async {
    when(() => patch(
          cabinetId: any(named: 'cabinetId'),
          payload: any(named: 'payload'),
          submit: true,
        )).thenAnswer((_) async => const Left(NotFoundFailure()));
    when(() => create(
            cabinetId: any(named: 'cabinetId'), payload: any(named: 'payload')))
        .thenAnswer((_) async => const Right(_draft));
    when(() => patch(
          cabinetId: any(named: 'cabinetId'),
          payload: null,
          submit: true,
        )).thenAnswer((_) async => const Right(_submitted));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('open_questionnaire'),
                onPressed: () => context.push('/q'),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/q',
          builder: (_, __) =>
              const MedicalQuestionnairePage(cabinetId: 'cab-1'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: NubiaTheme.light, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_questionnaire')));
    await tester.pumpAndSettle();

    final submitButton =
        find.byKey(const Key('medical_questionnaire_submit_button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Ouvrir'), findsOneWidget);
    verify(() => create(cabinetId: 'cab-1', payload: any(named: 'payload')))
        .called(1);
  });

  testWidgets('erreur serveur non 409/404 → bannière d\'erreur affichée',
      (tester) async {
    when(() => create(
        cabinetId: any(named: 'cabinetId'),
        payload: any(named: 'payload'))).thenAnswer(
      (_) async => const Left(
        ServerFailure(message: 'Erreur serveur.', statusCode: 500),
      ),
    );

    await tester.pumpWidget(buildPage());
    await tester.pumpAndSettle();

    final saveDraftButton =
        find.byKey(const Key('medical_questionnaire_save_draft_button'));
    await tester.ensureVisible(saveDraftButton);
    await tester.tap(saveDraftButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('medical_questionnaire_error_banner')),
      findsOneWidget,
    );
    expect(find.text('Erreur serveur.'), findsOneWidget);
  });
}
