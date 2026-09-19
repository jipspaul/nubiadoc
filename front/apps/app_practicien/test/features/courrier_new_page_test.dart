import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_practicien/features/courriers/courrier_new_page.dart';
import 'package:app_practicien/features/courriers/letter_compose_cubit.dart';
import 'package:app_practicien/features/courriers/letter_compose_state.dart';

class MockLetterComposeCubit extends MockCubit<LetterComposeState>
    implements LetterComposeCubit {}

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

  setUpAll(() {
    registerFallbackValue(<String, String>{});
  });

  setUp(() {
    cubit = MockLetterComposeCubit();
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
  });
}
