//! Tests : `ConsentTemplatesBloc`/`ConsentTemplatesPage` (#7198, DP-F6.c) —
//! chargement catalogue + cabinet, création/édition d'un modèle du cabinet
//! (recharge la liste), rendu de l'écran (squelette/erreur/liste).

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/consent_templates/consent_templates_bloc.dart';
import 'package:app_practicien/features/consent_templates/consent_templates_event.dart';
import 'package:app_practicien/features/consent_templates/consent_templates_page.dart';
import 'package:app_practicien/features/consent_templates/consent_templates_state.dart';

class _FakeFailure extends Failure {
  const _FakeFailure(super.message);
}

class MockListConsentTemplatesUseCase extends Mock
    implements ListConsentTemplatesUseCase {}

class MockCreateConsentTemplateUseCase extends Mock
    implements CreateConsentTemplateUseCase {}

class MockPatchConsentTemplateUseCase extends Mock
    implements PatchConsentTemplateUseCase {}

class MockConsentTemplatesBloc
    extends MockBloc<ConsentTemplatesEvent, ConsentTemplatesState>
    implements ConsentTemplatesBloc {}

final _catalogueTemplate = ConsentTemplate(
  id: 'tpl-global',
  actCategory: 'implantologie',
  title: 'Consentement implant (catalogue)',
  bodyMarkdown: 'Texte standard implantologie.',
  version: 1,
  isGlobal: true,
  createdAt: DateTime(2026, 1, 1),
);

final _cabinetTemplate = ConsentTemplate(
  id: 'tpl-cabinet',
  actCategory: 'endodontie',
  title: 'Consentement endo (cabinet)',
  bodyMarkdown: 'Texte propre au cabinet.',
  version: 1,
  isGlobal: false,
  createdAt: DateTime(2026, 2, 1),
);

