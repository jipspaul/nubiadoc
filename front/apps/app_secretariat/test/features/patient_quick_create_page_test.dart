//! Tests widget : formulaire de création rapide de patient (#4038).
//!
//! Couvre les critères d'acceptation de l'issue : formulaire vide (bouton
//! désactivé, aucun appel), formulaire rempli (bouton actif, appel du use
//! case de création via l'event `PatientsCreateRequested`), état de
//! soumission (loading) et état d'erreur.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/patients/patient_quick_create_page.dart';
import 'package:app_secretariat/features/patients/patients_bloc.dart';
import 'package:app_secretariat/features/patients/patients_event.dart';
import 'package:app_secretariat/features/patients/patients_state.dart';

class _MockPatientsBloc extends MockBloc<PatientsEvent, PatientsState>
    implements PatientsBloc {}

void main() {
  late _MockPatientsBloc bloc;

  setUp(() {
    bloc = _MockPatientsBloc();
    registerFallbackValue(const PatientsCreateRequested(
      firstName: '',
      lastName: '',
    ));
  });

  Widget buildPage() => MaterialApp(
        theme: NubiaTheme.light,
        home: BlocProvider<PatientsBloc>.value(
          value: bloc,
          child: const PatientQuickCreatePage(),
        ),
      );

  group('PatientQuickCreatePage — formulaire vide', () {
    testWidgets('le bouton de soumission est désactivé', (tester) async {
      when(() => bloc.state).thenReturn(const PatientsInitial());
      await tester.pumpWidget(buildPage());

      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('patient_create_submit_button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('taper sur le bouton désactivé n\'ajoute aucun event',
        (tester) async {
      when(() => bloc.state).thenReturn(const PatientsInitial());
      await tester.pumpWidget(buildPage());

      await tester.tap(find.byKey(const Key('patient_create_submit_button')));
      await tester.pump();

      verifyNever(() => bloc.add(any()));
    });
  });

  group('PatientQuickCreatePage — formulaire rempli', () {
    testWidgets(
        'le bouton s\'active et ajoute PatientsCreateRequested avec les champs saisis',
        (tester) async {
      when(() => bloc.state).thenReturn(const PatientsInitial());
      await tester.pumpWidget(buildPage());

      await tester.enterText(
        find.byKey(const Key('patient_create_first_name_field')),
        'Marie',
      );
      await tester.enterText(
        find.byKey(const Key('patient_create_last_name_field')),
        'Curie',
      );
      await tester.enterText(
        find.byKey(const Key('patient_create_phone_field')),
        '0600000000',
      );
      await tester.pump();

      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('patient_create_submit_button')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('patient_create_submit_button')));
      await tester.pump();

      final captured = verify(() => bloc.add(captureAny())).captured;
      expect(captured, hasLength(1));
      final event = captured.single as PatientsCreateRequested;
      expect(event.firstName, 'Marie');
      expect(event.lastName, 'Curie');
      expect(event.phone, '0600000000');
    });

    testWidgets('champ téléphone vide → phone null dans l\'event',
        (tester) async {
      when(() => bloc.state).thenReturn(const PatientsInitial());
      await tester.pumpWidget(buildPage());

      await tester.enterText(
        find.byKey(const Key('patient_create_first_name_field')),
        'Marie',
      );
      await tester.enterText(
        find.byKey(const Key('patient_create_last_name_field')),
        'Curie',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('patient_create_submit_button')));
      await tester.pump();

      final captured = verify(() => bloc.add(captureAny())).captured.single
          as PatientsCreateRequested;
      expect(captured.phone, isNull);
    });
  });

  group('PatientQuickCreatePage — soumission et erreur', () {
    testWidgets('état Creating affiche un indicateur de chargement',
        (tester) async {
      when(() => bloc.state).thenReturn(const PatientsCreating());
      await tester.pumpWidget(buildPage());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('état CreateError affiche le message d\'erreur',
        (tester) async {
      when(() => bloc.state).thenReturn(
          const PatientsCreateError('Nom et prénom sont obligatoires.'));
      await tester.pumpWidget(buildPage());

      expect(
        find.text('Nom et prénom sont obligatoires.'),
        findsOneWidget,
      );
    });
  });
}
