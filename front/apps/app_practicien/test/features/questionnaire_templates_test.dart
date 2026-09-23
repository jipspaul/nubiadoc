//! Tests : `QuestionnaireTemplatesBloc`/`QuestionnaireTemplatesPage` (#7158)
//! — chargement catalogue + modèle du cabinet (au plus un), création/édition
//! (recharge la liste), éditeur de questions + aperçu en direct.

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/questionnaire_templates/questionnaire_templates_bloc.dart';
import 'package:app_practicien/features/questionnaire_templates/questionnaire_templates_event.dart';
import 'package:app_practicien/features/questionnaire_templates/questionnaire_templates_page.dart';
import 'package:app_practicien/features/questionnaire_templates/questionnaire_templates_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListQuestionnaireTemplatesUseCase extends Mock
    implements ListQuestionnaireTemplatesUseCase {}

class MockCreateQuestionnaireTemplateUseCase extends Mock
    implements CreateQuestionnaireTemplateUseCase {}

class MockPatchQuestionnaireTemplateUseCase extends Mock
    implements PatchQuestionnaireTemplateUseCase {}

class MockQuestionnaireTemplatesBloc
    extends MockBloc<QuestionnaireTemplatesEvent, QuestionnaireTemplatesState>
    implements QuestionnaireTemplatesBloc {}

final _catalogueTemplate = QuestionnaireTemplate(
  id: 'tpl-global',
  title: 'Questionnaire médical standard',
  version: 1,
  isGlobal: true,
  createdAt: DateTime(2026, 1, 1),
  schema: const [
    QuestionnaireQuestion(
      key: 'allergies',
      type: QuestionnaireQuestionType.text,
      label: 'Allergies',
    ),
  ],
);

final _cabinetTemplate = QuestionnaireTemplate(
  id: 'tpl-cabinet',
  title: 'Questionnaire du cabinet',
  version: 1,
  isGlobal: false,
  createdAt: DateTime(2026, 2, 1),
  schema: const [
    QuestionnaireQuestion(
      key: 'diabete',
      type: QuestionnaireQuestionType.boolean,
      label: 'Diabète ?',
    ),
  ],
);