void main() {
  group('ConsentTemplatesBloc', () {
    blocTest<ConsentTemplatesBloc, ConsentTemplatesState>(
      'ConsentTemplatesLoadRequested réussi émet Loading puis Loaded',
      build: () {
        final listTemplates = MockListConsentTemplatesUseCase();
        when(() => listTemplates())
            .thenAnswer((_) async => Right([_catalogueTemplate]));
        return ConsentTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: MockCreateConsentTemplateUseCase(),
          patchTemplate: MockPatchConsentTemplateUseCase(),
        );
      },
      act: (bloc) => bloc.add(const ConsentTemplatesLoadRequested()),
      expect: () => [
        const ConsentTemplatesLoading(),
        ConsentTemplatesLoaded(templates: [_catalogueTemplate]),
      ],
    );

    blocTest<ConsentTemplatesBloc, ConsentTemplatesState>(
      'ConsentTemplatesLoadRequested en échec émet Loading puis Error',
      build: () {
        final listTemplates = MockListConsentTemplatesUseCase();
        when(() => listTemplates())
            .thenAnswer((_) async => const Left(_FakeFailure('Erreur réseau')));
        return ConsentTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: MockCreateConsentTemplateUseCase(),
          patchTemplate: MockPatchConsentTemplateUseCase(),
        );
      },
      act: (bloc) => bloc.add(const ConsentTemplatesLoadRequested()),
      expect: () => [
        const ConsentTemplatesLoading(),
        const ConsentTemplatesError('Erreur réseau'),
      ],
    );

    blocTest<ConsentTemplatesBloc, ConsentTemplatesState>(
      'ConsentTemplatesCreateRequested réussi recharge la liste',
      build: () {
        final listTemplates = MockListConsentTemplatesUseCase();
        final createTemplate = MockCreateConsentTemplateUseCase();
        var callCount = 0;
        when(() => listTemplates()).thenAnswer((_) async {
          callCount++;
          return callCount == 1
              ? Right([_catalogueTemplate])
              : Right([_catalogueTemplate, _cabinetTemplate]);
        });
        when(() => createTemplate(
              actCategory: 'endodontie',
              title: 'Consentement endo (cabinet)',
              bodyMarkdown: 'Texte propre au cabinet.',
            )).thenAnswer((_) async => const Right((id: 'tpl-cabinet', version: 1)));
        return ConsentTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: createTemplate,
          patchTemplate: MockPatchConsentTemplateUseCase(),
        );
      },
      act: (bloc) async {
        bloc.add(const ConsentTemplatesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ConsentTemplatesCreateRequested(
          actCategory: 'endodontie',
          title: 'Consentement endo (cabinet)',
          bodyMarkdown: 'Texte propre au cabinet.',
        ));
      },
      expect: () => [
        const ConsentTemplatesLoading(),
        ConsentTemplatesLoaded(templates: [_catalogueTemplate]),
        ConsentTemplatesLoaded(
          templates: [_catalogueTemplate],
          actionInProgress: true,
        ),
        const ConsentTemplatesLoading(),
        ConsentTemplatesLoaded(
          templates: [_catalogueTemplate, _cabinetTemplate],
        ),
      ],
    );

    blocTest<ConsentTemplatesBloc, ConsentTemplatesState>(
      'ConsentTemplatesUpdateRequested en échec expose actionError',
      build: () {
        final listTemplates = MockListConsentTemplatesUseCase();
        final patchTemplate = MockPatchConsentTemplateUseCase();
        when(() => listTemplates())
            .thenAnswer((_) async => Right([_cabinetTemplate]));
        when(() => patchTemplate(
              'tpl-cabinet',
              actCategory: 'endodontie',
              title: 'Titre modifié',
              bodyMarkdown: 'Texte modifié.',
            )).thenAnswer(
                (_) async => const Left(_FakeFailure('Modification refusée')));
        return ConsentTemplatesBloc(
          listTemplates: listTemplates,
          createTemplate: MockCreateConsentTemplateUseCase(),
          patchTemplate: patchTemplate,
        );
      },
      act: (bloc) async {
        bloc.add(const ConsentTemplatesLoadRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ConsentTemplatesUpdateRequested(
          id: 'tpl-cabinet',
          actCategory: 'endodontie',
          title: 'Titre modifié',
          bodyMarkdown: 'Texte modifié.',
        ));
      },
      expect: () => [
        const ConsentTemplatesLoading(),
        ConsentTemplatesLoaded(templates: [_cabinetTemplate]),
        ConsentTemplatesLoaded(
          templates: [_cabinetTemplate],
          actionInProgress: true,
        ),
        ConsentTemplatesLoaded(
          templates: [_cabinetTemplate],
          actionError: 'Modification refusée',
        ),
      ],
    );
  });

  group('ConsentTemplatesPage (widget)', () {
    testWidgets('affiche le squelette pendant le chargement', (tester) async {
      final bloc = MockConsentTemplatesBloc();
      when(() => bloc.state).thenReturn(const ConsentTemplatesLoading());
      await tester.pumpApp(
        BlocProvider<ConsentTemplatesBloc>.value(
          value: bloc,
          child: const ConsentTemplatesPage(),
        ),
      );

      expect(find.byKey(const Key('consent_templates_loading')), findsOneWidget);
    });

    testWidgets('affiche l\'erreur avec retry', (tester) async {
      final bloc = MockConsentTemplatesBloc();
      when(() => bloc.state).thenReturn(const ConsentTemplatesError('Boom'));
      await tester.pumpApp(
        BlocProvider<ConsentTemplatesBloc>.value(
          value: bloc,
          child: const ConsentTemplatesPage(),
        ),
      );

      expect(find.byKey(const Key('consent_templates_error')), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();

      // 2 appels : le chargement initial (`initState`) + le retry.
      verify(() => bloc.add(const ConsentTemplatesLoadRequested())).called(2);
    });

    testWidgets(
        'affiche le catalogue en lecture seule et les modèles du cabinet éditables',
        (tester) async {
      final bloc = MockConsentTemplatesBloc();
      when(() => bloc.state).thenReturn(
        ConsentTemplatesLoaded(
          templates: [_catalogueTemplate, _cabinetTemplate],
        ),
      );
      await tester.pumpApp(
        BlocProvider<ConsentTemplatesBloc>.value(
          value: bloc,
          child: const ConsentTemplatesPage(),
        ),
      );

      expect(find.byKey(const Key('consent_template_tpl-global')),
          findsOneWidget);
      expect(find.byKey(const Key('consent_template_tpl-cabinet')),
          findsOneWidget);
      expect(find.text('Consentement implant (catalogue)'), findsOneWidget);
      expect(find.text('Consentement endo (cabinet)'), findsOneWidget);

      // Catalogue global : pas de bouton « Modifier ».
      expect(find.byKey(const Key('consent_template_edit_tpl-global')),
          findsNothing);
      // Modèle du cabinet : éditable.
      expect(find.byKey(const Key('consent_template_edit_tpl-cabinet')),
          findsOneWidget);
    });

    testWidgets(
        'éditer un modèle du cabinet dispatch ConsentTemplatesUpdateRequested',
        (tester) async {
      final bloc = MockConsentTemplatesBloc();
      when(() => bloc.state).thenReturn(
        ConsentTemplatesLoaded(templates: [_cabinetTemplate]),
      );
      await tester.pumpApp(
        BlocProvider<ConsentTemplatesBloc>.value(
          value: bloc,
          child: const ConsentTemplatesPage(),
        ),
      );

      await tester.ensureVisible(
          find.byKey(const Key('consent_template_edit_tpl-cabinet')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('consent_template_edit_tpl-cabinet')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('consent_template_form_confirm')),
          findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('consent_template_title_field')),
        'Consentement endo (révisé)',
      );
      await tester.tap(find.byKey(const Key('consent_template_form_confirm')));
      await tester.pumpAndSettle();

      verify(() => bloc.add(const ConsentTemplatesUpdateRequested(
            id: 'tpl-cabinet',
            actCategory: 'endodontie',
            title: 'Consentement endo (révisé)',
            bodyMarkdown: 'Texte propre au cabinet.',
          ))).called(1);
    });

    testWidgets(
        'créer un modèle dispatch ConsentTemplatesCreateRequested',
        (tester) async {
      final bloc = MockConsentTemplatesBloc();
      when(() => bloc.state).thenReturn(
        const ConsentTemplatesLoaded(templates: []),
      );
      await tester.pumpApp(
        BlocProvider<ConsentTemplatesBloc>.value(
          value: bloc,
          child: const ConsentTemplatesPage(),
        ),
      );

      await tester.tap(find.byKey(const Key('consent_templates_create_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('consent_template_category_field')));
      await tester.pumpAndSettle();
      // Premier élément de la liste (toujours visible dans la feuille, pas
      // besoin de défiler) : « Chirurgie orale ».
      await tester.tap(find.text('Chirurgie orale'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('consent_template_title_field')),
        'Nouveau modèle endo',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('consent_template_body_field')),
        'Texte du nouveau modèle.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consent_template_form_confirm')));
      await tester.pumpAndSettle();

      verify(() => bloc.add(const ConsentTemplatesCreateRequested(
            actCategory: 'chirurgie_orale',
            title: 'Nouveau modèle endo',
            bodyMarkdown: 'Texte du nouveau modèle.',
          ))).called(1);
    });
  });
}