void main() {
  group('QuestionnaireTemplatesBloc', () {
    blocTest<QuestionnaireTemplatesBloc, QuestionnaireTemplatesState>(
      'QuestionnaireTemplatesLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final listTemplates = MockListQuestionnaireTemplatesUseCase();
        when(() => listTemplates())
            .thenAnswer((_) async => Right([_catalogueTemplate]));
        return QuestionnaireTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: MockCreateQuestionnaireTemplateUseCase(),
          patchTemplate: MockPatchQuestionnaireTemplateUseCase(),
        );
      },
      act: (bloc) => bloc.add(const QuestionnaireTemplatesLoadRequested()),
      expect: () => [
        const QuestionnaireTemplatesLoading(),
        QuestionnaireTemplatesLoaded(templates: [_catalogueTemplate]),
      ],
    );

    blocTest<QuestionnaireTemplatesBloc, QuestionnaireTemplatesState>(
      'QuestionnaireTemplatesLoadRequested en échec émet Loading puis Error',
      build: () {
        final listTemplates = MockListQuestionnaireTemplatesUseCase();
        when(() => listTemplates())
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        return QuestionnaireTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: MockCreateQuestionnaireTemplateUseCase(),
          patchTemplate: MockPatchQuestionnaireTemplateUseCase(),
        );
      },
      act: (bloc) => bloc.add(const QuestionnaireTemplatesLoadRequested()),
      expect: () => [
        const QuestionnaireTemplatesLoading(),
        const QuestionnaireTemplatesError('Erreur réseau'),
      ],
    );

    blocTest<QuestionnaireTemplatesBloc, QuestionnaireTemplatesState>(
      'QuestionnaireTemplatesCreateRequested réussi recharge la liste',
      build: () {
        final listTemplates = MockListQuestionnaireTemplatesUseCase();
        final createTemplate = MockCreateQuestionnaireTemplateUseCase();
        var callCount = 0;
        when(() => listTemplates()).thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? Right([_catalogueTemplate])
              : Right([_catalogueTemplate, _cabinetTemplate]);
        });
        when(() => createTemplate(
              title: 'Questionnaire du cabinet',
              schema: _cabinetTemplate.schema,
            )).thenAnswer((_) async => const Right((id: 'tpl-cabinet', version: 1)));
        return QuestionnaireTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: createTemplate,
          patchTemplate: MockPatchQuestionnaireTemplateUseCase(),
        );
      },
      act: (bloc) async {
        bloc.add(const QuestionnaireTemplatesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(QuestionnaireTemplatesCreateRequested(
          title: 'Questionnaire du cabinet',
          schema: _cabinetTemplate.schema,
        ));
      },
      expect: () => [
        const QuestionnaireTemplatesLoading(),
        QuestionnaireTemplatesLoaded(templates: [_catalogueTemplate]),
        QuestionnaireTemplatesLoaded(
          templates: [_catalogueTemplate],
          actionInProgress: true,
        ),
        const QuestionnaireTemplatesLoading(),
        QuestionnaireTemplatesLoaded(
          templates: [_catalogueTemplate, _cabinetTemplate],
        ),
      ],
    );

    blocTest<QuestionnaireTemplatesBloc, QuestionnaireTemplatesState>(
      'QuestionnaireTemplatesUpdateRequested en échec expose actionError',
      build: () {
        final listTemplates = MockListQuestionnaireTemplatesUseCase();
        final patchTemplate = MockPatchQuestionnaireTemplateUseCase();
        when(() => listTemplates())
            .thenAnswer((_) async => Right([_cabinetTemplate]));
        when(() => patchTemplate(
              'tpl-cabinet',
              title: 'Titre modifié',
              schema: _cabinetTemplate.schema,
            )).thenAnswer(
                (_) async => const Left(_FakeFailure('Modification refusée')));
        return QuestionnaireTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: MockCreateQuestionnaireTemplateUseCase(),
          patchTemplate: patchTemplate,
        );
      },
      act: (bloc) async {
        bloc.add(const QuestionnaireTemplatesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(QuestionnaireTemplatesUpdateRequested(
          id: 'tpl-cabinet',
          title: 'Titre modifié',
          schema: _cabinetTemplate.schema,
        ));
      },
      expect: () => [
        const QuestionnaireTemplatesLoading(),
        QuestionnaireTemplatesLoaded(templates: [_cabinetTemplate]),
        QuestionnaireTemplatesLoaded(
          templates: [_cabinetTemplate],
          actionInProgress: true,
        ),
        QuestionnaireTemplatesLoaded(
          templates: [_cabinetTemplate],
          actionError: 'Modification refusée',
        ),
      ],
    );
  });

  group('QuestionnaireTemplatesPage (widget)', () {
    testWidgets('affiche le squelette pendant le chargement', (tester) async {
      final bloc = MockQuestionnaireTemplatesBloc();
      when(() => bloc.state).thenReturn(const QuestionnaireTemplatesLoading());
      await tester.pumpApp(
        BlocProvider<QuestionnaireTemplatesBloc>.value(
          value: bloc,
          child: const QuestionnaireTemplatesPage(),
        ),
      );

      expect(find.byKey(const Key('questionnaire_templates_loading')),
          findsOneWidget);
    });

    testWidgets('affiche l\'erreur avec retry', (tester) async {
      final bloc = MockQuestionnaireTemplatesBloc();
      when(() => bloc.state).thenReturn(const QuestionnaireTemplatesError('Boom'));
      await tester.pumpApp(
        BlocProvider<QuestionnaireTemplatesBloc>.value(
          value: bloc,
          child: const QuestionnaireTemplatesPage(),
        ),
      );

      expect(
          find.byKey(const Key('questionnaire_templates_error')), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      // 2 appels : le chargement initial (`initState`) + le retry.
      verify(() => bloc.add(const QuestionnaireTemplatesLoadRequested()))
          .called(2);
    });

    testWidgets(
        'affiche le catalogue en lecture seule et propose de créer si le '
        'cabinet n\'a pas encore de modèle', (tester) async {
      final bloc = MockQuestionnaireTemplatesBloc();
      when(() => bloc.state).thenReturn(
        QuestionnaireTemplatesLoaded(templates: [_catalogueTemplate]),
      );
      await tester.pumpApp(
        BlocProvider<QuestionnaireTemplatesBloc>.value(
          value: bloc,
          child: const QuestionnaireTemplatesPage(),
        ),
      );

      expect(find.byKey(const Key('questionnaire_template_tpl-global')),
          findsOneWidget);
      expect(
          find.byKey(const Key('questionnaire_templates_create_button')),
          findsOneWidget);
      expect(find.byKey(const Key('questionnaire_templates_cabinet_empty')),
          findsOneWidget);
    });

    testWidgets(
        'affiche le modèle du cabinet éditable quand il existe déjà',
        (tester) async {
      final bloc = MockQuestionnaireTemplatesBloc();
      when(() => bloc.state).thenReturn(
        QuestionnaireTemplatesLoaded(
          templates: [_catalogueTemplate, _cabinetTemplate],
        ),
      );
      await tester.pumpApp(
        BlocProvider<QuestionnaireTemplatesBloc>.value(
          value: bloc,
          child: const QuestionnaireTemplatesPage(),
        ),
      );

      expect(find.byKey(const Key('questionnaire_template_tpl-cabinet')),
          findsOneWidget);
      expect(
          find.byKey(const Key('questionnaire_template_edit_tpl-cabinet')),
          findsOneWidget);
      // Catalogue global : pas de bouton « Modifier ».
      expect(
          find.byKey(const Key('questionnaire_template_edit_tpl-global')),
          findsNothing);
      // Un modèle du cabinet existe déjà : pas de bouton « Créer ».
      expect(
          find.byKey(const Key('questionnaire_templates_create_button')),
          findsNothing);
    });

    testWidgets(
        'créer un modèle : ajouter une question puis enregistrer dispatch '
        'QuestionnaireTemplatesCreateRequested puis ferme l\'éditeur '
        'seulement une fois le succès connu (#7507)', (tester) async {
      final bloc = MockQuestionnaireTemplatesBloc();
      const initial = QuestionnaireTemplatesLoaded(templates: []);
      final controller = StreamController<QuestionnaireTemplatesState>.broadcast();
      addTearDown(controller.close);
      when(() => bloc.state).thenReturn(initial);
      whenListen(bloc, controller.stream, initialState: initial);
      await tester.pumpApp(
        BlocProvider<QuestionnaireTemplatesBloc>.value(
          value: bloc,
          child: const QuestionnaireTemplatesPage(),
        ),
      );

      await tester
          .tap(find.byKey(const Key('questionnaire_templates_create_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('questionnaire_template_editor_title')),
        'Mon questionnaire',
      );

      // Bouton désactivé tant qu'aucune question n'est ajoutée.
      expect(
        tester
            .widget<TextButton>(
                find.byKey(const Key('questionnaire_template_editor_save')))
            .onPressed,
        isNull,
      );

      await tester.tap(
          find.byKey(const Key('questionnaire_template_editor_add_question')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('question_editor_key_0')),
        'antecedents',
      );
      await tester.enterText(
        find.byKey(const Key('question_editor_label_0')),
        'Antécédents médicaux',
      );
      await tester.pumpAndSettle();

      final saveButton =
          find.byKey(const Key('questionnaire_template_editor_save'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();

      verify(() => bloc.add(const QuestionnaireTemplatesCreateRequested(
            title: 'Mon questionnaire',
            schema: [
              QuestionnaireQuestion(
                key: 'antecedents',
                type: QuestionnaireQuestionType.text,
                label: 'Antécédents médicaux',
              ),
            ],
          ))).called(1);

      // Tant que la requête est en cours, l'éditeur reste ouvert.
      controller.add(initial.copyWith(
        actionInProgress: true,
        clearActionError: true,
      ));
      await tester.pump();
      expect(
        find.byKey(const Key('questionnaire_template_editor_scaffold')),
        findsOneWidget,
      );

      controller.add(QuestionnaireTemplatesLoaded(templates: [_cabinetTemplate]));
      await tester.pumpAndSettle();

      // L'éditeur ne se ferme qu'une fois le succès connu (#7507).
      expect(
        find.byKey(const Key('questionnaire_template_editor_scaffold')),
        findsNothing,
      );
    });

    testWidgets(
        'créer un modèle : un échec laisse l\'éditeur ouvert avec la '
        'saisie intacte et affiche l\'erreur (#7507)', (tester) async {
      final bloc = MockQuestionnaireTemplatesBloc();
      const initial = QuestionnaireTemplatesLoaded(templates: []);
      final controller = StreamController<QuestionnaireTemplatesState>.broadcast();
      addTearDown(controller.close);
      when(() => bloc.state).thenReturn(initial);
      whenListen(bloc, controller.stream, initialState: initial);
      await tester.pumpApp(
        BlocProvider<QuestionnaireTemplatesBloc>.value(
          value: bloc,
          child: const QuestionnaireTemplatesPage(),
        ),
      );

      await tester
          .tap(find.byKey(const Key('questionnaire_templates_create_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('questionnaire_template_editor_title')),
        'Mon questionnaire',
      );
      await tester.tap(
          find.byKey(const Key('questionnaire_template_editor_add_question')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('question_editor_key_0')),
        'antecedents',
      );
      await tester.enterText(
        find.byKey(const Key('question_editor_label_0')),
        'Antécédents médicaux',
      );
      await tester.pumpAndSettle();

      final saveButton =
          find.byKey(const Key('questionnaire_template_editor_save'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();

      controller.add(initial.copyWith(
        actionInProgress: true,
        clearActionError: true,
      ));
      await tester.pump();
      controller.add(initial.copyWith(
        actionInProgress: false,
        actionError: 'Impossible de créer le modèle de questionnaire.',
      ));
      await tester.pumpAndSettle();

      // L'éditeur reste ouvert, la saisie n'a pas disparu.
      expect(
        find.byKey(const Key('questionnaire_template_editor_scaffold')),
        findsOneWidget,
      );
      expect(find.text('Mon questionnaire'), findsOneWidget);
      expect(
        find.byKey(const Key('questionnaire_template_editor_error_snackbar')),
        findsOneWidget,
      );
    });
  });
}
